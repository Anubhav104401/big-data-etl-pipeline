-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  02_raw_tables.hql — External Tables for Raw HDFS Data             ║
-- ║                                                                    ║
-- ║  Creates EXTERNAL tables in raw_db that provide a SQL interface    ║
-- ║  to the raw files uploaded to HDFS.                               ║
-- ║                                                                    ║
-- ║  CRITICAL DESIGN PRINCIPLES:                                       ║
-- ║    • EXTERNAL keyword = Hive won't delete data on DROP TABLE       ║
-- ║    • LOCATION = Points to HDFS directory (NOT a specific file)     ║
-- ║    • SerDe selection is determined by the file format              ║
-- ║    • Schema is imposed at READ time (Hive reads whatever is there) ║
-- ╚══════════════════════════════════════════════════════════════════════╝

USE raw_db;

-- ============================================================
-- TABLE 1: raw_web_logs
--
-- File format: Apache Combined Log Format (CLF)
-- Example line:
--   192.168.1.1 - - [01/Jan/2024:12:00:01 +0000] "GET /index.html HTTP/1.1" 200 4523 "-" "Mozilla/5.0..."
--
-- SerDe: org.apache.hadoop.hive.contrib.serde2.RegexSerDe
-- Why RegexSerDe?
--   Logs have a non-standard format that CSV/JSON SerDes can't parse.
--   The RegexSerDe lets us define a capturing regex to extract fields.
--   Each capture group () maps to one column in order.
-- ============================================================

CREATE EXTERNAL TABLE IF NOT EXISTS raw_web_logs (
    -- Column 1: IP address (capture group 1)
    client_ip           STRING  COMMENT 'Client IP address (IPv4)',

    -- Columns 2-3: RFC1413 ident and auth user — almost always "-" in practice
    -- We still capture them to stay faithful to the log format
    rfc_ident           STRING  COMMENT 'RFC 1413 identity (usually -)',
    auth_user           STRING  COMMENT 'Authenticated user (usually -)',

    -- Column 4: Timestamp including timezone
    -- Full format: [01/Jan/2024:12:00:01 +0000]
    raw_timestamp       STRING  COMMENT 'Request timestamp: [DD/Mon/YYYY:HH:MM:SS +TZ]',

    -- Column 5: First line of HTTP request: "GET /url HTTP/1.1"
    http_request        STRING  COMMENT 'Full HTTP request line: "METHOD URL PROTOCOL"',

    -- Column 6: HTTP status code
    http_status         INT     COMMENT 'HTTP response status code (200, 404, 500, etc.)',

    -- Column 7: Response size in bytes (- if no body)
    response_bytes      STRING  COMMENT 'Response size in bytes (-  if empty body)',

    -- Column 8: Referrer URL
    referrer            STRING  COMMENT 'HTTP Referer header (- if not provided)',

    -- Column 9: User-Agent string
    user_agent          STRING  COMMENT 'Client User-Agent header string'
)
COMMENT 'External table on raw Apache Combined Log Format access logs.
         Schema-on-read: data is not moved or transformed.
         DROP TABLE only removes Metastore entry, NOT the HDFS data.'
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.RegexSerDe'
WITH SERDEPROPERTIES (
    --
    -- REGEX BREAKDOWN for Apache Combined Log Format:
    -- ([^ ]*)            → Group 1: client_ip         (non-space chars)
    -- \s+([^ ]*)\s+      → Group 2: rfc_ident          (non-space)
    -- ([^ ]*)            → Group 3: auth_user           (non-space)
    -- \[([^\]]*)\]       → Group 4: raw_timestamp       (chars inside [])
    -- \"([^\"]*)\"       → Group 5: http_request        (chars inside "")
    -- ([^ ]*)            → Group 6: http_status         (non-space)
    -- ([^ ]*)            → Group 7: response_bytes      (non-space)
    -- \"([^\"]*)\"       → Group 8: referrer            (chars inside "")
    -- \"([^\"]*)\"       → Group 9: user_agent          (chars inside "")
    --
    "input.regex" = "([^ ]*)\\s+([^ ]*)\\s+([^ ]*)\\s+\\[([^\\]]*)\\]\\s+\"([^\"]*)\"\\s+([^ ]*)\\s+([^ ]*)\\s+\"([^\"]*)\"\\s+\"([^\"]*)\""
)
STORED AS TEXTFILE
LOCATION '/pipeline/raw/web_logs'
TBLPROPERTIES (
    'skip.header.line.count' = '0',    -- No header in access logs
    'serialization.null.format' = '-'  -- "-" in log = NULL
);

