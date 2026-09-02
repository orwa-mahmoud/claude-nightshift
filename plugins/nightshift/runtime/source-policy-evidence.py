#!/usr/bin/env python3
"""source-policy-evidence.py — source policies, query manifests, and untrusted redaction."""
from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Set
from urllib.parse import urlparse


INJECTION_PATTERNS = [
    re.compile(r"(?i)ignore (all )?(previous|prior) instructions"),
    re.compile(r"(?i)system:\s*you are"),
    re.compile(r"(?i)disregard (the )?(above|prior)"),
    re.compile(r"(?i)run (this )?command:"),
    re.compile(r"(?i)execute the following"),
]
SECRET_PATTERNS = [
    re.compile(r"(?i)(password|api[_-]?key|secret|token)\s*=\s*\S+"),
    re.compile(r"https?://[^/\s]+:[^@\s]+@"),
]


def utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def domain_of(locator: str) -> Optional[str]:
    if locator.startswith("file:"):
        return None
    try:
        return urlparse(locator).netloc.lower()
    except Exception:
        return None


def policy_resolve(spec: Dict[str, Any]) -> Dict[str, Any]:
    policy = spec.get("policy") or "closed-list"
    sources: List[str] = list(spec.get("sources") or [])
    bounds = spec.get("bounds") or {}
    allowed: List[Dict[str, Any]] = []
    blocked: List[Dict[str, Any]] = []

    if policy == "closed-list":
        approved: Set[str] = set(spec.get("approvedSources") or sources)
        for loc in sources:
            if loc in approved:
                allowed.append({"locator": loc, "reason": "owner-listed"})
            else:
                blocked.append({"locator": loc, "reason": "not-on-closed-list"})

    elif policy == "bounded-discovery":
        domains = {d.lower() for d in (bounds.get("allowedDomains") or [])}
        classes = set(bounds.get("allowedClasses") or ["primary"])
        max_sources = int(bounds.get("maxSources") or 20)
        scoped_allowed: List[tuple[str, str]] = []
        for loc in sources:
            dom = domain_of(loc)
            src_class = spec.get("sourceClassByLocator", {}).get(loc, "primary")
            if loc.startswith("file:"):
                scoped_allowed.append((loc, "local-file-in-bounds"))
            elif dom and dom in domains and src_class in classes:
                scoped_allowed.append((loc, "domain-and-class-allowed"))
            else:
                blocked.append({"locator": loc, "reason": "outside-bounded-scope"})
        for i, (loc, reason) in enumerate(scoped_allowed):
            if i < max_sources:
                allowed.append({"locator": loc, "reason": reason})
            else:
                blocked.append({"locator": loc, "reason": "query-budget-exceeded"})

    elif policy == "connected-corpus":
        corpus_root = bounds.get("corpusRoot") or ""
        export_only = bool(bounds.get("exportOnly", True))
        for loc in sources:
            if loc.startswith("file:") and corpus_root and loc.startswith(f"file:{corpus_root}"):
                allowed.append({"locator": loc, "reason": "corpus-export"})
            elif loc.startswith("file:") and not export_only:
                allowed.append({"locator": loc, "reason": "connected-local"})
            else:
                blocked.append(
                    {
                        "locator": loc,
                        "reason": "direct-connector-out-of-scope" if not loc.startswith("file:") else "outside-corpus",
                    }
                )
    else:
        blocked = [{"locator": loc, "reason": "unknown-policy"} for loc in sources]

    return {
        "schemaVersion": 1,
        "kind": "source-policy",
        "policy": policy,
        "resolvedAt": utc_now(),
        "allowed": allowed,
        "blocked": blocked,
        "scopeEscapes": len(blocked) > 0 and policy == "bounded-discovery",
    }


def evidence_tier(source_class: str) -> str:
    if source_class in ("primary", "official", "first-party"):
        return "primary"
    if source_class in ("community", "forum", "social"):
        return "community"
    return "secondary"


