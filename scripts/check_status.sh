#!/usr/bin/env bash
export HIVE_HOME=/opt/hive
export HADOOP_HOME=/opt/hadoop
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=$HIVE_HOME/bin:$HADOOP_HOME/bin:/usr/local/bin:/usr/bin:/bin

PROJECT_ROOT="/mnt/c/Users/anubh/Anu's works/BDA/Mini project"

echo "=== hive.log last 40 lines ==="
tail -40 "$PROJECT_ROOT/hive.log" 2>/dev/null

echo ""
echo "=== PORT STATUS ==="
ss -tlnp 2>/dev/null | grep -E ':9083|:10000|:10002' || echo "No Hive ports open"

echo ""
echo "=== JPS ==="
jps 2>/dev/null

echo ""
echo "=== HiveServer2 Java args (check Xmx) ==="
ps aux 2>/dev/null | grep 'hiveserver2\|HiveServer2' | grep -v grep | grep -oE '\-Xmx[0-9]+[mMgG]?' || echo "HS2 not running"
