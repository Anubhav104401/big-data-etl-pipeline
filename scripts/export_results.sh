#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════╗
# ║  export_results.sh — Export Hive Query Results to Local CSV        ║
# ║                                                                    ║
# ║  Fetches aggregated results from HDFS output directories and       ║
# ║  writes them to local ./output/ directory for Tableau/Power BI.   ║
# ║                                                                    ║
# ║  For each result set:                                              ║
# ║    1. Run Hive INSERT OVERWRITE to /pipeline/output/<name>/        ║
# ║    2. HDFS get → merge part files into single CSV                 ║
# ║    3. Add CSV header                                               ║
# ║                                                                    ║
# ║  Usage: bash scripts/export_results.sh                            ║
# ╚══════════════════════════════════════════════════════════════════════╝

set -euo pipefail

# ─── Environment (required when run non-interactively — ~/.bashrc not sourced) ──
export JAVA_HOME="/usr/lib/jvm/java-8-openjdk-amd64"
export HADOOP_HOME="/opt/hadoop"
export HIVE_HOME="/opt/hive"
export HADOOP_CONF_DIR="$HADOOP_HOME/etc/hadoop"
export PATH="$HIVE_HOME/bin:$HADOOP_HOME/bin:$HADOOP_HOME/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
OUTPUT_LOCAL="$PROJECT_ROOT/output"
HDFS_OUTPUT="/pipeline/output"
BEELINE_URL="jdbc:hive2://localhost:10000"

log_info()    { echo "[$(date '+%H:%M:%S')] [INFO]  $*"; }
log_success() { echo "[$(date '+%H:%M:%S')] ✓ $*"; }
log_error()   { echo "[$(date '+%H:%M:%S')] ✗ ERROR: $*" >&2; exit 1; }

# Create local output directory
mkdir -p "$OUTPUT_LOCAL"

