-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  06_performance_tuning.hql — Hive Optimization Reference           ║
-- ║                                                                    ║
-- ║  Demonstrates key Hive performance settings with EXPLAIN output.   ║
-- ║                                                                    ║
-- ║  Topics covered:                                                   ║
-- ║    1. Execution engine settings (Tez vs MapReduce)                 ║
-- ║    2. Vectorized execution                                         ║
-- ║    3. Cost-Based Optimizer (CBO) with statistics                   ║
-- ║    4. Join optimization (Map Join, Sort-Merge Bucket Join)         ║
-- ║    5. Predicate pushdown                                           ║
-- ║    6. Partition and data skew handling                             ║
-- ║    7. EXPLAIN plan interpretation                                  ║
-- ╚══════════════════════════════════════════════════════════════════════╝

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- SECTION 1: Execution Engine
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

--
-- TEZ vs MAPREDUCE COMPARISON:
--
--   MapReduce pipeline:
--     Map → [write to HDFS] → Shuffle → [write to HDFS] → Reduce → [write to HDFS]
--     Every stage boundary hits disk. 3-stage MR query = 6 disk writes minimum.
--
--   Tez pipeline (DAG):
--     Map → [in-memory pipe] → Tez Vertex → [in-memory pipe] → Tez Vertex → HDFS
--     Intermediate results stay in memory. 10-100x faster for multi-stage queries.
--
-- To use Tez (requires Tez installation: tez.tar.gz in HDFS /apps/tez/):
-- SET hive.execution.engine = tez;

-- Using MapReduce (always available — Tez not installed in this dev setup):
SET hive.execution.engine = mr;

-- Tez container reuse — keep containers warm between tasks (avoids JVM startup cost)
SET tez.am.container.reuse.enabled = true;

-- Tez DAG recovery in case of container failure
SET tez.am.dag.recovery.enabled = true;

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- SECTION 2: Vectorized Execution
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

--
-- VECTORIZATION:
--   Standard Hive: processes 1 row at a time → 1 function call per row
--   Vectorized Hive: processes 1024 rows per batch → 1 function call per batch
--
--   Requires:
--   1. ORC or Parquet file format (columnar storage organizes data in batches)
--   2. Compatible operations (most arithmetic, comparisons, casts are vectorized)
--   3. NOT available for: user-defined functions (UDFs), SORT BY, some complex types
--
--   Speedup: 2-5x for scan-heavy queries, negligible for join-heavy queries.
--
SET hive.vectorized.execution.enabled              = true;
SET hive.vectorized.execution.reduce.enabled       = true;
SET hive.vectorized.execution.reduce.groupby.enabled = true;

-- Verify vectorization is being used (look for "VECTORIZED" in EXPLAIN output):
-- EXPLAIN VECTORIZATION DETAIL SELECT ...;

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- SECTION 3: Cost-Based Optimizer (CBO) with Column Statistics
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

--
-- CBO (Cost-Based Optimizer):
--   Without CBO: Hive uses rule-based optimization (fixed join order, heuristics)
--   With CBO:    Hive uses statistics (row count, cardinality, data distribution)
--               to estimate costs and choose the optimal execution plan.
--
--   CBO Benefits:
--   • Optimal join ORDER (put smallest tables first to minimize intermediate results)
--   • Optimal join ALGORITHM (map join vs sort-merge join)
--   • Better predicate pushdown decisions
--   • Column-level statistics for filter selectivity estimates
--
-- Enable CBO
SET hive.cbo.enable = true;

-- Tell CBO to use column-level statistics when available
SET hive.compute.query.using.stats   = true;
SET hive.stats.fetch.column.stats    = true;
SET hive.stats.fetch.partition.stats = true;

-- Automatically gather stats on INSERT (keeps CBO data fresh)
SET hive.stats.autogather = true;

-- ── Gather Statistics (run AFTER ETL loads data) ─────────────────────────

-- Table-level statistics: row count, total size, number of files
ANALYZE TABLE processed_db.web_traffic COMPUTE STATISTICS;
ANALYZE TABLE processed_db.sensor_readings COMPUTE STATISTICS;
ANALYZE TABLE processed_db.social_posts COMPUTE STATISTICS;
ANALYZE TABLE processed_db.device_metadata COMPUTE STATISTICS;

-- Column-level statistics: cardinality, min/max, num nulls, avg length
-- CBO uses these to estimate filter selectivity (e.g., "WHERE status = 'OK'" → ~95% rows)
ANALYZE TABLE processed_db.web_traffic
    COMPUTE STATISTICS FOR COLUMNS
    client_ip, http_method, url_path, http_status, response_bytes, request_hour;

