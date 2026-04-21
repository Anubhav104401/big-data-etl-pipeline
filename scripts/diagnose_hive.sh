#!/usr/bin/env bash
# Hive Diagnostic Script — run: bash scripts/diagnose_hive.sh

echo "============ ENVIRONMENT VARIABLES ============"
echo "JAVA_HOME        = $JAVA_HOME"
echo "HADOOP_HOME      = $HADOOP_HOME"
echo "HIVE_HOME        = $HIVE_HOME"
echo "HIVE_CONF_DIR    = $HIVE_CONF_DIR"
echo "HADOOP_CONF_DIR  = $HADOOP_CONF_DIR"
echo "PATH             = $PATH"
echo ""

echo "============ JAVA VERSION ============"
java -version 2>&1
echo ""

echo "============ JPS (Running Java Processes) ============"
jps 2>/dev/null || echo "jps not found"
echo ""

echo "============ HIVE HOME CONTENTS ============"
ls /opt/hive/bin/ 2>/dev/null || echo "Cannot read /opt/hive/bin/"
echo ""

echo "============ HIVE CONF DIR ============"
ls /opt/hive/conf/ 2>/dev/null || echo "Cannot read /opt/hive/conf/"
echo ""

echo "============ ACTIVE hive-site.xml (engine setting) ============"
grep -A2 'execution.engine' /opt/hive/conf/hive-site.xml 2>/dev/null || echo "Cannot read hive-site.xml"
echo ""

echo "============ ACTIVE hive-site.xml (metastore URI) ============"
grep -A2 'metastore.uris\|ConnectionURL\|metastore.warehouse' /opt/hive/conf/hive-site.xml 2>/dev/null
echo ""

echo "============ HIVE LOGS DIRECTORY ============"
ls -la /opt/hive/logs/ 2>/dev/null || echo "No logs at /opt/hive/logs/"
echo ""

echo "============ HIVESERVER2 LOG (last 80 lines) ============"
# Try common log name patterns
HS2_LOG=$(ls /opt/hive/logs/hive-*hiveserver2*.log 2>/dev/null | tail -1)
if [ -n "$HS2_LOG" ]; then
    echo "Reading: $HS2_LOG"
    tail -80 "$HS2_LOG"
else
    echo "No hiveserver2 log found. Trying all hive logs..."
    ls /opt/hive/logs/*.log 2>/dev/null | while read f; do
        echo "--- $f ---"
        tail -20 "$f"
    done
fi
echo ""

echo "============ METASTORE LOG (last 40 lines) ============"
MS_LOG=$(ls /opt/hive/logs/hive-*metastore*.log 2>/dev/null | tail -1)
if [ -n "$MS_LOG" ]; then
    echo "Reading: $MS_LOG"
    tail -40 "$MS_LOG"
else
    # Check project-level metastore.log for full content
    echo "No hive metastore log. Checking project metastore.log..."
    cat metastore.log 2>/dev/null || echo "No metastore.log found"
fi
echo ""

echo "============ OPEN PORTS (Hive-related) ============"
ss -tlnp 2>/dev/null | grep -E '9083|10000|10002' || echo "No Hive ports (9083/10000/10002) are currently open"
echo ""

echo "============ METASTORE DB LOCATION ============"
echo "Current dir: $(pwd)"
ls -la metastore_db/ 2>/dev/null | head -15 || echo "metastore_db/ not found in current directory"
echo ""

echo "============ DERBY.LOG (last 40 lines) ============"
tail -40 derby.log 2>/dev/null || echo "No derby.log"
echo ""

echo "============ HADOOP CLASSPATH (first 5 entries) ============"
hadoop classpath 2>/dev/null | tr ':' '\n' | head -5 || echo "hadoop classpath failed"
echo ""

echo "============ HIVE CLASSPATH CHECK ============"
ls /opt/hive/lib/hive-exec*.jar 2>/dev/null || echo "hive-exec jar not found"
ls /opt/hive/lib/hive-service*.jar 2>/dev/null || echo "hive-service jar not found"
echo ""

echo "============ HADOOP CORE-SITE (fs.defaultFS) ============"
grep -A2 'fs.defaultFS\|defaultFS' /opt/hadoop/etc/hadoop/core-site.xml 2>/dev/null || echo "Cannot read core-site.xml"
echo ""

echo "============ DIAGNOSIS COMPLETE ============"
