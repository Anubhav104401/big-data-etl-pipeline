#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════════════════╗
# ║  FINAL FIX — Install Java 8 for Hive, keep Java 11 for Hadoop ║
# ║                                                                  ║
# ║  Root cause (confirmed via decompilation):                      ║
# ║  SessionState.java:413 does an UNCONDITIONAL cast to            ║
# ║  URLClassLoader. In Java 8, AppClassLoader IS a URLClassLoader. ║
# ║  In Java 11, it is NOT. No config, no agent can fix this —      ║
# ║  only Java 8 resolves it natively.                              ║
# ║                                                                  ║
# ║  Usage: bash scripts/install_java8_and_start.sh                ║
# ╚══════════════════════════════════════════════════════════════════╝
set -euo pipefail

PR="/mnt/c/Users/anubh/Anu's works/BDA/Mini project"
JAVA8_HOME="/usr/lib/jvm/java-8-hive"
log() { echo "[$(date '+%H:%M:%S')] $*"; }
ok()  { echo "[$(date '+%H:%M:%S')] ✓ $*"; }
err() { echo "[$(date '+%H:%M:%S')] ✗ FATAL: $*" >&2; exit 1; }

# ─── EXPORTS — Java 11 for Hadoop, Java 8 will be used only for Hive ─────────
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export HADOOP_HOME=/opt/hadoop
export HIVE_HOME=/opt/hive
export HIVE_CONF_DIR=/opt/hive/conf
export HADOOP_CONF_DIR=$HADOOP_HOME/etc/hadoop
export PATH=$HIVE_HOME/bin:$HADOOP_HOME/bin:$HADOOP_HOME/sbin:/usr/local/bin:/usr/bin:/bin

# ─────────────────────────────────────────────────────────────────────────────
log "━━━ STEP 1: Kill all Java processes ━━━"
pkill -f java 2>/dev/null || true
sleep 4
ok "Done"

# ─────────────────────────────────────────────────────────────────────────────
log "━━━ STEP 2: Install Java 8 (trying multiple methods) ━━━"

JAVA8_FOUND=false

# Method A: Check if already installed from a previous attempt
if [ -x "$JAVA8_HOME/bin/java" ]; then
    log "  Java 8 already at $JAVA8_HOME"
    JAVA8_VERSION=$("$JAVA8_HOME/bin/java" -version 2>&1 | head -1)
    log "  $JAVA8_VERSION"
    JAVA8_FOUND=true
fi

# Method B: apt-get openjdk-8-jdk (works on Ubuntu 22.04; may work on 24.04 with universe)
if [ "$JAVA8_FOUND" = "false" ]; then
    log "  Trying: sudo apt-get install openjdk-8-jdk..."
    if echo "lenovo" | sudo -S apt-get install -y openjdk-8-jdk 2>&1 | grep -q 'is already the newest\|Setting up'; then
        JDK8_PATH=$(ls -d /usr/lib/jvm/java-8-openjdk-* 2>/dev/null | head -1)
        if [ -n "$JDK8_PATH" ] && [ -x "$JDK8_PATH/bin/java" ]; then
            echo "lenovo" | sudo -S mkdir -p "$JAVA8_HOME"
            echo "lenovo" | sudo -S ln -sfn "$JDK8_PATH" "$JAVA8_HOME" 2>/dev/null || true
            # If symlink failed, just use the path directly
            JAVA8_HOME="$JDK8_PATH"
            JAVA8_FOUND=true
            ok "  Java 8 installed via apt at $JAVA8_HOME"
        fi
    fi
fi

# Method C: Adoptium/Temurin 8 via apt repo
if [ "$JAVA8_FOUND" = "false" ]; then
    log "  Trying: Adoptium Temurin 8 via apt repo..."
    CODENAME=$(. /etc/os-release 2>/dev/null && echo "$VERSION_CODENAME" || echo "jammy")
    # Adoptium Temurin supports both jammy and noble
    wget -qO /tmp/adoptium.gpg https://packages.adoptium.net/artifactory/api/gpg/key/public 2>/dev/null || true
    if [ -s /tmp/adoptium.gpg ]; then
        echo "lenovo" | sudo -S gpg --dearmor < /tmp/adoptium.gpg | sudo tee /etc/apt/trusted.gpg.d/adoptium.gpg > /dev/null 2>&1 || true
        echo "deb https://packages.adoptium.net/artifactory/deb $CODENAME main" | sudo tee /etc/apt/sources.list.d/adoptium.list > /dev/null
        # If noble isn't supported, try jammy packages
        echo "lenovo" | sudo -S apt-get update -qq 2>&1 | tail -3 || true
        if echo "lenovo" | sudo -S apt-get install -y temurin-8-jdk 2>&1 | grep -q 'Setting up\|already'; then
            JDK8_PATH=$(ls -d /usr/lib/jvm/temurin-8* 2>/dev/null | head -1)
            if [ -n "$JDK8_PATH" ] && [ -x "$JDK8_PATH/bin/java" ]; then
                JAVA8_HOME="$JDK8_PATH"
                JAVA8_FOUND=true
                ok "  Temurin 8 installed at $JAVA8_HOME"
            fi
        fi
    fi
