#!/usr/bin/env python3
"""coverage-risk.py — explainable coverage risk mapping and test adequacy helpers."""
from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Tuple

RISK_PRIORITY = {
    "auth": 1,
    "public-api": 2,
    "error-handling": 3,
    "retry-timeout": 4,
    "validation": 5,
    "persistence": 6,
    "concurrency": 7,
    "migration": 8,
    "parser": 9,
    "state-machine": 10,
    "calculation": 11,
    "transformation": 12,
    "changed-code": 13,
    "low-coverage": 14,
}

FLOW_CATEGORY = {
    "login": "auth",
    "auth": "auth",
    "retry": "retry-timeout",
    "timeout": "retry-timeout",
    "validate": "validation",
    "persist": "persistence",
    "migrate": "migration",
    "parse": "parser",
    "state": "state-machine",
    "calculate": "calculation",
    "transform": "transformation",
}

CLUSTER_ID_FMT = "cluster-%03d"
NPM_TEST_SUITE = "npm test -- %s"


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def choose_test_level(category: str, critical: bool) -> str:
    if category in ("auth", "migration", "persistence"):
        return "integration" if critical else "unit"
    if category in ("parser", "state-machine"):
        return "unit"
    return "unit"


def cluster_from_flow(flow: Dict[str, Any], pkg: str, cov_pct: Optional[float], evidence: List[str]) -> Dict[str, Any]:
    cat = flow.get("category") or FLOW_CATEGORY.get(str(flow.get("id", "")).lower(), "public-api")
    critical = bool(flow.get("critical"))
    locator = flow.get("path") or pkg
    behavior = flow.get("behaviorProtected") or (
        "critical %s flow at %s remains behavior-tested, not line-count padded" % (cat, locator)
    )
    regression = flow.get("regressionCaught") or (
        "regression in %s handling at %s" % (cat.replace("-", " "), locator)
    )
    return {
        "riskCategory": cat,
        "behaviorProtected": behavior,
        "regressionCaught": regression,
        "testLevel": choose_test_level(cat, critical),
        "locator": locator,
        "evidence": evidence,
        "redStatePossible": bool(flow.get("redStatePossible", True)),
        "redStateNote": flow.get("redStateNote"),
        "containingSuites": flow.get("containingSuites") or [NPM_TEST_SUITE % pkg],
        "coveragePct": cov_pct,
        "misleadingCoverage": False,
    }


def flow_evidence(flow, path, changed, bug_paths, pct):
    evidence = []
    if flow.get("critical"):
        evidence.append("critical flow")
    if path in changed:
        evidence.append("recent change")
    if path in bug_paths:
        evidence.append("local bug history")
    if pct is not None:
        evidence.append("line coverage %.0f%%" % pct)
    if flow.get("publicExport"):
        evidence.append("public export %s" % flow["publicExport"])
    return evidence


def clusters_from_flows(manifest, coverage_by_path, changed, bug_paths):
    clusters = []
    n = 0
    for flow in manifest.get("flows") or []:
        path = flow.get("path") or "."
        cov = coverage_by_path.get(path) or {}
        pct = None
        if cov.get("lines") and isinstance(cov["lines"], dict):
            pct = cov["lines"].get("pct")
        evidence = flow_evidence(flow, path, changed, bug_paths, pct)
        n += 1
        c = cluster_from_flow(flow, path.rsplit("/", 1)[0] or ".", pct, evidence)
        c["id"] = CLUSTER_ID_FMT % n
        clusters.append(c)
    return clusters, n


def export_cluster(n, pkg_path, export):
    return {
                    "id": CLUSTER_ID_FMT % n,
        "riskCategory": "public-api",
        "behaviorProtected": "exported %s contract stays stable under change" % export,
        "regressionCaught": "breaking change to public export %s" % export,
        "testLevel": "unit",
        "locator": "%s:%s" % (pkg_path, export),
        "evidence": ["public export", "uncovered surface"],
        "priority": 0,
        "redStatePossible": True,
        "redStateNote": None,
                    "containingSuites": [NPM_TEST_SUITE % pkg_path],
        "coveragePct": None,
        "misleadingCoverage": False,
    }


