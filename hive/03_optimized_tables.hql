-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  03_optimized_tables.hql — Partitioned & Bucketed ORC Tables       ║
-- ║                                                                    ║
-- ║  Creates MANAGED tables in processed_db with:                      ║
-- ║    • ORC file format (best compression for Hive)                   ║
-- ║    • Partition by date (partition pruning)                         ║
-- ║    • Bucketing for optimized joins and sampling                    ║
-- ║    • Column statistics for Cost-Based Optimizer (CBO)              ║
-- ║                                                                    ║
-- ║  WHY ORC?                                                          ║
-- ║    1. Columnar storage → only read needed columns                  ║
-- ║    2. Built-in compression (Zlib default, Snappy optional)         ║
-- ║    3. Row-stripe statistics → predicate pushdown                   ║
-- ║    4. Supports Hive ACID (INSERT, UPDATE, DELETE)                  ║
-- ║    5. Vectorized execution support                                 ║
-- ║    Average compression: 10x vs raw text                            ║
-- ╚══════════════════════════════════════════════════════════════════════╝

USE processed_db;

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- Global Settings for this session
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- Allow dynamic partition creation without needing to pre-create partitions
SET hive.exec.dynamic.partition = true;
SET hive.exec.dynamic.partition.mode = nonstrict;

-- ORC compression codec (ZLIB=best compression ratio, SNAPPY=best throughput)
SET hive.exec.orc.default.compress = ZLIB;


-- Enable vectorized execution for columnar reads
SET hive.vectorized.execution.enabled = true;
SET hive.vectorized.execution.reduce.enabled = true;

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- TABLE 1: web_traffic
--
-- PARTITIONING STRATEGY: By date (dt)
--   - Web traffic is always queried with a date range filter
--   - Partition = one directory per day on HDFS
--   - /pipeline/processed/web_traffic/dt=2024-01-15/
--   - Query: WHERE dt = '2024-01-15' → only that directory is read
--   - Without partitioning: full table scan across ALL dates
--
-- BUCKETING STRATEGY: By client_ip into 32 buckets
--   - Enables efficient sampling:  TABLESAMPLE(BUCKET 1 OUT OF 32)
--   - Enables SM-B join with tables bucketed the same way on client_ip
--   - 32 buckets is a good starting point; adjust based on data volume
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CREATE TABLE IF NOT EXISTS web_traffic (
    -- Derived fields (parsed from raw log)
    client_ip           STRING  COMMENT 'Client IP address',
    http_method         STRING  COMMENT 'HTTP method: GET, POST, PUT, DELETE',
    url_path            STRING  COMMENT 'Requested URL path (no query string)',
    url_query           STRING  COMMENT 'URL query string (after ?)',
    http_protocol       STRING  COMMENT 'Protocol: HTTP/1.0 or HTTP/1.1',
    http_status         INT     COMMENT 'HTTP status code',
    response_bytes      BIGINT  COMMENT 'Response payload size in bytes',
    referrer            STRING  COMMENT 'Referrer URL (-  if direct)',
    user_agent          STRING  COMMENT 'Full User-Agent string',
    -- Derived time fields (much faster than parsing strings in queries)
    request_hour        INT     COMMENT 'Hour of request (0-23) for time-based aggregation',
    request_dow         INT     COMMENT 'Day of week (1=Sunday through 7=Saturday)',
    request_ts          TIMESTAMP COMMENT 'Full request timestamp'
)
COMMENT 'Processed web traffic data. Partitioned by date, bucketed by client_ip.
         Parsed from raw Apache CLF logs. ORC-compressed for optimal query speed.'
