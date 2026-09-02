#!/usr/bin/env python3
"""history-context.py — receipt index, shift comparison, presets, and source adapters."""
from __future__ import annotations

import argparse
import json
import sys
from typing import Any, Dict, List, Optional, Set


AUDIENCES = frozenset({"owner", "reviewer", "release", "maintainer", "artifact"})


def index_archive(raw: Dict[str, Any]) -> Dict[str, Any]:
    entries: List[Dict[str, Any]] = []
    corrupt: List[str] = []
    for rec in raw.get("archives") or []:
        if not rec.get("date") or not rec.get("objective"):
            corrupt.append(rec.get("path") or "unknown")
            continue
        entries.append(
            {
                "date": rec.get("date"),
                "objective": rec.get("objective"),
                "contracts": rec.get("contracts") or [],
                "host": rec.get("host"),
                "workTarget": rec.get("workTarget"),
                "outcome": rec.get("outcome"),
                "evidenceLocators": rec.get("evidenceLocators") or [],
                "verification": rec.get("verification"),
                "commitsOrArtifacts": rec.get("commitsOrArtifacts") or [],
                "durationMinutes": rec.get("durationMinutes"),
                "ending": rec.get("ending"),
            }
        )
    return {
        "schemaVersion": 1,
        "kind": "receipt-index",
        "entries": entries,
        "entryCount": len(entries),
        "corruptEntries": corrupt,
        "degradesHonestly": len(corrupt) > 0,
        "replaySideEffects": False,
    }


def compare_prior(raw: Dict[str, Any]) -> Dict[str, Any]:
    prior = raw.get("prior") or {}
    current = raw.get("current") or {}
    same_source = prior.get("evidenceSourceId") and prior.get("evidenceSourceId") == current.get(
        "evidenceSourceId"
    )
    locators_prior: Set[str] = set(prior.get("evidenceLocators") or [])
    locators_current: Set[str] = set(current.get("evidenceLocators") or [])
    reusable = sorted(locators_prior & locators_current)
    rejected = list(prior.get("rejectedFindings") or [])
    recurring = [f for f in (current.get("findings") or []) if f in rejected]
    return {
        "schemaVersion": 1,
        "kind": "shift-comparison",
        "sameSourceCompatible": same_source if prior.get("evidenceSourceId") else None,
        "reusableLocators": reusable,
        "recurringFailures": recurring,
        "successfulPatterns": prior.get("successfulPatterns") or [],
        "replaySideEffects": False,
        "replayPlansOnly": True,
        "estimatesFromPrior": bool(prior.get("durationMinutes")),
    }


def preset_compose(raw: Dict[str, Any]) -> Dict[str, Any]:
    preset = raw.get("preset") or {}
    rules = raw.get("rules") or {}
    defaults = raw.get("shiftDefaults") or {}
    resolved = {
        "branchMode": preset.get("branchMode") or rules.get("branchMode") or "default",
        "allowedSources": preset.get("allowedSources") or rules.get("allowedSources") or "closed-list",
        "verificationProfile": defaults.get("verificationProfile") or preset.get("verificationProfile"),
        "toolingPolicy": defaults.get("toolingPolicy") or preset.get("toolingPolicy"),
        "receiptRetentionDays": rules.get("retention", {}).get("archiveDays"),
        "resourceLimits": preset.get("resourceLimits") or {},
        "directModeBoundaries": preset.get("directModeBoundaries") or rules.get("directModeBoundaries") or [],
    }
    hidden = bool(preset.get("hiddenPolicy"))
    return {
        "schemaVersion": 1,
        "kind": "project-preset",
        "name": preset.get("name"),
        "resolved": resolved,
        "sources": {
            "preset": preset.get("name"),
            "rules": "rules.json",
            "defaults": "shift-defaults.json",
        },
        "ownerRulesAuthoritative": True,
        "hiddenPolicyCaptured": hidden,
        "presetNeverCapturesHiddenPolicy": not hidden,
    }


def audience_render(raw: Dict[str, Any]) -> Dict[str, Any]:
    audience = (raw.get("audience") or "owner").lower()
    if audience not in AUDIENCES:
        audience = "owner"
    evidence = raw.get("evidence") or {}
    sections: Dict[str, Any] = {
        "summary": evidence.get("summary"),
        "verification": evidence.get("verification"),
        "commitsOrArtifacts": evidence.get("commitsOrArtifacts"),
    }
    if audience == "reviewer":
        sections["reviewMap"] = evidence.get("reviewMap")
        sections["remainingRisks"] = evidence.get("remainingRisks")
    elif audience == "release":
        sections["verdict"] = evidence.get("releaseVerdict")
        sections["blockers"] = evidence.get("blockers")
    elif audience == "maintainer":
        sections["maintainerPreset"] = evidence.get("maintainerPreset")
    elif audience == "artifact":
        sections["receiptPaths"] = evidence.get("receiptPaths")
    return {
        "schemaVersion": 1,
        "kind": "audience-handoff",
        "audience": audience,
        "sections": sections,
        "singleEvidenceTruth": True,
    }


def adapter_boundary(raw: Dict[str, Any]) -> Dict[str, Any]:
    adapter = raw.get("adapter") or "local-export"
    authorized = bool(raw.get("authorized", False))
    read_only = raw.get("readOnly", True)
    scope = raw.get("scope") or {}
    return {
        "schemaVersion": 1,
        "kind": "source-adapter-boundary",
        "adapter": adapter,
        "readCapability": bool(scope.get("read", True)),
        "writeCapability": False if read_only else bool(scope.get("write", False)),
        "authorized": authorized,
        "trustClass": raw.get("trustClass") or "owner-supplied-export",
        "queryBudget": raw.get("queryBudget") or {},
        "redactionRequired": True,
        "provenanceRequired": True,
        "scopeBroadeningAllowed": False,
        "mandatoryConnector": False,
        "optionalIntegration": True,
    }


def main(argv: List[str]) -> int:
    p = argparse.ArgumentParser(prog="history-context.py")
    sub = p.add_subparsers(dest="cmd", required=True)
    for name in (
        "index-archive",
        "compare-prior",
        "preset-compose",
        "audience-render",
        "adapter-boundary",
    ):
        sub.add_parser(name).add_argument("--input", required=True)
    args = p.parse_args(argv)
    with open(args.input, encoding="utf-8") as fh:
        data = json.load(fh)
    handlers = {
        "index-archive": index_archive,
        "compare-prior": compare_prior,
        "preset-compose": preset_compose,
        "audience-render": audience_render,
        "adapter-boundary": adapter_boundary,
    }
    doc = handlers[args.cmd](data)
    sys.stdout.write(json.dumps(doc, indent=2, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
