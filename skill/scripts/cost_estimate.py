#!/usr/bin/env python3
"""cost_estimate.py — rough monthly cost estimate for a stack.

Reads a YAML spec describing the resources you plan to provision and prints
a per-line breakdown + total. Use it in Phase 1 (TDR) to keep the architecture
honest against the user's budget. Prices are conservative AWS US-East defaults
and **must** be reconciled with the official calculator for a real budget.

Usage:
    python cost_estimate.py spec.yml

spec.yml example:

    compute:
      - { kind: ecs_fargate, vcpu: 0.5, mem_gb: 1, count: 2, hours: 730 }
    database:
      - { kind: rds_postgres, instance: db.t4g.small, storage_gb: 100, multi_az: true }
    cache:
      - { kind: elasticache, instance: cache.t4g.micro, count: 1 }
    storage:
      - { kind: s3, storage_gb: 50, get_per_day: 10000, put_per_day: 1000 }
    egress_gb: 100
    cloudwatch_ingest_gb: 5
    llm:
      - { provider: anthropic, model: claude-sonnet, input_tokens_per_day: 5_000_000, output_tokens_per_day: 1_000_000 }
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

try:
    import yaml  # type: ignore[import-not-found]
except ImportError:
    sys.exit("pyyaml required: pip install pyyaml")


# Conservative AWS us-east-1 baseline. Update annually.
ECS_FARGATE_PER_VCPU_HR = 0.04048
ECS_FARGATE_PER_GB_HR = 0.004445

RDS_PRICES = {
    "db.t4g.micro":  {"on_demand": 0.016},
    "db.t4g.small":  {"on_demand": 0.032},
    "db.t4g.medium": {"on_demand": 0.065},
    "db.t4g.large":  {"on_demand": 0.129},
}
RDS_STORAGE_GP3_PER_GB_MO = 0.115
RDS_BACKUP_PER_GB_MO = 0.095

ELASTICACHE_PRICES = {
    "cache.t4g.micro":  0.016,
    "cache.t4g.small":  0.032,
    "cache.t4g.medium": 0.065,
}

S3_STORAGE_PER_GB_MO = 0.023
S3_PUT_PER_1K = 0.005
S3_GET_PER_1K = 0.0004

EGRESS_PER_GB = 0.09
CW_INGEST_PER_GB = 0.50

LLM_PRICES = {
    # $/M tokens (input, output) — verify before quoting.
    ("anthropic", "claude-haiku"):  (0.80, 4.00),
    ("anthropic", "claude-sonnet"): (3.00, 15.00),
    ("anthropic", "claude-opus"):   (15.00, 75.00),
    ("openai",    "gpt-4o-mini"):   (0.15, 0.60),
    ("openai",    "gpt-4o"):        (2.50, 10.00),
    ("google",    "gemini-flash"):  (0.075, 0.30),
    ("google",    "gemini-pro"):    (1.25, 5.00),
}


def cost_compute(spec: list[dict]) -> float:
    total = 0.0
    for r in spec or []:
        if r["kind"] == "ecs_fargate":
            hours = r.get("hours", 730)
            count = r.get("count", 1)
            total += (r["vcpu"] * ECS_FARGATE_PER_VCPU_HR + r["mem_gb"] * ECS_FARGATE_PER_GB_HR) * hours * count
    return total


def cost_database(spec: list[dict]) -> float:
    total = 0.0
    for r in spec or []:
        if r["kind"] == "rds_postgres":
            hr = RDS_PRICES.get(r["instance"], {"on_demand": 0.05})["on_demand"]
            multiplier = 2.0 if r.get("multi_az") else 1.0
            total += hr * 730 * multiplier
            total += r.get("storage_gb", 0) * RDS_STORAGE_GP3_PER_GB_MO
            backup_gb = r.get("backup_storage_gb", r.get("storage_gb", 0))
            total += backup_gb * RDS_BACKUP_PER_GB_MO
    return total


def cost_cache(spec: list[dict]) -> float:
    total = 0.0
    for r in spec or []:
        if r["kind"] == "elasticache":
            hr = ELASTICACHE_PRICES.get(r["instance"], 0.05)
            total += hr * 730 * r.get("count", 1)
    return total


def cost_storage(spec: list[dict]) -> float:
    total = 0.0
    for r in spec or []:
        if r["kind"] == "s3":
            total += r.get("storage_gb", 0) * S3_STORAGE_PER_GB_MO
            total += r.get("put_per_day", 0) * 30 / 1000 * S3_PUT_PER_1K
            total += r.get("get_per_day", 0) * 30 / 1000 * S3_GET_PER_1K
    return total


def cost_llm(spec: list[dict]) -> float:
    total = 0.0
    for r in spec or []:
        key = (r["provider"], r["model"])
        if key not in LLM_PRICES:
            print(f"warn: unknown LLM model {key}", file=sys.stderr)
            continue
        in_per_m, out_per_m = LLM_PRICES[key]
        days = 30
        total += r.get("input_tokens_per_day", 0) / 1_000_000 * in_per_m * days
        total += r.get("output_tokens_per_day", 0) / 1_000_000 * out_per_m * days
    return total


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("spec", type=Path)
    args = p.parse_args()

    data = yaml.safe_load(args.spec.read_text())

    items: list[tuple[str, float]] = [
        ("Compute (ECS Fargate)", cost_compute(data.get("compute", []))),
        ("Database (RDS)",        cost_database(data.get("database", []))),
        ("Cache (ElastiCache)",   cost_cache(data.get("cache", []))),
        ("Storage (S3)",          cost_storage(data.get("storage", []))),
        ("Egress",                data.get("egress_gb", 0) * EGRESS_PER_GB),
        ("CloudWatch logs",       data.get("cloudwatch_ingest_gb", 0) * CW_INGEST_PER_GB),
        ("LLM",                   cost_llm(data.get("llm", []))),
    ]

    total = sum(v for _, v in items)
    width = max(len(n) for n, _ in items) + 2

    print("Monthly cost estimate (USD, rough)")
    print("-" * (width + 12))
    for name, value in items:
        print(f"{name:<{width}} ${value:>8.2f}")
    print("-" * (width + 12))
    print(f"{'Total':<{width}} ${total:>8.2f}")
    print()
    print("note: AWS us-east-1 baseline; verify against the official calculator")
    print("before quoting to the user.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
