-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  05_analytics_queries.hql — Complete Analytical Query Suite        ║
-- ║                                                                    ║
-- ║  5 fully-worked analytical queries covering:                       ║
-- ║    Q1: Anomaly detection with rule-based filtering                 ║
-- ║    Q2: Web traffic aggregation with time functions                 ║
-- ║    Q3: Trending hashtags with LATERAL VIEW + window functions      ║
-- ║    Q4: Sensor-device enrichment join                               ║
-- ║    Q5: Multi-grain rollups with GROUPING SETS                      ║
-- ╚══════════════════════════════════════════════════════════════════════╝

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Session optimization settings
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

SET hive.execution.engine               = mr;   -- Use MapReduce (Tez not installed)
SET hive.cbo.enable                     = true;
SET hive.vectorized.execution.enabled   = true;
SET hive.optimize.ppd                   = true;   -- Predicate pushdown to ORC reader
SET hive.auto.convert.join              = true;   -- Map join for small tables

-- ════════════════════════════════════════════════════════════════════════
-- ┌─────────────────────────────────────────────────────────────────────┐
-- │  QUERY 1: Filter Anomalous Sensor Readings                         │
-- │                                                                    │
-- │  Task: Flag sensor readings that exceed physical bounds:           │
-- │    • Temperature > 100°C (boiling point) = hardware failure        │
-- │    • Temperature < -40°C (below instrument range) = sensor fail    │
-- │    • Humidity > 100% = physically impossible                       │
-- │    • Humidity < 0%   = physically impossible                       │
-- │    • NULL values     = MISSING data packet                         │
-- │                                                                    │
-- │  Technique: Multi-condition WHERE + CASE expression for            │
-- │             anomaly type classification                            │
-- └─────────────────────────────────────────────────────────────────────┘
-- ════════════════════════════════════════════════════════════════════════

-- Q1a: Raw anomaly count by type and device
SELECT
    device_id,
    zone,
    -- Classify each anomaly with a specific reason code
    CASE
        WHEN temperature IS NULL OR humidity IS NULL
                                    THEN 'MISSING_READING'
        WHEN temperature > 100      THEN 'EXTREME_HIGH_TEMP'       -- Far above boiling
        WHEN temperature < -40      THEN 'EXTREME_LOW_TEMP'         -- Below sensor spec
        WHEN humidity > 100         THEN 'INVALID_HUMIDITY_HIGH'    -- Physically impossible
        WHEN humidity < 0           THEN 'INVALID_HUMIDITY_LOW'     -- Physically impossible
        WHEN temperature > 85       THEN 'HIGH_TEMP_WARNING'        -- Severe but possible
        WHEN temperature < -20      THEN 'LOW_TEMP_WARNING'         -- Severe but possible
        ELSE 'UNSPECIFIED_ANOMALY'
    END                             AS anomaly_type,
    COUNT(*)                        AS occurrence_count,
    MIN(timestamp_ts)               AS first_occurrence,
    MAX(timestamp_ts)               AS last_occurrence,
    ROUND(MIN(temperature), 2)      AS min_temp_observed,
    ROUND(MAX(temperature), 2)      AS max_temp_observed
FROM processed_db.sensor_readings
WHERE
    -- Filter to anomalous readings ONLY (one or more conditions true)
    temperature IS NULL
    OR humidity IS NULL
    OR temperature > 100
    OR temperature < -40
    OR humidity > 100
    OR humidity < 0
GROUP BY
    device_id,
    zone,
    -- Must repeat the CASE when used in GROUP BY
    CASE
        WHEN temperature IS NULL OR humidity IS NULL THEN 'MISSING_READING'
        WHEN temperature > 100  THEN 'EXTREME_HIGH_TEMP'
        WHEN temperature < -40  THEN 'EXTREME_LOW_TEMP'
        WHEN humidity > 100     THEN 'INVALID_HUMIDITY_HIGH'
        WHEN humidity < 0       THEN 'INVALID_HUMIDITY_LOW'
        WHEN temperature > 85   THEN 'HIGH_TEMP_WARNING'
        WHEN temperature < -20  THEN 'LOW_TEMP_WARNING'
        ELSE 'UNSPECIFIED_ANOMALY'
    END
ORDER BY occurrence_count DESC, device_id;

-- Q1b: Anomaly rate per device (what % of readings are anomalous?)
SELECT
    device_id,
    zone,
    COUNT(*)                                                AS total_readings,
    SUM(CASE WHEN status IN ('ANOMALY', 'MISSING') THEN 1 ELSE 0 END) AS anomaly_count,
    ROUND(
        SUM(CASE WHEN status IN ('ANOMALY', 'MISSING') THEN 1.0 ELSE 0.0 END)
        / COUNT(*) * 100,
        2
    )                                                       AS anomaly_rate_pct,
    ROUND(AVG(data_quality_score), 3)                       AS avg_quality_score
