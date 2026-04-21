#!/usr/bin/env python3
"""
╔══════════════════════════════════════════════════════════════════════╗
║  generate_web_logs.py — Apache Web Server Log Generator            ║
║                                                                    ║
║  Simulates realistic Apache Combined Log Format (CLF) entries:    ║
║  IP_ADDRESS - - [TIMESTAMP] "METHOD URL HTTP/1.1" STATUS BYTES    ║
║  "REFERRER" "USER_AGENT"                                           ║
║                                                                    ║
║  Output: ../../sample_data/web_logs/access.log                     ║
║  Usage:  python generate_web_logs.py [--rows 50000]                ║
╚══════════════════════════════════════════════════════════════════════╝
"""

import random
import argparse
import os
from datetime import datetime, timedelta

# ─── Configuration ──────────────────────────────────────────────────────────
OUTPUT_DIR  = os.path.join(os.path.dirname(__file__), "../../sample_data/web_logs")
OUTPUT_FILE = os.path.join(OUTPUT_DIR, "access.log")
DEFAULT_ROWS = 50_000   # Realistic dataset size

# ─── Realistic sample data pools ────────────────────────────────────────────

# IP ranges mimicking different geographic regions
IP_POOLS = [
    # North America
    [f"192.168.{random.randint(0,255)}.{random.randint(1,254)}" for _ in range(100)],
    # Europe
    [f"10.{random.randint(0,255)}.{random.randint(0,255)}.{random.randint(1,254)}" for _ in range(100)],
    # Asia Pacific
    [f"172.{random.randint(16,31)}.{random.randint(0,255)}.{random.randint(1,254)}" for _ in range(100)],
]
ALL_IPS = [ip for pool in IP_POOLS for ip in pool]

# URL paths — weighted towards homepage and product pages (80/20 rule)
URL_PATHS_COMMON = [
    "/",
    "/index.html",
    "/products",
    "/products/electronics",
    "/products/clothing",
    "/about",
    "/contact",
    "/search?q=laptop",
    "/search?q=phone",
    "/cart",
    "/checkout",
    "/login",
    "/register",
    "/api/v1/products",
    "/api/v1/users",
]

URL_PATHS_RARE = [
    "/admin",
    "/admin/dashboard",
    "/wp-admin",                    # Common attack probe
    "/.env",                         # Security probe
    "/phpmyadmin",                   # Security probe
    "/api/v1/internal/metrics",
    "/favicon.ico",
    "/robots.txt",
    "/sitemap.xml",
    "/static/css/main.css",
    "/static/js/bundle.js",
    "/images/logo.png",
    "/blog/post/1",
    "/blog/post/2",
    "/news/latest",
]

# HTTP methods — weighted (GET is ~90% of real traffic)
HTTP_METHODS = ["GET"] * 70 + ["POST"] * 15 + ["PUT"] * 8 + ["DELETE"] * 4 + ["HEAD"] * 3

# HTTP status codes — weighted to reflect real-world distribution
HTTP_STATUSES = (
    [200] * 60 +   # OK — most frequent
    [304] * 12 +   # Not Modified (browser cache)
    [301] * 5 +    # Moved Permanently
    [302] * 5 +    # Found (redirect)
    [404] * 10 +   # Not Found
    [403] * 4 +    # Forbidden
    [500] * 3 +    # Internal Server Error
    [503] * 1      # Service Unavailable
)

# Realistic user agents
USER_AGENTS = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36",
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_1_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.1 Mobile/15E148 Safari/604.1",
    "Mozilla/5.0 (Android 14; Mobile; rv:109.0) Gecko/118.0 Firefox/118.0",
    "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)",
    "Mozilla/5.0 (compatible; Bingbot/2.0; +http://www.bing.com/bingbot.htm)",
    "curl/7.88.1",                                          # API client
    "python-requests/2.31.0",                               # Automated script
    "PostmanRuntime/7.36.0",                                # Dev testing
]

