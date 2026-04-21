#!/usr/bin/env bash
# ENGINEERING INVESTIGATION — stops all guessing, gets ground truth
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export HADOOP_HOME=/opt/hadoop
export HIVE_HOME=/opt/hive
export PATH=$HIVE_HOME/bin:$HADOOP_HOME/bin:/usr/local/bin:/usr/bin:/bin

PR="/mnt/c/Users/anubh/Anu's works/BDA/Mini project"

echo "===== 1. ALL hive-site.xml FILES ON SYSTEM ====="
find / -name 'hive-site.xml' 2>/dev/null | grep -v proc
echo ""

echo "===== 2. CLASSPATH Hive reads config from ====="
# Check what's on the classpath when hive runs
cat /opt/hive/bin/hive | grep -E 'CLASSPATH|CONFDIR|conf' | head -20
echo ""

echo "===== 3. DECOMPILE CLIService.class — see ACTUAL line 128 ====="
mkdir -p /tmp/hive_dc
cd /tmp/hive_dc
jar xf /opt/hive/lib/hive-service-3.1.3.jar org/apache/hive/service/cli/CLIService.class 2>/dev/null
javap -p -l org/apache/hive/service/cli/CLIService.class 2>/dev/null | grep -A3 -B3 'applyAuth\|line 115\|line 118\|line 128\|line 12[0-9]'
echo ""

echo "===== 4. ACTUAL hive.security.authorization.manager DEFAULT ====="
# Read it from the hive default template
grep -A3 'authorization.manager\|AUTHORIZATION_MANAGER' /opt/hive/conf/hive-default.xml.template 2>/dev/null | head -20
echo ""

echo "===== 5. WHAT hive-site.xml IS ACTIVE RIGHT NOW ====="
# Find what config HS2 actually loaded — check its JVM args for conf dir
ps aux 2>/dev/null | grep HiveServer2 | grep -v grep | tr ' ' '\n' | grep -E 'conf|CONF|hive.conf'
echo ""

echo "===== 6. CONTENT OF DEPLOYED /opt/hive/conf/hive-site.xml (authorization section) ====="
grep -A2 'authorization\|authenticator' /opt/hive/conf/hive-site.xml 2>/dev/null | head -40
echo ""

echo "===== 7. VERIFY HIVE_CONF_DIR VALUE in running process ====="
cat /proc/$(pgrep -f HiveServer2 | head -1)/environ 2>/dev/null | tr '\0' '\n' | grep -E 'HIVE_CONF|HADOOP_CONF|JAVA_HOME' || echo "No HS2 process found (expected)"
echo ""

echo "===== 8. DECOMPILE SessionState line 413 — see exact cast ====="
cd /tmp/hive_dc
jar xf /opt/hive/lib/hive-exec-3.1.3.jar org/apache/hadoop/hive/ql/session/SessionState.class 2>/dev/null
# Show bytecode around line 413
javap -p -l -c org/apache/hadoop/hive/ql/session/SessionState.class 2>/dev/null | grep -A10 'line 41[0-9]\|line 38[5-9]' | head -50
echo ""

echo "===== 9. CHECK JAVA 8 AVAILABILITY ====="
apt-cache show openjdk-8-jdk 2>/dev/null | grep -E 'Package|Version' | head -3 || echo "openjdk-8 NOT in apt"
ls /usr/lib/jvm/ 2>/dev/null
which java8 2>/dev/null || echo "no java8 alias"
echo ""

echo "===== 10. CHECK ADOPTIUM/TEMURIN AVAILABILITY ====="
apt-cache show temurin-8-jdk 2>/dev/null | head -3 || apt-cache search temurin 2>/dev/null | head -5 || echo "temurin not in apt"
echo ""

echo "===== INVESTIGATION COMPLETE ====="