FROM processed_db.sensor_readings
GROUP BY device_id, zone
ORDER BY anomaly_rate_pct DESC;

-- ════════════════════════════════════════════════════════════════════════
-- ┌─────────────────────────────────────────────────────────────────────┐
-- │  QUERY 2: Web Traffic Aggregation by Hour, URL, and Status Code    │
-- │                                                                    │
-- │  Task: Hourly traffic analysis to understand:                      │
-- │    • Peak traffic hours                                            │
-- │    • Most popular pages                                            │
-- │    • Error rate per hour                                           │
-- │                                                                    │
-- │  Technique: GROUP BY with multiple dimensions, aggregate           │
-- │             functions, HAVING for post-aggregation filtering       │
-- └─────────────────────────────────────────────────────────────────────┘
-- ════════════════════════════════════════════════════════════════════════

-- Q2a: Traffic summary by hour and HTTP status category
SELECT
    request_hour,
    -- Group status codes into categories (HTTP status classes)
    CASE
        WHEN http_status BETWEEN 200 AND 299 THEN '2xx_Success'
        WHEN http_status BETWEEN 300 AND 399 THEN '3xx_Redirect'
        WHEN http_status BETWEEN 400 AND 499 THEN '4xx_Client_Error'
        WHEN http_status BETWEEN 500 AND 599 THEN '5xx_Server_Error'
        ELSE 'Unknown'
    END                                         AS status_class,
    COUNT(*)                                    AS total_requests,
    COUNT(DISTINCT client_ip)                   AS unique_visitors,
    SUM(response_bytes)                         AS total_bytes_served,
    ROUND(AVG(response_bytes), 0)               AS avg_response_size_bytes,
    MIN(http_status)                            AS min_status_code,
    MAX(http_status)                            AS max_status_code
FROM processed_db.web_traffic
GROUP BY
    request_hour,
    CASE
        WHEN http_status BETWEEN 200 AND 299 THEN '2xx_Success'
        WHEN http_status BETWEEN 300 AND 399 THEN '3xx_Redirect'
        WHEN http_status BETWEEN 400 AND 499 THEN '4xx_Client_Error'
        WHEN http_status BETWEEN 500 AND 599 THEN '5xx_Server_Error'
        ELSE 'Unknown'
    END
ORDER BY request_hour ASC, total_requests DESC;

-- Q2b: Top 20 most requested URLs (with error rate per URL)
SELECT
    url_path,
    COUNT(*)                                                AS total_requests,
    SUM(CASE WHEN http_status = 200 THEN 1 ELSE 0 END)     AS success_count,
    SUM(CASE WHEN http_status = 404 THEN 1 ELSE 0 END)     AS not_found_count,
    SUM(CASE WHEN http_status >= 500 THEN 1 ELSE 0 END)    AS server_error_count,
    ROUND(
        SUM(CASE WHEN http_status >= 400 THEN 1.0 ELSE 0.0 END)
        / COUNT(*) * 100,
        2
    )                                                       AS error_rate_pct,
    SUM(response_bytes)                                     AS total_bytes,
    ROUND(AVG(response_bytes), 0)                           AS avg_response_bytes
FROM processed_db.web_traffic
WHERE url_path NOT IN ('/favicon.ico', '/robots.txt', '/sitemap.xml')  -- Exclude noise
GROUP BY url_path
HAVING COUNT(*) >= 10   -- HAVING: post-aggregation filter (WHERE applies to rows, HAVING to groups)
ORDER BY total_requests DESC
LIMIT 20;

-- Q2c: Hourly traffic heatmap data (hour × day-of-week matrix)
SELECT
    request_hour                                            AS hour_of_day,
    request_dow                                             AS day_of_week,
    CASE request_dow
        WHEN 1 THEN 'Sunday'    WHEN 2 THEN 'Monday'
        WHEN 3 THEN 'Tuesday'   WHEN 4 THEN 'Wednesday'
        WHEN 5 THEN 'Thursday'  WHEN 6 THEN 'Friday'
        WHEN 7 THEN 'Saturday'
    END                                                     AS day_name,
    COUNT(*)                                                AS request_count,
    COUNT(DISTINCT client_ip)                               AS unique_ips
FROM processed_db.web_traffic
GROUP BY request_hour, request_dow
ORDER BY request_dow, request_hour;