fi

# Method D: Direct download from GitHub Adoptium releases
if [ "$JAVA8_FOUND" = "false" ]; then
    log "  Trying: Direct download of Temurin 8 from GitHub (~105MB)..."
    TEMURIN8_URL="https://github.com/adoptium/temurin8-binaries/releases/download/jdk8u402-b06/OpenJDK8U-jdk_x64_linux_hotspot_8u402b06.tar.gz"
    TARBALL=/tmp/temurin8-jdk.tar.gz

    wget --progress=dot:mega -O "$TARBALL" "$TEMURIN8_URL" 2>&1 || \
    curl -L --progress-bar -o "$TARBALL" "$TEMURIN8_URL" 2>&1 || \
    err "All download methods failed. Please manually install Java 8 and set JAVA8_HOME=$JAVA8_HOME"

    echo "lenovo" | sudo -S mkdir -p "$JAVA8_HOME"
    echo "lenovo" | sudo -S tar -xzf "$TARBALL" -C "$JAVA8_HOME" --strip-components=1
    rm -f "$TARBALL"
    JAVA8_FOUND=true
    ok "  Temurin 8 extracted to $JAVA8_HOME"
fi

# Final verification
if [ "$JAVA8_FOUND" = "false" ]; then
    err "Could not install Java 8 by any method. Cannot proceed."
fi

log "  Java 8 path: $JAVA8_HOME"
"$JAVA8_HOME/bin/java" -version 2>&1 | head -1
ok "Java 8 ready"

# ─────────────────────────────────────────────────────────────────────────────
log "━━━ STEP 3: Configure Hive to use Java 8 ━━━"
cat > /tmp/hive-env-java8.sh << ENVEOF
#!/usr/bin/env bash
# Hive Environment — Uses Java 8 to fix Hive 3.1.3 ClassCastException
# Hadoop still uses Java 11 (set in hadoop-env.sh separately).

# ─── CRITICAL: Use Java 8 for ALL Hive processes ─────────────────────────────
# Hive 3.1.3 SessionState.java:413 casts AppClassLoader to URLClassLoader.
# In Java 8, AppClassLoader IS a URLClassLoader (cast works).
# In Java 11, it is NOT (ClassCastException). Hence Java 8 required for Hive.
export JAVA_HOME=${JAVA8_HOME}

# ─── Heap sizes ──────────────────────────────────────────────────────────────
export HIVE_SERVER2_HEAPSIZE=1024
export HIVE_METASTORE_HEAP_SIZE=512
export HADOOP_HEAPSIZE=1024

# ─── Other paths ─────────────────────────────────────────────────────────────
export HADOOP_HOME=/opt/hadoop
export HIVE_HOME=/opt/hive
export HIVE_CONF_DIR=/opt/hive/conf
ENVEOF

echo "lenovo" | sudo -S cp /tmp/hive-env-java8.sh /opt/hive/conf/hive-env.sh
echo "lenovo" | sudo -S chmod 755 /opt/hive/conf/hive-env.sh
ok "hive-env.sh configured to use Java 8 ($JAVA8_HOME)"

# ─────────────────────────────────────────────────────────────────────────────
log "━━━ STEP 4: Deploy hive-site.xml ━━━"
echo "lenovo" | sudo -S cp "$PR/config/hive-site.xml" /opt/hive/conf/hive-site.xml
echo "lenovo" | sudo -S chmod 644 /opt/hive/conf/hive-site.xml
ok "hive-site.xml deployed"

# ─────────────────────────────────────────────────────────────────────────────
log "━━━ STEP 5: Clean and init metastore (with Java 8) ━━━"
rm -rf ~/hive_metastore_db 2>/dev/null || true
# Run schematool with Java 8 explicitly
export JAVA_HOME="$JAVA8_HOME"
export PATH="$JAVA8_HOME/bin:$HADOOP_HOME/bin:$HIVE_HOME/bin:/usr/local/bin:/usr/bin:/bin"

