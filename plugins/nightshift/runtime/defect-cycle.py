#!/usr/bin/env python3
"""defect-cycle.py — defect hunt lens rotation and convergence tracking."""
from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional

LENSES = [
    "correctness",
    "state",
    "error-handling",
    "concurrency",
    "boundaries",
    "data-loss",
    "compatibility",
    "recent-change",
]


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def empty_state(shift_id: str) -> Dict[str, Any]:
    return {
        "schemaVersion": 1,
        "shiftId": shift_id,
        "updatedAt": utc_now(),
        "cycle": 1,
        "currentLens": LENSES[0],
        "lenses": list(LENSES),
        "lensesUsedThisCycle": [],
        "findings": [],
        "rejected": [],
        "exploredSurfaces": [],
        "converged": False,
    }


def read_state(path: str) -> Dict[str, Any]:
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, json.JSONDecodeError):
        return empty_state("unknown")


def write_state(path: str, doc: Dict[str, Any]) -> None:
    doc["updatedAt"] = utc_now()
    with open(path + ".tmp", "w", encoding="utf-8") as fh:
        json.dump(doc, fh, indent=2, sort_keys=True)
        fh.write("\n")
    import os

    os.replace(path + ".tmp", path)


def surface_key(finding: Dict[str, Any]) -> str:
    return "%s|%s|%s" % (finding.get("lens"), finding.get("locator"), finding.get("summary", "")[:80])


def next_lens(doc: Dict[str, Any]) -> Dict[str, Any]:
    used = list(doc.get("lensesUsedThisCycle") or [])
    if doc.get("currentLens") and doc["currentLens"] not in used:
        used.append(doc["currentLens"])
    remaining = [l for l in LENSES if l not in used]
    if remaining:
        doc["currentLens"] = remaining[0]
        doc["lensesUsedThisCycle"] = used + [remaining[0]]
        return doc
    doc["lensesUsedThisCycle"] = []
    open_this_cycle = [
        f
        for f in doc.get("findings") or []
        if f.get("status") == "open" and f.get("cycle") == doc.get("cycle")
    ]
    if not open_this_cycle:
        doc["converged"] = True
    else:
        doc["cycle"] = int(doc.get("cycle") or 1) + 1
        doc["currentLens"] = LENSES[0]
        doc["lensesUsedThisCycle"] = [LENSES[0]]
    return doc


def record_finding(doc: Dict[str, Any], finding: Dict[str, Any]) -> Dict[str, Any]:
    fid = finding.get("id")
    if not fid:
        print("defect-cycle: finding id required", file=sys.stderr)
        raise SystemExit(1)
    if finding.get("evidenceKind") not in ("reproduced", "code-path", "observed"):
        print("defect-cycle: evidenceKind must be reproduced, code-path, or observed", file=sys.stderr)
        raise SystemExit(1)
    if finding.get("evidenceKind") == "observed" and not finding.get("strongPath"):
        print("defect-cycle: observed findings require strongPath evidence", file=sys.stderr)
        raise SystemExit(1)
    for existing in doc.get("findings") or []:
        if existing.get("id") == fid:
            print("defect-cycle: duplicate finding id", file=sys.stderr)
            raise SystemExit(1)
        if (
            existing.get("locator") == finding.get("locator")
            and existing.get("summary") == finding.get("summary")
            and existing.get("status") not in ("rejected", "duplicate")
        ):
            finding["status"] = "duplicate"
            finding["duplicateOf"] = existing.get("id")
            finding.setdefault("lens", doc.get("currentLens"))
            finding["cycle"] = doc.get("cycle")
            doc.setdefault("findings", []).append(finding)
            return doc
    surface = surface_key(finding)
    if surface in doc.get("exploredSurfaces") or []:
        print("defect-cycle: surface already explored this shift", file=sys.stderr)
        raise SystemExit(1)
    finding.setdefault("lens", doc.get("currentLens"))
    finding.setdefault("status", "open")
    finding["cycle"] = doc.get("cycle")
    doc.setdefault("findings", []).append(finding)
    doc.setdefault("exploredSurfaces", []).append(surface)
    return doc