PARTITIONED BY (
    dt                  STRING  COMMENT 'Partition key: request date (YYYY-MM-DD)'
)
CLUSTERED BY (client_ip) INTO 32 BUCKETS
STORED AS ORC
LOCATION '/pipeline/processed/web_traffic'
TBLPROPERTIES (
    'orc.compress'              = 'ZLIB',
    'orc.stripe.size'           = '67108864',   -- 64MB stripes
    'orc.row.index.stride'      = '10000',      -- Row index every 10k rows
    'orc.bloom.filter.columns'  = 'http_status,http_method',  -- Fast filter for common predicates
    'transactional'             = 'false'        -- Read-only table (no ACID needed)
);

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- TABLE 2: sensor_readings
--
-- PARTITIONING: By date (dt) + zone
--   - Zone is a low-cardinality column (6 values: server_room, office, ...)
--   - Combining date + zone keeps partition count manageable
--   - HDFS path: /sensor_readings/dt=2024-01-15/zone=server_room/
--
-- BUCKETING: By device_id into 16 buckets
--   - device_id has 15 unique values → 16 buckets is appropriate
--   - Enables MB-JOIN with device_metadata bucketed on device_id
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CREATE TABLE IF NOT EXISTS sensor_readings (
    reading_id              BIGINT      COMMENT 'Unique reading ID',
    device_id               STRING      COMMENT 'Sensor device identifier',
    location                STRING      COMMENT 'Physical building',
    timestamp_ts            TIMESTAMP   COMMENT 'Parsed reading timestamp',
    temperature             DOUBLE      COMMENT 'Temperature in Celsius',
    humidity                DOUBLE      COMMENT 'Relative humidity (0-100%)',
    status                  STRING      COMMENT 'Reading status: OK, ANOMALY, MISSING',
    is_duplicate            BOOLEAN     COMMENT 'Duplicate packet flag',
    -- Derived quality flag
    data_quality_score      DOUBLE      COMMENT 'Quality score 0-1.0 (1.0 = perfect, 0 = missing/anomaly)'
)
COMMENT 'Cleaned and validated sensor readings. Partitioned by date and zone.
         Anomalies are retained (not filtered) — use WHERE status = OK for clean analysis.'
PARTITIONED BY (
    dt                      STRING  COMMENT 'Partition: reading date (YYYY-MM-DD)',
    zone                    STRING  COMMENT 'Partition: sensor zone type'
)
CLUSTERED BY (device_id) INTO 16 BUCKETS
STORED AS ORC
LOCATION '/pipeline/processed/sensor_readings'
TBLPROPERTIES (
    'orc.compress'              = 'ZLIB',
    'orc.bloom.filter.columns'  = 'device_id,status',
    'transactional'             = 'false'
);

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- TABLE 3: social_posts
--
-- PARTITIONING: By date (dt) + language
--   - Allows filtering by language without scanning all posts
--   - Useful for language-specific analytics without cross-product
--
-- Why NO bucketing for social_posts?
--   - Username-based bucketing would work but we primarily query
--     by hashtag (which requires LATERAL VIEW, not join)
--   - Partition pruning by dt already handles most filtering
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CREATE TABLE IF NOT EXISTS social_posts (
    tweet_id                BIGINT      COMMENT 'Unique post identifier',
    username                STRING      COMMENT 'Author username',
    user_type               STRING      COMMENT 'Tier: nano/micro/mid/macro/mega',
    followers               BIGINT      COMMENT 'Follower count at time of post',
    verified                BOOLEAN     COMMENT 'Account verification status',
    post_ts                 TIMESTAMP   COMMENT 'Post timestamp',
    post_text               STRING      COMMENT 'Post content (max 280 chars)',
    hashtags                STRING      COMMENT 'Space-separated hashtags (raw string)',
    hashtag_count           INT         COMMENT 'Number of hashtags in post',
    likes                   BIGINT      COMMENT 'Like count',
    retweets                BIGINT      COMMENT 'Share/retweet count',
    replies                 BIGINT      COMMENT 'Reply count',
    impressions             BIGINT      COMMENT 'Total impression count',
    engagement_rate         DOUBLE      COMMENT 'Engagement rate: (likes+retweets+replies)/impressions',
    source                  STRING      COMMENT 'Client application'
)
COMMENT 'Processed social media posts. Partitioned by date and language.
         Hashtags kept as raw string — use LATERAL VIEW explode(split(hashtags, " ")) to normalize.'