-- ════════════════════════════════════════════════════════════════════════
-- ┌─────────────────────────────────────────────────────────────────────┐
-- │  QUERY 3: Top 10 Trending Hashtags from Social Media              │
-- │                                                                    │
-- │  Task: Rank hashtags by total mentions and composite trending      │
-- │        score (weighted mentions + engagement).                     │
-- │                                                                    │
-- │  Technique:                                                        │
-- │    • LATERAL VIEW explode() — normalize space-separated hashtags   │
-- │    • Window functions: RANK() OVER (ORDER BY...) for ranking       │
-- │    • Weighted scoring for "trending" vs just "popular"             │
-- └─────────────────────────────────────────────────────────────────────┘
-- ════════════════════════════════════════════════════════════════════════

-- Q3a: Top 10 overall trending hashtags
SELECT
    hashtag,
    total_mentions,
    total_likes,
    total_retweets,
    ROUND(avg_engagement_rate * 100, 4)                     AS avg_engagement_pct,
    first_seen,
    last_seen,
    -- Composite trending score:
    -- Weighted formula: mentions × 1 + likes × 0.1 + retweets × 0.5
    -- Retweets weighted higher (true content sharing signal)
    -- Likes are passive engagement, retweets = active spreading
    ROUND(
        total_mentions
        + (total_likes    * 0.1)
        + (total_retweets * 0.5),
        2
    )                                                       AS trending_score
FROM (
    -- Aggregate from pre-computed daily table (much faster than re-exploding)
    SELECT
        hashtag,
        SUM(mention_count)          AS total_mentions,
        SUM(total_likes)            AS total_likes,
        SUM(total_retweets)         AS total_retweets,
        AVG(avg_engagement_rate)    AS avg_engagement_rate,
        MIN(first_seen)             AS first_seen,
        MAX(last_seen)              AS last_seen
    FROM processed_db.trending_hashtags_daily
    GROUP BY hashtag
) agg
ORDER BY trending_score DESC
LIMIT 10;

-- Q3b: Hashtag trend over time (show rise and fall of trending topics)
WITH hashtag_daily AS (
    SELECT
        hashtag,
        dt,
        mention_count,
        -- Previous day's mention count using LAG window function
        LAG(mention_count, 1) OVER (
            PARTITION BY hashtag    -- LAG is per-hashtag
            ORDER BY dt             -- Ordered by date
        )                                                   AS prev_day_count
    FROM processed_db.trending_hashtags_daily
    -- Focus on top hashtags only
    WHERE hashtag IN (
        SELECT hashtag
        FROM processed_db.trending_hashtags_daily
        GROUP BY hashtag
        ORDER BY SUM(mention_count) DESC
        LIMIT 5
    )
)
SELECT
    hashtag,
    dt,
    mention_count,
    COALESCE(prev_day_count, 0)                             AS prev_day_mentions,
    -- Day-over-day change
    mention_count - COALESCE(prev_day_count, 0)             AS daily_delta,
    -- Growth rate (%)
    ROUND(
        CASE
            WHEN COALESCE(prev_day_count, 0) = 0 THEN 100.0
            ELSE (mention_count - prev_day_count) * 100.0 / prev_day_count
        END,
        2
    )                                                       AS growth_rate_pct
FROM hashtag_daily
ORDER BY hashtag, dt;

-- Q3c: RANK hashtags using window function (demonstrates RANK vs DENSE_RANK vs ROW_NUMBER)
SELECT hashtag, total_mentions, mention_rank, dense_rank, row_num, percentile
FROM (
    SELECT
        hashtag,
        total_mentions,
        RANK()       OVER (ORDER BY total_mentions DESC)        AS mention_rank,
        DENSE_RANK() OVER (ORDER BY total_mentions DESC)        AS dense_rank,
        ROW_NUMBER() OVER (ORDER BY total_mentions DESC)        AS row_num,
        ROUND(PERCENT_RANK() OVER (ORDER BY total_mentions DESC), 4) AS percentile
    FROM (
        SELECT hashtag, SUM(mention_count) AS total_mentions
        FROM processed_db.trending_hashtags_daily
        GROUP BY hashtag
    ) agg
) ranked
WHERE mention_rank <= 10;

-- ════════════════════════════════════════════════════════════════════════
-- ┌─────────────────────────────────────────────────────────────────────┐
-- │  QUERY 4: Join Sensor Data with Device Metadata                    │
-- │                                                                    │
-- │  Task: Enrich sensor readings with device context (zone, model,    │
-- │        thresholds) to produce actionable alerts.                   │
-- │                                                                    │
-- │  Technique: INNER JOIN (device_metadata broadcast via Map Join)    │
-- │    • LEFT JOIN to include devices with NO recent readings           │
-- │    • Alert logic: compare reading against device's own thresholds  │
-- │    • Hive auto-converts to Map Join (device_metadata < 25MB)       │
-- └─────────────────────────────────────────────────────────────────────┘
-- ════════════════════════════════════════════════════════════════════════

