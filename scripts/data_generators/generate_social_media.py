#!/usr/bin/env python3
"""
╔══════════════════════════════════════════════════════════════════════╗
║  generate_social_media.py — Social Media Post Generator            ║
║                                                                    ║
║  Simulates Twitter/X-style posts with:                             ║
║   - Realistic usernames and follower distributions (power law)     ║
║   - Hashtag patterns including trending and niche topics           ║
║   - Engagement metrics (likes, retweets, replies, impressions)     ║
║   - Temporal patterns (viral spikes, trending windows)             ║
║                                                                    ║
║  Output: ../../sample_data/social_media/tweets.csv                 ║
║  Usage:  python generate_social_media.py [--rows 30000]            ║
╚══════════════════════════════════════════════════════════════════════╝
"""

import csv
import random
import argparse
import os
from datetime import datetime, timedelta

# ─── Configuration ──────────────────────────────────────────────────────────
OUTPUT_DIR  = os.path.join(os.path.dirname(__file__), "../../sample_data/social_media")
OUTPUT_FILE = os.path.join(OUTPUT_DIR, "tweets.csv")
DEFAULT_ROWS = 30_000

# ─── Hashtag Universe ────────────────────────────────────────────────────────
# Trending hashtags (high frequency — viral topics)
TRENDING_HASHTAGS = [
    "#BigData", "#MachineLearning", "#AI", "#TechNews",
    "#Python", "#DataScience", "#CloudComputing", "#Hadoop",
    "#OpenAI", "#ChatGPT", "#WebDev", "#Kubernetes",
]

# Niche hashtags (lower frequency — community topics)
NICHE_HASHTAGS = [
    "#ApacheHive", "#Spark", "#Kafka", "#Flink",
    "#DataEngineering", "#ETL", "#DataPipeline", "#DataLake",
    "#HDFS", "#YARN", "#MapReduce", "#HBase",
    "#DataWarehouse", "#ORC", "#Parquet", "#Avro",
    "#MLOps", "#DataOps", "#DevOps", "#GitOps",
    "#OpenSource", "#Linux", "#Docker", "#Terraform",
    "#Analytics", "#BI", "#Tableau", "#PowerBI",
]

# Wider interest hashtags (medium frequency)
GENERAL_HASHTAGS = [
    "#Tech", "#Innovation", "#Startup", "#Coding",
    "#Programming", "#Software", "#Engineering", "#Career",
    "#Learning", "#Tutorial", "#Productivity", "#Remote",
    "#Interview", "#JobSearch", "#Resume", "#Hiring",
    "#Cybersecurity", "#Privacy", "#Blockchain", "#NFT",
    "#Metaverse", "#AR", "#VR", "#IoT",
]

# Weighted pool: trending=60%, general=25%, niche=15%
def pick_hashtags(n: int = 3) -> list[str]:
    """Pick n hashtags with realistic weighting."""
    pool = (
        TRENDING_HASHTAGS * 6 +
        GENERAL_HASHTAGS  * 3 +
        NICHE_HASHTAGS    * 1
    )
    # Ensure no duplicate hashtags in a single post
    selected = list(set(random.choices(pool, k=n * 3)))[:n]
    return selected


# ─── User Base ───────────────────────────────────────────────────────────────
# Power-law follower distribution (a few influencers, many small accounts)
def generate_user(user_id: int) -> dict:
    """
    Generate a realistic user profile.
    Follower distribution follows a power law (Pareto-like):
    - Top 1% of users have 80% of followers (influencers)
    - Bottom 80% have < 1000 followers
    """
    user_type = random.choices(
        ["nano", "micro", "mid", "macro", "mega"],
        weights=[60, 20, 12, 6, 2],
        k=1
    )[0]

    follower_ranges = {
        "nano":  (10, 999),
        "micro": (1_000, 9_999),
        "mid":   (10_000, 99_999),
        "macro": (100_000, 999_999),
        "mega":  (1_000_000, 50_000_000),
    }
    lo, hi = follower_ranges[user_type]
    followers = random.randint(lo, hi)

    # Verified accounts are >10K followers, ~30% chance
    verified = followers > 10_000 and random.random() < 0.30

    username = f"user_{random.choice(['tech', 'data', 'dev', 'eng', 'ai', 'ml'])}_{user_id:05d}"
    return {
        "username":       username,
        "user_type":      user_type,
        "followers":      followers,
        "verified":       verified,
    }


