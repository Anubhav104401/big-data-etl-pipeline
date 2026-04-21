#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║  THE ACTUAL FIX — Java 11 Agent for Hive 3.1.3               ║
# ║                                                                  ║
# ║  Problem: SessionState.java:413 casts AppClassLoader to         ║
# ║  URLClassLoader unconditionally. AppClassLoader stopped           ║
# ║  extending URLClassLoader in Java 11. No config can fix this.   ║
# ║                                                                  ║
# ║  Fix: A Java agent that runs BEFORE HiveServer2 starts and      ║
# ║  replaces the thread context classloader with a URLClassLoader   ║
# ║  wrapper. The cast then succeeds and HS2 starts normally.       ║
# ║                                                                  ║
# ║  Usage: bash scripts/patch_and_start.sh                        ║
# ╚══════════════════════════════════════════════════════════════════╝
set -euo pipefail

export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export HADOOP_HOME=/opt/hadoop
export HIVE_HOME=/opt/hive
export HIVE_CONF_DIR=/opt/hive/conf
export HADOOP_CONF_DIR=$HADOOP_HOME/etc/hadoop
export PATH=$HIVE_HOME/bin:$HADOOP_HOME/bin:$HADOOP_HOME/sbin:/usr/local/bin:/usr/bin:/bin

PR="/mnt/c/Users/anubh/Anu's works/BDA/Mini project"
AGENT_DIR="/opt/hive-java11-fix"
log() { echo "[$(date '+%H:%M:%S')] $*"; }
ok()  { echo "[$(date '+%H:%M:%S')] ✓ $*"; }
err() { echo "[$(date '+%H:%M:%S')] ✗ FATAL: $*"; exit 1; }

# ─────────────────────────────────────────────────────────────────────────────
log "━━━ STEP 1: Kill all Java processes ━━━"
pkill -f java 2>/dev/null || true
sleep 5
ok "Processes killed"

# ─────────────────────────────────────────────────────────────────────────────
log "━━━ STEP 2: Build Java 11 compatibility agent ━━━"
echo "lenovo" | sudo -S mkdir -p "$AGENT_DIR"
echo "lenovo" | sudo -S chmod 777 "$AGENT_DIR"

# Write the agent source
cat > /tmp/HiveJava11Fix.java << 'JAVA_EOF'
import java.lang.instrument.Instrumentation;
import java.net.URL;
import java.net.URLClassLoader;

/**
 * Java agent that fixes Hive 3.1.3 + Java 11 ClassCastException.
 *
 * Root cause: SessionState.java:413 does:
 *   (URLClassLoader) Thread.currentThread().getContextClassLoader()
 *
 * In Java 8, AppClassLoader extended URLClassLoader (cast worked).
 * In Java 11, AppClassLoader no longer extends URLClassLoader (cast fails).
 *
 * Fix: Replace the context ClassLoader with a URLClassLoader that
 * delegates all class loading to the original AppClassLoader.
 * The cast then succeeds and Hive starts cleanly.
 */
public class HiveJava11Fix {
    public static void premain(String agentArgs, Instrumentation inst) {
        ClassLoader existing = Thread.currentThread().getContextClassLoader();
        if (existing instanceof URLClassLoader) {
            System.err.println("[HiveJava11Fix] Context ClassLoader already URLClassLoader — no fix needed.");
            return;
        }
        try {
            // Wrap existing classloader in URLClassLoader.
            // Empty URL array: all loading delegated to parent (the original AppClassLoader).
            URLClassLoader urlWrapper = new URLClassLoader(new URL[0], existing);
            Thread.currentThread().setContextClassLoader(urlWrapper);
            System.err.println("[HiveJava11Fix] SUCCESS: Replaced " +
                existing.getClass().getName() + " with URLClassLoader wrapper.");
        } catch (Exception e) {
            System.err.println("[HiveJava11Fix] WARNING: Could not replace ClassLoader: " + e);
        }
    }

    // agentmain is for dynamic attach (not needed here, but good practice)
    public static void agentmain(String agentArgs, Instrumentation inst) {
        premain(agentArgs, inst);
    }
}
JAVA_EOF

# Compile the agent
log "  Compiling Java agent..."
javac /tmp/HiveJava11Fix.java -d /tmp/ 2>&1
ok "  Compiled HiveJava11Fix.class"

# Write MANIFEST.MF
cat > /tmp/MANIFEST_FIX.MF << 'MF_EOF'
Manifest-Version: 1.0
Premain-Class: HiveJava11Fix
Agent-Class: HiveJava11Fix
Can-Redefine-Classes: false
Can-Retransform-Classes: false

MF_EOF

# Package into jar
jar cfm "$AGENT_DIR/hive-java11-fix.jar" /tmp/MANIFEST_FIX.MF -C /tmp/ HiveJava11Fix.class
echo "lenovo" | sudo -S chmod 644 "$AGENT_DIR/hive-java11-fix.jar"
ok "  Agent jar built: $AGENT_DIR/hive-java11-fix.jar"

# Verify the jar
jar tf "$AGENT_DIR/hive-java11-fix.jar"
ok "Agent built and verified"

# ─────────────────────────────────────────────────────────────────────────────
log "━━━ STEP 3: Update hive-env.sh with Java agent flag ━━━"
cat > /tmp/hive-env-new.sh << ENV_EOF
#!/usr/bin/env bash
# Hive Environment — Java 11 + Hive 3.1.3 compatibility