# ─── Helper: Export a Hive query result to CSV ──────────────────────────────
export_query_result() {
    local query="$1"          # The SELECT query to export
    local hdfs_dir="$2"       # HDFS output directory
    local local_file="$3"     # Local CSV output file
    local header="$4"         # CSV header line
    local description="$5"    # Human-readable description

    log_info "Exporting: $description"

    # Step 1: Run INSERT OVERWRITE to produce output files in HDFS
    # Hive produces multiple part-*.000 files (one per reducer)
    # We use CSV format (field terminated by ',', rows by '\n')
    local full_query="
        SET hive.exec.compress.output=false;
        INSERT OVERWRITE DIRECTORY '${hdfs_dir}'
        ROW FORMAT DELIMITED
        FIELDS TERMINATED BY ','
        LINES TERMINATED BY '\n'
        ${query};
    "

    beeline -u "$BEELINE_URL" -n "" -e "$full_query" --silent=true 2>&1
    log_info "  Hive query complete. Downloading from HDFS..."

    # Step 2: Merge all part files to a single local file
    local tmp_dir
    tmp_dir=$(mktemp -d)

    # hdfs dfs -get downloads all part files to temp directory
    hdfs dfs -get "${hdfs_dir}/*" "$tmp_dir/" 2>/dev/null || true

    # Step 3: Write CSV with header, concatenating all parts
    echo "$header" > "$local_file"
    cat "$tmp_dir"/part-* >> "$local_file" 2>/dev/null || true
    rm -rf "$tmp_dir"

    # Validate output
    local row_count
    row_count=$(wc -l < "$local_file")
    local file_size
    file_size=$(du -sh "$local_file" | cut -f1)

    log_success "Exported: $local_file ($((row_count-1)) data rows, $file_size)"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Export 1: Hourly Web Traffic Aggregation
# ═══════════════════════════════════════════════════════════════════════════════
log_info ""
log_info "=== Exporting hourly web traffic aggregation ==="

export_query_result \
    "SELECT
         request_hour,
         url_path,
         http_status,
         COUNT(*)                                     AS total_requests,
         SUM(response_bytes)                          AS total_bytes,
         COUNT(DISTINCT client_ip)                    AS unique_visitors,
         ROUND(AVG(response_bytes), 2)                AS avg_response_bytes
     FROM processed_db.web_traffic
     GROUP BY request_hour, url_path, http_status
     ORDER BY request_hour, total_requests DESC" \
    "${HDFS_OUTPUT}/hourly_traffic" \
    "${OUTPUT_LOCAL}/hourly_traffic.csv" \
    "request_hour,url_path,http_status,total_requests,total_bytes,unique_visitors,avg_response_bytes" \
    "Hourly web traffic by URL and status code"

# ═══════════════════════════════════════════════════════════════════════════════
# Export 2: Top 20 Trending Hashtags
# ═══════════════════════════════════════════════════════════════════════════════
log_info ""
log_info "=== Exporting trending hashtags ==="

export_query_result \
    "SELECT
         hashtag,
         mention_count,
         total_likes,
         total_retweets,
         avg_engagement_rate,
         first_seen,
         last_seen
     FROM processed_db.trending_hashtags_daily
     ORDER BY mention_count DESC
     LIMIT 20" \
    "${HDFS_OUTPUT}/trending_hashtags" \
    "${OUTPUT_LOCAL}/trending_hashtags.csv" \
    "hashtag,mention_count,total_likes,total_retweets,avg_engagement_rate,first_seen,last_seen" \
    "Top 20 trending hashtags"

# ═══════════════════════════════════════════════════════════════════════════════
# Export 3: Sensor Anomalies
# ═══════════════════════════════════════════════════════════════════════════════
log_info ""
log_info "=== Exporting sensor anomalies ==="

export_query_result \
    "SELECT
         sr.reading_id,
         sr.device_id,
         dm.device_name,
         dm.zone,
         dm.location,
         sr.timestamp_ts,
         sr.temperature,
         sr.humidity,
         sr.status,
         CASE
             WHEN sr.temperature > 100 THEN 'EXTREME_HIGH_TEMP'
             WHEN sr.temperature < -40 THEN 'EXTREME_LOW_TEMP'
             WHEN sr.humidity > 100    THEN 'INVALID_HUMIDITY_HIGH'
             WHEN sr.humidity < 0      THEN 'INVALID_HUMIDITY_LOW'
             ELSE 'ANOMALY'
         END AS anomaly_type
     FROM processed_db.sensor_readings sr
     INNER JOIN processed_db.device_metadata dm
         ON sr.device_id = dm.device_id
     WHERE sr.status = 'ANOMALY'
        OR sr.temperature > 100
        OR sr.temperature < -40
        OR sr.humidity > 100
        OR sr.humidity < 0
     ORDER BY sr.timestamp_ts DESC" \
    "${HDFS_OUTPUT}/sensor_anomalies" \
    "${OUTPUT_LOCAL}/sensor_anomalies.csv" \
    "reading_id,device_id,device_name,zone,location,timestamp,temperature,humidity,status,anomaly_type" \
    "Sensor anomalies with device context"

# ═══════════════════════════════════════════════════════════════════════════════
# Export 4: Daily Rollups (GROUPING SETS)
# ═══════════════════════════════════════════════════════════════════════════════
log_info ""
log_info "=== Exporting daily rollups ==="

export_query_result \
    "SELECT
         COALESCE(dt, 'ALL_DATES')       AS date_key,
         COALESCE(device_id, 'ALL')      AS device_key,
         COALESCE(zone, 'ALL_ZONES')     AS zone_key,
         ROUND(AVG(avg_temp), 2)         AS avg_temperature,
         ROUND(MIN(min_temp), 2)         AS min_temperature,
         ROUND(MAX(max_temp), 2)         AS max_temperature,
         SUM(total_readings)             AS total_readings,
         SUM(anomaly_count)              AS anomaly_count,
         ROUND(AVG(avg_humidity), 2)     AS avg_humidity
     FROM processed_db.sensor_daily_summary
     GROUP BY dt, device_id, zone
         GROUPING SETS (
             (dt, device_id, zone),   -- Finest grain: per day, per device, per zone
             (dt, zone),              -- Daily summary per zone
             (dt),                    -- Daily summary all zones
             ()                       -- Grand total
         )
     ORDER BY date_key, zone_key, device_key" \
    "${HDFS_OUTPUT}/daily_rollups" \
    "${OUTPUT_LOCAL}/daily_rollups.csv" \
    "date_key,device_key,zone_key,avg_temperature,min_temperature,max_temperature,total_readings,anomaly_count,avg_humidity" \
    "Daily/weekly rollups using GROUPING SETS"

# ═══════════════════════════════════════════════════════════════════════════════
# Export 5: Device + Sensor Join Summary
# ═══════════════════════════════════════════════════════════════════════════════
log_info ""
log_info "=== Exporting sensor-device joined summary ==="

export_query_result \
    "SELECT
         dm.device_id,
         dm.device_name,
         dm.manufacturer,
         dm.model,
         dm.zone,
         dm.location,
         dm.sla_tier,
         dm.alert_temp_min,
         dm.alert_temp_max,
         dm.connectivity,
         COUNT(sr.reading_id)                         AS total_readings,
         ROUND(AVG(sr.temperature), 2)                AS avg_temp,
         ROUND(MIN(sr.temperature), 2)                AS min_temp,
         ROUND(MAX(sr.temperature), 2)                AS max_temp,
         ROUND(AVG(sr.humidity), 2)                   AS avg_humidity,
         SUM(CASE WHEN sr.status = 'ANOMALY' THEN 1 ELSE 0 END) AS anomaly_count,
         SUM(CASE WHEN sr.status = 'MISSING' THEN 1 ELSE 0 END) AS missing_count
     FROM processed_db.device_metadata dm
     LEFT JOIN processed_db.sensor_readings sr
         ON dm.device_id = sr.device_id
     GROUP BY
         dm.device_id, dm.device_name, dm.manufacturer, dm.model,
         dm.zone, dm.location, dm.sla_tier, dm.alert_temp_min,
         dm.alert_temp_max, dm.connectivity
     ORDER BY dm.location, dm.zone, dm.device_id" \
    "${HDFS_OUTPUT}/sensor_device_joined" \
    "${OUTPUT_LOCAL}/sensor_device_summary.csv" \
    "device_id,device_name,manufacturer,model,zone,location,sla_tier,alert_temp_min,alert_temp_max,connectivity,total_readings,avg_temp,min_temp,max_temp,avg_humidity,anomaly_count,missing_count" \
    "Sensor readings joined with device metadata"

# ═══════════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════════
log_info ""
log_info "=== Export Summary ==="
ls -lh "$OUTPUT_LOCAL"/*.csv 2>/dev/null | awk '{print "  " $NF " (" $5 ")"}'
log_success "All results exported to: $OUTPUT_LOCAL/"
log_info ""
log_info "To connect to HiveServer2 from BI tools:"
log_info "  JDBC URL:  jdbc:hive2://localhost:10000/processed_db"
log_info "  ODBC DSN:  Configure via Cloudera/HortonWorks ODBC driver"
log_info ""
log_info "To browse HDFS output directly:"
log_info "  hdfs dfs -ls /pipeline/output/"