# ─── Engagement Model ────────────────────────────────────────────────────────
def engagement_metrics(followers: int, hashtags: list[str]) -> dict:
    """
    Simulate realistic engagement metrics.
    
    Engagement rate:
    - Mega influencers: ~1-3% (paradox of large audiences)
    - Micro influencers: ~5-15% (niche, loyal communities)
    - Trending hashtags boost engagement by 20-40%
    
    Model:
    likes ≈ followers × engagement_rate
    retweets ≈ likes × 0.1 to 0.3
    replies ≈ likes × 0.02 to 0.08
    impressions ≈ likes × 5 to 20
    """
    # Base engagement rate by follower tier
    if followers < 1_000:
        eng_rate = random.uniform(0.02, 0.10)
    elif followers < 10_000:
        eng_rate = random.uniform(0.05, 0.15)
    elif followers < 100_000:
        eng_rate = random.uniform(0.02, 0.08)
    else:
        eng_rate = random.uniform(0.005, 0.03)

    # Boost for trending hashtags
    trending_count = sum(1 for ht in hashtags if ht in TRENDING_HASHTAGS)
    eng_multiplier = 1 + (trending_count * 0.15)

    base_likes  = int(followers * eng_rate * eng_multiplier)
    likes       = max(0, base_likes + random.randint(-base_likes // 4, base_likes // 4))
    retweets    = max(0, int(likes * random.uniform(0.08, 0.30)))
    replies     = max(0, int(likes * random.uniform(0.01, 0.07)))
    impressions = max(likes, int(likes * random.uniform(5, 20)))

    return {
        "likes":       likes,
        "retweets":    retweets,
        "replies":     replies,
        "impressions": impressions,
    }


# ─── Post Content Templates ──────────────────────────────────────────────────
TEMPLATES = [
    "Just built a {topic} pipeline from scratch. The performance gains are incredible! {hashtags}",
    "Hot take: {topic} will replace traditional databases in 5 years. Change my mind. {hashtags}",
    "Thread: Why every data engineer should learn {topic} in 2024 ↓ 1/{n} {hashtags}",
    "TIL {topic} can process {num}M records per second with the right configuration. Mind blown. {hashtags}",
    "New blog post: 'Getting Started with {topic} in {year}' — link in bio {hashtags}",
    "Finally fixed that {topic} memory issue that's been haunting me for weeks 😅 Solution: {fix}. {hashtags}",
    "Interview tip: Know your {topic} internals. Understanding {detail} will set you apart. {hashtags}",
    "Day {day} of learning {topic}: {progress}. Slowly getting the hang of it! {hashtags}",
    "Hiring! Senior {topic} Engineer @ our team. DM me for details. Top comp + remote. {hashtags}",
    "Benchmarked {topic} vs {alt}: {topic} was {percent}% faster on our {size}TB dataset. Results below ↓ {hashtags}",
    "The {topic} documentation is actually really good once you know where to look. {url} {hashtags}",
    "PSA: Remember to set {param} in your {topic} config. Lost {num} hours debugging this. {hashtags}",
]

TOPICS    = ["Apache Hive", "Hadoop", "Spark", "Kafka", "HDFS", "Flink", "Airflow", "dbt", "Databricks"]
ALT_TOOLS = ["Snowflake", "BigQuery", "Redshift", "Postgres", "MySQL", "MongoDB"]
FIXES     = ["increase heap size", "tune parallelism", "add proper partitioning", "cache the right dataset"]
DETAILS   = ["execution plans", "join strategies", "partition pruning", "data skew handling"]
PROGRESSES = ["completed Week 1", "ran first distributed query", "got the cluster running", "deployed to prod"]


def generate_post(tweet_id: int, user: dict, timestamp: datetime) -> dict:
    """Generate a single social media post."""
    hashtags     = pick_hashtags(random.randint(1, 5))
    hashtag_str  = " ".join(hashtags)

    template = random.choice(TEMPLATES)
    text = template.format(
        topic   = random.choice(TOPICS),
        alt     = random.choice(ALT_TOOLS),
        hashtags= hashtag_str,
        fix     = random.choice(FIXES),
        detail  = random.choice(DETAILS),
        progress= random.choice(PROGRESSES),
        num     = random.randint(1, 500),
        n       = random.randint(5, 20),
        percent = random.randint(20, 300),
        size    = random.choice([1, 5, 10, 50, 100]),
        day     = random.randint(1, 100),
        year    = random.choice([2024, 2025]),
        param   = random.choice(["dfs.replication", "hive.exec.parallel", "spark.executor.memory"]),
        url     = "https://docs.example.com/guide",
    )

    metrics = engagement_metrics(user["followers"], hashtags)

    return {
        "tweet_id":    tweet_id,
        "username":    user["username"],
        "user_type":   user["user_type"],
        "followers":   user["followers"],
        "verified":    user["verified"],
        "timestamp":   timestamp.strftime("%Y-%m-%d %H:%M:%S"),
        "text":        text[:280],               # Twitter's 280-char limit
        "hashtags":    " ".join(hashtags),       # Space-separated for Hive LATERAL VIEW
        "likes":       metrics["likes"],
        "retweets":    metrics["retweets"],
        "replies":     metrics["replies"],
        "impressions": metrics["impressions"],
        "language":    "en",
        "source":      random.choice(["Twitter for Android", "Twitter for iPhone", "TweetDeck", "Twitter Web App"]),
    }


def main():
    parser = argparse.ArgumentParser(description="Generate synthetic social media posts")
    parser.add_argument("--rows",   type=int, default=DEFAULT_ROWS,
                        help=f"Number of posts to generate (default: {DEFAULT_ROWS:,})")
    parser.add_argument("--days",   type=int, default=30,
                        help="Spread posts across this many days (default: 30)")
    parser.add_argument("--users",  type=int, default=5_000,
                        help="Number of unique users in the simulation (default: 5,000)")
    parser.add_argument("--output", type=str, default=OUTPUT_FILE,
                        help=f"Output file path (default: {OUTPUT_FILE})")
    args = parser.parse_args()

    # Pre-generate user pool (simulates real accounts, not per-post generation)
    print(f"[+] Generating {args.users:,} user profiles...")
    user_pool = [generate_user(i) for i in range(1, args.users + 1)]

    # Time window
    end_time      = datetime(2024, 1, 31, 23, 59, 59)
    start_time    = end_time - timedelta(days=args.days)
    total_seconds = int((end_time - start_time).total_seconds())

    os.makedirs(os.path.dirname(args.output), exist_ok=True)

    fieldnames = [
        "tweet_id", "username", "user_type", "followers", "verified",
        "timestamp", "text", "hashtags", "likes", "retweets",
        "replies", "impressions", "language", "source"
    ]

    print(f"[+] Generating {args.rows:,} posts...")
    print(f"    Time range: {start_time.date()} → {end_time.date()}")
    print(f"    Output:     {args.output}")

    generated = 0
    with open(args.output, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames, quoting=csv.QUOTE_ALL)
        writer.writeheader()

        for tweet_id in range(1, args.rows + 1):
            user      = random.choice(user_pool)
            offset    = random.randint(0, total_seconds)
            timestamp = start_time + timedelta(seconds=offset)
            row       = generate_post(tweet_id, user, timestamp)
            writer.writerow(row)
            generated += 1

            if generated % 10_000 == 0:
                print(f"    Progress: {generated:,} / {args.rows:,} posts written...")

    print(f"\n[✓] Done! Generated {generated:,} social media posts → {args.output}")
    print(f"    Unique hashtags: {len(TRENDING_HASHTAGS + NICHE_HASHTAGS + GENERAL_HASHTAGS)}")
    print(f"    File size: {os.path.getsize(args.output) / 1024:.1f} KB")


if __name__ == "__main__":
    main()