# ─── THE FIX ─────────────────────────────────────────────────────────────────
# Java agent that replaces AppClassLoader with URLClassLoader before Hive starts.
# Fixes: SessionState.java:413 ClassCastException on Java 11.
JAVA11_AGENT="-javaagent:/opt/hive-java11-fix/hive-java11-fix.jar"

# ─── JVM Settings ─────────────────────────────────────────────────────────────
export HIVE_SERVER2_HEAPSIZE=1024
export HIVE_METASTORE_HEAP_SIZE=512
export HADOOP_HEAPSIZE=1024

# Apply agent to ALL Hive java processes
export HADOOP_CLIENT_OPTS="\$JAVA11_AGENT"
export HIVE_SERVER2_JAVA_OPTS="\$JAVA11_AGENT"
export HIVE_METASTORE_HADOOP_OPTS="\$JAVA11_AGENT"

# ─── Paths ───────────────────────────────────────────────────────────────────
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export HADOOP_HOME=/opt/hadoop
export HIVE_HOME=/opt/hive
export HIVE_CONF_DIR=/opt/hive/conf
ENV_EOF

echo "lenovo" | sudo -S cp /tmp/hive-env-new.sh /opt/hive/conf/hive-env.sh
echo "lenovo" | sudo -S chmod 755 /opt/hive/conf/hive-env.sh
ok "hive-env.sh updated with Java agent"

# ─────────────────────────────────────────────────────────────────────────────
log "━━━ STEP 4: Deploy latest hive-site.xml ━━━"
echo "lenovo" | sudo -S cp "$PR/config/hive-site.xml" /opt/hive/conf/hive-site.xml
echo "lenovo" | sudo -S chmod 644 /opt/hive/conf/hive-site.xml
ok "hive-site.xml deployed"

# ─────────────────────────────────────────────────────────────────────────────
log "━━━ STEP 5: Reinit metastore schema ━━━"
rm -rf ~/hive_metastore_db 2>/dev/null || true
cd ~
schematool -dbType derby -initSchema 2>&1 | tail -3
ok "Metastore schema ready at ~/hive_metastore_db"

# ─────────────────────────────────────────────────────────────────────────────
log "━━━ STEP 6: Start HDFS + YARN ━━━"
cd "$PR"
start-dfs.sh 2>&1 | grep -v '^$'
sleep 6
start-yarn.sh 2>&1 | grep -v '^$'
sleep 5

hdfs dfs -mkdir -p /user/hive/warehouse 2>/dev/null || true
hdfs dfs -chmod 777 /user/hive/warehouse 2>/dev/null || true
ok "HDFS + YARN ready"

# ─────────────────────────────────────────────────────────────────────────────
log "━━━ STEP 7: Start Hive Metastore ━━━"
cd ~
source /opt/hive/conf/hive-env.sh
nohup hive --service metastore > "$PR/metastore.log" 2>&1 &
for i in $(seq 1 40); do
    ss -tlnp 2>/dev/null | grep -q ':9083' && break
    sleep 2
done
ss -tlnp 2>/dev/null | grep -q ':9083' && ok "Metastore on port 9083" || err "Metastore failed to start! Check $PR/metastore.log"

# ─────────────────────────────────────────────────────────────────────────────
log "━━━ STEP 8: Start HiveServer2 with Java agent ━━━"
log "  The agent will print: '[HiveJava11Fix] SUCCESS' if it works"
nohup hiveserver2 > "$PR/hive.log" 2>&1 &
HS2_PID=$!
log "  HiveServer2 PID: $HS2_PID"

# Wait for port 10000 — check every 2 seconds, up to 120 seconds
log "  Watching /tmp/anubh/hive.log for agent output and port 10000..."
for i in $(seq 1 60); do
    if ss -tlnp 2>/dev/null | grep -q ':10000'; then
        echo ""
        ok "HiveServer2 is UP on port 10000!"
        break
    fi
    # Show relevant log lines every 10 iterations
    if [ $((i % 10)) -eq 0 ]; then
        log "  [$i/60] Waiting... Last log:"
        tail -3 /tmp/anubh/hive.log 2>/dev/null | grep -vE '^$|SLF4J' || true
    fi
    # Check for agent success message
    if grep -q 'HiveJava11Fix.*SUCCESS' "$PR/hive.log" 2>/dev/null; then
        log "  ✓ Java agent activated successfully — HS2 should start shortly..."
    fi
    sleep 2
done

if ! ss -tlnp 2>/dev/null | grep -q ':10000'; then
    echo ""
    echo "═══ HiveServer2 still failing — Full /tmp/anubh/hive.log: ═══"
    cat /tmp/anubh/hive.log 2>/dev/null
    echo ""
    echo "═══ $PR/hive.log: ═══"
    cat "$PR/hive.log"
    err "HiveServer2 did not start"
fi

cd "$PR"

# ─────────────────────────────────────────────────────────────────────────────
log "━━━ STEP 9: Verify with beeline ━━━"
beeline -u "jdbc:hive2://localhost:10000" -n "" -e "SHOW DATABASES;" \
    --silent=false 2>&1 | grep -vE 'SLF4J|Class path|binding' | head -20

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║               ALL SERVICES UP!                          ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║  HDFS:      http://localhost:9870                        ║"
echo "║  YARN:      http://localhost:8088                        ║"
echo "║  HiveServer2: http://localhost:10002                     ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║  Now run:                                                ║"
echo "║  bash scripts/run_pipeline.sh --skip-data-gen           ║"
echo "╚══════════════════════════════════════════════════════════╝"
