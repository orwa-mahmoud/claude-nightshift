#!/usr/bin/env python3
"""engineering-evidence.py — shared evidence helpers for engineering-confidence shifts."""
from __future__ import annotations

import argparse
import json
import re
import sys
from typing import Any, Dict, List

CI_PREFIX = re.compile(
    r"^\[workflow:(?P<workflow>[^\]]+)\]\s+job:(?P<job>\S+)\s+step:(?P<step>\S+)\s+"
    r"(?P<level>warning|deprecated|warn):\s*(?P<message>.+)$",
    re.I,
)
CI_SIMPLE = re.compile(r"^(?P<level>warning|deprecated|warn):\s*(?P<message>.+)$", re.I)
TODO_RE = re.compile(r"\b(TODO|FIXME|HACK|XXX)\b", re.I)


def flaky_matrix(manifest: Dict[str, Any]) -> Dict[str, Any]:
    rows: List[Dict[str, Any]] = []
    for s in manifest.get("suspects") or []:
        rows.append(
            {
                "testId": s.get("id"),
                "locator": s.get("locator"),
                "repetitions": int(s.get("repetitions") or manifest.get("defaultRepetitions") or 20),
                "seed": s.get("seed"),
                "order": s.get("order"),
                "isolation": s.get("isolation", "file"),
                "parallelism": s.get("parallelism", "default"),
                "locale": s.get("locale"),
                "timezone": s.get("timezone"),
                "environment": s.get("environment") or {},
                "ciHistory": s.get("ciHistory") or [],
                "command": s.get("command"),
            }
        )
    return {"schemaVersion": 1, "kind": "flaky-matrix", "rows": rows}


def parse_ci_warnings(raw: str) -> Dict[str, Any]:
    warnings: List[Dict[str, Any]] = []
    seen = set()
    for line in raw.splitlines():
        line = line.strip()
        if not line:
            continue
        m = CI_PREFIX.match(line) or CI_SIMPLE.match(line)
        if not m:
            continue
        d = m.groupdict()
        msg = d.get("message") or line
        key = msg.lower()
        recurrent = key in seen
        seen.add(key)
        repo_owned = any(x in msg for x in ("src/", "packages/", "repository-owned"))
        warnings.append(
            {
                "workflow": d.get("workflow"),
                "job": d.get("job"),
                "step": d.get("step"),
                "level": (d.get("level") or "warning").lower(),
                "message": msg,
                "causeClass": "repository-owned" if repo_owned else "external",
                "recurrent": recurrent,
                "remotePending": d.get("workflow") is not None,
            }
        )
    return {"schemaVersion": 1, "kind": "ci-warning", "warnings": warnings}


def dead_code_guard(finding: Dict[str, Any]) -> Dict[str, Any]:
    refs = set(finding.get("references") or [])
    guards = {
        "publicExport": "publicExport" in refs,
        "reflection": "reflection" in refs,
        "dynamicImport": "dynamicImport" in refs,
        "registration": "registration" in refs,
        "configuration": "configuration" in refs,
        "generated": "generated" in refs,
        "pluginEntry": "pluginEntry" in refs,
        "serialization": "serialization" in refs,
        "compatibilityShim": "compatibilityShim" in refs,
    }
    blocked = [k for k, v in guards.items() if v]
    verdict = "safe" if not blocked else "forbidden"
    if finding.get("uncertain"):
        verdict = "uncertain"
    return {
        "schemaVersion": 1,
        "kind": "dead-code-guard",
        "locator": finding.get("locator"),
        "verdict": verdict,
        "guards": guards,
        "blastRadius": finding.get("blastRadius") or [],
        "reason": finding.get("reason"),
    }


def classify_todo(line: str, context: Dict[str, Any]) -> Dict[str, Any]:
    m = TODO_RE.search(line)
    marker = m.group(1).upper() if m else "TODO"
    age_days = context.get("ageDays")
    classification = "actionable"
    if any(w in line.lower() for w in ("ux", "product", "breaking", "owner", "decide")):
        classification = "ambiguous"
    if marker == "HACK":
        classification = "warning"
    if marker == "XXX":
        classification = "defect"
    return {
        "schemaVersion": 1,
        "kind": "todo-class",
        "marker": marker,
        "line": line.strip(),
        "classification": classification,
        "ageDays": age_days,
        "stageTo": "drafting-table" if classification == "ambiguous" else "punch-list",
    }


def enrich_vuln(adv: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "schemaVersion": 1,
        "kind": "vuln-advisory",
        "id": adv.get("id"),
        "provenance": adv.get("source") or "audit-tool",
        "severity": adv.get("severity"),
        "affectedVersions": adv.get("affectedVersions") or [],
        "fixedVersion": adv.get("fixedVersion"),
        "transitivePath": adv.get("transitivePath") or [],
        "reachable": adv.get("reachable"),
        "runtimeExposure": adv.get("runtimeExposure") or "unknown",
        "devOnly": bool(adv.get("devOnly")),
        "refusalReason": adv.get("refusalReason"),
    }


def dep_batch(report: Dict[str, Any]) -> Dict[str, Any]:
    pkgs = report.get("packages") or []
    patches = [p for p in pkgs if p.get("kind") == "patch"]
    minors = [p for p in pkgs if p.get("kind") == "minor"]
    majors = [p for p in pkgs if p.get("kind") == "major"]
    return {
        "schemaVersion": 1,
        "kind": "dep-batch",
        "ordered": patches + minors + majors,
        "lockfile": report.get("lockfile"),
        "ecosystem": report.get("ecosystem"),
        "evidence": report.get("evidence") or [],
        "refused": [p for p in pkgs if p.get("refused")],
    }


def main(argv: List[str]) -> int:
    p = argparse.ArgumentParser(prog="engineering-evidence.py")
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("flaky-matrix").add_argument("--input", required=True)
    sub.add_parser("ci-warnings").add_argument("--input", required=True)
    sub.add_parser("dead-code-guard").add_argument("--input", required=True)
    pt = sub.add_parser("todo-classify")
    pt.add_argument("--input", required=True)
    pt.add_argument("--context")
    sub.add_parser("vuln-enrich").add_argument("--input", required=True)
    sub.add_parser("dep-batch").add_argument("--input", required=True)

    args = p.parse_args(argv)

    if args.cmd == "flaky-matrix":
        with open(args.input, encoding="utf-8") as fh:
            doc = flaky_matrix(json.load(fh))
    elif args.cmd == "ci-warnings":
        with open(args.input, encoding="utf-8") as fh:
            doc = parse_ci_warnings(fh.read())
    elif args.cmd == "dead-code-guard":
        with open(args.input, encoding="utf-8") as fh:
            doc = dead_code_guard(json.load(fh))
    elif args.cmd == "todo-classify":
        ctx = {}
        if args.context:
            with open(args.context, encoding="utf-8") as fh:
                ctx = json.load(fh)
        with open(args.input, encoding="utf-8") as fh:
            doc = classify_todo(fh.read(), ctx)
    elif args.cmd == "vuln-enrich":
        with open(args.input, encoding="utf-8") as fh:
            doc = enrich_vuln(json.load(fh))
    elif args.cmd == "dep-batch":
        with open(args.input, encoding="utf-8") as fh:
            doc = dep_batch(json.load(fh))
    else:
        return 1

    sys.stdout.write(json.dumps(doc, indent=2, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