-- Verify: sample a few rows to check parsing
SELECT client_ip, raw_timestamp, http_request, http_status, response_bytes
FROM raw_web_logs
LIMIT 5;

-- ============================================================
-- TABLE 2: raw_sensor_readings
--
-- File format: CSV with header row
-- Example CSV row:
--   1,SENSOR-001,Building-A,server_room,2024-01-15 09:30:00,21.5,45.2,OK,false
--
-- SerDe: OpenCSVSerde
-- Why OpenCSVSerde?
--   Standard LazySimpleSerDe doesn't handle quoted CSV fields properly.
--   OpenCSVSerde correctly parses fields with embedded commas (e.g., text fields).
-- ============================================================

CREATE EXTERNAL TABLE IF NOT EXISTS raw_sensor_readings (
    reading_id      BIGINT  COMMENT 'Unique reading identifier (auto-generated)',
    device_id       STRING  COMMENT 'Sensor device ID (e.g., SENSOR-001)',
    location        STRING  COMMENT 'Physical building location',
    zone            STRING  COMMENT 'Zone type: server_room, office, warehouse, etc.',
    ts              STRING  COMMENT 'Reading timestamp: YYYY-MM-DD HH:MM:SS (stored as STRING, cast in processed layer)',
    temperature     DOUBLE  COMMENT 'Temperature reading in Celsius',
    humidity        DOUBLE  COMMENT 'Relative humidity in percent (0-100)',
    status          STRING  COMMENT 'Reading status: OK, ANOMALY, MISSING',
    is_duplicate    BOOLEAN COMMENT 'Flag for duplicate packet retransmissions'
)
COMMENT 'External table on raw IoT sensor readings CSV data.
         Anomalous and missing values are preserved as-is for audit purposes.'
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES (
    "separatorChar" = ",",
    "quoteChar"     = "\"",
    "escapeChar"    = "\\"
)
STORED AS TEXTFILE
LOCATION '/pipeline/raw/iot_sensors'
TBLPROPERTIES (
    'skip.header.line.count' = '1'   -- Skip the CSV header row
);

-- Verify: check for anomalies in raw data
SELECT status, COUNT(*) AS cnt
FROM raw_sensor_readings
GROUP BY status;

-- ============================================================
-- TABLE 3: raw_social_posts
--
-- File format: CSV with header row, quoted fields (text may contain commas)
-- Example CSV row:
--   1,"user_tech_00042","micro",2500,false,"2024-01-15 14:22:01",
--   "Just learned about HDFS #BigData #Hadoop ...","#BigData #Hadoop",45,12,3,300,"en","Twitter Web App"
-- ============================================================

CREATE EXTERNAL TABLE IF NOT EXISTS raw_social_posts (
    tweet_id        BIGINT  COMMENT 'Unique post identifier',
    username        STRING  COMMENT 'Author username',
    user_type       STRING  COMMENT 'User tier: nano, micro, mid, macro, mega',
    followers       BIGINT  COMMENT 'Number of followers',
    verified        BOOLEAN COMMENT 'Whether account is verified',
    ts              STRING  COMMENT 'Post timestamp: YYYY-MM-DD HH:MM:SS',
    post_text       STRING  COMMENT 'Post content (up to 280 characters)',
    hashtags        STRING  COMMENT 'Space-separated hashtag string for LATERAL VIEW',
    likes           BIGINT  COMMENT 'Number of likes/hearts',
    retweets        BIGINT  COMMENT 'Number of shares/retweets',
    replies         BIGINT  COMMENT 'Number of reply posts',
    impressions     BIGINT  COMMENT 'Estimated total views',
    language        STRING  COMMENT 'Language code (en, es, fr, etc.)',
    source          STRING  COMMENT 'Client that posted (e.g., Twitter for iPhone)'
)
COMMENT 'External table on raw social media post CSV data.
         Hashtags stored as space-separated string — use LATERAL VIEW explode() to normalize.'
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES (
    "separatorChar" = ",",
    "quoteChar"     = "\"",
    "escapeChar"    = "\\"
)
STORED AS TEXTFILE
LOCATION '/pipeline/raw/social_media'
TBLPROPERTIES (
    'skip.header.line.count' = '1'
);

