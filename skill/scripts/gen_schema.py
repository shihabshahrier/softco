#!/usr/bin/env python3
"""gen_schema.py — generate docs/DB_SCHEMA.md from SQLAlchemy models.

Looks for a `Base` (DeclarativeBase) in the given module path and dumps
each mapped table: columns, types, nullability, defaults, primary key,
unique constraints, foreign keys, indexes.

Usage:
    python gen_schema.py --models apps.api.src.db.base:Base --out docs/DB_SCHEMA.md

Module string is `package.path:attr` where `attr` is the Base.
"""

from __future__ import annotations

import argparse
import importlib
import sys
from pathlib import Path

from sqlalchemy import MetaData
from sqlalchemy.schema import Column, ForeignKeyConstraint, Index, Table, UniqueConstraint


def load_metadata(spec: str) -> MetaData:
    mod_path, _, attr = spec.partition(":")
    if not mod_path or not attr:
        sys.exit("invalid --models, expected 'package.path:Base'")
    module = importlib.import_module(mod_path)
    base = getattr(module, attr)
    return base.metadata


def col_type(c: Column) -> str:
    try:
        return str(c.type)
    except Exception:
        return c.type.__class__.__name__


def render(meta: MetaData) -> str:
    lines: list[str] = ["# Database Schema", ""]
    lines.append("Auto-generated from SQLAlchemy models. Do not edit by hand.")
    lines.append("")

    for table in sorted(meta.sorted_tables, key=lambda t: t.name):
        lines.append(f"## `{table.name}`")
        lines.append("")
        lines.append("| Column | Type | Nullable | Default | PK | Notes |")
        lines.append("| ------ | ---- | -------- | ------- | -- | ----- |")

        for col in table.columns:
            default = ""
            if col.server_default is not None:
                default = str(col.server_default.arg)
            elif col.default is not None:
                default = repr(col.default.arg) if hasattr(col.default, "arg") else "<callable>"
            notes_parts: list[str] = []
            if col.unique:
                notes_parts.append("unique")
            for fk in col.foreign_keys:
                notes_parts.append(f"fk→{fk.target_fullname}")
            lines.append(
                f"| `{col.name}` | {col_type(col)} | "
                f"{'yes' if col.nullable else 'no'} | "
                f"{default or ''} | "
                f"{'yes' if col.primary_key else ''} | "
                f"{', '.join(notes_parts)} |"
            )
        lines.append("")

        uniques = [c for c in table.constraints if isinstance(c, UniqueConstraint) and c.columns]
        if uniques:
            lines.append("**Unique constraints**")
            for u in uniques:
                cols = ", ".join(c.name for c in u.columns)
                lines.append(f"- `{u.name or ''}` ({cols})")
            lines.append("")

        fks = [c for c in table.constraints if isinstance(c, ForeignKeyConstraint)]
        if fks:
            lines.append("**Foreign keys**")
            for fk in fks:
                local = ", ".join(c.name for c in fk.columns)
                remote = ", ".join(e.target_fullname for e in fk.elements)
                ondelete = f" on delete {fk.ondelete}" if fk.ondelete else ""
                lines.append(f"- ({local}) → ({remote}){ondelete}")
            lines.append("")

        idx: list[Index] = list(table.indexes)
        if idx:
            lines.append("**Indexes**")
            for ix in idx:
                cols = ", ".join(c.name for c in ix.columns)
                kind = "unique " if ix.unique else ""
                lines.append(f"- `{ix.name}` — {kind}({cols})")
            lines.append("")

    return "\n".join(lines) + "\n"


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--models", required=True, help="package.path:Base")
    p.add_argument("--out", type=Path, default=Path("docs/DB_SCHEMA.md"))
    args = p.parse_args()

    meta = load_metadata(args.models)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(render(meta))
    print(f"[gen_schema] wrote {args.out} ({len(meta.tables)} tables)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
