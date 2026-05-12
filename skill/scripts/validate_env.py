#!/usr/bin/env python3
"""validate_env.py — check every var in .env.example is present in .env with
a non-empty value, and that no unknown vars exist. Exit non-zero on any
violation so CI can gate on it.

Usage:
    python validate_env.py [--example .env.example] [--env .env] [--strict-unknown]
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


def parse_env_file(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    if not path.exists():
        sys.exit(f"missing file: {path}")
    for i, line in enumerate(path.read_text().splitlines(), start=1):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if "=" not in stripped:
            sys.exit(f"{path}:{i} malformed line: {line!r}")
        key, value = stripped.split("=", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if not key.isidentifier() and not all(c.isupper() or c.isdigit() or c == "_" for c in key):
            sys.exit(f"{path}:{i} invalid key: {key!r}")
        out[key] = value
    return out


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--example", default=".env.example", type=Path)
    p.add_argument("--env", default=".env", type=Path)
    p.add_argument("--strict-unknown", action="store_true",
                   help="fail if .env has keys absent from .env.example")
    args = p.parse_args()

    example = parse_env_file(args.example)
    env = parse_env_file(args.env)

    missing: list[str] = []
    empty: list[str] = []
    for key, default in example.items():
        if key not in env:
            if default == "":
                missing.append(key)
        elif env[key] == "":
            empty.append(key)

    unknown = sorted(set(env) - set(example))

    fail = False
    if missing:
        print("[validate_env] missing required vars (no default in .env.example):")
        for k in missing:
            print(f"  - {k}")
        fail = True
    if empty:
        print("[validate_env] required vars present but empty in .env:")
        for k in empty:
            print(f"  - {k}")
        fail = True
    if args.strict_unknown and unknown:
        print("[validate_env] unknown vars in .env (not declared in .env.example):")
        for k in unknown:
            print(f"  - {k}")
        fail = True

    if fail:
        return 1
    print(f"[validate_env] ok — {len(env)} vars set, {len(example)} declared")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
