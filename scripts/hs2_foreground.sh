#!/usr/bin/env bash
# Runs HiveServer2 in foreground with full logging to capture the crash
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export HADOOP_HOME=/opt/hadoop
export HIVE_HOME=/opt/hive
export HIVE_CONF_DIR=/opt/hive/conf
export HADOOP_CONF_DIR=$HADOOP_HOME/etc/hadoop
export PATH=$HIVE_HOME/bin:$HADOOP_HOME/bin:$HADOOP_HOME/sbin:/usr/local/bin:/usr/bin:/bin

# Kill any existing HS2
pkill -f 'HiveServer2\|hiveserver2' 2>/dev/null || true
sleep 3

echo "[$(date)] Starting HiveServer2 in FOREGROUND with full logging..."
echo "[$(date)] Watch for errors below:"
echo "============================================"

# Run from home dir, with full log4j debug output to stdout
cd ~
exec hiveserver2 --hiveconf hive.root.logger=INFO,console 2>&1