cd ~
schematool -dbType derby -initSchema 2>&1 | tail -3
ok "Metastore schema initialized at ~/hive_metastore_db"

# ─────────────────────────────────────────────────────────────────────────────
log "━━━ STEP 6: Start HDFS (using Java 11) ━━━"
# Hadoop needs Java 11 — reset JAVA_HOME for hadoop commands
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH="$HADOOP_HOME/bin:$HADOOP_HOME/sbin:/usr/local/bin:/usr/bin:/bin"

cd "$PR"
start-dfs.sh 2>&1 | grep -v '^$'
sleep 7
hdfs dfs -ls / >/dev/null 2>&1 && ok "HDFS online" || err "HDFS failed"

log "━━━ STEP 7: Start YARN (using Java 11) ━━━"
start-yarn.sh 2>&1 | grep -v '^$'
sleep 5
ok "YARN started"

# Set up HDFS directories
hdfs dfs -mkdir -p /user/hive/warehouse 2>/dev/null || true
hdfs dfs -chmod 777 /user/hive/warehouse 2>/dev/null || true
hdfs dfs -mkdir -p /user/anubh 2>/dev/null || true
hdfs dfs -chmod 755 /user/anubh 2>/dev/null || true
ok "HDFS directories ready"

# ─────────────────────────────────────────────────────────────────────────────
log "━━━ STEP 8: Start Hive Metastore (Java 8 via hive-env.sh) ━━━"
cd ~
source /opt/hive/conf/hive-env.sh  # Sets JAVA_HOME to Java 8
export PATH="$JAVA_HOME/bin:$HADOOP_HOME/bin:$HIVE_HOME/bin:/usr/local/bin:/usr/bin:/bin"
nohup hive --service metastore > "$PR/metastore.log" 2>&1 &
log "  Waiting for port 9083..."
for i in $(seq 1 40); do
    ss -tlnp 2>/dev/null | grep -q ':9083' && break; sleep 2
done
ss -tlnp 2>/dev/null | grep -q ':9083' && ok "Metastore on port 9083" || {
    log "  Metastore log tail:"; tail -20 "$PR/metastore.log"; err "Metastore failed!"
}

# ─────────────────────────────────────────────────────────────────────────────
log "━━━ STEP 9: Start HiveServer2 (Java 8) ━━━"
log "  If Java 8 is used, NO ClassCastException will occur ←"
nohup hiveserver2 > "$PR/hive.log" 2>&1 &
HS2_PID=$!
log "  PID=$HS2_PID — watching port 10000 (up to 120s)..."
for i in $(seq 1 60); do
    if ss -tlnp 2>/dev/null | grep -q ':10000'; then
        echo ""
        ok "HiveServer2 UP on port 10000!"
        break
    fi
    if [ $((i % 15)) -eq 0 ]; then
        log "  [$i/60] Still waiting..."
        tail -5 /tmp/anubh/hive.log 2>/dev/null | grep -vE '^$|SLF4J|Class path' | grep -iE 'error|warn|start|bound|listen|success' || true
    fi
    sleep 2
done

if ! ss -tlnp 2>/dev/null | grep -q ':10000'; then
    echo ""
    log "  FULL /tmp/anubh/hive.log:"
    cat /tmp/anubh/hive.log 2>/dev/null
    echo ""
    log "  FULL $PR/hive.log:"
    cat "$PR/hive.log"
    err "HiveServer2 failed. See logs above."
fi

cd "$PR"

# ─────────────────────────────────────────────────────────────────────────────
log "━━━ STEP 10: Verify Beeline connection ━━━"
beeline -u "jdbc:hive2://localhost:10000" -n "" \
        -e "SHOW DATABASES;" \
        --silent=false 2>&1 | grep -vE 'SLF4J|Class path|binding|Actual binding' | head -20

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║            ALL SERVICES UP — PIPELINE READY             ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║  Java 11: Hadoop (HDFS/YARN)                            ║"
echo "║  Java 8:  Hive Metastore + HiveServer2                  ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║  HDFS:        http://localhost:9870                      ║"
echo "║  YARN:        http://localhost:8088                      ║"
echo "║  HiveServer2: http://localhost:10002                     ║"
echo "╠══════════════════════════════════════════════════════════╣"
echo "║  Run the pipeline:                                       ║"
echo "║  bash scripts/run_pipeline.sh --skip-data-gen           ║"
echo "╚══════════════════════════════════════════════════════════╝"
