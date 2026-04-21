#!/usr/bin/env bash
# Quick fix applier — to be run directly from WSL
set -e

PROJECT_ROOT="/mnt/c/Users/anubh/Anu's works/BDA/Mini project"

echo "[1/5] Killing all Java processes..."
pkill -f java 2>/dev/null || true
sleep 4

echo "[2/5] Deploying updated hive-env.sh..."
sudo cp "$PROJECT_ROOT/config/hive-env.sh" /opt/hive/conf/hive-env.sh
sudo chmod 755 /opt/hive/conf/hive-env.sh
echo "      hive-env.sh deployed"

echo "[3/5] Starting HDFS..."
start-dfs.sh
sleep 5

echo "[4/5] Starting YARN..."
start-yarn.sh
sleep 5

echo "[5/5] Starting Hive services from home directory..."
cd ~

echo "      Starting Hive Metastore..."
nohup hive --service metastore > "$PROJECT_ROOT/metastore.log" 2>&1 &
MS_PID=$!
echo "      Metastore PID: $MS_PID — waiting for port 9083..."
for i in $(seq 1 30); do
    ss -tlnp 2>/dev/null | grep -q ':9083' && break
    echo "      [$i/30] Waiting..."
    sleep 2
done
ss -tlnp 2>/dev/null | grep -q ':9083' && echo "      ✓ Metastore on port 9083" || { echo "FAIL: Metastore did not start"; exit 1; }

echo "      Starting HiveServer2..."
nohup hiveserver2 > "$PROJECT_ROOT/hive.log" 2>&1 &
HS2_PID=$!
echo "      HiveServer2 PID: $HS2_PID — waiting for port 10000..."
for i in $(seq 1 60); do
    ss -tlnp 2>/dev/null | grep -q ':10000' && break
    if [ $((i % 10)) -eq 0 ]; then
        echo "      [$i/60] Still waiting..."
        # Show last error if any
        tail -3 /tmp/anubh/hive.log 2>/dev/null | grep -i 'error\|exception' || true
    fi
    sleep 2
done

if ss -tlnp 2>/dev/null | grep -q ':10000'; then
    echo ""
    echo "==============================="
    echo "  ✓ HiveServer2 on port 10000!"
    echo "  ✓ ALL SERVICES UP"
    echo "==============================="
    echo ""
    echo "Run the pipeline now:"
    echo "  bash scripts/run_pipeline.sh --skip-data-gen"
else
    echo "FAIL: HiveServer2 did not bind port 10000"
    echo "--- hive.log tail ---"
    tail -20 "$PROJECT_ROOT/hive.log"
    echo "--- /tmp/anubh/hive.log tail ---"
    tail -30 /tmp/anubh/hive.log 2>/dev/null
    exit 1
fi