ANALYZE TABLE processed_db.sensor_readings
    COMPUTE STATISTICS FOR COLUMNS
    device_id, temperature, humidity, status, data_quality_score;

ANALYZE TABLE processed_db.device_metadata
    COMPUTE STATISTICS FOR COLUMNS
    device_id, zone, sla_tier, manufacturer;

-- View gathered statistics
DESCRIBE EXTENDED processed_db.sensor_readings;
DESCRIBE FORMATTED processed_db.device_metadata;

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- SECTION 4: Join Optimization
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

--
-- JOIN ALGORITHM COMPARISON:
--
-- 1. COMMON JOIN (Shuffle Join / Reduce-Side Join):
--    • Default when tables are large
--    • Both tables sorted and shuffled by join key to reducers
--    • High network I/O (all data moved to reducers)
--    • Scales to any table size
--
-- 2. MAP JOIN (Broadcast Join):
--    • Small table fits in memory (< mapjoin.smalltable.filesize)
--    • Small table loaded into each mapper's memory (hash map)
--    • No shuffle phase → massive speedup for star-schema joins
--    • Perfect for: large fact table JOIN small dimension table
--
-- 3. SORT-MERGE BUCKET JOIN (SMB Join):
--    • BOTH tables bucketed on the same key, same number of buckets
--    • Sorted within each bucket
--    • Mappers read one bucket from each table, merge-join them
--    • Avoids shuffle entirely — largest tables can join efficiently
--    • Requires: CLUSTERED BY (key) on both tables
--

-- Enable automatic map join conversion
SET hive.auto.convert.join = true;

-- Map join threshold (bytes): tables smaller than this → map join
SET hive.mapjoin.smalltable.filesize = 25000000;   -- 25MB

-- Enable bucket map join
SET hive.optimize.bucketmapjoin = true;

-- Enable sort-merge bucket join (requires bucketed, sorted tables)
SET hive.auto.convert.sortmerge.join = true;
SET hive.optimize.bucketmapjoin.sortedmerge = true;

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- SECTION 5: Predicate Pushdown (PPD)
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

--
-- PREDICATE PUSHDOWN (PPD) for ORC:
--   ORC files store stripe-level statistics (min, max, count, null count)
--   for each column. When a WHERE clause is applied, the ORC reader checks
--   stripe stats BEFORE reading any rows.
--
--   Example: WHERE temperature > 100
--   → ORC reader checks each stripe's max(temperature)
--   → If max < 100, entire stripe is SKIPPED (no disk read)
--   → Only stripes that MIGHT contain rows matching the filter are read
--
--   PPD also pushes filters into sub-queries and through JOIN operations.
--
SET hive.optimize.ppd         = true;
SET hive.optimize.ppd.storage = true;   -- PPD to storage layer (ORC)

-- Bloom filter for frequently filtered columns (set in table TBLPROPERTIES)
-- Covered in 03_optimized_tables.hql:
-- 'orc.bloom.filter.columns' = 'http_status,http_method'
-- A Bloom filter gives O(1) lookup: "is this value DEFINITELY not in this stripe?"

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- SECTION 6: Data Skew Handling
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

--
-- DATA SKEW: When one reducer gets much more data than others.
-- Symptom: "99% complete, 1 reducer still running for 2 hours"
-- Cause: GROUP BY key or JOIN key with highly unequal distribution
--        (e.g., 80% of rows have url_path='/')
--
-- Solutions:
--

-- Solution 1: Skew join optimization (for JOIN skew)
SET hive.optimize.skewjoin = true;
SET hive.skewjoin.key = 100000;    -- Key considered skewed if > 100K rows in one reducer

-- Solution 2: Limit reducer skew via MAP SIDE aggregation
-- Pre-aggregate in map phase to reduce data sent to reducers
SET hive.map.aggr = true;
SET hive.groupby.skewindata = true;   -- Two-pass GROUP BY for skewed keys

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- SECTION 7: EXPLAIN Plan — How to Read It
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

--
-- EXPLAIN shows the logical and physical plan Hive will execute.
-- Run this BEFORE executing expensive queries.
--
-- Modes:
--   EXPLAIN <query>                → Logical plan (operator tree)
--   EXPLAIN EXTENDED <query>       → Logical + physical plan
--   EXPLAIN DEPENDENCY <query>     → Input partitions the query will read
--   EXPLAIN AUTHORIZATION <query>  → Required permissions
--   EXPLAIN VECTORIZATION <query>  → Which operators are vectorized
--

-- Example: EXPLAIN a web traffic query
EXPLAIN
SELECT
    url_path,
    http_status,
    COUNT(*)                AS total_requests,
    SUM(response_bytes)     AS total_bytes
