#!/usr/bin/env python3
"""
╔══════════════════════════════════════════════════════════════════════╗
║  generate_iot_data.py — IoT Sensor Readings Generator              ║
║                                                                    ║
║  Simulates temperature and humidity readings from a fleet of       ║
║  distributed IoT devices. Includes:                                ║
║   - Realistic sensor noise (Gaussian)                              ║
║   - Intentional anomalies (for Hive filtering queries)             ║
║   - Device-specific baselines (e.g., boiler room vs server room)  ║
║   - Data quality issues (missing values, duplicate readings)       ║
║                                                                    ║
║  Output: ../../sample_data/iot_sensors/sensor_readings.csv         ║
║  Usage:  python generate_iot_data.py [--rows 100000]               ║
╚══════════════════════════════════════════════════════════════════════╝
"""

import csv
import random
import argparse
import os
import math
from datetime import datetime, timedelta

# ─── Configuration ──────────────────────────────────────────────────────────
OUTPUT_DIR  = os.path.join(os.path.dirname(__file__), "../../sample_data/iot_sensors")
OUTPUT_FILE = os.path.join(OUTPUT_DIR, "sensor_readings.csv")
DEFAULT_ROWS = 100_000

# ─── Device Fleet Definition ────────────────────────────────────────────────
# Each device has a zone-dependent baseline temperature, humidity, and anomaly rate

DEVICES = [
    # (device_id, location,         zone,          base_temp, base_humidity, anomaly_rate)
    ("SENSOR-001", "Building-A",    "server_room",   18.0,      45.0,          0.02),
    ("SENSOR-002", "Building-A",    "server_room",   19.5,      43.0,          0.01),
    ("SENSOR-003", "Building-B",    "office",        22.0,      55.0,          0.005),
    ("SENSOR-004", "Building-B",    "office",        21.8,      57.0,          0.005),
    ("SENSOR-005", "Building-C",    "warehouse",     15.0,      65.0,          0.03),
    ("SENSOR-006", "Building-C",    "warehouse",     14.5,      67.0,          0.03),
    ("SENSOR-007", "Building-D",    "boiler_room",   35.0,      30.0,          0.05),
    ("SENSOR-008", "Building-D",    "boiler_room",   38.0,      28.0,          0.05),
    ("SENSOR-009", "Building-E",    "cold_storage",  -5.0,      85.0,          0.04),
    ("SENSOR-010", "Building-E",    "cold_storage",  -3.0,      83.0,          0.04),
    ("SENSOR-011", "Building-F",    "lab",           20.0,      40.0,          0.01),
    ("SENSOR-012", "Building-F",    "lab",           20.5,      42.0,          0.01),
    ("SENSOR-013", "Building-G",    "cafeteria",     24.0,      60.0,          0.01),
    ("SENSOR-014", "Building-H",    "datacenter",    16.0,      40.0,          0.02),
    ("SENSOR-015", "Building-H",    "datacenter",    17.0,      38.0,          0.02),
]

# ─── Helper Functions ────────────────────────────────────────────────────────

def sine_wave_offset(timestamp: datetime, period_hours: float = 24, amplitude: float = 2.0) -> float:
    """
    Add diurnal (day/night) temperature variation using a sine wave.
    Real buildings are warmest in afternoon, coolest at night.
    
    period_hours: Cycle length (24 = daily variation)
    amplitude:    Peak-to-trough variation in degrees
    """
    hour_of_day = timestamp.hour + timestamp.minute / 60.0
    # Peak at 14:00 (2 PM), trough at 04:00 (4 AM)
    phase = 2 * math.pi * (hour_of_day - 4) / period_hours
    return amplitude * math.sin(phase)