-- Q4a: Sensor readings enriched with device metadata + threshold alerts
SELECT
    -- Device context from dimension table
    dm.device_id,
    dm.device_name,
    dm.manufacturer,
    dm.model,
    dm.zone,
    dm.location,
    dm.`floor`,
    dm.sla_tier,
    dm.connectivity,
    dm.sampling_interval_sec,

    -- Reading data from facts table
    sr.timestamp_ts,
    sr.temperature,
    sr.humidity,
    sr.status,
    sr.data_quality_score,

    -- Device-specific threshold values for context
    dm.alert_temp_min,
    dm.alert_temp_max,
    dm.alert_humidity_min,
    dm.alert_humidity_max,

    -- Alert flag: does this reading violate THIS DEVICE's thresholds?
    -- Note: Different from global anomaly check — uses device-specific config
    CASE
        WHEN sr.temperature < dm.alert_temp_min
                                THEN CONCAT('TEMP_TOO_LOW (', CAST(sr.temperature AS STRING), '°C < ', CAST(dm.alert_temp_min AS STRING), '°C threshold)')
        WHEN sr.temperature > dm.alert_temp_max
                                THEN CONCAT('TEMP_TOO_HIGH (', CAST(sr.temperature AS STRING), '°C > ', CAST(dm.alert_temp_max AS STRING), '°C threshold)')
        WHEN sr.humidity < dm.alert_humidity_min
                                THEN CONCAT('HUMIDITY_TOO_LOW (', CAST(sr.humidity AS STRING), '% < ', CAST(dm.alert_humidity_min AS STRING), '% threshold)')
        WHEN sr.humidity > dm.alert_humidity_max
                                THEN CONCAT('HUMIDITY_TOO_HIGH (', CAST(sr.humidity AS STRING), '% > ', CAST(dm.alert_humidity_max AS STRING), '% threshold)')
        ELSE 'WITHIN_THRESHOLD'
    END                                                     AS threshold_alert

FROM processed_db.sensor_readings   sr
-- INNER JOIN: only rows that exist in BOTH tables
-- Map Join: device_metadata is tiny (15 rows) → Hive broadcasts it to all nodes
INNER JOIN processed_db.device_metadata dm
    ON sr.device_id = dm.device_id      -- Join condition: matching device IDs
WHERE
    sr.status   <> 'MISSING'            -- Exclude missing readings from alerts
    AND sr.dt   >= '2024-01-15'         -- Partition pruning: only read this date's data
    AND sr.dt   <= '2024-01-20'         -- Hive skips all other date partitions
ORDER BY
    dm.sla_tier ASC,                    -- GOLD devices first (highest priority)
    sr.timestamp_ts DESC                -- Most recent reading first
LIMIT 1000;

-- Q4b: Device health summary — average metrics per device with threshold breach counts
SELECT
    dm.device_id,
    dm.device_name,
    dm.zone,
    dm.sla_tier,
    dm.manufacturer,

    COUNT(sr.reading_id)                                    AS total_readings,
    ROUND(AVG(sr.temperature), 2)                           AS avg_temp,
    ROUND(MIN(sr.temperature), 2)                           AS min_temp,
    ROUND(MAX(sr.temperature), 2)                           AS max_temp,
    ROUND(AVG(sr.humidity), 2)                              AS avg_humidity,
    ROUND(AVG(sr.data_quality_score), 3)                    AS avg_quality_score,

    -- Threshold breach counts (device-specific)
    SUM(CASE WHEN sr.temperature < dm.alert_temp_min
               OR sr.temperature > dm.alert_temp_max
               THEN 1 ELSE 0 END)                           AS temp_breach_count,

    SUM(CASE WHEN sr.humidity < dm.alert_humidity_min
               OR sr.humidity > dm.alert_humidity_max
               THEN 1 ELSE 0 END)                           AS humidity_breach_count,

    -- Overall health percentage (good readings / total)
    ROUND(
        SUM(CASE WHEN sr.status = 'OK' THEN 1.0 ELSE 0.0 END)
        / GREATEST(COUNT(sr.reading_id), 1) * 100,
        2
    )                                                       AS health_pct

FROM processed_db.device_metadata  dm
-- LEFT JOIN: include devices even if they have no sensor readings
-- (useful for detecting silent/offline devices)
LEFT JOIN processed_db.sensor_readings  sr
    ON dm.device_id = sr.device_id
