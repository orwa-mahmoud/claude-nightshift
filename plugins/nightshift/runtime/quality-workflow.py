#!/usr/bin/env python3
"""quality-workflow.py — normalize, dedupe, and rank quality findings."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from collections import defaultdict
from copy import deepcopy
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Tuple


SEVERITY_RANK = {"critical": 0, "high": 1, "medium": 2, "low": 3, "info": 4}
CONF_RANK = {"high": 0, "medium": 1, "low": 2}
IMPACT_RANK = {"production": 0, "user": 1, "developer": 2, "none": 3}


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def sha256(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def root_locator(locator: str) -> str:
    parts = locator.split(":")
    if len(parts) >= 2:
        return "%s:%s" % (parts[0], parts[1])
    return locator


def root_cause_key(locator: str, message: str) -> str:
    return sha256("%s|%s" % (root_locator(locator), message.strip().lower()))


def next_id(prefix: str, n: int) -> str:
    return "%s-%04d" % (prefix, n)


def eslint_severity(level: int) -> str:
    if level >= 2:
        return "high"
    if level == 1:
        return "medium"
    return "low"


def parse_eslint_json(
    raw: str,
    source_class: str,
    source: str,
    scope: str,
    work_target: str,
    host: str,
    now: str,
    id_start: int,
) -> Tuple[List[Dict[str, Any]], int]:
    out: List[Dict[str, Any]] = []
    n = id_start
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return out, n
    if not isinstance(data, list):
        data = [data]
    for file_entry in data:
        if not isinstance(file_entry, dict):
            continue
        path = file_entry.get("filePath") or file_entry.get("file") or scope
        for msg in file_entry.get("messages") or []:
            if not isinstance(msg, dict):
                continue
            line = msg.get("line") or 0
            col = msg.get("column") or 0
            rule = msg.get("ruleId") or "eslint"
            message = msg.get("message") or ""
            locator = "%s:%s:%s" % (path, line, col)
            digest = sha256("%s|%s|%s" % (locator, rule, message))
            root = root_cause_key(locator, message)
            n += 1
            out.append(
                {
                    "schemaVersion": 1,
                    "id": next_id("f-eslint", n),
                    "domain": "quality",
                    "sourceClass": source_class,
                    "source": source,
                    "sourceTool": rule,
                    "scope": scope,
                    "severity": eslint_severity(int(msg.get("severity") or 1)),
                    "confidence": "high",
                    "impact": "developer",
                    "status": "open",
                    "ladder": "observed",
                    "locator": locator,
                    "digest": digest,
                    "rootCauseKey": root,
                    "firstSeen": now,
                    "lastChecked": now,
                    "action": message,
                    "host": host,
                    "workTarget": work_target,
                    "message": message,
                    "package": scope.rstrip("/").split("/")[-1] if scope else None,
                }
            )
    return out, n


LINE_RE = re.compile(r"^(?P<file>[^:]+):(?P<line>\d+)(?::(?P<col>\d+))?:\s*(?P<msg>.+)$")


def parse_text_lines(
    raw: str,
    source_class: str,
    source: str,
    scope: str,
    work_target: str,
    host: str,
    now: str,
    id_start: int,
) -> Tuple[List[Dict[str, Any]], int]:
    out: List[Dict[str, Any]] = []
    n = id_start
    for line in raw.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        m = LINE_RE.match(line)
        if not m:
            continue
        locator = "%s:%s" % (m.group("file"), m.group("line"))
        message = m.group("msg")
        digest = sha256("%s|%s|%s" % (locator, source_class, message))
        root = root_cause_key(locator, message)
        n += 1
        out.append(
            {
                "schemaVersion": 1,
                "id": next_id("f-text", n),
                "domain": "quality",
                "sourceClass": source_class,
                "source": source,
                "sourceTool": source_class,
                "scope": scope,
                "severity": "medium",
                "confidence": "high",
                "impact": "developer",
                "status": "open",
                "ladder": "observed",
                "locator": locator,
                "digest": digest,
                "rootCauseKey": root,
                "firstSeen": now,
                "lastChecked": now,
                "action": message,
                "host": host,
                "workTarget": work_target,
                "message": message,
                "package": scope.rstrip("/").split("/")[-1] if scope else None,
            }
        )
    return out, n


def normalize_manifest(manifest: Dict[str, Any]) -> Dict[str, Any]:
    work_target = manifest.get("workTarget") or "/repo"
    host = manifest.get("host") or "claude"
    now = manifest.get("scannedAt") or utc_now()
    findings: List[Dict[str, Any]] = []
    sources_meta: List[Dict[str, Any]] = []
    n = 0
    for src in manifest.get("sources") or []:
        fmt = src.get("format") or "unavailable"
        scope = src.get("scope") or "."
        source_class = src.get("sourceClass") or "unknown"
        source = src.get("source") or source_class
        raw = src.get("raw") or ""
        if src.get("unavailable"):
            sources_meta.append(
                {
                    "sourceClass": source_class,
                    "source": source,
                    "scope": scope,
                    "format": "unavailable",
                    "command": src.get("command"),
                    "unavailable": True,
                }
            )
            continue
        raw_digest = sha256(raw) if raw else None
        sources_meta.append(
            {
                "sourceClass": source_class,
                "source": source,
                "scope": scope,
                "format": fmt,
                "command": src.get("command"),
                "rawDigest": raw_digest,
                "unavailable": False,
            }
        )
        if fmt == "eslint-json":
            batch, n = parse_eslint_json(raw, source_class, source, scope, work_target, host, now, n)
        elif fmt == "text-lines":
            batch, n = parse_text_lines(raw, source_class, source, scope, work_target, host, now, n)
        else:
            batch = []
        findings.extend(batch)
    return {
        "schemaVersion": 1,
        "workTarget": work_target,
        "workMode": manifest.get("workMode") or "repository",
        "host": host,
        "scannedAt": now,
        "sources": sources_meta,
        "findings": findings,
    }


def dedupe_findings(findings: List[Dict[str, Any]]) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]]]:
    groups: Dict[str, List[Dict[str, Any]]] = defaultdict(list)
    for f in findings:
        key = f.get("rootCauseKey") or f["digest"]
        groups[key].append(f)
    survivors: List[Dict[str, Any]] = []
    dupes: List[Dict[str, Any]] = []
    group_records: List[Dict[str, Any]] = []
    for key, items in sorted(groups.items()):
        ranked = sorted(
            items,
            key=lambda x: (
                SEVERITY_RANK.get(x.get("severity", "medium"), 9),
                CONF_RANK.get(x.get("confidence", "medium"), 9),
                x.get("id", ""),
            ),
        )
        keep = deepcopy(ranked[0])
        source_tools = sorted({str(x.get("sourceClass")) for x in items})
        source_ids = sorted({str(x.get("id")) for x in items})
        keep["sources"] = source_tools
        keep["sourceIds"] = source_ids
        survivors.append(keep)
        removed = []
        for loser in ranked[1:]:
            copy = deepcopy(loser)
            copy["duplicateOf"] = keep["id"]
            copy["sources"] = source_tools
            dupes.append(copy)
            removed.append(loser["id"])
        if len(items) > 1:
            group_records.append(
                {
                    "rootCauseKey": key,
                    "kept": keep["id"],
                    "removed": removed,
                    "sources": source_tools,
                }
            )
    return survivors, group_records


def rank_queue(findings: List[Dict[str, Any]], established: Optional[set] = None) -> List[Dict[str, Any]]:
    established = established or set()
    ranked = sorted(
        findings,
        key=lambda x: (
            SEVERITY_RANK.get(x.get("severity", "medium"), 9),
            IMPACT_RANK.get(x.get("impact", "developer"), 9),
            CONF_RANK.get(x.get("confidence", "medium"), 9),
            x.get("locator", ""),
            x.get("id", ""),
        ),
    )
    queue: List[Dict[str, Any]] = []
    for i, f in enumerate(ranked, 1):
        queue.append(
            {
                "id": f["id"],
                "digest": f["digest"],
                "locator": f["locator"],
                "sources": list(f.get("sources") or [f.get("sourceClass")]),
                "sourceIds": list(f.get("sourceIds") or [f["id"]]),
                "severity": f.get("severity"),
                "confidence": f.get("confidence"),
                "impact": f.get("impact"),
                "scope": f.get("scope"),
                "package": f.get("package"),
                "rank": i,
                "established": f["digest"] in established,
                "message": f.get("message") or f.get("action") or "",
            }
        )
    return queue


def pipeline(manifest: Dict[str, Any], established: Optional[set] = None) -> Dict[str, Any]:
    scan = normalize_manifest(manifest)
    survivors, groups = dedupe_findings(scan["findings"])
    input_count = len(scan["findings"])
    queue = rank_queue(survivors, established)
    scan["queue"] = queue
    scan["dedupeSummary"] = {
        "inputCount": input_count,
        "outputCount": len(survivors),
        "groups": groups,
    }
    scan["findings"] = survivors
    return scan


def compose_discovery(scan: Dict[str, Any], hours: float = 4.0) -> Dict[str, Any]:
    overlaps = []
    for g in scan.get("dedupeSummary", {}).get("groups") or []:
        if len(g.get("sources") or []) > 1 or len(g.get("removed") or []) > 0:
            overlaps.append(
                {
                    "group": (g.get("rootCauseKey") or g.get("digest") or "group")[:12],
                    "finding": g.get("kept"),
                    "candidates": [g["kept"]] + list(g.get("removed") or []),
                }
            )
    evidence_lines = []
    for q in scan.get("queue") or []:
        evidence_lines.append(
            "%s (%s): %s [%s]" % (q["locator"], ",".join(q["sources"]), q["message"], q["severity"])
        )
    effort = max(30, min(240, len(scan.get("queue") or []) * 20))
    return {
        "schemaVersion": 1,
        "workMode": scan.get("workMode") or "repository",
        "workTarget": scan.get("workTarget") or "/repo",
        "toolingPolicy": "existing-tools",
        "candidates": [
            {
                "contractId": "clear-quality-debt",
                "title": "Clear quality debt — fix what the project's own tooling reports.",
                "ending": "finite",
                "applicable": len(scan.get("queue") or []) > 0,
                "evidence": evidence_lines[:20],
                "impact": 5,
                "evidenceStrength": 5 if evidence_lines else 0,
                "confidence": 5 if evidence_lines else 0,
                "effortMinutes": effort,
                "reversibility": 5,
                "dependencyValue": 2,
                "recurrence": 1,
                "priorResult": None,
                "overlapGroup": None,
                "prerequisites": [],
                "sharedRoots": sorted({q.get("scope") or "" for q in scan.get("queue") or []}),
                "blockers": [],
                "capabilityStatus": "available-and-verified",
                "fallback": None,
            }
        ],
        "overlaps": overlaps,
    }


def cmd_pipeline(args: argparse.Namespace) -> int:
    with open(args.input, encoding="utf-8") as fh:
        manifest = json.load(fh)
    established = set()
    if args.established:
        with open(args.established, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    rec = json.loads(line)
                    if rec.get("digest"):
                        established.add(rec["digest"])
                except json.JSONDecodeError:
                    pass
    doc = pipeline(manifest, established)
    sys.stdout.write(json.dumps(doc, indent=2, sort_keys=True) + "\n")
    return 0


def cmd_compose(args: argparse.Namespace) -> int:
    with open(args.input, encoding="utf-8") as fh:
        scan = json.load(fh)
    doc = compose_discovery(scan, args.hours)
    sys.stdout.write(json.dumps(doc, indent=2, sort_keys=True) + "\n")
    return 0


def main(argv: List[str]) -> int:
    p = argparse.ArgumentParser(prog="quality-workflow.py")
    sub = p.add_subparsers(dest="cmd", required=True)

    pp = sub.add_parser("pipeline")
    pp.add_argument("--input", required=True)
    pp.add_argument("--established")
    pp.set_defaults(func=cmd_pipeline)

    pc = sub.add_parser("compose-discovery")
    pc.add_argument("--input", required=True)
    pc.add_argument("--hours", type=float, default=4.0)
    pc.set_defaults(func=cmd_compose)

    args = p.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
