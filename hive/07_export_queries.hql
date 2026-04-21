-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  07_export_queries.hql — Export Queries for BI Tool Integration    ║
-- ║                                                                    ║
-- ║  Produces CSV-ready result sets for Tableau / Power BI.           ║
-- ║  These queries are designed for readability and direct export.    ║
-- ║                                                                    ║
-- ║  Two integration methods:                                          ║
-- ║    Method A: JDBC/ODBC live connection from BI tool → HiveServer2 ║
-- ║    Method B: CSV export → import into BI tool                     ║
-- ║                                                                    ║
-- ║  For Method A: Run these queries directly in Tableau/Power BI     ║
-- ║  For Method B: export_results.sh wraps these in INSERT OVERWRITE  ║
-- ╚══════════════════════════════════════════════════════════════════════╝

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- CONNECTING TABLEAU / POWER BI TO HIVESERVER2
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- JDBC Connection URL:
--   jdbc:hive2://localhost:10000/processed_db
--   Authentication: NONE (dev) or LDAP/Kerberos (prod)
--   Driver: org.apache.hive.jdbc.HiveDriver (from hive-jdbc-*.jar)

-- ODBC Connection (Tableau preferred):
--   Install: Cloudera Hive ODBC Driver 2.7.x
--   DSN settings:
--     Host:     localhost
--     Port:     10000
--     Database: processed_db
--     Auth:     No Authentication (dev)
--     HTTP Mode: TCP (for direct Thrift)

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- DASHBOARD 1 DATA: Web Traffic Analysis
-- Suggested charts:
--   a) Line chart: Requests by hour (x=hour, y=requests, color=status_class)
--   b) Heatmap: Traffic by hour × day_of_week (color=intensity)
--   c) Bar chart: Top 15 pages by request count
--   d) Pie chart: HTTP status distribution (2xx/3xx/4xx/5xx)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

USE processed_db;

-- Export: Hourly traffic with status class
SELECT
    dt                                                      AS date,
    request_hour                                            AS hour_of_day,
    request_dow                                             AS day_of_week,
    CASE request_dow
        WHEN 1 THEN 'Sunday' WHEN 2 THEN 'Monday'  WHEN 3 THEN 'Tuesday'
        WHEN 4 THEN 'Wednesday' WHEN 5 THEN 'Thursday'
        WHEN 6 THEN 'Friday' WHEN 7 THEN 'Saturday'
    END                                                     AS day_name,
    CASE
        WHEN http_status BETWEEN 200 AND 299 THEN '2xx Success'
        WHEN http_status BETWEEN 300 AND 399 THEN '3xx Redirect'
        WHEN http_status BETWEEN 400 AND 499 THEN '4xx Client Error'
        WHEN http_status BETWEEN 500 AND 599 THEN '5xx Server Error'
        ELSE 'Unknown'
    END                                                     AS status_class,
    http_method,
    url_path,
    COUNT(*)                                                AS request_count,
    COUNT(DISTINCT client_ip)                               AS unique_visitors,
    SUM(response_bytes)                                     AS total_bytes_mb,
    ROUND(AVG(response_bytes) / 1024.0, 2)                 AS avg_response_kb
FROM web_traffic
GROUP BY
    dt, request_hour, request_dow, http_status, http_method, url_path
ORDER BY dt, request_hour, request_count DESC;

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- DASHBOARD 2 DATA: IoT Sensor Monitoring
-- Suggested charts:
--   a) Multi-line: Avg temp over time per device
--   b) Gauge/KPI: Current status of each sensor
--   c) Scatter: Temp vs humidity colored by anomaly
--   d) Geographic: Sensor location map with color = avg_temp
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- Export: Time series data for sensor dashboards
SELECT
    sr.dt                                                   AS reading_date,
    sr.device_id,
    dm.device_name,
    dm.zone,
    dm.location,
    dm.floor,
    dm.manufacturer,
    dm.model,
    dm.sla_tier,
    dm.alert_temp_min,
    dm.alert_temp_max,
    dm.connectivity,
    dm.latitude,
    dm.longitude,
    ROUND(AVG(sr.temperature), 2)                           AS avg_temperature_c,
    ROUND(MIN(sr.temperature), 2)                           AS min_temperature_c,
    ROUND(MAX(sr.temperature), 2)                           AS max_temperature_c,
    -- Convert Celsius to Fahrenheit for dashboards targeting US audience
    ROUND(AVG(sr.temperature) * 9.0/5.0 + 32, 2)           AS avg_temperature_f,
    ROUND(AVG(sr.humidity), 2)                              AS avg_humidity_pct,
    COUNT(sr.reading_id)                                    AS reading_count,
    SUM(CASE WHEN sr.status = 'ANOMALY' THEN 1 ELSE 0 END) AS anomaly_count,
    SUM(CASE WHEN sr.status = 'MISSING' THEN 1 ELSE 0 END) AS missing_count,
    ROUND(AVG(sr.data_quality_score) * 100, 1)              AS quality_score_pct,
    -- Threshold breach flag for alerting in dashboards
    CASE
        WHEN MAX(sr.temperature) > dm.alert_temp_max THEN 'HIGH_TEMP_BREACH'
        WHEN MIN(sr.temperature) < dm.alert_temp_min THEN 'LOW_TEMP_BREACH'
        WHEN AVG(sr.data_quality_score) < 0.8        THEN 'LOW_QUALITY'
        ELSE 'NORMAL'
    END                                                     AS daily_status
