#!/usr/bin/env python3
"""release-readiness-evidence.py — baseline comparison and public-claims evidence."""
from __future__ import annotations

import argparse
import fnmatch
import json
import sys
from typing import Any, Dict, List, Optional, Set, Tuple

SCHEMA_VERSION = 1
COMPARE_DIMENSIONS = [
    "tests",
    "publicApi",
    "package",
    "install",
    "version",
    "docs",
    "security",
    "budgets",
]
MECHANICAL_AUTHORITIES = {"repository", "manifest", "released-package", "behavior", "LICENSE"}


def _filter_exclusions(paths: List[str], patterns: List[str]) -> List[str]:
    if not patterns:
        return list(paths)
    out: List[str] = []
    for path in paths:
        if any(fnmatch.fnmatch(path, pat) for pat in patterns):
            continue
        out.append(path)
    return out


def _compare_tests(b: Dict[str, Any], c: Dict[str, Any]) -> Tuple[str, Dict[str, Any]]:
    b_status = b.get("status")
    c_status = c.get("status")
    entry = {
        "dimension": "tests",
        "baseline": b_status,
        "candidate": c_status,
        "provenance": c.get("provenance") or b.get("provenance"),
    }
    if b_status == "pass" and c_status != "pass":
        return "regression", {**entry, "reason": "test-regression"}
    if b_status != "pass" and c_status == "pass":
        return "improvement", {**entry, "reason": "test-improved"}
    return "unchanged", entry


def _compare_public_api(b: Dict[str, Any], c: Dict[str, Any]) -> Tuple[str, Dict[str, Any]]:
    breaking = int(c.get("breaking") or 0)
    entry = {
        "dimension": "publicApi",
        "breaking": breaking,
        "additive": int(c.get("additive") or 0),
        "provenance": c.get("provenance"),
    }
    if breaking > 0:
        return "regression", {**entry, "reason": "breaking-api-change"}
    if int(c.get("additive") or 0) > int(b.get("additive") or 0):
        return "drift", {**entry, "kind": "additive-api-change", "severity": "non-blocker"}
    return "unchanged", entry


def _compare_package(b: Dict[str, Any], c: Dict[str, Any], exclusions: List[str]) -> Tuple[str, Dict[str, Any]]:
    b_files = set(_filter_exclusions(b.get("files") or [], exclusions))
    c_files = set(_filter_exclusions(c.get("files") or [], exclusions))
    added = sorted(c_files - b_files)
    removed = sorted(b_files - c_files)
    digest_changed = b.get("digest") and c.get("digest") and b["digest"] != c["digest"]
    entry = {
        "dimension": "package",
        "added": added,
        "removed": removed,
        "digestChanged": bool(digest_changed),
        "provenance": c.get("provenance"),
    }
    if removed:
        return "regression", {**entry, "reason": "package-file-removed"}
    if added or digest_changed:
        return "drift", {**entry, "kind": "package-drift", "severity": "non-blocker"}
    return "unchanged", entry


def _compare_install(b: Dict[str, Any], c: Dict[str, Any]) -> Tuple[str, Dict[str, Any]]:
    entry = {
        "dimension": "install",
        "baselineSmoke": b.get("smoke"),
        "candidateSmoke": c.get("smoke"),
        "upgradePath": c.get("upgradePath"),
        "provenance": c.get("provenance"),
    }
    if b.get("smoke") == "pass" and c.get("smoke") != "pass":
        return "regression", {**entry, "reason": "install-smoke-failed"}
    if c.get("upgradePath") == "failed":
        return "regression", {**entry, "reason": "upgrade-path-failed"}
    if b.get("smoke") != "pass" and c.get("smoke") == "pass":
        return "improvement", {**entry, "reason": "install-smoke-improved"}
    return "unchanged", entry


def _compare_version(b: Dict[str, Any], c: Dict[str, Any]) -> Tuple[str, Dict[str, Any]]:
    entry = {
        "dimension": "version",
        "baselineVersion": b.get("version"),
        "candidateVersion": c.get("version"),
        "changelogEntry": c.get("changelogEntry"),
    }
    if b.get("version") != c.get("version") and not c.get("changelogEntry"):
        return "drift", {**entry, "kind": "missing-changelog", "severity": "non-blocker"}
    if b.get("version") == c.get("version"):
        return "unchanged", entry
    return "drift", {**entry, "kind": "version-bump", "severity": "non-blocker"}


