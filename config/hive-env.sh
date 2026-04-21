#!/usr/bin/env bash
# Hive Environment — Java 8 required for Hive 3.1.3 on this system
#
# Root cause: SessionState.java:413 casts AppClassLoader -> URLClassLoader.
# Java 8: AppClassLoader IS-A URLClassLoader (works).
# Java 11: AppClassLoader is NOT a URLClassLoader (ClassCastException).
#
# Hadoop still uses Java 11 via its own hadoop-env.sh. Only Hive uses Java 8.

export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64

export HIVE_SERVER2_HEAPSIZE=1024
export HIVE_METASTORE_HEAP_SIZE=512
export HADOOP_HEAPSIZE=512

export HADOOP_HOME=/opt/hadoop
export HIVE_HOME=/opt/hive
export HIVE_CONF_DIR=/opt/hive/conf
