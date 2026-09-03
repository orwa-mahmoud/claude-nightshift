#!/usr/bin/env python3
"""plan-learning.py — private project-local planning learning store."""
from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import datetime, timezone
from typing import Any, Dict, List


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def empty_learning() -> Dict[str, Any]:
    return {"schemaVersion": 1, "updatedAt": utc_now(), "contracts": {}, "rejectedFindings": [], "suppressedContracts": []}


def read_learning(path: str) -> Dict[str, Any]:
    if not os.path.isfile(path):
        return empty_learning()
    with open(path, encoding="utf-8") as fh:
        doc = json.load(fh)
    if not isinstance(doc, dict):
        return empty_learning()
    doc.setdefault("schemaVersion", 1)
    doc.setdefault("contracts", {})
    doc.setdefault("rejectedFindings", [])
    doc.setdefault("suppressedContracts", [])
    return doc


def write_learning(path: str, doc: Dict[str, Any]) -> None:
    doc["updatedAt"] = utc_now()
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path + ".tmp", "w", encoding="utf-8") as fh:
        json.dump(doc, fh, indent=2, sort_keys=True)
        fh.write("\n")
    os.replace(path + ".tmp", path)


def merge_contract_entry(doc: Dict[str, Any], contracts: Dict[str, Any], entry: Dict[str, Any]) -> None:
    cid = entry.get("contractId")
    if not cid:
        return
    slot = contracts.setdefault(cid, {})
    mins = entry.get("actualDurationMinutes")
    if isinstance(mins, int):
        slot.setdefault("actualDurationMinutes", []).append(mins)
        vals = slot["actualDurationMinutes"]
        slot["averageEffortMinutes"] = int(round(sum(vals) / len(vals)))
    runtime = entry.get("toolRuntimeSeconds")
    if isinstance(runtime, int):
        slot.setdefault("toolRuntimesSeconds", []).append(runtime)
    outcome = entry.get("outcome")
    if outcome == "success":
        slot["successfulOutcomes"] = int(slot.get("successfulOutcomes", 0)) + 1
    elif outcome == "failed":
        slot["failedOutcomes"] = int(slot.get("failedOutcomes", 0)) + 1
        fails = int(slot.get("failedOutcomes", 0))
        if fails >= 3 and cid not in doc.setdefault("suppressedContracts", []):
            doc["suppressedContracts"].append(cid)


def merge_rejected_findings(doc: Dict[str, Any], receipt: Dict[str, Any]) -> None:
    for fid in receipt.get("rejectedFindings") or []:
        if isinstance(fid, str) and fid not in doc.setdefault("rejectedFindings", []):
            doc["rejectedFindings"].append(fid)


def merge_receipt(doc: Dict[str, Any], receipt: Dict[str, Any]) -> Dict[str, Any]:
    contracts = doc.setdefault("contracts", {})
    for entry in receipt.get("contracts") or []:
        if not isinstance(entry, dict):
            continue
        merge_contract_entry(doc, contracts, entry)
    merge_rejected_findings(doc, receipt)
    return doc


def cmd_read(path: str) -> int:
    sys.stdout.write(json.dumps(read_learning(path), indent=2, sort_keys=True) + "\n")
    return 0


def cmd_update(path: str, receipt_path: str) -> int:
    doc = read_learning(path)
    with open(receipt_path, encoding="utf-8") as fh:
        receipt = json.load(fh)
    doc = merge_receipt(doc, receipt)
    write_learning(path, doc)
    sys.stdout.write(json.dumps(doc, indent=2, sort_keys=True) + "\n")
    return 0


def main(argv: List[str]) -> int:
    p = argparse.ArgumentParser(add_help=False)
    p.add_argument("command", choices=["read", "update-from-receipt"])
    p.add_argument("--path", required=True)
    p.add_argument("--receipt")
    args = p.parse_args(argv)

    if args.command == "read":
        return cmd_read(args.path)
    if args.command == "update-from-receipt":
        if not args.receipt:
            print("plan-learning: --receipt is required", file=sys.stderr)
            return 1
        return cmd_update(args.path, args.receipt)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
