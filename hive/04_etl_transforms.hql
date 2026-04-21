-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  04_etl_transforms.hql — ETL: Raw Text → Processed ORC             ║
-- ║                                                                    ║
-- ║  Transforms raw external tables → partitioned ORC managed tables.  ║
-- ║                                                                    ║
-- ║  ETL Pattern Used:                                                  ║
-- ║    INSERT OVERWRITE TABLE ... SELECT ... FROM raw_db.*             ║
-- ║    This is idempotent — safe to re-run (overwrites partitions)     ║
-- ║                                                                    ║
-- ║  Transformations performed:                                        ║
-- ║    • Web logs:   Parse CLF format → structured columns             ║
-- ║    • Sensors:    Type casting, quality scoring, deduplication      ║
-- ║    • Social:     Timestamp parsing, engagement rate calculation     ║
-- ║    • Metadata:   Direct load (already structured)                  ║
-- ╚══════════════════════════════════════════════════════════════════════╝

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Session settings for ETL performance
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- Use Tez for faster multi-stage ETL DAGs
SET hive.execution.engine           = mr;   -- Use MapReduce (Tez not installed in this env)

-- Enable dynamic partitioning (we partition by date without pre-creating partitions)
SET hive.exec.dynamic.partition     = true;
SET hive.exec.dynamic.partition.mode = nonstrict;

-- Parallel execution of independent stages within a DAG
SET hive.exec.parallel              = true;
SET hive.exec.parallel.thread.number = 8;

-- Reduce output compression
SET hive.exec.compress.output       = true;

-- Auto map join: broadcast small tables (< 25MB) to all mappers
SET hive.auto.convert.join          = true;
SET hive.mapjoin.smalltable.filesize = 25000000;

-- Cost-Based Optimizer
SET hive.cbo.enable                 = true;
SET hive.stats.autogather           = true;

-- Merge small ORC output files to avoid "small files problem"
SET hive.merge.mapfiles             = true;
SET hive.merge.mapredfiles          = true;
SET hive.merge.size.per.task        = 256000000;   -- 256MB target per merged file
SET hive.merge.smallfiles.avgsize   = 16000000;    -- Merge if avg file < 16MB

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- ETL 1: Web Logs — Parse Apache CLF format into structured columns
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

INSERT OVERWRITE TABLE processed_db.web_traffic
PARTITION (dt)   -- Dynamic partition: value determined per-row from SELECT
SELECT
    -- ── IP Address ──────────────────────────────────────────────────────
    client_ip,

    -- ── Parse HTTP request line ──────────────────────────────────────────
    -- http_request format: "GET /path?query HTTP/1.1"
    -- split()[0] = method,  split()[1] = full URL,  split()[2] = protocol
    REGEXP_EXTRACT(http_request, '^(\\S+)\\s+', 1)
                                                    AS http_method,

    -- Extract path without query string (split at '?', take first part)
    SPLIT(
        REGEXP_EXTRACT(http_request, '^\\S+\\s+(\\S+)', 1),
        '\\?'
    )[0]                                            AS url_path,

    -- Extract query string (after '?', empty string if none)
    COALESCE(
        SPLIT(
            REGEXP_EXTRACT(http_request, '^\\S+\\s+(\\S+)', 1),
            '\\?'
        )[1],
        ''
    )                                               AS url_query,

    -- Protocol: HTTP/1.0 or HTTP/1.1
    REGEXP_EXTRACT(http_request, '(HTTP/[\\d.]+)$', 1)
                                                    AS http_protocol,

    -- ── Status and Size ──────────────────────────────────────────────────
    http_status,

    -- Convert response bytes: "-" in logs means 0 bytes (no body)
    CASE
        WHEN response_bytes = '-' THEN 0
        ELSE CAST(response_bytes AS BIGINT)
    END                                             AS response_bytes,

    referrer,
    user_agent,

    -- ── Parse Timestamp: [DD/Mon/YYYY:HH:MM:SS +0000] ───────────────────
    -- Step 1: Extract just the time portion
    -- Step 2: Parse individual components with REGEXP_EXTRACT
    CAST(
        REGEXP_EXTRACT(raw_timestamp, ':(\\d{2}):\\d{2}:\\d{2}', 1)
    AS INT)                                         AS request_hour,

    -- Day of week: use from_unixtime → dayofweek() chain
    -- We parse the full timestamp to a unix timestamp, then extract DOW
    DAYOFWEEK(FROM_UNIXTIME(
        UNIX_TIMESTAMP(
            REGEXP_EXTRACT(raw_timestamp, '[:(]([0-9]{2}/[A-Za-z]+/[0-9]{4}:[0-9]{2}:[0-9]{2}:[0-9]{2})', 1),
            'dd/MMM/yyyy:HH:mm:ss'
        )
    ))                                              AS request_dow,

    -- Full timestamp as TIMESTAMP type
    FROM_UNIXTIME(
        UNIX_TIMESTAMP(
            REGEXP_EXTRACT(raw_timestamp, '[:(]([0-9]{2}/[A-Za-z]+/[0-9]{4}:[0-9]{2}:[0-9]{2}:[0-9]{2})', 1),
            'dd/MMM/yyyy:HH:mm:ss'
        )
    )                                               AS request_ts,

    -- ── Partition key: extract YYYY-MM-DD from timestamp ─────────────────
    FROM_UNIXTIME(
        UNIX_TIMESTAMP(
            REGEXP_EXTRACT(raw_timestamp, '[:(]([0-9]{2}/[A-Za-z]+/[0-9]{4}:[0-9]{2}:[0-9]{2}:[0-9]{2})', 1),
            'dd/MMM/yyyy:HH:mm:ss'
        ),
        'yyyy-MM-dd'
    )                                               AS dt   -- Dynamic partition column (must be LAST)

