#!/usr/bin/env python3
# /// script
# requires-python = ">=3.13"
# dependencies = [
#     "jinja2",
#     "sqlparse",
# ]
# ///

import shutil
import subprocess
from pathlib import Path

import sqlparse
from jinja2 import Environment, FileSystemLoader

PROTOS = [
    # flag: precomputed boolean in CTE (from raw columns)
    # cond: condition used in sumIf (references precomputed flags)
    # rate_stats: also emit per-minute min/max/p95 bps & pps stats (L3/L4 protocols only,
    #             not the tcp_* flag pseudo-protocols)
    {"name": "any", "cond": None, "rate_stats": True},
    {"name": "tcp", "cond": "is_tcp", "flag": "proto = 6", "rate_stats": True},
    {"name": "udp", "cond": "is_udp", "flag": "proto = 17", "rate_stats": True},
    {"name": "gre", "cond": "is_gre", "flag": "proto = 47", "rate_stats": True},
    {"name": "esp", "cond": "is_esp", "flag": "proto = 50", "rate_stats": True},
    {
        "name": "icmp",
        "cond": "is_icmp",
        "flag": "(etype = 0x0800 AND proto = 1) OR (etype = 0x86dd AND proto = 58)",
        "rate_stats": True,
    },
    {
        "name": "tcp_fin",
        "cond": "is_tcp_fin",
        "flag": "is_tcp AND bitAnd(tcp_flags, 0x01)",
    },
    {
        "name": "tcp_syn",
        "cond": "is_tcp_syn",
        "flag": "is_tcp AND bitAnd(tcp_flags, 0x02)",
    },
    {
        "name": "tcp_rst",
        "cond": "is_tcp_rst",
        "flag": "is_tcp AND bitAnd(tcp_flags, 0x04)",
    },
    {
        "name": "tcp_psh",
        "cond": "is_tcp_psh",
        "flag": "is_tcp AND bitAnd(tcp_flags, 0x08)",
    },
    {
        "name": "tcp_ack",
        "cond": "is_tcp_ack",
        "flag": "is_tcp AND bitAnd(tcp_flags, 0x10)",
    },
    {
        "name": "tcp_urg",
        "cond": "is_tcp_urg",
        "flag": "is_tcp AND bitAnd(tcp_flags, 0x20)",
    },
]

# TTL retention periods (in days)
TTL = {
    "raw": 30,
    "prefixes_src_1h": 7,
    "prefixes_src_1d": 90,
    "prefixes_ip_port_1m": 3,
    "prefixes_ip_port_1h": 14,
    "prefixes_ip_port_1d": 90,
    "prefixes_ip_1m": 7,
    "prefixes_ip_1h": 30,
    "prefixes_ip_1d": 90,
    "prefixes_proto_1m": 30,
    "prefixes_proto_1h": 90,
    "prefixes_proto_1d": 90,
    "alerts": 90,
    "expression_metrics": 30,
}

# Protocols kept past the 1m tables (the tcp_* flag pseudo-protocols are 1m-only).
PROTOCOLS = [p for p in PROTOS if p.get("rate_stats")]

BASE_DIR = Path(__file__).parent
TEMPLATES_DIR = BASE_DIR / "templates"
OUTPUT_DIR = BASE_DIR / "initdb.d"


def main():
    env = Environment(
        loader=FileSystemLoader(TEMPLATES_DIR),
        keep_trailing_newline=True,
        lstrip_blocks=True,
        trim_blocks=True,
    )

    env.filters["rstrip"] = lambda s: s.rstrip()

    context = {"protos": PROTOS, "protocols": PROTOCOLS, "ttl": TTL}

    # Render templates
    generated = set()
    for template_file in sorted(TEMPLATES_DIR.glob("*.sql.j2")):
        template = env.get_template(template_file.name)
        output = template.render(**context)
        output_path = OUTPUT_DIR / template_file.name.removesuffix(".j2")
        output_path.write_text(output)
        generated.add(output_path.name)
        print(f"Generated {output_path.relative_to(BASE_DIR)}")

    # Format all SQL files in initdb.d
    if shutil.which("clickhouse-format"):
        for sql_file in sorted(OUTPUT_DIR.glob("*.sql")):
            original = sql_file.read_text()
            formatted = format_sql(original)
            if formatted != original:
                sql_file.write_text(formatted)
                print(f"Formatted {sql_file.relative_to(BASE_DIR)}")
    else:
        print("clickhouse-format not found, skipping formatting")


def format_sql(sql: str) -> str:
    """Format each SQL statement using clickhouse-format."""
    statements = sqlparse.split(sql)
    formatted = []

    for stmt in statements:
        stmt = stmt.strip().rstrip(";")
        if not stmt:
            continue

        result = subprocess.run(
            ["clickhouse-format"],
            input=stmt,
            capture_output=True,
            text=True,
        )
        if result.returncode == 0:
            formatted.append(result.stdout.strip())
        else:
            formatted.append(stmt)

    return ";\n\n".join(formatted) + ";\n"


if __name__ == "__main__":
    main()
