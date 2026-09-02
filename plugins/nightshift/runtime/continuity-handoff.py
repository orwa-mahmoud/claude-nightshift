#!/usr/bin/env python3
"""continuity-handoff.py — cross-host handoff packages and campaign sequencing."""
from __future__ import annotations

import argparse
import json
import sys
from typing import Any, Dict, List


def handoff_package(raw: Dict[str, Any]) -> Dict[str, Any]:
    required = [
        "stateVersion",
        "contract",
        "workTarget",
        "completedItems",
        "openItems",
        "priorHost",
        "cleanStandDownProof",
    ]
    missing = [k for k in required if not raw.get(k) and raw.get(k) != 0]
    return {
        "schemaVersion": 1,
        "kind": "handoff-package",
        "version": raw.get("version") or 1,
        "stateVersion": raw.get("stateVersion"),
        "contract": raw.get("contract"),
        "workTarget": raw.get("workTarget"),
        "completedItems": raw.get("completedItems") or [],
        "openItems": raw.get("openItems") or [],
        "capabilityLocators": raw.get("capabilityLocators") or [],
        "evidenceLocators": raw.get("evidenceLocators") or [],
        "decisions": raw.get("decisions") or [],
        "deadlineSemantics": raw.get("deadlineSemantics"),
        "lease": raw.get("lease"),
        "nonce": raw.get("nonce"),
        "session": raw.get("session"),
        "priorHost": raw.get("priorHost"),
        "cleanStandDownProof": raw.get("cleanStandDownProof"),
        "complete": len(missing) == 0,
        "missingFields": missing,
    }


def fence_check(raw: Dict[str, Any]) -> Dict[str, Any]:
    prior_active = bool(raw.get("priorWorkerActive"))
    prior_fenced = bool(raw.get("priorOwnerFenced"))
    new_worker = raw.get("newWorkerId")
    duplicate = bool(raw.get("duplicateWorkerDetected"))
    allowed = prior_fenced and not prior_active and not duplicate and bool(new_worker)
    return {
        "schemaVersion": 1,
        "kind": "handoff-fence",
        "priorOwnerFenced": prior_fenced,
        "priorWorkerActive": prior_active,
        "duplicateWorkerRejected": duplicate,
        "takeoverAllowed": allowed,
        "action": "proceed" if allowed else "refuse",
        "twoActiveWorkersAllowed": False,
    }


def campaign_sequence(raw: Dict[str, Any]) -> Dict[str, Any]:
    nights = raw.get("nights") or []
    issues: List[str] = []
    for i, night in enumerate(nights):
        if not night.get("archivedOrAccepted") and i > 0:
            issues.append("prior-night-not-archived-or-accepted")
        if night.get("sharedMutablePunchList"):
            issues.append("shared-mutable-punch-list-forbidden")
    return {
        "schemaVersion": 1,
        "kind": "campaign-sequence",
        "nightCount": len(nights),
        "independentBoundedShifts": True,
        "dispatcherRuntime": False,
        "issues": issues,
        "valid": len(issues) == 0,
        "nextMayBegin": len(nights) == 0 or bool(nights[-1].get("archivedOrAccepted")),
    }


def transition_history(raw: Dict[str, Any]) -> Dict[str, Any]:
    events: List[Dict[str, Any]] = []
    for ev in raw.get("events") or []:
        events.append(
            {
                "at": ev.get("at"),
                "kind": ev.get("kind"),
                "reason": ev.get("reason"),
                "host": ev.get("host"),
                "leaseUsed": ev.get("leaseUsed"),
                "sessionKind": ev.get("sessionKind"),
                "secretsRedacted": True,
            }
        )
    return {
        "schemaVersion": 1,
        "kind": "transition-history",
        "events": events,
        "compactForStatusDoctor": True,
        "exposeSecrets": False,
    }


def main(argv: List[str]) -> int:
    p = argparse.ArgumentParser(prog="continuity-handoff.py")
    sub = p.add_subparsers(dest="cmd", required=True)
    for name in ("handoff-package", "fence-check", "campaign-sequence", "transition-history"):
        sub.add_parser(name).add_argument("--input", required=True)
    args = p.parse_args(argv)
    with open(args.input, encoding="utf-8") as fh:
        data = json.load(fh)
    handlers = {
        "handoff-package": handoff_package,
        "fence-check": fence_check,
        "campaign-sequence": campaign_sequence,
        "transition-history": transition_history,
    }
    doc = handlers[args.cmd](data)
    sys.stdout.write(json.dumps(doc, indent=2, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