def _compare_docs(b: Dict[str, Any], c: Dict[str, Any]) -> Tuple[str, Dict[str, Any]]:
    mismatches = int(c.get("claimMismatches") or 0)
    entry = {
        "dimension": "docs",
        "claimMismatches": mismatches,
        "provenance": c.get("provenance"),
    }
    if mismatches > 0:
        return "drift", {**entry, "kind": "documentation-claim-drift", "severity": "non-blocker"}
    return "unchanged", entry


def _compare_security(b: Dict[str, Any], c: Dict[str, Any]) -> Tuple[str, Dict[str, Any]]:
    b_adv = int(b.get("advisories") or 0)
    c_adv = int(c.get("advisories") or 0)
    entry = {
        "dimension": "security",
        "baselineAdvisories": b_adv,
        "candidateAdvisories": c_adv,
        "provenance": c.get("provenance"),
    }
    if c_adv > b_adv:
        return "regression", {**entry, "reason": "new-security-advisories"}
    if c_adv < b_adv:
        return "improvement", {**entry, "reason": "fewer-advisories"}
    return "unchanged", entry


def _compare_budgets(b: Dict[str, Any], c: Dict[str, Any]) -> Tuple[str, Dict[str, Any]]:
    entry = {
        "dimension": "budgets",
        "baselineBytes": b.get("bytes"),
        "candidateBytes": c.get("bytes"),
        "measured": c.get("measured"),
        "provenance": c.get("provenance"),
    }
    if c.get("measured") is False:
        return "drift", {**entry, "kind": "unmeasured", "severity": "unmeasured"}
    if (
        b.get("bytes") is not None
        and c.get("bytes") is not None
        and c["bytes"] > b["bytes"] * 1.1
    ):
        return "regression", {**entry, "reason": "budget-exceeded"}
    return "unchanged", entry


def _compare_dimension(
    dim: str,
    baseline: Dict[str, Any],
    candidate: Dict[str, Any],
    exclusions: List[str],
) -> Tuple[str, Optional[Dict[str, Any]]]:
    b = baseline.get(dim)
    c = candidate.get(dim)
    if b is None and c is None:
        return "skip", None
    if b is None and c is not None:
        return "drift", {"dimension": dim, "kind": "new-in-candidate"}
    if b is not None and c is None:
        return "drift", {"dimension": dim, "kind": "missing-in-candidate", "severity": "blocker"}

    comparators = {
        "tests": _compare_tests,
        "publicApi": _compare_public_api,
        "package": lambda bb, cc: _compare_package(bb, cc, exclusions),
        "install": _compare_install,
        "version": _compare_version,
        "docs": _compare_docs,
        "security": _compare_security,
        "budgets": _compare_budgets,
    }
    return comparators[dim](b, c)


def baseline_compare(raw: Dict[str, Any]) -> Dict[str, Any]:
    baseline_ref = raw.get("baselineRef")
    baseline = raw.get("baseline") or {}
    candidate = raw.get("candidate") or {}
    exclusions = list(raw.get("packageExclusions") or [])

    if not baseline_ref:
        return {
            "schemaVersion": SCHEMA_VERSION,
            "kind": "baseline-compare",
            "baselinePresent": False,
            "regressions": [],
            "improvements": [],
            "unchanged": [],
            "drift": [],
            "error": "missing-baseline-ref",
            "action": "park",
        }
    if not baseline:
        return {
            "schemaVersion": SCHEMA_VERSION,
            "kind": "baseline-compare",
            "baselineRef": baseline_ref,
            "baselinePresent": False,
            "regressions": [],
            "improvements": [],
            "unchanged": [],
            "drift": [],
            "error": "missing-baseline-artifacts",
            "action": "park",
        }

    regressions: List[Dict[str, Any]] = []
    improvements: List[Dict[str, Any]] = []
    unchanged: List[Dict[str, Any]] = []
    drift: List[Dict[str, Any]] = []

    for dim in COMPARE_DIMENSIONS:
        outcome, entry = _compare_dimension(dim, baseline, candidate, exclusions)
        if outcome == "skip" or entry is None:
            continue
        if outcome == "regression":
            regressions.append(entry)
        elif outcome == "improvement":
            improvements.append(entry)
        elif outcome == "drift":
            drift.append(entry)
        else:
            unchanged.append(entry)

    return {
        "schemaVersion": SCHEMA_VERSION,
        "kind": "baseline-compare",
        "baselineRef": baseline_ref,
        "baselinePresent": True,
        "regressions": regressions,
        "improvements": improvements,
        "unchanged": unchanged,
        "drift": drift,
        "provenancePreserved": True,
    }