GROUP BY
    dm.device_id, dm.device_name, dm.zone, dm.sla_tier, dm.manufacturer
ORDER BY
    dm.sla_tier ASC,
    health_pct ASC;          -- Unhealthiest devices first

-- ════════════════════════════════════════════════════════════════════════
-- ┌─────────────────────────────────────────────────────────────────────┐
-- │  QUERY 5: Daily & Weekly Rollups Using GROUPING SETS               │
-- │                                                                    │
-- │  Task: Produce multiple levels of aggregation in a SINGLE query:   │
-- │    • Level 1: Per day + per device + per zone (finest grain)       │
-- │    • Level 2: Per day + per zone (zone summary)                    │
-- │    • Level 3: Per day (daily total)                                │
-- │    • Level 4: Grand total (all days, all devices)                  │
-- │                                                                    │
-- │  Technique: GROUPING SETS — produces all rollup levels in one pass │
-- │    Alternative: ROLLUP (hierarchical), CUBE (all combinations)     │
-- └─────────────────────────────────────────────────────────────────────┘
-- ════════════════════════════════════════════════════════════════════════

-- Q5a: GROUPING SETS — Multiple aggregation grains in one scan
SELECT
    -- COALESCE handles NULL aggregation keys (NULL = "ALL" in grouping context)
    COALESCE(dt,        'ALL_DATES')    AS date_key,
    COALESCE(device_id, 'ALL_DEVICES') AS device_key,
    COALESCE(zone,      'ALL_ZONES')   AS zone_key,

    -- COALESCE shows 'ALL_X' for any rolled-up dimension (NULL in GROUPING SETS context)

    ROUND(AVG(avg_temp), 2)             AS avg_temperature,
    ROUND(MIN(min_temp), 2)             AS min_temperature,
    ROUND(MAX(max_temp), 2)             AS max_temperature,
    ROUND(AVG(avg_humidity), 2)         AS avg_humidity,
    SUM(total_readings)                 AS total_readings,
    SUM(anomaly_count)                  AS total_anomalies,
    ROUND(
        SUM(anomaly_count) * 100.0 / GREATEST(SUM(total_readings), 1),
        3
    )                                   AS anomaly_rate_pct

FROM processed_db.sensor_daily_summary
GROUP BY dt, device_id, zone
    GROUPING SETS (
        (dt, device_id, zone),  -- Grain 1: per day + device + zone (most granular)
        (dt, zone),             -- Grain 2: per day + zone (zone rollup)
        (dt),                   -- Grain 3: per day only (daily total)
        ()                      -- Grain 4: grand total (empty parens = no grouping)
    )
ORDER BY
    date_key,
    zone_key,
    device_key;

-- Q5b: ROLLUP — hierarchical aggregation (Date → Zone → Device)
-- ROLLUP produces N+1 grouping levels for N dimensions (less flexible than GROUPING SETS)
SELECT
    COALESCE(dt,        '=== GRAND TOTAL ===') AS date_key,
    COALESCE(zone,      '=== ZONE TOTAL ===')  AS zone_key,
    COALESCE(device_id, '=== DEVICE TOTAL ===') AS device_key,

    SUM(total_readings)                         AS readings,
    ROUND(AVG(avg_temp), 2)                     AS avg_temp,
    SUM(anomaly_count)                          AS anomalies

FROM processed_db.sensor_daily_summary
GROUP BY dt, zone, device_id
    WITH ROLLUP     -- Equivalent to GROUPING SETS((dt,zone,device_id),(dt,zone),(dt),())
ORDER BY date_key NULLS LAST, zone_key NULLS LAST, device_key NULLS LAST;

-- Q5c: Weekly rollup — aggregate by ISO week
SELECT
    WEEKOFYEAR(CAST(dt AS DATE))                AS week_number,
    MIN(dt)                                     AS week_start_date,
    MAX(dt)                                     AS week_end_date,
    zone,
    SUM(total_readings)                         AS weekly_readings,
    ROUND(AVG(avg_temp), 2)                     AS weekly_avg_temp,
    ROUND(MIN(min_temp), 2)                     AS weekly_min_temp,
    ROUND(MAX(max_temp), 2)                     AS weekly_max_temp,
    SUM(anomaly_count)                          AS weekly_anomalies,
    ROUND(
        SUM(anomaly_count) * 100.0 / GREATEST(SUM(total_readings), 1),
        3
    )                                           AS weekly_anomaly_rate_pct
FROM processed_db.sensor_daily_summary
GROUP BY WEEKOFYEAR(CAST(dt AS DATE)), zone
ORDER BY week_number, zone;
