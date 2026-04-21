#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════════╗
# ║  reset_and_start.sh — Full environment reset + Hive startup        ║
# ║  Run this ONCE to fix all configuration issues.                    ║
# ║  Usage: bash scripts/reset_and_start.sh                            ║
# ╚══════════════════════════════════════════════════════════════════════╝

set -euo pipefail

# ─── Environment ────────────────────────────────────────────────────────────
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export HADOOP_HOME=/opt/hadoop
export HIVE_HOME=/opt/hive
export HIVE_CONF_DIR=/opt/hive/conf
export HADOOP_CONF_DIR=$HADOOP_HOME/etc/hadoop
export PATH=$HIVE_HOME/bin:$HADOOP_HOME/bin:$HADOOP_HOME/sbin:/usr/local/bin:/usr/bin:/bin

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() { echo "[$(date '+%H:%M:%S')] $*"; }

log "=== STEP 1: Kill all existing Java processes ==="
pkill -f java 2>/dev/null || true
sleep 4
log "  Done."

log "=== STEP 2: Copy config files to Hive conf dir ==="
sudo cp "$PROJECT_ROOT/config/hive-site.xml" /opt/hive/conf/hive-site.xml
sudo cp "$PROJECT_ROOT/config/hive-env.sh"   /opt/hive/conf/hive-env.sh
sudo chmod 644 /opt/hive/conf/hive-site.xml
sudo chmod 755 /opt/hive/conf/hive-env.sh
log "  Copied hive-site.xml and hive-env.sh"

log "=== STEP 3: Remove old Derby metastore (Windows NTFS — causes lock failures) ==="
rm -rf "$PROJECT_ROOT/metastore_db" 2>/dev/null || true
rm -f  "$PROJECT_ROOT/derby.log"    2>/dev/null || true
log "  Removed old metastore_db"

log "=== STEP 4: Re-init metastore schema on Linux native filesystem ==="
log "  Location: /home/$USER/hive_metastore_db  (Linux ext4 — no lock issues)"
# Change to home dir so schematool writes derby.log there, not to /mnt/c
cd ~
schematool -dbType derby -initSchema 2>&1 | tail -3
cd "$PROJECT_ROOT"
log "  Schema initialized."

log "=== STEP 5: Start HDFS ==="
start-dfs.sh
sleep 5
log "  HDFS started."

log "=== STEP 6: Start YARN ==="
start-yarn.sh
sleep 5
log "  YARN started."

log "=== STEP 7: Create HDFS warehouse directory ==="
hdfs dfs -mkdir -p /user/hive/warehouse 2>/dev/null || true
hdfs dfs -chmod 777 /user/hive/warehouse 2>/dev/null || true
log "  /user/hive/warehouse ready."

log "=== STEP 8: Start Hive Metastore (standalone, port 9083) ==="
cd ~   # Run from home dir to avoid Derby path issues with spaces
nohup hive --service metastore > "$PROJECT_ROOT/metastore.log" 2>&1 &
METASTORE_PID=$!
log "  Metastore PID: $METASTORE_PID — waiting 25s for it to bind port 9083..."
sleep 25

# Check metastore actually bound
if ss -tlnp 2>/dev/null | grep -q ':9083'; then
    log "  ✓ Metastore is listening on port 9083"
else
    log "  ✗ ERROR: Metastore failed to bind port 9083. Check metastore.log"
    tail -30 "$PROJECT_ROOT/metastore.log"
    exit 1
fi

cd "$PROJECT_ROOT"

log "=== STEP 9: Start HiveServer2 (port 10000) ==="
cd ~   # Run from home dir
nohup hiveserver2 > "$PROJECT_ROOT/hive.log" 2>&1 &
HS2_PID=$!
log "  HiveServer2 PID: $HS2_PID — waiting up to 60s..."
cd "$PROJECT_ROOT"

# Wait for port 10000 to open
retries=0
until ss -tlnp 2>/dev/null | grep -q ':10000'; do
    retries=$((retries + 1))
    if [ $retries -gt 30 ]; then
        log "  ✗ HiveServer2 did not bind port 10000 after 60s."
        log "  Last 30 lines of hive.log:"
        tail -30 "$PROJECT_ROOT/hive.log"
        exit 1
    fi
    log "  Waiting for port 10000... ($retries/30)"
    sleep 2
done
log "  ✓ HiveServer2 is listening on port 10000!"

log "=== STEP 10: Verify beeline connection ==="
beeline -u "jdbc:hive2://localhost:10000" -n "" -e "SHOW DATABASES;" 2>&1 | grep -v SLF4J | grep -v 'Class path' || true

log ""
log "======================================================"
log "  ✓ ALL SERVICES READY!"
log "    HDFS NameNode:    http://localhost:9870"
log "    YARN ResourceMgr: http://localhost:8088"
log "    HiveServer2:      http://localhost:10002"
log "    Beeline URL:      jdbc:hive2://localhost:10000"
log "======================================================"
log ""
log "  Now run the pipeline:"
log "    bash scripts/run_pipeline.sh --skip-data-gen"