def clusters_from_exports(manifest, n):
    clusters = []
    for pkg in manifest.get("packages") or []:
        pkg_path = pkg.get("path") or pkg.get("name") or "."
        for export in pkg.get("publicExports") or []:
            if any(export in (f.get("publicExport") or "") for f in manifest.get("flows") or []):
                continue
            n += 1
            clusters.append(export_cluster(n, pkg_path, export))
    return clusters, n


def misleading_coverage_cluster(n, path, pct):
    return {
                    "id": CLUSTER_ID_FMT % n,
        "riskCategory": "low-coverage",
        "behaviorProtected": "",
        "regressionCaught": "",
        "testLevel": "unit",
        "locator": path,
        "evidence": ["high line coverage without mapped critical behavior"],
        "priority": 99,
        "redStatePossible": False,
        "redStateNote": "high coverage alone does not satisfy the contract",
        "containingSuites": [],
        "coveragePct": pct,
        "misleadingCoverage": True,
    }


def low_coverage_cluster(n, path, pct, branch_pct, changed):
    cat = "changed-code" if path in changed else "low-coverage"
    evidence = ["low branch/path coverage"]
    if branch_pct is not None:
        evidence.append("branch coverage %.0f%%" % branch_pct)
    if path in changed:
        evidence.append("recent change")
    return {
                    "id": CLUSTER_ID_FMT % n,
        "riskCategory": cat,
        "behaviorProtected": "untested branches on %s cannot hide regressions" % path,
        "regressionCaught": "silent failure in rarely executed path at %s" % path,
        "testLevel": "unit",
        "locator": path,
        "evidence": evidence,
        "priority": 0,
        "redStatePossible": True,
        "redStateNote": None,
                    "containingSuites": [NPM_TEST_SUITE % path.rsplit("/", 1)[0]],
        "coveragePct": pct,
        "misleadingCoverage": False,
    }


def _append_coverage_cluster(path, cov, changed, bug_paths, clusters, n):
    pct = cov.get("lines", {}).get("pct") if isinstance(cov.get("lines"), dict) else None
    branches = cov.get("branches", {})
    branch_pct = branches.get("pct") if isinstance(branches, dict) else None
    if pct is not None and pct >= 85 and path not in changed and path not in bug_paths:
        if not any(c.get("locator") == path for c in clusters):
            n += 1
            clusters.append(misleading_coverage_cluster(n, path, pct))
        return clusters, n
    if pct is not None and pct < 60:
        if any(c.get("locator") == path and c.get("riskCategory") != "low-coverage" for c in clusters):
            return clusters, n
        n += 1
        clusters.append(low_coverage_cluster(n, path, pct, branch_pct, changed))
    return clusters, n


def clusters_from_coverage(coverage_by_path, changed, bug_paths, clusters, n):
    for path, cov in coverage_by_path.items():
        clusters, n = _append_coverage_cluster(path, cov, changed, bug_paths, clusters, n)
    return clusters, n


def map_risks(manifest: Dict[str, Any]) -> Dict[str, Any]:
    work_target = manifest.get("workTarget") or "/repo"
    mutation_allowed = bool(manifest.get("mutationAllowed"))
    coverage_by_path = {
        c.get("path"): c for c in manifest.get("coverage") or [] if c.get("path")
    }
    changed = set(manifest.get("recentChanges") or [])
    bug_paths = {b.get("path") for b in manifest.get("bugHistory") or [] if b.get("path")}

    clusters, n = clusters_from_flows(manifest, coverage_by_path, changed, bug_paths)
    export_clusters, n = clusters_from_exports(manifest, n)
    clusters.extend(export_clusters)
    clusters, n = clusters_from_coverage(coverage_by_path, changed, bug_paths, clusters, n)

    unsupported = []
    if manifest.get("mutationDetected") and not mutation_allowed:
        unsupported.append("mutation/property/fuzz checks detected but not allowed by shift policy")

    ranked = rank_clusters(clusters)
    misleading = any(c.get("misleadingCoverage") for c in ranked)
    valid = [c for c in ranked if not c.get("misleadingCoverage") and c.get("behaviorProtected")]
    return {
        "schemaVersion": 1,
        "workTarget": work_target,
        "mappedAt": manifest.get("mappedAt") or utc_now(),
        "mutationAllowed": mutation_allowed,
        "misleadingCoverageRejected": misleading,
        "clusters": valid,
        "unsupportedSurfaces": unsupported,
    }


