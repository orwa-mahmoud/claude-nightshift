#!/usr/bin/env python3
"""seo-evidence.py — Local, Live, and Connected SEO evidence helpers."""
from __future__ import annotations

import argparse
import json
import sys
from typing import Any, Dict, List
from urllib.parse import urlparse


BLOCKER_ORDER = [
    "crawl-indexing",
    "canonical-redirect",
    "rendered-schema",
    "evidence-opportunity",
    "internal-discovery",
    "performance-accessibility",
    "editorial",
]


def origin_allowed(url: str, origins: List[str]) -> bool:
    try:
        netloc = urlparse(url).netloc.lower()
    except Exception:
        return False
    for o in origins:
        base = urlparse(o if "://" in o else f"https://{o}").netloc.lower()
        if netloc == base:
            return True
    return False


def local_inventory(raw: Dict[str, Any]) -> Dict[str, Any]:
    orphans = raw.get("orphanCandidates") or []
    cannibal = raw.get("cannibalizationCandidates") or []
    gaps = raw.get("contentGaps") or []
    not_measured = raw.get("notMeasured") or []
    blockers: List[Dict[str, Any]] = []
    for o in orphans:
        blockers.append(
            {
                "category": "internal-discovery",
                "summary": "orphan candidate: %s" % o.get("pageId"),
                "action": "repair-or-noindex",
            }
        )
    for c in cannibal:
        blockers.append(
            {
                "category": "evidence-opportunity",
                "summary": "cannibalization: %s" % c.get("intent"),
                "action": "consolidate-or-differentiate",
            }
        )
    return {
        "schemaVersion": 1,
        "kind": "local-inventory",
        "evidenceMode": "local",
        "inventoryCount": len(raw.get("inventory") or []),
        "orphanCount": len(orphans),
        "cannibalizationCount": len(cannibal),
        "contentGapCount": len(gaps),
        "notMeasured": not_measured,
        "blockers": sorted(blockers, key=lambda b: BLOCKER_ORDER.index(b["category"])),
        "rankingsInvented": False,
    }


def live_crawl(raw: Dict[str, Any]) -> Dict[str, Any]:
    origins = raw.get("approvedOrigins") or []
    pages = raw.get("pages") or []
    escapes: List[str] = []
    malicious: List[str] = []
    for p in pages:
        url = p.get("finalUrl") or p.get("url") or ""
        if url and not origin_allowed(url, origins):
            escapes.append(url)
        mp = p.get("maliciousPageInstructions") or {}
        if mp.get("detected"):
            malicious.append(url)
    sitemap = raw.get("sitemapHealth") or {}
    blockers: List[Dict[str, Any]] = []
    if escapes:
        blockers.append(
            {
                "category": "crawl-indexing",
                "summary": "crawl left approved origins",
                "action": "park",
                "count": len(escapes),
            }
        )
    if sitemap.get("missingFromSitemap"):
        blockers.append(
            {
                "category": "crawl-indexing",
                "summary": "urls missing from sitemap",
                "action": "repair",
                "count": len(sitemap.get("missingFromSitemap") or []),
            }
        )
    for p in pages:
        if p.get("canonical") and p.get("finalUrl") and p["canonical"] != p["finalUrl"]:
            blockers.append(
                {
                    "category": "canonical-redirect",
                    "summary": "canonical mismatch: %s" % p.get("finalUrl"),
                    "action": "repair",
                }
            )
    for url in malicious:
        blockers.append(
            {
                "category": "rendered-schema",
                "summary": "malicious page instructions detected: %s" % url,
                "action": "neutralize-never-execute",
            }
        )
    return {
        "schemaVersion": 1,
        "kind": "live-crawl",
        "evidenceMode": "live",
        "approvedOrigins": origins,
        "originEscapes": escapes,
        "maliciousPages": malicious,
        "sitemapStatus": sitemap.get("status"),
        "blockers": sorted(blockers, key=lambda b: BLOCKER_ORDER.index(b["category"])),
        "neverLeaveApprovedOrigins": True,
    }


def connected_export(raw: Dict[str, Any]) -> Dict[str, Any]:
    disclaimer = raw.get("metricsDisclaimer") or {}
    blockers: List[Dict[str, Any]] = []
    if disclaimer.get("clicksNotSessions") is not True:
        blockers.append(
            {
                "category": "evidence-opportunity",
                "summary": "metrics disclaimer missing clicks-not-sessions",
                "action": "repair-receipt",
            }
        )
    sc_rows = (raw.get("searchConsole") or {}).get("rows") or []
    ga_rows = (raw.get("analytics") or {}).get("rows") or []
    return {
        "schemaVersion": 1,
        "kind": "connected-export",
        "evidenceMode": "connected",
        "searchConsoleRows": len(sc_rows),
        "analyticsRows": len(ga_rows),
        "metricsSeparate": True,
        "clicksEqualSessionsClaimAllowed": False,
        "periodComparison": raw.get("periodComparison"),
        "segmentation": raw.get("segmentation"),
        "blockers": blockers,
    }


def rank_blockers(raw: Dict[str, Any]) -> Dict[str, Any]:
    combined: List[Dict[str, Any]] = list(raw.get("blockers") or [])
    for mode in raw.get("modes") or []:
        combined.extend(mode.get("blockers") or [])
    ranked = sorted(combined, key=lambda b: BLOCKER_ORDER.index(b.get("category", "editorial")))
    return {
        "schemaVersion": 1,
        "kind": "seo-blocker-ranking",
        "ranked": ranked,
        "order": BLOCKER_ORDER,
    }


def receipt_summary(raw: Dict[str, Any]) -> Dict[str, Any]:
    modes = raw.get("evidenceModes") or []
    unknowable = raw.get("notMeasured") or []
    return {
        "schemaVersion": 1,
        "kind": "seo-receipt-summary",
        "evidenceModesRan": modes,
        "unknowableSurfaces": [u.get("surface") for u in unknowable],
        "receiptMustStateModes": True,
        "text": "Evidence modes: %s. Unknowable: %s"
        % (", ".join(modes) or "none", ", ".join(u.get("surface", "?") for u in unknowable) or "none"),
    }


def main(argv: List[str]) -> int:
    p = argparse.ArgumentParser(prog="seo-evidence.py")
    sub = p.add_subparsers(dest="cmd", required=True)
    for name in (
        "local-inventory",
        "live-crawl",
        "connected-export",
        "rank-blockers",
        "receipt-summary",
    ):
        sub.add_parser(name).add_argument("--input", required=True)
    args = p.parse_args(argv)
    with open(args.input, encoding="utf-8") as fh:
        data = json.load(fh)
    if args.cmd == "local-inventory":
        doc = local_inventory(data)
    elif args.cmd == "live-crawl":
        doc = live_crawl(data)
    elif args.cmd == "connected-export":
        doc = connected_export(data)
    elif args.cmd == "rank-blockers":
        doc = rank_blockers(data)
    elif args.cmd == "receipt-summary":
        doc = receipt_summary(data)
    else:
        return 1
    sys.stdout.write(json.dumps(doc, indent=2, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