PARTITIONED BY (
    dt                      STRING  COMMENT 'Partition: post date (YYYY-MM-DD)',
    language                STRING  COMMENT 'Partition: language code (en, es, etc.)'
)
STORED AS ORC
LOCATION '/pipeline/processed/social_posts'
TBLPROPERTIES (
    'orc.compress'              = 'SNAPPY',   -- Snappy for lighter CPU load on social text
    'orc.bloom.filter.columns'  = 'username,user_type',
    'transactional'             = 'false'
);

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- TABLE 4: device_metadata (Dimension Table — NOT partitioned)
--
-- WHY NOT PARTITIONED?
--   - Only 15 rows → partitioning adds overhead, no benefit
--   - Small enough for Hive to broadcast as a MAP JOIN in any query
--   - This is a SLOWLY CHANGING DIMENSION (Type 1 in our case)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CREATE TABLE IF NOT EXISTS device_metadata (
    device_id               STRING  COMMENT 'Unique device identifier (PK)',
    device_name             STRING  COMMENT 'Human-readable name',
    model                   STRING  COMMENT 'Hardware model',
    firmware_version        STRING  COMMENT 'Firmware version',
    manufacturer            STRING  COMMENT 'Manufacturer',
    location                STRING  COMMENT 'Building location',
    `floor`                 STRING  COMMENT 'Floor level',
    zone                    STRING  COMMENT 'Zone type',
    latitude                DOUBLE  COMMENT 'GPS latitude',
    longitude               DOUBLE  COMMENT 'GPS longitude',
    install_date            DATE    COMMENT 'Installation date',
    last_maintenance        DATE    COMMENT 'Last maintenance/calibration',
    battery_level_pct       INT     COMMENT 'Battery % (NULL = grid-powered)',
    connectivity            STRING  COMMENT 'Network connectivity type',
    sampling_interval_sec   INT     COMMENT 'Seconds between readings',
    alert_temp_min          DOUBLE  COMMENT 'Minimum temperature alert threshold (°C)',
    alert_temp_max          DOUBLE  COMMENT 'Maximum temperature alert threshold (°C)',
    alert_humidity_min      DOUBLE  COMMENT 'Minimum humidity alert threshold (%)',
    alert_humidity_max      DOUBLE  COMMENT 'Maximum humidity alert threshold (%)',
    active                  BOOLEAN COMMENT 'Device active status',
    cost_center             STRING  COMMENT 'Cost center code',
    sla_tier                STRING  COMMENT 'Service level: GOLD/SILVER/BRONZE'
)
COMMENT 'Device registry dimension table. Not partitioned (15 rows, broadcast join candidate).
         Acts as the Type-1 SCD (Slowly Changing Dimension) for sensor devices.'
STORED AS ORC
LOCATION '/pipeline/processed/device_metadata'
TBLPROPERTIES (
    'orc.compress' = 'ZLIB'
);

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- TABLE 5: sensor_daily_summary (Pre-aggregated for GROUPING SETS queries)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CREATE TABLE IF NOT EXISTS sensor_daily_summary (
    device_id               STRING  COMMENT 'Sensor device ID',
    zone                    STRING  COMMENT 'Zone type',
    avg_temp                DOUBLE  COMMENT 'Average temperature for the day',
    min_temp                DOUBLE  COMMENT 'Minimum temperature for the day',
    max_temp                DOUBLE  COMMENT 'Maximum temperature for the day',
    avg_humidity            DOUBLE  COMMENT 'Average humidity for the day',
    total_readings          BIGINT  COMMENT 'Total number of readings',
    anomaly_count           BIGINT  COMMENT 'Count of readings with ANOMALY status',
    missing_count           BIGINT  COMMENT 'Count of readings with MISSING status'
)
COMMENT 'Daily aggregated sensor summary. Populated by ETL. Used for GROUPING SETS rollups.'
PARTITIONED BY (
    dt                      STRING  COMMENT 'Partition: summary date (YYYY-MM-DD)'
)
STORED AS ORC
TBLPROPERTIES ('orc.compress' = 'ZLIB');

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- TABLE 6: trending_hashtags_daily (Pre-aggregated hashtag counts)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

CREATE TABLE IF NOT EXISTS trending_hashtags_daily (
    hashtag                 STRING  COMMENT 'Hashtag string (including # prefix)',
    mention_count           BIGINT  COMMENT 'Times hashtag appeared across all posts',
    total_likes             BIGINT  COMMENT 'Sum of likes on posts with this hashtag',
    total_retweets          BIGINT  COMMENT 'Sum of retweets on posts with this hashtag',
    avg_engagement_rate     DOUBLE  COMMENT 'Average engagement rate for posts with this hashtag',
    first_seen              TIMESTAMP COMMENT 'Earliest post with this hashtag',
    last_seen               TIMESTAMP COMMENT 'Most recent post with this hashtag'
)
COMMENT 'Daily hashtag aggregation table. Source for Top-N trending hashtag queries.'
PARTITIONED BY (
    dt                      STRING  COMMENT 'Partition: aggregation date'
)
STORED AS ORC
TBLPROPERTIES ('orc.compress' = 'ZLIB');

-- Verify all processed tables were created
SHOW TABLES IN processed_db;

--
-- EXPECTED TABLES:
-- device_metadata
-- sensor_daily_summary
-- sensor_readings
-- social_posts
-- trending_hashtags_daily
-- web_traffic
--