def rank_clusters(clusters: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    def key(c: Dict[str, Any]) -> Tuple[int, int, str]:
        cat = c.get("riskCategory") or "low-coverage"
        pri = RISK_PRIORITY.get(cat, 50)
        if c.get("misleadingCoverage"):
            pri = 100
        cov = c.get("coveragePct")
        cov_key = int(cov) if isinstance(cov, (int, float)) else 999
        return (pri, cov_key, c.get("locator") or "")

    ranked = sorted(clusters, key=key)
    for i, c in enumerate(ranked, 1):
        c["priority"] = i
    return ranked


def receipt_line(cluster: Dict[str, Any]) -> str:
    return (
        "protected: %s — regression: %s — level: %s — locator: %s"
        % (
            cluster.get("behaviorProtected"),
            cluster.get("regressionCaught"),
            cluster.get("testLevel"),
            cluster.get("locator"),
        )
    )


def red_state_check(cluster: Dict[str, Any], observed: str) -> Dict[str, Any]:
    ok = bool(cluster.get("redStatePossible")) and observed.strip().lower() in (
        "fail",
        "failed",
        "red",
        "failing",
    )
    return {
        "clusterId": cluster.get("id"),
        "redStateDemonstrated": ok,
        "note": cluster.get("redStateNote"),
        "containingSuites": cluster.get("containingSuites") or [],
    }


def cmd_map(args: argparse.Namespace) -> int:
    with open(args.input, encoding="utf-8") as fh:
        manifest = json.load(fh)
    doc = map_risks(manifest)
    sys.stdout.write(json.dumps(doc, indent=2, sort_keys=True) + "\n")
    return 0


def cmd_receipt(args: argparse.Namespace) -> int:
    with open(args.input, encoding="utf-8") as fh:
        doc = json.load(fh)
    idx = args.cluster - 1
    clusters = doc.get("clusters") or []
    if idx < 0 or idx >= len(clusters):
        print("coverage-risk: cluster index out of range", file=sys.stderr)
        return 1
    sys.stdout.write(receipt_line(clusters[idx]) + "\n")
    return 0


def cmd_red_state(args: argparse.Namespace) -> int:
    with open(args.input, encoding="utf-8") as fh:
        doc = json.load(fh)
    clusters = doc.get("clusters") or []
    cluster = next((c for c in clusters if c.get("id") == args.cluster), None)
    if not cluster:
        print("coverage-risk: cluster not found", file=sys.stderr)
        return 1
    out = red_state_check(cluster, args.observed or "")
    sys.stdout.write(json.dumps(out, indent=2, sort_keys=True) + "\n")
    return 0


def main(argv: List[str]) -> int:
    p = argparse.ArgumentParser(prog="coverage-risk.py")
    sub = p.add_subparsers(dest="cmd", required=True)

    pm = sub.add_parser("map")
    pm.add_argument("--input", required=True)
    pm.set_defaults(func=cmd_map)

    pr = sub.add_parser("receipt-line")
    pr.add_argument("--input", required=True)
    pr.add_argument("--cluster", type=int, default=1)
    pr.set_defaults(func=cmd_receipt)

    ps = sub.add_parser("red-state")
    ps.add_argument("--input", required=True)
    ps.add_argument("--cluster", required=True)
    ps.add_argument("--observed", default="")
    ps.set_defaults(func=cmd_red_state)

    args = p.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
