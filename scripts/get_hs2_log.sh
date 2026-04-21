#!/usr/bin/env bash
# Read the actual HiveServer2 output captured by nohup
PROJECT_ROOT="/mnt/c/Users/anubh/Anu's works/BDA/Mini project"

echo "=== hive.log (last 100 lines) ==="
tail -100 "$PROJECT_ROOT/hive.log" 2>/dev/null || echo "hive.log not found"

echo ""
echo "=== metastore.log (last 50 lines) ==="
tail -50 "$PROJECT_ROOT/metastore.log" 2>/dev/null || echo "metastore.log not found"

echo ""
echo "=== PORT 10000 status ==="
ss -tlnp 2>/dev/null | grep 10000 || echo "Port 10000 NOT listening"
ss -tlnp 2>/dev/null | grep 9083  || echo "Port 9083 NOT listening"

echo ""
echo "=== HiveServer2 process check ==="
# PID 14522 — check if it's still alive and what it's doing
ps aux | grep -E 'hive|RunJar' | grep -v grep

echo ""
echo "=== Try beeline manually ==="
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export HIVE_HOME=/opt/hive
export HADOOP_HOME=/opt/hadoop
export PATH=$HIVE_HOME/bin:$HADOOP_HOME/bin:/usr/local/bin:/usr/bin:/bin
which beeline
beeline -u "jdbc:hive2://localhost:10000" -n "" -e "SHOW DATABASES;" 2>&1 | head -30 || echo "beeline failed"

echo ""
echo "=== start hiveserver2 directly (foreground, 15s) ==="
# Run HS2 in foreground briefly to see immediate error output
timeout 15 hiveserver2 2>&1 | head -60 || true