FROM raw_db.raw_web_logs
WHERE
    -- Basic validation: skip rows where RegexSerDe failed to extract fields
    client_ip IS NOT NULL
    AND http_request IS NOT NULL
    AND http_status IS NOT NULL;

-- Check loaded data
SELECT dt, COUNT(*) AS row_count, COUNT(DISTINCT client_ip) AS unique_ips
FROM processed_db.web_traffic
GROUP BY dt
ORDER BY dt
LIMIT 10;

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- ETL 2: Sensor Readings — Type casting, quality scoring, deduplication
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

INSERT OVERWRITE TABLE processed_db.sensor_readings
PARTITION (dt, zone)   -- Two partition keys
SELECT
    reading_id,
    device_id,
    location,

    -- Parse timestamp string → proper TIMESTAMP type
    CAST(ts AS TIMESTAMP)                           AS timestamp_ts,

    -- Temperature: keep as-is (anomalies preserved, filter in analytics layer)
    temperature,
    humidity,
    status,
    is_duplicate,

    -- ── Data Quality Score ───────────────────────────────────────────────
    -- A composite score 0.0 to 1.0 indicating reading reliability:
    --   1.0    = Perfect (OK, not duplicate, in physical range)
    --   0.5    = Degraded (valid range but flagged as duplicate)
    --   0.0    = Invalid (MISSING or ANOMALY)
    CASE
        WHEN status = 'MISSING'                         THEN 0.0
        WHEN status = 'ANOMALY'                         THEN 0.0
        WHEN is_duplicate = true                        THEN 0.5
        WHEN temperature IS NULL OR humidity IS NULL    THEN 0.0
        WHEN temperature > 85 OR temperature < -30      THEN 0.25  -- Extreme but possible
        ELSE 1.0
    END                                             AS data_quality_score,

    -- ── Partition keys (must be last in SELECT for dynamic partitioning) ──
    DATE_FORMAT(CAST(ts AS TIMESTAMP), 'yyyy-MM-dd') AS dt,
    zone

FROM (
    -- Subquery: deduplicate readings
    -- In case of exact duplicates (same device_id + timestamp), keep ONE
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY device_id, ts   -- Identify duplicates by device + time
               ORDER BY reading_id          -- Keep the one with lower reading_id (first received)
           ) AS rn
    FROM raw_db.raw_sensor_readings
    WHERE reading_id IS NOT NULL
      AND device_id  IS NOT NULL
      AND ts         IS NOT NULL
) deduped
WHERE rn = 1;   -- Only keep the first occurrence of each device+timestamp combination

-- Check partition distribution
SELECT dt, zone, COUNT(*) AS readings
FROM processed_db.sensor_readings
GROUP BY dt, zone
ORDER BY dt, zone
LIMIT 20;

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- ETL 3: Social Posts — Parse timestamps, calculate engagement rate
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