def public_claims_matrix(manifest: Dict[str, Any]) -> Dict[str, Any]:
    rows: List[Dict[str, Any]] = []
    for claim in manifest.get("claims") or []:
        authority = claim.get("authority")
        verified = claim.get("verifiedLocally")
        surface_type = claim.get("surfaceType") or claim.get("surface")
        positioning = surface_type in ("positioning", "legal") or authority in ("marketing", "legal")
        mechanical = (
            verified is False
            and authority in MECHANICAL_AUTHORITIES
            and not positioning
        )
        rows.append(
            {
                "claim": claim.get("text"),
                "surface": claim.get("surface"),
                "surfaceType": surface_type,
                "authority": authority,
                "verifiedLocally": verified,
                "mechanicalDrift": mechanical,
                "action": "repair" if mechanical else "park",
            }
        )
    return {
        "schemaVersion": SCHEMA_VERSION,
        "kind": "public-claims-matrix",
        "rows": rows,
        "parkPositioningLegal": True,
        "networkQueryAllowed": False,
    }


def _collect_release_blockers(
    compare: Dict[str, Any],
    blockers: List[Dict[str, Any]],
    non_blockers: List[Dict[str, Any]],
    unmeasured: List[Dict[str, Any]],
) -> None:
    if not compare.get("baselinePresent", True):
        blockers.append(
            {
                "source": "baseline-compare",
                "reason": compare.get("error") or "missing-baseline",
                "action": compare.get("action") or "park",
            }
        )

    for reg in compare.get("regressions") or []:
        blockers.append({**reg, "source": "baseline-compare"})

    for item in compare.get("drift") or []:
        wrapped = {**item, "source": "baseline-compare"}
        severity = item.get("severity")
        if severity == "blocker":
            blockers.append(wrapped)
        elif severity == "unmeasured":
            unmeasured.append(wrapped)
        else:
            non_blockers.append(wrapped)


def verdict(raw: Dict[str, Any]) -> Dict[str, Any]:
    blockers: List[Dict[str, Any]] = list(raw.get("blockers") or [])
    non_blockers: List[Dict[str, Any]] = list(raw.get("nonBlockers") or [])
    unmeasured: List[Dict[str, Any]] = list(raw.get("unmeasured") or [])
    compare = raw.get("baselineCompare") or {}
    ci_green = bool(raw.get("ciGreen"))

    _collect_release_blockers(compare, blockers, non_blockers, unmeasured)

    for claim in (raw.get("publicClaims") or {}).get("rows") or []:
        if claim.get("mechanicalDrift"):
            non_blockers.append({**claim, "source": "public-claims"})

    status = "ready"
    if blockers:
        status = "not-ready"
    elif non_blockers or unmeasured:
        status = "conditionally-ready"

    return {
        "schemaVersion": SCHEMA_VERSION,
        "kind": "release-verdict",
        "status": status,
        "blockers": blockers,
        "nonBlockers": non_blockers,
        "unmeasured": unmeasured,
        "neverPublish": True,
        "humanAcceptanceClaimAllowed": False,
        "greenCiIsCompleteEvidence": False,
        "ciGreen": ci_green,
        "nightshiftVerdictIsHumanAcceptance": False,
    }


def unmeasured_surfaces(raw: Dict[str, Any]) -> Dict[str, Any]:
    surfaces: List[Dict[str, Any]] = []
    for item in raw.get("surfaces") or []:
        surfaces.append(
            {
                "surface": item.get("surface"),
                "reason": item.get("reason") or "not measured",
                "provenance": item.get("provenance"),
                "environment": item.get("environment"),
            }
        )
    return {
        "schemaVersion": SCHEMA_VERSION,
        "kind": "unmeasured-surfaces",
        "surfaces": surfaces,
        "count": len(surfaces),
    }


def main(argv: List[str]) -> int:
    p = argparse.ArgumentParser(prog="release-readiness-evidence.py")
    sub = p.add_subparsers(dest="cmd", required=True)
    for name in ("baseline-compare", "public-claims-matrix", "verdict", "unmeasured-surfaces"):
        sub.add_parser(name).add_argument("--input", required=True)
    args = p.parse_args(argv)

    with open(args.input, encoding="utf-8") as fh:
        data = json.load(fh)

    if args.cmd == "baseline-compare":
        doc = baseline_compare(data)
    elif args.cmd == "public-claims-matrix":
        doc = public_claims_matrix(data)
    elif args.cmd == "verdict":
        doc = verdict(data)
    elif args.cmd == "unmeasured-surfaces":
        doc = unmeasured_surfaces(data)
    else:
        return 1

    sys.stdout.write(json.dumps(doc, indent=2, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