def generate_reading(
    device_id: str,
    location: str,
    zone: str,
    base_temp: float,
    base_humidity: float,
    anomaly_rate: float,
    timestamp: datetime,
    reading_id: int
) -> dict:
    """
    Generate a single sensor reading for a given device.
    
    Noise model:
      - Normal readings: base ± Gaussian noise ± diurnal variation
      - Anomalous readings: base ± extreme values (simulates sensor failure or real events)
    """
    # Determine if this reading is anomalous
    is_anomaly = random.random() < anomaly_rate

    if is_anomaly:
        # Anomaly types:
        # Type 1: Sensor spike (hardware malfunction) → wildly out-of-range value
        # Type 2: Physical event (fire, AC failure, freezer door left open)
        anomaly_type = random.choice(["spike", "event"])
        if anomaly_type == "spike":
            temperature = random.uniform(-60, 150)       # Completely out of physical range
            humidity    = random.uniform(-10, 110)        # Impossible range (>100% or <0%)
        else:
            # Physical event: gradual but extreme
            temperature = base_temp + random.uniform(60, 80)  # Overheating event
            humidity    = base_humidity + random.uniform(30, 50)
        status = "ANOMALY"
    else:
        # Normal reading: base + daily variation + sensor noise
        daily_offset  = sine_wave_offset(timestamp)
        temp_noise    = random.gauss(0, 0.5)              # Gaussian noise σ=0.5°C
        humid_noise   = random.gauss(0, 1.5)              # Gaussian noise σ=1.5%
        temperature   = base_temp   + daily_offset + temp_noise
        humidity      = base_humidity + humid_noise
        # Clamp humidity to physically valid range [0, 100]
        humidity      = max(0.0, min(100.0, humidity))
        status        = "OK"

    # Simulate occasional missing/null values (~0.5% of readings)
    if random.random() < 0.005:
        temperature = None
        humidity    = None
        status      = "MISSING"

    # Simulate duplicate readings (sensor retransmitting same packet, ~0.2%)
    # We mark these for detection in Hive dedup queries
    is_duplicate = random.random() < 0.002

    return {
        "reading_id":   reading_id,
        "device_id":    device_id,
        "location":     location,
        "zone":         zone,
        "timestamp":    timestamp.strftime("%Y-%m-%d %H:%M:%S"),
        "temperature":  round(temperature, 2) if temperature is not None else "",
        "humidity":     round(humidity, 2)   if humidity    is not None else "",
        "status":       status,
        "is_duplicate": is_duplicate,
    }


def main():
    parser = argparse.ArgumentParser(description="Generate synthetic IoT sensor readings")
    parser.add_argument("--rows",     type=int, default=DEFAULT_ROWS,
                        help=f"Number of readings to generate (default: {DEFAULT_ROWS:,})")
    parser.add_argument("--days",     type=int, default=30,
                        help="Spread readings across this many days (default: 30)")
    parser.add_argument("--output",   type=str, default=OUTPUT_FILE,
                        help=f"Output file path (default: {OUTPUT_FILE})")
    args = parser.parse_args()

    # Time window matching web log generator
    end_time   = datetime(2024, 1, 31, 23, 59, 59)
    start_time = end_time - timedelta(days=args.days)
    total_seconds = int((end_time - start_time).total_seconds())

    os.makedirs(os.path.dirname(args.output), exist_ok=True)

    # CSV columns
    fieldnames = [
        "reading_id", "device_id", "location", "zone",
        "timestamp", "temperature", "humidity", "status", "is_duplicate"
    ]

    print(f"[+] Generating {args.rows:,} IoT sensor readings...")
    print(f"    Devices:    {len(DEVICES)} sensors across {len(set(d[2] for d in DEVICES))} zones")
    print(f"    Time range: {start_time.date()} → {end_time.date()}")
    print(f"    Output:     {args.output}")

    generated = 0
    with open(args.output, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()

        for reading_id in range(1, args.rows + 1):
            # Pick a random device
            device = random.choice(DEVICES)
            device_id, location, zone, base_temp, base_humidity, anomaly_rate = device

            # Random timestamp within our time window
            offset      = random.randint(0, total_seconds)
            timestamp   = start_time + timedelta(seconds=offset)

            row = generate_reading(
                device_id, location, zone,
                base_temp, base_humidity, anomaly_rate,
                timestamp, reading_id
            )
            writer.writerow(row)
            generated += 1

            if generated % 20_000 == 0:
                print(f"    Progress: {generated:,} / {args.rows:,} readings written...")

    print(f"\n[✓] Done! Generated {generated:,} sensor readings → {args.output}")

    # Statistics summary
    anomaly_count = int(args.rows * sum(d[5] for d in DEVICES) / len(DEVICES))
    print(f"    Estimated anomalies: ~{anomaly_count:,} readings ({anomaly_count/args.rows*100:.1f}%)")
    print(f"    File size: {os.path.getsize(args.output) / 1024:.1f} KB")


if __name__ == "__main__":
    main()