INSERT OVERWRITE TABLE processed_db.social_posts
PARTITION (dt, language)
SELECT
    tweet_id,
    username,
    user_type,
    followers,
    verified,

    -- Parse timestamp string to TIMESTAMP
    CAST(ts AS TIMESTAMP)                                       AS post_ts,

    post_text,
    hashtags,

    -- Count hashtags: split on space, then count array elements
    -- If no hashtags, split returns [''] (array of 1 empty string), so subtract
    SIZE(SPLIT(TRIM(hashtags), '\\s+'))                        AS hashtag_count,

    likes,
    retweets,
    replies,
    impressions,

    -- Engagement rate = interactions / impressions
    -- GREATEST(..., 1) prevents division by zero when impressions = 0
    ROUND(
        CAST(likes + retweets + replies AS DOUBLE)
        / GREATEST(impressions, 1),
        6
    )                                                           AS engagement_rate,

    source,

    -- Partition keys (must be last)
    DATE_FORMAT(CAST(ts AS TIMESTAMP), 'yyyy-MM-dd')           AS dt,
    language

FROM raw_db.raw_social_posts
WHERE tweet_id   IS NOT NULL
  AND username   IS NOT NULL
  AND ts         IS NOT NULL;

-- Check loaded data
SELECT language, dt, COUNT(*) AS posts
FROM processed_db.social_posts
GROUP BY language, dt
ORDER BY dt, language
LIMIT 10;

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- ETL 4: Device Metadata — Direct load (already structured CSV)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

INSERT OVERWRITE TABLE processed_db.device_metadata
SELECT
    device_id,
    device_name,
    model,
    firmware_version,
    manufacturer,
    location,
    `floor`,
    zone,
    CAST(latitude  AS DOUBLE),
    CAST(longitude AS DOUBLE),
    CAST(install_date     AS DATE),
    CAST(last_maintenance AS DATE),
    CAST(battery_level_pct AS INT),
    connectivity,
    CAST(sampling_interval_sec AS INT),
    CAST(alert_temp_min    AS DOUBLE),
    CAST(alert_temp_max    AS DOUBLE),
    CAST(alert_humidity_min AS DOUBLE),
    CAST(alert_humidity_max AS DOUBLE),
    CAST(active AS BOOLEAN),
    cost_center,
    sla_tier
FROM raw_db.raw_device_metadata;

-- Verify all devices loaded
SELECT device_id, zone, sla_tier, connectivity FROM processed_db.device_metadata ORDER BY device_id;

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- ETL 5: Populate sensor_daily_summary (pre-aggregated for rollups)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

INSERT OVERWRITE TABLE processed_db.sensor_daily_summary
PARTITION (dt)
SELECT
    device_id,
    zone,
    ROUND(AVG(temperature), 4)                                  AS avg_temp,
    MIN(temperature)                                            AS min_temp,
    MAX(temperature)                                            AS max_temp,
    ROUND(AVG(humidity), 4)                                     AS avg_humidity,
    COUNT(*)                                                    AS total_readings,
    SUM(CASE WHEN status = 'ANOMALY' THEN 1 ELSE 0 END)        AS anomaly_count,
    SUM(CASE WHEN status = 'MISSING' THEN 1 ELSE 0 END)        AS missing_count,
    dt
FROM processed_db.sensor_readings
WHERE temperature IS NOT NULL    -- Exclude MISSING readings from averages
  AND humidity    IS NOT NULL
GROUP BY device_id, zone, dt;

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- ETL 6: Populate trending_hashtags_daily
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

INSERT OVERWRITE TABLE processed_db.trending_hashtags_daily
PARTITION (dt)
SELECT
    hashtag,
    COUNT(*)                                                    AS mention_count,
    SUM(likes)                                                  AS total_likes,
    SUM(retweets)                                               AS total_retweets,
    ROUND(AVG(engagement_rate), 6)                              AS avg_engagement_rate,
    MIN(post_ts)                                                AS first_seen,
    MAX(post_ts)                                                AS last_seen,
    dt
FROM processed_db.social_posts
-- LATERAL VIEW explode() is the key transformation:
-- It "explodes" the space-separated hashtag string into individual rows
-- BEFORE: one row with hashtags="  #BigData #Hadoop #AI"
-- AFTER:  three rows, one per hashtag
LATERAL VIEW OUTER explode(SPLIT(TRIM(hashtags), '\\s+')) ht_table AS hashtag
WHERE hashtag IS NOT NULL
  AND hashtag != ''
  AND hashtag RLIKE '^#.*'    -- Only valid hashtags (starting with #)
GROUP BY hashtag, dt;

-- Final validation: show top hashtags
SELECT hashtag, SUM(mention_count) AS total_mentions
FROM processed_db.trending_hashtags_daily
GROUP BY hashtag
ORDER BY total_mentions DESC
LIMIT 15;