# Referrers
REFERRERS = [
    "-",                              # Direct traffic (no referrer)
    "-",
    "-",
    "https://www.google.com/",
    "https://www.google.com/",
    "https://www.google.com/",
    "https://www.bing.com/",
    "https://www.facebook.com/",
    "https://twitter.com/",
    "https://www.reddit.com/",
    "https://example-partner.com/",
]


def random_ip() -> str:
    """Return a random IP address from pre-generated pool."""
    return random.choice(ALL_IPS)


def random_url() -> str:
    """Return a URL path, weighted 80% common, 20% rare."""
    if random.random() < 0.80:
        return random.choice(URL_PATHS_COMMON)
    return random.choice(URL_PATHS_RARE)


def random_timestamp(start: datetime, end: datetime) -> str:
    """
    Return a timestamp string in Apache CLF format:
    [DD/Mon/YYYY:HH:MM:SS +0000]
    Timestamps are not perfectly monotonic — real logs have concurrent requests.
    """
    delta   = end - start
    seconds = random.randint(0, int(delta.total_seconds()))
    dt      = start + timedelta(seconds=seconds)
    return dt.strftime("[%d/%b/%Y:%H:%M:%S +0000]")


def random_bytes(method: str, status: int) -> int:
    """Simulate response size in bytes based on method and status."""
    if method == "GET" and status == 200:
        return random.randint(200, 150_000)   # HTML/JSON/image response
    elif status in (301, 302, 304):
        return random.randint(0, 512)          # Redirect, minimal body
    elif status == 404:
        return random.randint(150, 2_000)      # Error page
    elif status >= 500:
        return random.randint(50, 500)         # Server error page
    else:
        return random.randint(100, 5_000)


def generate_log_entry(start: datetime, end: datetime) -> str:
    """
    Generate a single Apache Combined Log Format entry.
    
    Format:
    <ip> - - <timestamp> "<method> <url> HTTP/1.1" <status> <bytes> "<referrer>" "<ua>"
    
    The two dashes represent:
    1. RFC 1413 ident (always - in modern web)
    2. Auth user (- if no HTTP auth required)
    """
    ip        = random_ip()
    timestamp = random_timestamp(start, end)
    method    = random.choice(HTTP_METHODS)
    url       = random_url()
    status    = random.choice(HTTP_STATUSES)
    size      = random_bytes(method, status)
    referrer  = random.choice(REFERRERS)
    ua        = random.choice(USER_AGENTS)

    # Apache Combined Log Format
    return f'{ip} - - {timestamp} "{method} {url} HTTP/1.1" {status} {size} "{referrer}" "{ua}"'


def main():
    parser = argparse.ArgumentParser(description="Generate synthetic Apache web server access logs")
    parser.add_argument("--rows",   type=int, default=DEFAULT_ROWS,
                        help=f"Number of log entries to generate (default: {DEFAULT_ROWS:,})")
    parser.add_argument("--days",   type=int, default=30,
                        help="Spread entries across this many days (default: 30)")
    parser.add_argument("--output", type=str, default=OUTPUT_FILE,
                        help=f"Output file path (default: {OUTPUT_FILE})")
    args = parser.parse_args()

    # Time window for log entries
    end_time   = datetime(2024, 1, 31, 23, 59, 59)
    start_time = end_time - timedelta(days=args.days)

    # Create output directory if needed
    os.makedirs(os.path.dirname(args.output), exist_ok=True)

    print(f"[+] Generating {args.rows:,} web log entries...")
    print(f"    Time range: {start_time.date()} → {end_time.date()}")
    print(f"    Output:     {args.output}")

    generated = 0
    with open(args.output, "w", encoding="utf-8") as f:
        for i in range(args.rows):
            entry = generate_log_entry(start_time, end_time)
            f.write(entry + "\n")
            generated += 1

            # Progress indicator every 10,000 rows
            if generated % 10_000 == 0:
                print(f"    Progress: {generated:,} / {args.rows:,} entries written...")

    print(f"\n[✓] Done! Generated {generated:,} log entries → {args.output}")
    print(f"    File size: {os.path.getsize(args.output) / 1024 / 1024:.1f} MB")


if __name__ == "__main__":
    main()
