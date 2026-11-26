#!/usr/bin/env python3
"""
merge-stevenblack.py — merges a fresh StevenBlack/hosts into the MYbloXX
PACs shipped in MYbloXX/PAC/.

Writes the output PACs (same filenames: MYbloXX.pac, MYbloXXnoFB.pac,
MYbloXXnoXXX.pac, MYbloXXnoFBnoXXX.pac) to --output-dir, preserving the
noFB variant's special-case (graph.facebook.com + graph.instagram.com
stay UNblocked so Facebook login SDK works).

Usage (from the GitHub Actions workflow, after `curl`-fetching the hosts) :

    python3 MYbloXX/scripts/merge-stevenblack.py \\
      --pac-dir     MYbloXX/PAC/ \\
      --hosts       /tmp/stevenblack.hosts \\
      --output-dir  Resources/AdBlock/PAC/

Runs with -I so a planted json.py in cwd can't shadow stdlib.
"""
import argparse
import json
import os
import re
import sys
from pathlib import Path


BASES = ["MYbloXX.pac", "MYbloXXnoFB.pac", "MYbloXXnoXXX.pac", "MYbloXXnoFBnoXXX.pac"]


def parse_stevenblack(path):
    """Return a set of blocked domains from a StevenBlack/hosts file."""
    domains = set()
    with open(path, "r", encoding="utf-8", errors="ignore") as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split()
            if len(parts) < 2 or parts[0] != "0.0.0.0":
                continue
            dom = parts[1].lower().strip()
            if dom and "." in dom and not dom.startswith("#"):
                domains.add(dom)
    return domains


def extract_json_block(text, var_name):
    """Find `var_name={...}` in PAC source, return (start, end, parsed_dict)."""
    m = re.search(re.escape(var_name) + r"=\{", text)
    if not m:
        return None
    start = m.end() - 1
    depth = 0
    for i in range(start, len(text)):
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
            if depth == 0:
                try:
                    return (start, i + 1, json.loads(text[start:i + 1]))
                except json.JSONDecodeError:
                    return (start, i + 1, None)
    return None


def merge_pac(pac_text, fresh_domains, is_nofb):
    """Return the PAC with bad_da_host_JSON merged with fresh_domains."""
    r = extract_json_block(pac_text, "bad_da_host_JSON")
    if not r:
        return pac_text
    start, end, existing = r
    merged = dict(existing) if existing else {}
    for d in fresh_domains:
        merged[d] = None
    if is_nofb:
        merged.pop("graph.facebook.com", None)
        merged.pop("graph.instagram.com", None)
    pairs = [f'"{k}":null' for k in sorted(merged.keys())]
    new_json = "{" + ",".join(pairs) + "}"
    return pac_text[:start] + new_json + pac_text[end:]


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--pac-dir",    required=True, help="MYbloXX/PAC/ with base PACs")
    ap.add_argument("--hosts",      required=True, help="StevenBlack hosts file path")
    ap.add_argument("--output-dir", required=True, help="Where to write merged PACs")
    args = ap.parse_args()

    pac_dir = Path(args.pac_dir)
    out_dir = Path(args.output_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    domains = parse_stevenblack(args.hosts)
    print(f"[+] StevenBlack: {len(domains):,} unique blocked domains")

    for name in BASES:
        src = pac_dir / name
        if not src.exists():
            print(f"[!] {src} missing, skipping", file=sys.stderr)
            continue
        text = src.read_text(encoding="utf-8")
        merged = merge_pac(text, domains, is_nofb=("noFB" in name))
        dst = out_dir / name
        dst.write_text(merged, encoding="utf-8")
        print(f"[+] {name}: {dst.stat().st_size:,} bytes")


if __name__ == "__main__":
    main()
