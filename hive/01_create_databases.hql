-- ╔══════════════════════════════════════════════════════════════════════╗
-- ║  01_create_databases.hql — Database Initialization                 ║
-- ║                                                                    ║
-- ║  Creates the two-tier database architecture:                       ║
-- ║    • raw_db:       External tables on raw HDFS data               ║
-- ║    • processed_db: Managed ORC tables for optimized analytics      ║
-- ║                                                                    ║
-- ║  Usage: beeline -u jdbc:hive2://localhost:10000 -f 01_create_databases.hql
-- ╚══════════════════════════════════════════════════════════════════════╝

-- ============================================================
-- DATABASE 1: raw_db
-- 
-- Purpose: Houses EXTERNAL tables that point to raw HDFS data.
-- 
-- KEY PRINCIPLE — External Tables:
--   • Hive manages ONLY the metadata (schema, location, SerDe)
--   • Actual data stays in HDFS as-is (no movement or copy)
--   • DROP TABLE removes schema from Metastore ONLY — data is safe
--   • Perfect for the "schema-on-read" data lake pattern
--   • Multiple engines (Hive, Spark, Presto) can read the same files
-- ============================================================

CREATE DATABASE IF NOT EXISTS raw_db
    COMMENT 'Raw data layer: external tables on unprocessed HDFS data. Data is immutable here.'
    LOCATION '/pipeline/raw'
    WITH DBPROPERTIES (
        'created_by'     = 'pipeline_admin',
        'created_date'   = '2024-01-01',
        'data_retention' = 'indefinite',
        'layer'          = 'raw',
        'contact'        = 'data-engineering@company.com'
    );

-- Verify creation
DESCRIBE DATABASE EXTENDED raw_db;

-- ============================================================
-- DATABASE 2: processed_db
--
-- Purpose: Houses MANAGED tables with optimized ORC format data.
--
-- KEY PRINCIPLE — Managed Tables:
--   • Hive manages BOTH metadata AND data
--   • DROP TABLE removes BOTH schema AND HDFS data
--   • Used for curated data after ETL transformation
--   • Supports Hive ACID transactions (INSERT, UPDATE, DELETE)
--   • Supports full predicate pushdown with ORC
-- ============================================================

CREATE DATABASE IF NOT EXISTS processed_db
    COMMENT 'Processed data layer: managed ORC tables, partitioned and bucketed for optimal query performance.'
    LOCATION '/pipeline/processed'
    WITH DBPROPERTIES (
        'created_by'     = 'pipeline_admin',
        'created_date'   = '2024-01-01',
        'data_retention' = '90_days',
        'layer'          = 'processed',
        'contact'        = 'data-engineering@company.com'
    );

-- Verify creation
DESCRIBE DATABASE EXTENDED processed_db;

-- ============================================================
-- Show all databases to confirm creation
-- ============================================================
SHOW DATABASES;

--
-- EXPECTED OUTPUT:
-- ┌────────────────────┐
-- │   database_name    │
-- ├────────────────────┤
-- │   default          │
-- │   processed_db     │
-- │   raw_db           │
-- └────────────────────┘
--
