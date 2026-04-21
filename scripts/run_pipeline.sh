#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════╗
# ║  run_pipeline.sh — Master Pipeline Orchestration Script            ║
# ║                                                                    ║
# ║  Runs the complete Big Data Pipeline end-to-end:                  ║
# ║    1. Generate sample data                                         ║
# ║    2. Start Hadoop & Hive services                                 ║
# ║    3. Set up HDFS directories and upload data                      ║
# ║    4. Execute HiveQL scripts (DDL + ETL + Analytics)               ║
# ║    5. Export results to CSV for BI tools                           ║
# ║                                                                    ║
# ║  Usage: bash scripts/run_pipeline.sh [--skip-data-gen]            ║
# ╚══════════════════════════════════════════════════════════════════════╝

set -euo pipefail

# ─── Load Environment Variables (works in both interactive & non-interactive) ─
# When run as 'bash script.sh', ~/.bashrc is NOT sourced automatically.
# We must set these explicitly so JAVA_HOME, HADOOP_HOME, HIVE_HOME are available.
export JAVA_HOME="/usr/lib/jvm/java-11-openjdk-amd64"
export HADOOP_HOME="/opt/hadoop"
export HIVE_HOME="/opt/hive"
export HADOOP_CONF_DIR="$HADOOP_HOME/etc/hadoop"
export HADOOP_MAPRED_HOME="$HADOOP_HOME"
export HADOOP_COMMON_HOME="$HADOOP_HOME"
export HADOOP_HDFS_HOME="$HADOOP_HOME"
export YARN_HOME="$HADOOP_HOME"
export PATH="$HIVE_HOME/bin:$HADOOP_HOME/bin:$HADOOP_HOME/sbin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# ─── Variables ──────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
HIVE_SCRIPTS="$PROJECT_ROOT/hive"
DATA_GEN_DIR="$SCRIPT_DIR/data_generators"

# Beeline JDBC URL — connects to HiveServer2
BEELINE_URL="jdbc:hive2://localhost:10000"

# Pipeline stage timing
PIPELINE_START=$(date '+%s')
SKIP_DATA_GEN=false

# Parse arguments
for arg in "$@"; do
    case $arg in
        --skip-data-gen) SKIP_DATA_GEN=true ;;
        --help)
            echo "Usage: $0 [--skip-data-gen]"
            echo "  --skip-data-gen  Skip data generation (use existing sample files)"
            exit 0
            ;;
    esac
done

# ─── Logging ────────────────────────────────────────────────────────────────
LOG_FILE="$PROJECT_ROOT/pipeline_$(date '+%Y%m%d_%H%M%S').log"
exec > >(tee -a "$LOG_FILE") 2>&1   # All output goes to both terminal and log file

log_stage() {
    echo ""
    echo "╔════════════════════════════════════════════════════════════╗"
    printf "║  %-56s  ║\n" "$*"
    echo "╚════════════════════════════════════════════════════════════╝"
    echo ""
}

log_info()    { echo "[$(date '+%H:%M:%S')] [INFO]  $*"; }
log_success() { echo "[$(date '+%H:%M:%S')] ✓ $*"; }
log_warn()    { echo "[$(date '+%H:%M:%S')] ⚠ $*" >&2; }
log_error()   { echo "[$(date '+%H:%M:%S')] ✗ ERROR: $*" >&2; exit 1; }

elapsed() {
    local now end diff
    now=$(date '+%s')
    diff=$((now - PIPELINE_START))
    printf "%02d:%02d" $((diff/60)) $((diff%60))
}

