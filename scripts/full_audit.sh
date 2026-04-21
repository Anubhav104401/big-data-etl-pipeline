#!/usr/bin/env bash
# Full system audit — run as: bash scripts/full_audit.sh
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export HADOOP_HOME=/opt/hadoop
export HIVE_HOME=/opt/hive
export PATH=$HIVE_HOME/bin:$HADOOP_HOME/bin:$HADOOP_HOME/sbin:/usr/local/bin:/usr/bin:/bin

PR="/mnt/c/Users/anubh/Anu's works/BDA/Mini project"

echo "===== JAVA VERSIONS AVAILABLE ====="
ls /usr/lib/jvm/ 2>/dev/null
java -version 2>&1
echo ""

echo "===== HIVE/HADOOP VERSIONS ====="
echo "Hive:   $(hive --version 2>&1 | head -1)"
echo "Hadoop: $(hadoop version 2>&1 | head -1)"
echo ""

echo "===== HIVE-SITE.XML authorization settings ====="
grep -A2 'authorization\|doAs\|authentication' /opt/hive/conf/hive-site.xml 2>/dev/null | head -60
echo ""

echo "===== HIVE-ENV.SH ====="
cat /opt/hive/conf/hive-env.sh 2>/dev/null || echo "MISSING"
echo ""

echo "===== RUNNING PROCESSES ====="
jps 2>/dev/null
echo ""

echo "===== PORTS ====="
ss -tlnp 2>/dev/null | grep -E '9083|10000|10002|9870|8088' || echo "none"
echo ""

echo "===== HIVE REAL LOG (last 50 lines) ====="
tail -50 /tmp/anubh/hive.log 2>/dev/null || echo "no log at /tmp/anubh/hive.log"
echo ""

echo "===== METASTORE DB LOCATION ====="
ls ~/hive_metastore_db/ 2>/dev/null | head -5 || echo "not found at home"
ls "$PR/metastore_db/" 2>/dev/null | head -5 || echo "not found in project"
echo ""

echo "===== HIVE BIN SCRIPT ====="
head -30 /opt/hive/bin/hiveserver2 2>/dev/null
echo ""

echo "===== HIVE CLASSPATH (first 10 jars) ====="
ls /opt/hive/lib/*.jar 2>/dev/null | wc -l
echo ""

echo "===== JAVA OPTS when HS2 runs (check --add-opens presence) ====="
ps aux 2>/dev/null | grep 'hiveserver2\|HiveServer2' | grep -v grep | tr ' ' '\n' | grep -E 'add-opens|Xmx|attach' | head -20
echo ""

echo "===== AUDIT COMPLETE ====="