def query_manifest(raw: Dict[str, Any]) -> Dict[str, Any]:
    entries: List[Dict[str, Any]] = []
    contradictions: List[Dict[str, Any]] = []
    for q in raw.get("queries") or []:
        src_class = q.get("sourceClass") or "primary"
        entries.append(
            {
                "id": q.get("id"),
                "locator": q.get("locator"),
                "retrievedAt": q.get("retrievedAt") or utc_now(),
                "author": q.get("author"),
                "publishedAt": q.get("publishedAt"),
                "sourceClass": src_class,
                "evidenceTier": evidence_tier(src_class),
                "exclusions": q.get("exclusions") or [],
                "confidence": q.get("confidence") or "medium",
                "status": q.get("status") or "ok",
            }
        )
    for pair in raw.get("contradictions") or []:
        contradictions.append(
            {
                "between": pair.get("between") or [],
                "topic": pair.get("topic"),
                "resolution": pair.get("resolution") or "named-not-resolved",
            }
        )
    return {
        "schemaVersion": 1,
        "kind": "query-manifest",
        "queryLog": entries,
        "primaryCount": sum(1 for e in entries if e["evidenceTier"] == "primary"),
        "secondaryCount": sum(1 for e in entries if e["evidenceTier"] == "secondary"),
        "communityCount": sum(1 for e in entries if e["evidenceTier"] == "community"),
        "contradictions": contradictions,
        "limitations": raw.get("limitations") or [],
        "untrustedMaterial": True,
    }


def redact_untrusted(raw: Dict[str, Any]) -> Dict[str, Any]:
    content = raw.get("content") or ""
    redactions: List[str] = []
    safe = content
    for pat in INJECTION_PATTERNS:
        if pat.search(safe):
            redactions.append("instruction-injection-neutralized")
            safe = pat.sub("[REDACTED-UNTRUSTED-INSTRUCTION]", safe)
    for pat in SECRET_PATTERNS:
        if pat.search(safe):
            redactions.append("secret-pattern-redacted")
            safe = pat.sub("[REDACTED-SECRET]", safe)
    return {
        "schemaVersion": 1,
        "kind": "redacted-untrusted",
        "locator": raw.get("locator"),
        "redactions": redactions,
        "content": safe,
        "treatAsUntrusted": True,
        "remoteInstructionsAlterShift": False,
    }


def artifact_receipt_plan(raw: Dict[str, Any]) -> Dict[str, Any]:
    outputs = raw.get("outputs") or []
    receipts: List[Dict[str, Any]] = []
    for out in outputs:
        receipts.append(
            {
                "output": out.get("path"),
                "item": out.get("item") or "Artifact deliverable",
                "verify": out.get("verify") or "file exists",
                "source": out.get("source"),
                "requiresGit": False,
                "destination": "$NS/receipts/",
            }
        )
    return {
        "schemaVersion": 1,
        "kind": "artifact-receipt-plan",
        "workMode": "artifact",
        "requiresRepository": False,
        "requiresPackageManager": False,
        "inventGitPrompts": False,
        "receipts": receipts,
    }


def connector_boundary(raw: Dict[str, Any]) -> Dict[str, Any]:
    connector = raw.get("connector") or "local-export"
    authorized = bool(raw.get("authorized", False))
    trust = raw.get("trustClass") or "owner-supplied-export"
    read_only = raw.get("readOnly", True)
    return {
        "schemaVersion": 1,
        "kind": "connector-boundary",
        "connector": connector,
        "authorized": authorized,
        "directConnectorAllowed": authorized and connector != "remote-api",
        "readCapability": read_only or raw.get("readCapability", True),
        "writeCapability": False if read_only else bool(raw.get("writeCapability", False)),
        "trustClass": trust,
        "queryBudget": raw.get("queryBudget") or {"maxQueries": 0, "maxBytes": 0},
        "redactionRequired": True,
        "provenanceRequired": True,
        "credentialsOutsideNightshift": True,
        "integrationsOptional": True,
    }


def main(argv: List[str]) -> int:
    p = argparse.ArgumentParser(prog="source-policy-evidence.py")
    sub = p.add_subparsers(dest="cmd", required=True)
    for name in (
        "policy-resolve",
        "query-manifest",
        "redact-untrusted",
        "artifact-receipt-plan",
        "connector-boundary",
    ):
        sub.add_parser(name).add_argument("--input", required=True)
    args = p.parse_args(argv)
    with open(args.input, encoding="utf-8") as fh:
        data = json.load(fh)
    if args.cmd == "policy-resolve":
        doc = policy_resolve(data)
    elif args.cmd == "query-manifest":
        doc = query_manifest(data)
    elif args.cmd == "redact-untrusted":
        doc = redact_untrusted(data)
    elif args.cmd == "artifact-receipt-plan":
        doc = artifact_receipt_plan(data)
    elif args.cmd == "connector-boundary":
        doc = connector_boundary(data)
    else:
        return 1
    sys.stdout.write(json.dumps(doc, indent=2, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