# ─── Helper: Run Beeline query ───────────────────────────────────────────────
run_hive_script() {
    local script_file="$1"
    local description="${2:-$script_file}"

    if [ ! -f "$script_file" ]; then
        log_error "HiveQL script not found: $script_file"
    fi

    log_info "Executing: $description"
    log_info "  File: $script_file"

    # beeline options:
    #   -u: JDBC URL
    #   -n: Username (for NONE auth mode)
    #   -f: Execute script file
    #   --hiveconf: Pass Hive settings
    #   --silent=false: Show progress
    #   --fastConnect=false: Ensure full JDBC handshake
    beeline \
        -u "${BEELINE_URL}" \
        -n "" \
        -f "${script_file}" \
        --silent=false \
        2>&1

    local exit_code=$?
    if [ $exit_code -eq 0 ]; then
        log_success "Completed: $description (elapsed: $(elapsed))"
    else
        log_error "Failed: $description (exit code: $exit_code)"
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# STAGE 1: Generate Sample Data
# ═══════════════════════════════════════════════════════════════════════════════
log_stage "STAGE 1: Data Generation"

if [ "$SKIP_DATA_GEN" = true ]; then
    log_info "Skipping data generation (--skip-data-gen flag set)"
else
    log_info "Generating Apache web server logs (50,000 entries)..."
    python3 "$DATA_GEN_DIR/generate_web_logs.py" --rows 50000

    log_info "Generating IoT sensor readings (100,000 entries)..."
    python3 "$DATA_GEN_DIR/generate_iot_data.py" --rows 100000

    log_info "Generating social media posts (30,000 entries)..."
    python3 "$DATA_GEN_DIR/generate_social_media.py" --rows 30000

    log_info "Generating device metadata (15 devices)..."
    python3 "$DATA_GEN_DIR/generate_device_metadata.py"

    log_success "All sample data generated (elapsed: $(elapsed))"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# STAGE 2: Start Hadoop & Hive Services
# ═══════════════════════════════════════════════════════════════════════════════
log_stage "STAGE 2: Starting Hadoop Services"

log_info "Checking if NameNode is already running..."
if hdfs dfs -ls / >/dev/null 2>&1; then
    log_info "HDFS already running — skipping start"
else
    log_info "Starting HDFS daemons (NameNode, DataNode, SecondaryNameNode)..."
    start-dfs.sh

    # Wait for DataNode to register and exit safe mode
    log_info "Waiting for HDFS to exit safe mode..."
    retries=0
    until hdfs dfsadmin -safemode get | grep -q "Safe mode is OFF"; do
        retries=$((retries+1))
        if [ $retries -gt 30 ]; then
            log_error "HDFS did not exit safe mode after 60 seconds"
        fi
        log_info "  Waiting for safe mode exit... ($retries/30)"
        sleep 2
    done
    log_success "HDFS is ready"
fi

log_info "Checking if YARN ResourceManager is already running..."
if jps 2>/dev/null | grep -q 'ResourceManager'; then
    log_info "YARN already running — skipping start"
else
    log_info "Starting YARN daemons (ResourceManager, NodeManager)..."
    start-yarn.sh
    sleep 5
    log_success "YARN started"
fi

# Check and start Hive Metastore (required before HiveServer2)
log_info "Checking Hive Metastore service..."
if ss -tlnp 2>/dev/null | grep -q ':9083'; then
    log_info "Hive Metastore already running on port 9083 — skipping start"
else
    log_info "Starting Hive Metastore in background (this may take ~25 seconds)..."
    # IMPORTANT: Run from ~ (home dir) so Derby db is on Linux filesystem, not /mnt/c
    (cd ~ && nohup hive --service metastore > "$PROJECT_ROOT/metastore.log" 2>&1 &)
    log_info "  Waiting for metastore to bind port 9083..."
    ms_retries=0
    until ss -tlnp 2>/dev/null | grep -q ':9083'; do
        ms_retries=$((ms_retries+1))
        if [ $ms_retries -gt 30 ]; then
            log_error "Metastore did not bind port 9083 after 60s. Check $PROJECT_ROOT/metastore.log"
        fi
        sleep 2
    done
    log_success "Hive Metastore is listening on port 9083"
fi

# Check HiveServer2
log_info "Checking HiveServer2..."
if ss -tlnp 2>/dev/null | grep -q ':10000'; then
    log_info "HiveServer2 already running on port 10000 — skipping start"
else
    log_info "Starting HiveServer2 in background..."
    # IMPORTANT: Run from ~ to avoid Derby/path issues
    (cd ~ && nohup hiveserver2 > "$PROJECT_ROOT/hive.log" 2>&1 &)
    log_info "  Waiting for HiveServer2 to bind port 10000 (may take 30-60s)..."
    hs2_retries=0
    until ss -tlnp 2>/dev/null | grep -q ':10000'; do
        hs2_retries=$((hs2_retries+1))
        if [ $hs2_retries -gt 60 ]; then
            log_error "HiveServer2 did not bind port 10000 after 120s. Last log:"; tail -20 "$PROJECT_ROOT/hive.log"
        fi
        if [ $((hs2_retries % 5)) -eq 0 ]; then
            log_info "  Still waiting... ($hs2_retries/60)"
        fi
        sleep 2
    done
    log_success "HiveServer2 is listening on port 10000"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# STAGE 3: HDFS Setup
# ═══════════════════════════════════════════════════════════════════════════════
log_stage "STAGE 3: HDFS Directory Setup & Data Upload"

bash "$SCRIPT_DIR/hdfs_setup.sh"
log_success "HDFS setup complete (elapsed: $(elapsed))"

# ═══════════════════════════════════════════════════════════════════════════════
# STAGE 4: Hive DDL — Create Databases & Tables
# ═══════════════════════════════════════════════════════════════════════════════
log_stage "STAGE 4: Hive DDL — Databases & External Tables"

run_hive_script "$HIVE_SCRIPTS/01_create_databases.hql" \
    "Create databases (raw_db, processed_db)"

run_hive_script "$HIVE_SCRIPTS/02_raw_tables.hql" \
    "Create external tables on raw HDFS data"

run_hive_script "$HIVE_SCRIPTS/03_optimized_tables.hql" \
    "Create partitioned ORC tables in processed_db"

# ═══════════════════════════════════════════════════════════════════════════════
# STAGE 5: ETL — Load & Transform Raw → Processed
# ═══════════════════════════════════════════════════════════════════════════════
log_stage "STAGE 5: ETL — Raw to Processed (ORC)"

log_info "Collecting statistics before ETL..."
beeline -u "$BEELINE_URL" -n "" -e "
    ANALYZE TABLE raw_db.raw_web_logs COMPUTE STATISTICS;
    ANALYZE TABLE raw_db.raw_sensor_readings COMPUTE STATISTICS;
    ANALYZE TABLE raw_db.raw_social_posts COMPUTE STATISTICS;
" 2>&1

run_hive_script "$HIVE_SCRIPTS/04_etl_transforms.hql" \
    "ETL: Load raw data into partitioned ORC tables"

# ═══════════════════════════════════════════════════════════════════════════════
# STAGE 6: Analytics — Run Queries
# ═══════════════════════════════════════════════════════════════════════════════
log_stage "STAGE 6: Analytics Queries"

run_hive_script "$HIVE_SCRIPTS/05_analytics_queries.hql" \
    "Run analytics queries (anomaly detection, traffic analysis, hashtags, joins, rollups)"

# ═══════════════════════════════════════════════════════════════════════════════
# STAGE 7: Export Results
# ═══════════════════════════════════════════════════════════════════════════════
log_stage "STAGE 7: Export Results to CSV"

bash "$SCRIPT_DIR/export_results.sh"
log_success "Results exported (elapsed: $(elapsed))"

# ═══════════════════════════════════════════════════════════════════════════════
# PIPELINE COMPLETE
# ═══════════════════════════════════════════════════════════════════════════════
PIPELINE_END=$(date '+%s')
TOTAL_SECONDS=$((PIPELINE_END - PIPELINE_START))

log_info ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║           PIPELINE COMPLETED SUCCESSFULLY                  ║"
echo "╠════════════════════════════════════════════════════════════╣"
printf "║  Total elapsed time: %02d:%02d                               ║\n" $((TOTAL_SECONDS/60)) $((TOTAL_SECONDS%60))
echo "║  Log file: $(basename $LOG_FILE)                    ║"
echo "╠════════════════════════════════════════════════════════════╣"
echo "║  Web UIs:                                                  ║"
echo "║    • HDFS NameNode:      http://localhost:9870              ║"
echo "║    • YARN ResourceMgr:   http://localhost:8088              ║"
echo "║    • HiveServer2:        http://localhost:10002             ║"
echo "╠════════════════════════════════════════════════════════════╣"
echo "║  Output CSVs:            ./output/                         ║"
echo "╚════════════════════════════════════════════════════════════╝"