def reject_finding(doc: Dict[str, Any], fid: str, reason: str) -> Dict[str, Any]:
    doc.setdefault("rejected", []).append(
        {"id": fid, "reason": reason, "lens": doc.get("currentLens")}
    )
    for f in doc.get("findings") or []:
        if f.get("id") == fid:
            f["status"] = "rejected"
    return doc


def summary(doc: Dict[str, Any]) -> Dict[str, Any]:
    open_findings = [f for f in doc.get("findings") or [] if f.get("status") == "open"]
    fixed = [f for f in doc.get("findings") or [] if f.get("status") == "fixed"]
    return {
        "shiftId": doc.get("shiftId"),
        "cycle": doc.get("cycle"),
        "currentLens": doc.get("currentLens"),
        "converged": doc.get("converged"),
        "open": len(open_findings),
        "fixed": len(fixed),
        "rejected": len(doc.get("rejected") or []),
        "duplicate": len([f for f in doc.get("findings") or [] if f.get("status") == "duplicate"]),
        "receiptLines": [
            "lens=%s id=%s evidence=%s locator=%s — %s"
            % (f.get("lens"), f.get("id"), f.get("evidenceKind"), f.get("locator"), f.get("summary"))
            for f in fixed
        ],
    }


def cmd_init(args: argparse.Namespace) -> int:
    doc = empty_state(args.shift_id)
    write_state(args.path, doc)
    sys.stdout.write(json.dumps(doc, indent=2, sort_keys=True) + "\n")
    return 0


def cmd_next(args: argparse.Namespace) -> int:
    doc = read_state(args.path)
    doc = next_lens(doc)
    write_state(args.path, doc)
    sys.stdout.write(json.dumps(doc, indent=2, sort_keys=True) + "\n")
    return 0


def cmd_record(args: argparse.Namespace) -> int:
    doc = read_state(args.path)
    with open(args.finding, encoding="utf-8") as fh:
        finding = json.load(fh)
    doc = record_finding(doc, finding)
    write_state(args.path, doc)
    sys.stdout.write(json.dumps(summary(doc), indent=2, sort_keys=True) + "\n")
    return 0


def cmd_reject(args: argparse.Namespace) -> int:
    doc = read_state(args.path)
    doc = reject_finding(doc, args.id, args.reason)
    write_state(args.path, doc)
    sys.stdout.write(json.dumps(summary(doc), indent=2, sort_keys=True) + "\n")
    return 0


def cmd_fix(args: argparse.Namespace) -> int:
    doc = read_state(args.path)
    for f in doc.get("findings") or []:
        if f.get("id") == args.id:
            f["status"] = "fixed"
            break
    write_state(args.path, doc)
    sys.stdout.write(json.dumps(summary(doc), indent=2, sort_keys=True) + "\n")
    return 0


def cmd_summary(args: argparse.Namespace) -> int:
    doc = read_state(args.path)
    sys.stdout.write(json.dumps(summary(doc), indent=2, sort_keys=True) + "\n")
    return 0


def main(argv: List[str]) -> int:
    p = argparse.ArgumentParser(prog="defect-cycle.py")
    sub = p.add_subparsers(dest="cmd", required=True)

    pi = sub.add_parser("init")
    pi.add_argument("--path", required=True)
    pi.add_argument("--shift-id", required=True)
    pi.set_defaults(func=cmd_init)

    pn = sub.add_parser("next-lens")
    pn.add_argument("--path", required=True)
    pn.set_defaults(func=cmd_next)

    pr = sub.add_parser("record")
    pr.add_argument("--path", required=True)
    pr.add_argument("--finding", required=True)
    pr.set_defaults(func=cmd_record)

    pj = sub.add_parser("reject")
    pj.add_argument("--path", required=True)
    pj.add_argument("--id", required=True)
    pj.add_argument("--reason", required=True)
    pj.set_defaults(func=cmd_reject)

    pf = sub.add_parser("fix")
    pf.add_argument("--path", required=True)
    pf.add_argument("--id", required=True)
    pf.set_defaults(func=cmd_fix)

    ps = sub.add_parser("summary")
    ps.add_argument("--path", required=True)
    ps.set_defaults(func=cmd_summary)

    args = p.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