-- Verify: check user type distribution
SELECT user_type, COUNT(*) AS post_count
FROM raw_social_posts
GROUP BY user_type
ORDER BY post_count DESC;

-- ============================================================
-- TABLE 4: raw_device_metadata
--
-- This is a DIMENSION TABLE — a small reference table joining to
-- sensor facts. Key for enriching sensor readings with device context.
-- ============================================================

CREATE EXTERNAL TABLE IF NOT EXISTS raw_device_metadata (
    device_id               STRING   COMMENT 'Unique device identifier (FK to sensor_readings)',
    device_name             STRING   COMMENT 'Human-readable device name',
    model                   STRING   COMMENT 'Sensor hardware model',
    firmware_version        STRING   COMMENT 'Current firmware/software version',
    manufacturer            STRING   COMMENT 'Sensor manufacturer',
    location                STRING   COMMENT 'Building location',
    `floor`                 STRING   COMMENT 'Floor/level (G=Ground, B1=Basement 1, etc.)',
    zone                    STRING   COMMENT 'Zone classification',
    latitude                DOUBLE   COMMENT 'GPS latitude',
    longitude               DOUBLE   COMMENT 'GPS longitude',
    install_date            STRING   COMMENT 'Installation date: YYYY-MM-DD',
    last_maintenance        STRING   COMMENT 'Last maintenance/calibration date: YYYY-MM-DD',
    battery_level_pct       STRING   COMMENT 'Battery percentage (empty if grid-powered)',
    connectivity            STRING   COMMENT 'Network type: Ethernet, WiFi, LoRaWAN, etc.',
    sampling_interval_sec   INT      COMMENT 'How often the device sends readings (seconds)',
    alert_temp_min          DOUBLE   COMMENT 'Lower threshold for temperature alerts',
    alert_temp_max          DOUBLE   COMMENT 'Upper threshold for temperature alerts',
    alert_humidity_min      DOUBLE   COMMENT 'Lower threshold for humidity alerts',
    alert_humidity_max      DOUBLE   COMMENT 'Upper threshold for humidity alerts',
    active                  BOOLEAN  COMMENT 'Whether device is currently active',
    cost_center             STRING   COMMENT 'Organizational cost center code',
    sla_tier                STRING   COMMENT 'SLA tier: GOLD (99.9%), SILVER (99.5%), BRONZE (99%)'
)
COMMENT 'External dimension table for IoT device metadata/registry.
         15 sensors across 8 buildings, 6 zone types, 3 SLA tiers.'
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
WITH SERDEPROPERTIES (
    "separatorChar" = ",",
    "quoteChar"     = "\"",
    "escapeChar"    = "\\"
)
STORED AS TEXTFILE
LOCATION '/pipeline/raw/device_metadata'
TBLPROPERTIES (
    'skip.header.line.count' = '1'
);

-- Verify: show all devices with their SLA tier
SELECT device_id, device_name, zone, sla_tier, connectivity
FROM raw_device_metadata
ORDER BY sla_tier DESC, zone, device_id;

-- ============================================================
-- Summary: Show all external tables
-- ============================================================
SHOW TABLES IN raw_db;

--
-- EXPECTED:
-- raw_device_metadata
-- raw_sensor_readings
-- raw_social_posts
-- raw_web_logs
--
