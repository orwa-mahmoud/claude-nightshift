#!/usr/bin/env python3
"""product-truth-evidence.py — product-truth shift evidence helpers."""
from __future__ import annotations

import argparse
import json
import sys
from typing import Any, Dict, List


def api_classify(report: Dict[str, Any]) -> Dict[str, Any]:
    items: List[Dict[str, Any]] = []
    for m in report.get("mismatches") or []:
        kind = m.get("kind") or "unknown"
        breaking = kind in ("breaking", "removed", "narrowed", "required-field", "status-code")
        items.append(
            {
                "locator": m.get("locator"),
                "authoritativeSource": report.get("authoritativeSource"),
                "consumerBlastRadius": m.get("consumers") or [],
                "classification": "breaking" if breaking else m.get("classification", "additive"),
                "migrationNoteRequired": breaking,
                "action": "park" if breaking else "repair",
            }
        )
    return {"schemaVersion": 1, "kind": "api-drift", "items": items}


def a11y_report(raw: Dict[str, Any]) -> Dict[str, Any]:
    automated: List[Dict[str, Any]] = []
    human_only: List[Dict[str, Any]] = []
    for v in raw.get("violations") or []:
        rule = v.get("rule") or ""
        entry = {
            "rule": rule,
            "locator": v.get("locator"),
            "message": v.get("message"),
            "journey": v.get("journey"),
        }
        if rule.startswith("human/") or v.get("requiresHumanReview"):
            human_only.append({**entry, "limit": "WCAG or assistive-tech judgment required"})
        else:
            automated.append(entry)
    return {
        "schemaVersion": 1,
        "kind": "a11y-evidence",
        "automated": automated,
        "humanOnly": human_only,
        "environmentExists": bool(raw.get("environmentExists")),
        "certificationClaimAllowed": False,
    }


def _locale_key_issues(locale: str, table: Dict[str, Any], keys: set[str]) -> List[Dict[str, Any]]:
    issues: List[Dict[str, Any]] = []
    for key in keys:
        if key not in table:
            issues.append(
                {"locale": locale, "key": key, "issue": "missing-key", "action": "park-translation"}
            )
    for key, val in table.items():
        if "{" in val and val.count("{") != val.count("}"):
            issues.append({"locale": locale, "key": key, "issue": "interpolation", "action": "repair-structure"})
    return issues


def l10n_validate(catalog: Dict[str, Any]) -> Dict[str, Any]:
    source = catalog.get("canonicalLocale") or "en"
    keys = set((catalog.get("locales") or {}).get(source, {}).keys())
    issues: List[Dict[str, Any]] = []
    for locale, table in (catalog.get("locales") or {}).items():
        if locale == source:
            continue
        issues.extend(_locale_key_issues(locale, table, keys))
    return {
        "schemaVersion": 1,
        "kind": "l10n-parity",
        "canonicalLocale": source,
        "issues": issues,
        "translationQualityCertified": False,
    }


def doc_claim_matrix(manifest: Dict[str, Any]) -> Dict[str, Any]:
    rows: List[Dict[str, Any]] = []
    for claim in manifest.get("claims") or []:
        authority = claim.get("authority")
        verified = claim.get("verifiedLocally")
        rows.append(
            {
                "claim": claim.get("text"),
                "surface": claim.get("surface"),
                "authority": authority,
                "verifiedLocally": verified,
                "action": "repair" if verified is False and authority == "repository" else "park",
            }
        )
    return {"schemaVersion": 1, "kind": "doc-claim-matrix", "rows": rows}


def doc_outline(brief: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "schemaVersion": 1,
        "kind": "doc-outline",
        "audience": brief.get("audience"),
        "decisionOrAction": brief.get("decisionOrAction"),
        "prerequisites": brief.get("prerequisites") or [],
        "architectureNotes": brief.get("architectureNotes") or [],
        "sourceHierarchy": brief.get("sourceHierarchy") or [],
        "verifiedExamples": brief.get("verifiedExamples") or [],
        "freshReaderPassRequired": True,
    }


def main(argv: List[str]) -> int:
    p = argparse.ArgumentParser(prog="product-truth-evidence.py")
    sub = p.add_subparsers(dest="cmd", required=True)
    for name in ("api-classify", "a11y-report", "l10n-validate", "doc-claim-matrix", "doc-outline"):
        sub.add_parser(name).add_argument("--input", required=True)
    args = p.parse_args(argv)
    with open(args.input, encoding="utf-8") as fh:
        data = json.load(fh)
    if args.cmd == "api-classify":
        doc = api_classify(data)
    elif args.cmd == "a11y-report":
        doc = a11y_report(data)
    elif args.cmd == "l10n-validate":
        doc = l10n_validate(data)
    elif args.cmd == "doc-claim-matrix":
        doc = doc_claim_matrix(data)
    elif args.cmd == "doc-outline":
        doc = doc_outline(data)
    else:
        return 1
    sys.stdout.write(json.dumps(doc, indent=2, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