FROM processed_db.web_traffic
WHERE
    dt = '2024-01-15'           -- Partition filter: Hive should prune other dates
    AND http_status = 200        -- Non-partition filter: ORC PPD may skip stripes
GROUP BY url_path, http_status
ORDER BY total_requests DESC
LIMIT 10;

--
-- HOW TO READ THE EXPLAIN OUTPUT:
--
-- Look for these key items:
--
-- 1. "Partition Pruning":
--    "pruned partition predicates: (dt = '2024-01-15')"
--    → GOOD: Only the Jan 15 partition directory is read
--    MISSING → BAD: Full table scan across ALL dates
--
-- 2. "Number of rows":
--    "Statistics: Num rows: 12453 Data size: 2345678"
--    → CBO is using stats; lower number = better pruning
--
-- 3. "Map Join operator" (vs "Reduce Output Operator"):
--    "Map Join Operator" → small table broadcast; no shuffle
--    "Reduce Output Operator" → shuffle join; more I/O
--
-- 4. "ORC Pushdown Predicate":
--    "sarg: (http_status = 200)"
--    → ORC reader will skip stripes where max(http_status) < 200
--
-- 5. "VECTORIZED Execution":
--    "operates on Vectorized RowBatch"
--    → 1024-row batches processed per CPU instruction
--
-- 6. "Number of reducers":
--    Look for "estimated sum of all rows = X" — divide by 256MB target
--    Too few reducers = bottleneck; too many = task startup overhead
--

-- Extended EXPLAIN for vectorization details
EXPLAIN VECTORIZATION DETAIL
SELECT
    device_id,
    ROUND(AVG(temperature), 2) AS avg_temp,
    COUNT(*) AS readings
FROM processed_db.sensor_readings
WHERE dt = '2024-01-15'
  AND zone = 'server_room'
  AND temperature IS NOT NULL
GROUP BY device_id;

--
-- In the output, look for:
-- "allNative: true"          → All operators vectorized natively
-- "allNative: false"          → Some operators fall back to row mode
-- "notVectorizedReason: ..."  → Why a particular operator isn't vectorized
--

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- SECTION 8: Parallel Query Execution
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

-- Run independent map stages in parallel (multi-insert queries)
SET hive.exec.parallel = true;
SET hive.exec.parallel.thread.number = 8;  -- Max concurrent parallel stages

-- Example: Multi-insert — populates three tables in ONE scan of sensor_readings
-- Without hive.exec.parallel: stages run sequentially
-- With hive.exec.parallel: independent inserts run concurrently
FROM processed_db.sensor_readings
INSERT OVERWRITE TABLE processed_db.sensor_daily_summary PARTITION (dt)
    SELECT device_id, zone,
           AVG(temperature), MIN(temperature), MAX(temperature),
           AVG(humidity), COUNT(*),
           SUM(CASE WHEN status='ANOMALY' THEN 1 ELSE 0 END),
           SUM(CASE WHEN status='MISSING' THEN 1 ELSE 0 END),
           dt
    FROM processed_db.sensor_readings
    WHERE temperature IS NOT NULL
    GROUP BY device_id, zone, dt;

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- SECTION 9: Small Files Problem and Merging
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

--
-- SMALL FILES PROBLEM:
--   Hadoop works best with large files (>> block size = 128MB).
--   Each small file = one block entry in NameNode memory (~150 bytes).
--   Millions of small files → NameNode memory exhaustion → cluster instability.
--
--   Common cause: Dynamic partitioning with many partitions creates
--   one small file per partition per reducer.
--
-- Solutions:
--

-- Solution 1: Merge ORC output files after job
SET hive.merge.mapfiles             = true;   -- Merge output of map-only jobs
SET hive.merge.mapredfiles          = true;   -- Merge output of MR jobs
SET hive.merge.tezfiles             = true;   -- Merge output of Tez jobs
SET hive.merge.size.per.task        = 268435456;  -- Target: 256MB per merged file
SET hive.merge.smallfiles.avgsize   = 16777216;   -- Trigger: when avg file < 16MB

-- Solution 2: CONCATENATE command — manually merge ORC files in a partition
-- (Only works for ORC format managed tables)
-- ALTER TABLE processed_db.sensor_readings PARTITION (dt='2024-01-15', zone='office') CONCATENATE;

-- Solution 3: Control reducer count to reduce output file count
SET hive.exec.reducers.bytes.per.reducer = 268435456;  -- 1 reducer per 256MB of input
SET hive.exec.reducers.max = 1009;   -- Cap to avoid absurd parallelism
