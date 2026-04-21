#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  DEFINITIVE FIX SCRIPT — Run once to fix everything        ║
# ║  Usage: bash scripts/fix_and_start.sh                      ║
# ╚══════════════════════════════════════════════════════════════╝
set -euo pipefail

# ─── Environment ─────────────────────────────────────────────────────────────
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export HADOOP_HOME=/opt/hadoop
export HIVE_HOME=/opt/hive
export HIVE_CONF_DIR=/opt/hive/conf
export HADOOP_CONF_DIR=$HADOOP_HOME/etc/hadoop
export PATH=$HIVE_HOME/bin:$HADOOP_HOME/bin:$HADOOP_HOME/sbin:/usr/local/bin:/usr/bin:/bin

PR="/mnt/c/Users/anubh/Anu's works/BDA/Mini project"
log() { echo "[$(date '+%H:%M:%S')] $*"; }
ok()  { echo "[$(date '+%H:%M:%S')] ✓ $*"; }
err() { echo "[$(date '+%H:%M:%S')] ✗ $*"; exit 1; }

log "━━━ STEP 1: Kill ALL Java processes ━━━"
pkill -f java 2>/dev/null || true
sleep 5
jps 2>/dev/null | grep -v Jps && { pkill -9 -f java 2>/dev/null; sleep 2; } || true
ok "All Java processes killed"

log "━━━ STEP 2: Deploy fixed config files ━━━"
echo "lenovo" | sudo -S cp "$PR/config/hive-site.xml" /opt/hive/conf/hive-site.xml
echo "lenovo" | sudo -S cp "$PR/config/hive-env.sh"   /opt/hive/conf/hive-env.sh
echo "lenovo" | sudo -S chmod 644 /opt/hive/conf/hive-site.xml
echo "lenovo" | sudo -S chmod 755 /opt/hive/conf/hive-env.sh
ok "Configs deployed"

log "━━━ STEP 3: Verify authorization fix in deployed config ━━━"
grep 'DefaultHiveAuthorizationProvider' /opt/hive/conf/hive-site.xml && ok "Java 11 fix confirmed in config" || err "Fix NOT in deployed config!"

log "━━━ STEP 4: Clean metastore DB (fresh init on Linux FS) ━━━"
rm -rf ~/hive_metastore_db 2>/dev/null || true
rm -rf "$PR/metastore_db" 2>/dev/null || true
rm -f  "$PR/derby.log" ~/derby.log 2>/dev/null || true

cd ~
schematool -dbType derby -initSchema 2>&1 | tail -3
ok "Metastore schema initialized at ~/hive_metastore_db"

log "━━━ STEP 5: Start HDFS ━━━"
cd "$PR"
start-dfs.sh 2>&1 | tail -5
sleep 6
hdfs dfs -ls / >/dev/null 2>&1 && ok "HDFS is online" || err "HDFS failed to start"

log "━━━ STEP 6: Start YARN ━━━"
start-yarn.sh 2>&1 | tail -4
sleep 5
ok "YARN started"

log "━━━ STEP 7: Create HDFS directories ━━━"
hdfs dfs -mkdir -p /user/hive/warehouse 2>/dev/null || true
hdfs dfs -chmod 777 /user/hive/warehouse 2>/dev/null || true
hdfs dfs -mkdir -p /user/"$(whoami)" 2>/dev/null || true
hdfs dfs -chmod 755 /user/"$(whoami)" 2>/dev/null || true
ok "HDFS directories ready"

log "━━━ STEP 8: Start Hive Metastore ━━━"
cd ~
nohup hive --service metastore > "$PR/metastore.log" 2>&1 &
log "   Waiting for metastore port 9083..."
for i in $(seq 1 40); do
    ss -tlnp 2>/dev/null | grep -q ':9083' && break
    sleep 2
done
ss -tlnp 2>/dev/null | grep -q ':9083' && ok "Metastore on port 9083" || err "Metastore failed — check $PR/metastore.log"

log "━━━ STEP 9: Start HiveServer2 ━━━"
# Source hive-env.sh so HADOOP_CLIENT_OPTS is set correctly in this shell too
source /opt/hive/conf/hive-env.sh 2>/dev/null || true
nohup hiveserver2 > "$PR/hive.log" 2>&1 &
log "   Waiting for HiveServer2 port 10000 (up to 90 seconds)..."
for i in $(seq 1 45); do
    ss -tlnp 2>/dev/null | grep -q ':10000' && break
    if [ $((i % 10)) -eq 0 ]; then
        log "   [$i/45] still waiting..."
        # Show last meaningful log line
        grep -i 'error\|starting\|started\|bound\|listening' /tmp/anubh/hive.log 2>/dev/null | tail -2 || true
    fi
    sleep 2
done

if ss -tlnp 2>/dev/null | grep -q ':10000'; then
    ok "HiveServer2 on port 10000!"
else
    echo ""
    echo "═══ HiveServer2 FAILED — Full log: ═══"
    tail -40 /tmp/anubh/hive.log 2>/dev/null
    err "HiveServer2 did not start. See log above."
fi

log "━━━ STEP 10: Test beeline connection ━━━"
beeline -u "jdbc:hive2://localhost:10000" -n "" \
    -e "SHOW DATABASES;" \
    --silent=false 2>&1 | grep -v SLF4J | grep -v 'Class path' | head -20

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║         ALL SERVICES UP — READY TO RUN          ║"
echo "╠══════════════════════════════════════════════════╣"
echo "║  HDFS NameNode:    http://localhost:9870         ║"
echo "║  YARN ResourceMgr: http://localhost:8088         ║"
echo "║  HiveServer2:      http://localhost:10002        ║"
echo "║  Beeline:          jdbc:hive2://localhost:10000  ║"
echo "╠══════════════════════════════════════════════════╣"
echo "║  Next:                                           ║"
echo "║  bash scripts/run_pipeline.sh --skip-data-gen   ║"
echo "╚══════════════════════════════════════════════════╝"
