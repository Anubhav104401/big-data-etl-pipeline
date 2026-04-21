# 🏗️ Big Data Analytics Pipeline — Hadoop & Hive

> A production-grade, end-to-end Big Data Pipeline that collects multi-source data (web logs, IoT sensors, social media), stores it in HDFS, transforms it with Hive, and exports results for BI visualization.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Environment Setup](#2-environment-setup)
3. [Data Collection](#3-data-collection)
4. [HDFS Storage Design](#4-hdfs-storage-design)
5. [Hive Data Modeling](#5-hive-data-modeling)
6. [Data Processing with HiveQL](#6-data-processing-with-hiveql)
7. [Performance Optimization](#7-performance-optimization)
8. [Visualization Layer](#8-visualization-layer)
9. [Error Handling & Monitoring](#9-error-handling--monitoring)
10. [What You've Learned](#10-what-youve-learned)

---

## Project Structure

```
Mini project/
├── README.md                          # This guide
├── docs/
│   └── ARCHITECTURE.md                # Detailed architecture documentation
├── config/
│   ├── core-site.xml                  # Hadoop core configuration
│   ├── hdfs-site.xml                  # HDFS configuration
│   ├── mapred-site.xml                # MapReduce configuration
│   ├── yarn-site.xml                  # YARN configuration
│   └── hive-site.xml                  # Hive configuration
├── scripts/
│   ├── data_generators/
│   │   ├── generate_web_logs.py       # Apache access.log simulator
│   │   ├── generate_iot_data.py       # IoT sensor data simulator
│   │   ├── generate_social_media.py   # Social media data simulator
│   │   └── generate_device_metadata.py # Device metadata generator
│   ├── hdfs_setup.sh                  # HDFS directory setup & data loading
│   ├── run_pipeline.sh                # Master orchestration script
│   └── export_results.sh             # Export Hive results to CSV
├── hive/
│   ├── 01_create_databases.hql        # Database creation
│   ├── 02_raw_tables.hql              # External tables on raw data
│   ├── 03_optimized_tables.hql        # ORC partitioned/bucketed tables
│   ├── 04_etl_transforms.hql          # ETL: raw → processed
│   ├── 05_analytics_queries.hql       # Analytical queries
│   ├── 06_performance_tuning.hql      # Optimization settings
│   └── 07_export_queries.hql          # Export queries for BI
├── sample_data/                       # Pre-generated sample datasets
│   ├── web_logs/
│   ├── iot_sensors/
│   ├── social_media/
│   └── device_metadata/
└── output/                            # Exported query results (CSV)
```

---

## 1. Architecture Overview

### ASCII Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        BIG DATA ANALYTICS PIPELINE                         │
│                     Hadoop 3.x + Hive 3.x Architecture                     │
└─────────────────────────────────────────────────────────────────────────────┘

  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
  │  Web Server  │  │  IoT Sensor  │  │ Social Media │
  │    Logs      │  │   Devices    │  │     API      │
  │ (access.log) │  │ (JSON/CSV)   │  │  (JSON/CSV)  │
  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘
         │                 │                  │
         ▼                 ▼                  ▼
  ┌─────────────────────────────────────────────────────┐
  │              DATA INGESTION LAYER                    │
  │  ┌────────────┐ ┌────────────┐ ┌────────────────┐   │
  │  │  Python    │ │  Python    │ │    Python      │   │
  │  │  Log Gen   │ │  IoT Gen   │ │  Social Gen    │   │
  │  └─────┬──────┘ └─────┬──────┘ └──────┬─────────┘   │
  │        │              │               │              │
  │        ▼              ▼               ▼              │
  │  ┌─────────────────────────────────────────────┐     │
  │  │         hdfs dfs -put / -copyFromLocal      │     │
  │  └─────────────────────┬───────────────────────┘     │
  └────────────────────────┼─────────────────────────────┘
                           │
                           ▼
  ┌─────────────────────────────────────────────────────────────────────┐
  │                     HADOOP CLUSTER (Pseudo-Distributed)             │
  │                                                                     │
  │  ┌──────────────────────────────────────────────────────────────┐   │
  │  │                    HDFS (Storage Layer)                       │   │
  │  │                                                              │   │
  │  │  ┌────────────┐        ┌──────────────────────────────────┐  │   │
  │  │  │  NameNode  │◄──────►│          DataNode(s)             │  │   │
  │  │  │  (Master)  │        │  ┌──────────────────────────┐    │  │   │
  │  │  │            │        │  │   /pipeline/raw/          │    │  │   │
  │  │  │ • Metadata │        │  │     ├── web_logs/         │    │  │   │
  │  │  │ • Namespace│        │  │     ├── iot_sensors/      │    │  │   │
  │  │  │ • Block Map│        │  │     └── social_media/     │    │  │   │
  │  │  │            │        │  │   /pipeline/processed/    │    │  │   │
  │  │  └────────────┘        │  │   /pipeline/archive/      │    │  │   │
  │  │                        │  │   /pipeline/output/       │    │  │   │
  │  │                        │  └──────────────────────────┘    │  │   │
  │  │                        └──────────────────────────────────┘  │   │
  │  └──────────────────────────────────────────────────────────────┘   │
  │                                                                     │
  │  ┌──────────────────────────────────────────────────────────────┐   │
  │  │                    YARN (Resource Management)                 │   │
  │  │                                                              │   │
  │  │  ┌─────────────────┐        ┌─────────────────────────┐     │   │
  │  │  │ ResourceManager │◄──────►│    NodeManager(s)       │     │   │
  │  │  │                 │        │  • Container Allocation │     │   │
  │  │  │ • Scheduling    │        │  • Resource Monitoring  │     │   │
  │  │  │ • App Tracking  │        │  • Health Reporting     │     │   │
  │  │  └─────────────────┘        └─────────────────────────┘     │   │
  │  └──────────────────────────────────────────────────────────────┘   │
  │                                                                     │
  │  ┌──────────────────────────────────────────────────────────────┐   │
  │  │                 HIVE (Processing & Analytics)                 │   │
  │  │                                                              │   │
  │  │  ┌──────────────┐  ┌───────────┐  ┌───────────────────┐     │   │
  │  │  │ HiveServer2  │  │ Metastore │  │  Execution Engine │     │   │
  │  │  │              │  │           │  │                   │     │   │
  │  │  │ • JDBC/ODBC  │  │ • Schema  │  │ • Tez (default)  │     │   │
  │  │  │ • Thrift     │  │ • Table   │  │ • MapReduce      │     │   │
  │  │  │ • Beeline    │  │   Metadata│  │ • LLAP (optional)│     │   │
  │  │  │              │  │ • Derby/  │  │                   │     │   │
  │  │  │              │  │   MySQL   │  │                   │     │   │
  │  │  └──────┬───────┘  └───────────┘  └───────────────────┘     │   │
  │  │         │                                                    │   │
  │  │         ▼                                                    │   │
  │  │  ┌─────────────────────────────────────────────────────┐     │   │
  │  │  │              HiveQL Processing                       │     │   │
  │  │  │                                                     │     │   │
  │  │  │  Raw Tables ──► ETL Transforms ──► Optimized ORC    │     │   │
  │  │  │  (External)     (INSERT OVERWRITE) (Partitioned +   │     │   │
  │  │  │                                    Bucketed)        │     │   │
  │  │  └─────────────────────────┬───────────────────────────┘     │   │
  │  └────────────────────────────┼────────────────────────────────┘   │
  └───────────────────────────────┼─────────────────────────────────────┘
                                  │
                                  ▼
  ┌─────────────────────────────────────────────────────────────────┐
  │                    OUTPUT / VISUALIZATION LAYER                  │
  │                                                                 │
  │  ┌──────────────┐  ┌──────────────┐  ┌────────────────────┐    │
  │  │  CSV Export   │  │   Tableau    │  │    Power BI        │    │
  │  │  (hdfs -get)  │  │   (JDBC →   │  │    (ODBC →         │    │
  │  │              │  │  HiveServer2)│  │   HiveServer2)     │    │
  │  └──────────────┘  └──────────────┘  └────────────────────┘    │
  └─────────────────────────────────────────────────────────────────┘
```

### Component Roles

| Component | Role | Port |
|-----------|------|------|
| **NameNode** | Master node managing HDFS namespace and metadata. Tracks which DataNode holds which block of data. Single point of coordination for file operations. | 9870 (Web UI), 9000 (IPC) |
| **DataNode** | Worker node storing actual data blocks. Reports block status to NameNode via heartbeats. In pseudo-distributed mode, runs on the same machine as NameNode. | 9864 (Web UI) |
| **ResourceManager** | YARN's master daemon. Allocates cluster resources (CPU, memory) to applications. Schedules jobs across NodeManagers. | 8088 (Web UI) |
| **NodeManager** | YARN's worker daemon. Manages containers on individual nodes. Monitors resource usage and reports to ResourceManager. | 8042 (Web UI) |
| **HiveServer2** | Provides JDBC/ODBC interface for remote clients (Beeline, Tableau, Power BI). Handles query compilation and execution. | 10000 (Thrift), 10002 (Web UI) |
| **Hive Metastore** | Stores metadata (table schemas, partition info, SerDe details) in a relational database (Derby for dev, MySQL/PostgreSQL for production). | 9083 (Thrift) |
| **Tez** | DAG-based execution engine replacing MapReduce for Hive. Reduces disk I/O by piping intermediate results through memory. | N/A |

### Architectural Decisions & Justifications

| Decision | Justification |
|----------|---------------|
| **Pseudo-distributed mode** | Single-machine development; all daemons run as separate JVM processes, simulating a real cluster |
| **ORC file format** | Best compression ratios for Hive; supports predicate pushdown, ACID, and vectorized execution |
| **Tez over MapReduce** | 3-10x faster for interactive queries; eliminates unnecessary disk writes between stages |
| **External tables for raw data** | Dropping the table doesn't delete the underlying HDFS data — safe for data lake patterns |
| **Partitioning by date** | Time-series data access pattern; Hive skips entire partitions not matching the WHERE clause |
| **Derby Metastore** | Zero-config for development; swap to MySQL for multi-user/production |

> **Key Concepts — Hadoop Architecture**
>
> - **HDFS** follows a master-slave architecture. Files are split into 128MB blocks and
>   replicated across DataNodes (default 3 replicas in production, 1 in pseudo-distributed).
> - **YARN** decouples resource management from data processing, allowing multiple engines
>   (MapReduce, Tez, Spark) to share the same cluster.
> - **Hive** is NOT a database — it's a data warehouse infrastructure that projects structure
>   onto HDFS data and translates SQL into distributed jobs (Tez/MR).
> - The **Metastore** is the brain of Hive: it maps logical table definitions to physical
>   HDFS locations and SerDe (Serializer/Deserializer) classes.

---

## 2. Environment Setup

### Prerequisites

| Software | Version | Purpose |
|----------|---------|---------|
| Java JDK | 8 or 11 | Required by Hadoop and Hive |
| Hadoop | 3.3.6 | Distributed storage and processing |
| Hive | 3.1.3 | SQL-on-Hadoop data warehouse |
| Python | 3.8+ | Data generation scripts |
| SSH | latest | Required for Hadoop daemon communication |

### Step-by-Step Installation (Ubuntu/Linux)

#### Step 1: Install Java

```bash
# Install OpenJDK 11
sudo apt-get update
sudo apt-get install -y openjdk-11-jdk

# Verify installation
java -version
# Expected: openjdk version "11.0.x"

# Set JAVA_HOME
echo 'export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64' >> ~/.bashrc
source ~/.bashrc
```

#### Step 2: Configure Passwordless SSH

```bash
# Hadoop requires SSH to communicate between daemons, even on a single node
sudo apt-get install -y ssh

# Generate SSH key pair (no passphrase)
ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa

# Authorize the key for localhost connections
cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
chmod 0600 ~/.ssh/authorized_keys

# Test SSH to localhost (should not prompt for password)
ssh localhost exit
```

#### Step 3: Install Hadoop 3.3.6

```bash
# Download Hadoop
cd /opt
sudo wget https://dlcdn.apache.org/hadoop/common/hadoop-3.3.6/hadoop-3.3.6.tar.gz
sudo tar -xzf hadoop-3.3.6.tar.gz
sudo mv hadoop-3.3.6 /opt/hadoop

# Set environment variables
cat >> ~/.bashrc << 'EOF'
# ─── Hadoop Environment Variables ───
export HADOOP_HOME=/opt/hadoop
export HADOOP_CONF_DIR=$HADOOP_HOME/etc/hadoop
export HADOOP_MAPRED_HOME=$HADOOP_HOME
export HADOOP_COMMON_HOME=$HADOOP_HOME
export HADOOP_HDFS_HOME=$HADOOP_HOME
export YARN_HOME=$HADOOP_HOME
export PATH=$PATH:$HADOOP_HOME/bin:$HADOOP_HOME/sbin
EOF

source ~/.bashrc

# Verify Hadoop installation
hadoop version
# Expected: Hadoop 3.3.6
```

#### Step 4: Install Hive 3.1.3

```bash
# Download Hive
cd /opt
sudo wget https://dlcdn.apache.org/hive/hive-3.1.3/apache-hive-3.1.3-bin.tar.gz
sudo tar -xzf apache-hive-3.1.3-bin.tar.gz
sudo mv apache-hive-3.1.3-bin /opt/hive

# Set environment variables
cat >> ~/.bashrc << 'EOF'
# ─── Hive Environment Variables ───
export HIVE_HOME=/opt/hive
export PATH=$PATH:$HIVE_HOME/bin
EOF

source ~/.bashrc

# Fix Guava version conflict between Hadoop 3.x and Hive 3.x
# Hive ships with an older Guava; we need to use Hadoop's version
rm $HIVE_HOME/lib/guava-19.0.jar
cp $HADOOP_HOME/share/hadoop/common/lib/guava-27.0-jre.jar $HIVE_HOME/lib/

# Initialize the Hive Metastore schema (Derby for development)
schematool -dbType derby -initSchema

# Verify Hive installation
hive --version
# Expected: Hive 3.1.3
```

### Configuration Files

See the `config/` directory for all XML configuration files. Each file is documented inline.

> **Key Concepts — Hadoop Configuration System**
>
> - Hadoop uses XML configuration files with `<property>` elements containing `<name>` and `<value>`.
> - `*-default.xml` files ship with Hadoop and contain ALL settings with defaults.
> - `*-site.xml` files are user overrides — only specify what you want to change.
> - Configuration precedence: `*-site.xml` > `*-default.xml` > hardcoded defaults.
> - The `fs.defaultFS` in `core-site.xml` is the single most important setting — it tells
>   every component where HDFS lives.

---

## 3. Data Collection

Three Python scripts generate realistic sample data. See the `scripts/data_generators/` directory.

- **Web Logs**: Apache Combined Log Format (CLF) — realistic IPs, URLs, status codes, user agents
- **IoT Sensors**: Temperature/humidity readings from simulated devices with realistic noise and anomalies
- **Social Media**: Tweet-like posts with hashtags, engagement metrics, and timestamps

Run all generators:

```bash
cd scripts/data_generators/
python generate_web_logs.py          # → ../sample_data/web_logs/access.log
python generate_iot_data.py          # → ../sample_data/iot_sensors/sensor_readings.csv
python generate_social_media.py      # → ../sample_data/social_media/tweets.csv
python generate_device_metadata.py   # → ../sample_data/device_metadata/devices.csv
```

> **Key Concepts — Data Ingestion Patterns**
>
> - **Batch Ingestion**: Files are generated locally, then uploaded to HDFS via `hdfs dfs -put`.
>   This is the simplest pattern — suitable for periodic batch loads.
> - **Flume**: Apache Flume is designed for streaming log ingestion (e.g., tailing access.log
>   in real-time). It uses Sources, Channels, and Sinks to move data reliably.
> - **Sqoop**: Apache Sqoop imports/exports data between RDBMS and HDFS. Use it when your
>   source is a SQL database (MySQL, PostgreSQL, Oracle).
> - In this project, we simulate data with Python — in production, you'd replace the scripts
>   with Flume agents (for logs) and Kafka consumers (for streaming IoT/social data).

---

## 4. HDFS Storage Design

### Directory Structure

```
/pipeline/
├── raw/                    # Immutable landing zone — raw data as-is
│   ├── web_logs/           # Apache access logs
│   ├── iot_sensors/        # Sensor CSV files
│   ├── social_media/       # Tweet CSV files
│   └── device_metadata/    # Device info (dimension table)
├── processed/              # Cleaned, transformed ORC data
│   ├── web_traffic/        # Parsed and partitioned web logs
│   ├── sensor_readings/    # Cleaned sensor data
│   └── social_posts/       # Processed social media data
├── archive/                # Historical snapshots (date-stamped)
│   └── YYYY-MM-DD/
└── output/                 # Aggregated results for BI export
    ├── hourly_traffic/
    ├── trending_hashtags/
    ├── sensor_anomalies/
    └── daily_rollups/
```

### Design Rationale

| Layer | Purpose | Retention |
|-------|---------|-----------|
| **raw/** | Data lake zone — immutable, append-only. Never modify raw data. | Indefinite |
| **processed/** | Clean, schema-enforced, optimized format (ORC). Hive managed tables live here. | Current + 1 archive cycle |
| **archive/** | Point-in-time snapshots for compliance/auditing. Date-stamped directories. | Per retention policy |
| **output/** | Aggregated query results ready for export. Small files, CSV-friendly. | Overwritten each run |

### Replication & Block Size

| Parameter | Value | Justification |
|-----------|-------|---------------|
| `dfs.replication` | 1 | Pseudo-distributed (single machine). Set to 3 for production. |
| `dfs.blocksize` | 128MB (134217728) | Default. Optimal for large files. Smaller blocks increase NameNode memory pressure. |

Run `scripts/hdfs_setup.sh` to create all directories and load sample data.

> **Key Concepts — HDFS Design Principles**
>
> - **Write Once, Read Many (WORM)**: HDFS is optimized for sequential reads of large files.
>   Small files (<< block size) waste NameNode memory (each file = ~150 bytes of metadata).
> - **Replication Factor**: Each block is replicated N times across different DataNodes.
>   Factor of 3 = tolerates 2 simultaneous DataNode failures.
> - **Block Placement Policy**: First replica on the writer's node, second on a different
>   rack, third on the same rack as the second (balances fault tolerance and network traffic).
> - **raw/ vs processed/ separation**: A fundamental data lake pattern. Raw data is your
>   "source of truth" — if processing logic changes, you re-derive from raw, not processed.

---

## 5. Hive Data Modeling

See the `hive/` directory for all HiveQL DDL scripts, executed in order (01_ through 07_).

### File Format Comparison

| Format | Compression | Splittable | Schema Evolution | Hive Optimization | Best For |
|--------|-------------|------------|------------------|-------------------|----------|
| **ORC** | Zlib/Snappy/LZO | ✅ | ✅ (add columns) | Predicate pushdown, vectorization, ACID | Hive-centric workloads |
| **Parquet** | Snappy/Gzip | ✅ | ✅ (add/rename) | Predicate pushdown | Multi-engine (Spark + Hive + Impala) |
| **Avro** | Snappy/Deflate | ✅ | ✅ (full) | Limited | Schema-heavy streaming (Kafka) |
| **CSV/Text** | None/Gzip | ⚠️ (Gzip=No) | ❌ | None | Raw data landing zone |

**Our choice: ORC** — We're Hive-only, and ORC gives the best compression (up to 75%), predicate pushdown, and vectorized query execution out of the box.

> **Key Concepts — Hive Table Types**
>
> - **External Table**: Metadata only in Metastore; data stays in HDFS. `DROP TABLE` removes
>   metadata but NOT data. Perfect for raw data you don't want to lose accidentally.
> - **Managed Table**: Hive owns both metadata AND data. `DROP TABLE` deletes everything.
>   Use for intermediate/processed tables where you control the lifecycle.
> - **Partitioning**: Directories on HDFS (e.g., `/table/dt=2024-01-15/`). Hive uses
>   partition pruning to skip irrelevant directories — massive speedup for date-filtered queries.
> - **Bucketing**: Hash-based file splitting within partitions. Enables efficient sampling
>   and optimized joins (sort-merge bucket join) between tables with matching bucket counts.
> - **SerDe**: Serializer/Deserializer — tells Hive how to read/write a file format.
>   `RegexSerDe` for parsing logs, `OpenCSVSerde` for CSVs, built-in ORC SerDe for ORC files.

---

## 6. Data Processing with HiveQL

See `hive/05_analytics_queries.hql` for all queries. Summary:

| Query | Description | Technique |
|-------|-------------|-----------|
| Q1 | Filter anomalous sensor readings (temp > 100°C or < -40°C) | WHERE clause filtering |
| Q2 | Aggregate web traffic by hour, URL, and status code | GROUP BY + date functions |
| Q3 | Top 10 trending hashtags | LATERAL VIEW explode() + RANK() |
| Q4 | Join sensor data with device metadata | INNER JOIN on device_id |
| Q5 | Daily and weekly rollups | GROUPING SETS / CUBE |

---

## 7. Performance Optimization

See `hive/06_performance_tuning.hql` for all optimization settings.

### Key Optimization Strategies

| Strategy | Setting | Impact |
|----------|---------|--------|
| **Tez Engine** | `SET hive.execution.engine=tez;` | 3-10x faster than MapReduce |
| **Vectorization** | `SET hive.vectorized.execution.enabled=true;` | Processes 1024 rows at a time instead of 1 |
| **CBO** | `SET hive.cbo.enable=true;` | Cost-Based Optimizer picks optimal join order |
| **Partition Pruning** | Automatic with partitioned tables | Skips irrelevant HDFS directories |
| **ORC Predicate Pushdown** | `SET hive.optimize.ppd=true;` | Skips row groups that don't match filter |
| **Map Join** | `SET hive.auto.convert.join=true;` | Broadcasts small tables to all mappers |

### EXPLAIN Plan Example

```sql
EXPLAIN
SELECT url_path, COUNT(*) as hits
FROM processed_db.web_traffic
WHERE dt = '2024-01-15' AND http_status = 200
GROUP BY url_path
ORDER BY hits DESC
LIMIT 10;
```

The EXPLAIN output shows the DAG of stages Tez will execute. Key things to look for:
- **TableScan → Filter**: Are filters pushed down to the ORC reader? (predicate pushdown)
- **ReduceSink → Group By**: How many reducers? (too few = bottleneck, too many = overhead)
- **Partition Pruning**: Does the plan show "partition predicates"? (yes = good)

---

## 8. Visualization Layer

### CSV Export

Run `scripts/export_results.sh` to export all Hive query results to local CSV files in `output/`.

### Connecting Tableau/Power BI

Both tools connect to HiveServer2 via JDBC or ODBC:

1. **Download** the Cloudera Hive ODBC/JDBC driver
2. **Configure** the connection:
   - Host: `localhost` (or cluster NameNode IP)
   - Port: `10000`
   - Database: `processed_db`
   - Authentication: `NOSASL` (dev) or `Kerberos` (production)

### Suggested Dashboards

| Data Source | Dashboard | Chart Type | Metric |
|-------------|-----------|------------|--------|
| **Web Logs** | Hourly Traffic Heatmap | Heatmap | Requests per hour × day of week |
| **Web Logs** | HTTP Status Distribution | Stacked Bar | 2xx/3xx/4xx/5xx by hour |
| **Web Logs** | Top Pages Funnel | Funnel | Page views by URL path |
| **Web Logs** | Geographic Traffic Map | Map | Requests by IP geolocation |
| **IoT Sensors** | Real-Time Sensor Grid | Multi-line | Temp & humidity per device |
| **IoT Sensors** | Anomaly Alert Dashboard | Scatter + Threshold | Flagged anomalous readings |
| **IoT Sensors** | Device Health Scorecard | KPI Cards | Uptime, avg temp, alert count |
| **IoT Sensors** | Location Heatmap | Geographic Heat | Readings by facility/zone |
| **Social Media** | Trending Hashtags Leaderboard | Horizontal Bar | Top 20 hashtags by mention count |
| **Social Media** | Engagement Timeline | Area Chart | Likes + retweets over time |
| **Social Media** | Sentiment Word Cloud | Word Cloud | Most frequent words in posts |
| **Social Media** | Influencer Network | Bubble Chart | Users by follower count × activity |

---

## 9. Error Handling & Monitoring

### Common Failure Points

| Failure | Symptom | Resolution |
|---------|---------|------------|
| NameNode not starting | `Connection refused` on port 9000 | Check logs: `$HADOOP_HOME/logs/hadoop-*-namenode-*.log`. Re-format NameNode: `hdfs namenode -format` |
| HDFS safe mode | `Cannot create file. NameNode is in safe mode.` | Wait for DataNode to register, or: `hdfs dfsadmin -safemode leave` |
| Hive Metastore conflict | `MetaException: Version info not found` | Re-initialize: `schematool -dbType derby -initSchema` |
| Guava version clash | `NoSuchMethodError: com.google.common.base...` | Replace Hive's guava jar with Hadoop's (see setup) |
| Tez not found | `TezSession has not been started` | Ensure Tez JARs are in HDFS: `hdfs dfs -put tez.tar.gz /apps/tez/` |
| OOM on reducer | `Container killed by YARN for exceeding memory` | Increase `mapreduce.reduce.memory.mb` or reduce data skew |
| Small files problem | Slow NameNode, many mappers | Merge small files: `ALTER TABLE ... CONCATENATE` for ORC |

### Monitoring Endpoints

| Component | URL | Purpose |
|-----------|-----|---------|
| NameNode | `http://localhost:9870` | HDFS health, block reports, capacity |
| ResourceManager | `http://localhost:8088` | Running/completed apps, cluster resources |
| NodeManager | `http://localhost:8042` | Container logs, local resource usage |
| HiveServer2 | `http://localhost:10002` | Active sessions, query execution stats |

### Log Locations

```bash
# Hadoop logs
$HADOOP_HOME/logs/hadoop-*-namenode-*.log
$HADOOP_HOME/logs/hadoop-*-datanode-*.log
$HADOOP_HOME/logs/yarn-*-resourcemanager-*.log

# Hive logs
/tmp/$USER/hive.log                          # Default location
$HIVE_HOME/logs/                             # If configured

# YARN application logs (after job completion)
yarn logs -applicationId application_XXXX_YYYY
```

> **Key Concepts — Production Monitoring**
>
> - **Heartbeat Mechanism**: DataNodes send heartbeats to NameNode every 3 seconds.
>   If no heartbeat for 10 minutes (default), the DataNode is marked dead and blocks are
>   re-replicated.
> - **YARN ResourceManager HA**: In production, run 2 ResourceManagers in Active/Standby mode
>   with ZooKeeper-based automatic failover.
> - **Hive EXPLAIN**: Always run `EXPLAIN` before executing expensive queries. Look for
>   partition pruning, predicate pushdown, and total number of map/reduce tasks.
> - **Log Aggregation**: Enable `yarn.log-aggregation-enable=true` to centralize container
>   logs on HDFS for post-mortem debugging.

---

## 10. What You've Learned

### Hadoop Architecture
- ✅ HDFS master-slave architecture (NameNode + DataNodes)
- ✅ Block storage, replication, and fault tolerance
- ✅ YARN resource management (ResourceManager + NodeManagers)
- ✅ How Hive maps SQL semantics onto HDFS data

### Data Modeling
- ✅ External vs Managed tables — when to use each
- ✅ Partitioning for query performance (partition pruning)
- ✅ Bucketing for sampling and optimized joins
- ✅ File format trade-offs (ORC vs Parquet vs Avro)
- ✅ Schema-on-read vs schema-on-write

### Data Processing
- ✅ ETL pipeline: raw text → cleaned ORC
- ✅ Complex HiveQL: window functions, LATERAL VIEW, GROUPING SETS
- ✅ Performance optimization: Tez, vectorization, CBO, predicate pushdown
- ✅ EXPLAIN plan analysis

### Pipeline Design
- ✅ Data lake directory patterns (raw / processed / archive / output)
- ✅ Batch ingestion workflow
- ✅ BI tool integration via JDBC/ODBC
- ✅ Error handling and monitoring strategies

---

**🎉 Congratulations!** You've built a complete, production-grade Big Data pipeline. From raw data ingestion through HDFS storage, Hive transformation, and BI-ready output — you now understand every layer of the Hadoop ecosystem.