FROM sensor_readings sr
INNER JOIN device_metadata dm ON sr.device_id = dm.device_id
WHERE sr.temperature IS NOT NULL
GROUP BY
    sr.dt, sr.device_id, dm.device_name, dm.zone, dm.location, dm.floor,
    dm.manufacturer, dm.model, dm.sla_tier, dm.alert_temp_min, dm.alert_temp_max,
    dm.connectivity, dm.latitude, dm.longitude
ORDER BY sr.dt, dm.zone, sr.device_id;

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- DASHBOARD 3 DATA: Social Media Analytics
-- Suggested charts:
--   a) Horizontal bar: Top 20 hashtags by total mentions
--   b) Area chart: Cumulative likes + retweets over time
--   c) Bubble chart: Users (x=followers, y=engagement_rate, size=posts)
--   d) Stacked bar: Posts by user_type per day
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- Export: Hashtag trends for BI
SELECT
    th.dt                                                   AS trend_date,
    th.hashtag,
    th.mention_count,
    th.total_likes,
    th.total_retweets,
    ROUND(th.avg_engagement_rate * 100, 4)                  AS avg_engagement_pct,
    -- Rank hashtag by mentions within each day partition
    RANK() OVER (PARTITION BY th.dt ORDER BY th.mention_count DESC) AS daily_rank,
    -- Overall rank across all dates
    RANK() OVER (ORDER BY SUM(th.mention_count)
                          OVER (PARTITION BY th.hashtag) DESC)      AS overall_rank,
    -- 7-day rolling sum of mentions (sparkline data)
    SUM(th.mention_count) OVER (
        PARTITION BY th.hashtag
        ORDER BY th.dt
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW  -- 7-day window
    )                                                       AS rolling_7d_mentions
FROM trending_hashtags_daily th
ORDER BY th.dt, th.mention_count DESC;

-- Export: User engagement summary
SELECT
    user_type,
    dt,
    COUNT(DISTINCT username)                                AS unique_users,
    COUNT(tweet_id)                                         AS total_posts,
    SUM(likes)                                              AS total_likes,
    SUM(retweets)                                           AS total_retweets,
    SUM(impressions)                                        AS total_impressions,
    ROUND(AVG(engagement_rate) * 100, 4)                    AS avg_engagement_pct,
    ROUND(AVG(followers), 0)                                AS avg_followers,
    -- Posts per user
    ROUND(COUNT(tweet_id) * 1.0 / COUNT(DISTINCT username), 2) AS posts_per_user,
    -- Average hashtags per post
    ROUND(AVG(hashtag_count), 2)                            AS avg_hashtags_per_post
FROM social_posts
GROUP BY user_type, dt
ORDER BY dt, user_type;

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- DASHBOARD 4 DATA: Executive Summary / Cross-Source Rollup
-- Suggested charts:
--   a) KPI cards: Total reads, anomaly rate, top hashtag, peak traffic hour
--   b) Multi-axis line: Web requests + sensor anomalies on same timeline
--   c) Table: Device SLA compliance report
--   d) Treemap: Data volume by source (web, IoT, social)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- Executive KPI summary (one row per date per data source)
SELECT
    dt,
    'web_traffic'       AS data_source,
    COUNT(*)            AS record_count,
    0                   AS anomaly_count,
    0.0                 AS anomaly_rate_pct,
    SUM(response_bytes) AS total_data_bytes
FROM web_traffic
GROUP BY dt

UNION ALL

SELECT
    dt,
    'iot_sensors'       AS data_source,
    SUM(total_readings) AS record_count,
    SUM(anomaly_count)  AS anomaly_count,
    ROUND(SUM(anomaly_count) * 100.0 / GREATEST(SUM(total_readings), 1), 3) AS anomaly_rate_pct,
    0                   AS total_data_bytes
FROM sensor_daily_summary
GROUP BY dt

UNION ALL

SELECT
    dt,
    'social_media'      AS data_source,
    COUNT(tweet_id)     AS record_count,
    0                   AS anomaly_count,
    0.0                 AS anomaly_rate_pct,
    0                   AS total_data_bytes
FROM social_posts
GROUP BY dt

ORDER BY dt, data_source;

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- CSV EXPORT VIA BEELINE CLI
-- Run these commands in your terminal to get CSV files directly
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

--
-- Export to CSV from Beeline:
--
--   beeline -u jdbc:hive2://localhost:10000/processed_db \
--     --outputformat=csv2 \
--     --silent=true \
--     -e "SELECT ... FROM web_traffic LIMIT 100000;" \
--     > output/web_traffic_export.csv
--
-- Options:
--   --outputformat=csv2      Clean CSV with proper quoting
--   --outputformat=tsv2      Tab-separated (good for Excel direct import)
--   --outputformat=table     Pretty-printed table (good for terminal viewing)
--   --maxWidth=500           Prevent column truncation
--   --silent=true            Suppress Beeline info messages (cleaner CSV)
--
-- Example commands:
--
--   # Trending hashtags → CSV
--   beeline -u jdbc:hive2://localhost:10000/processed_db \
--     --outputformat=csv2 --silent=true \
--     -e "SELECT hashtag, SUM(mention_count) AS mentions FROM trending_hashtags_daily GROUP BY hashtag ORDER BY mentions DESC LIMIT 50;" \
--     > output/trending_hashtags.csv
--
--   # Sensor anomalies → TSV (for Excel)
--   beeline -u jdbc:hive2://localhost:10000/processed_db \
--     --outputformat=tsv2 --silent=true \
--     -e "SELECT * FROM sensor_readings WHERE status='ANOMALY' LIMIT 10000;" \
--     > output/sensor_anomalies.tsv
--
