#!/usr/bin/env python3
"""specialist-evidence.py — product journey and evidence-gated specialist helpers."""
from __future__ import annotations

import argparse
import json
import sys
from typing import Any, Dict, List, Optional, Set

SCHEMA_VERSION = 1

JOURNEY_MODES = frozenset(
    {"journey", "error-experience", "responsive-cross-browser", "accessibility-journey"}
)

GATED_SPECIALISTS = frozenset(
    {
        "slo-alert-quality",
        "backup-restore",
        "capacity-load",
        "license-compliance",
        "support-feedback",
        "product-analytics",
        "competitive-landscape",
        "architecture-health",
        "data-quality",
        "supply-chain",
        "content-architecture",
        "maintainer-health",
    }
)

MAINTAINER_PRESET = [
    {
        "contract": "developer-onboarding",
        "helper": "runtime/build-onboarding-evidence.sh onboarding-journey",
    },
    {
        "contract": "documentation-drift",
        "helper": "runtime/product-truth-evidence.sh doc-claim-matrix",
    },
    {
        "contract": "ci-warning-cleanup",
        "helper": "runtime/engineering-evidence.sh ci-warnings",
    },
    {
        "contract": "release-readiness",
        "helper": "runtime/release-readiness-evidence.sh public-claims-matrix",
    },
]

SPECIALIST_REQUIREMENTS: Dict[str, List[str]] = {
    "slo-alert-quality": ["sloDefinition", "alertHistory", "telemetryScope"],
    "backup-restore": ["namedData", "recoveryObjective", "disposableEnvironment"],
    "capacity-load": ["safeEnvironment", "loadBudget", "ownerAuthority"],
    "license-compliance": ["licenseInventory", "declaredLegalPolicy"],
    "support-feedback": ["feedbackExport", "piiPolicy", "sourceLimits"],
    "product-analytics": ["ownerQuestion", "exportScope"],
    "competitive-landscape": ["namedSources"],
    "architecture-health": ["repositoryStructure"],
    "data-quality": ["domainRules"],
    "supply-chain": ["repositoryTools"],
    "content-architecture": ["documentationTree"],
    "maintainer-health": ["repositoryStructure"],
}

AUTHORITY_GATED = frozenset(
    {"slo-alert-quality", "backup-restore", "capacity-load", "license-compliance", "support-feedback"}
)
EVIDENCE_PRESENT = "evidence present"


def _unavailable(rows: List[Dict[str, Any]], surface: str, reason: str) -> None:
    rows.append({"surface": surface, "status": "unavailable", "reason": reason})


def _journey_required_blockers(
    persona: str, goal: str, starting: str, steps: List[Any]
) -> List[Dict[str, Any]]:
    blockers: List[Dict[str, Any]] = []
    if not persona:
        blockers.append({"category": "persona", "summary": "missing persona", "action": "park"})
    if not goal:
        blockers.append({"category": "goal", "summary": "missing goal", "action": "park"})
    if not starting:
        blockers.append({"category": "starting-state", "summary": "missing starting state", "action": "park"})
    if not steps:
        blockers.append({"category": "steps", "summary": "missing journey steps", "action": "park"})
    return blockers


def _journey_mode_blockers(
    mode: str,
    steps: List[Any],
    browser_available: bool,
    keyboard: List[Any],
    unavailable: List[Dict[str, Any]],
) -> List[Dict[str, Any]]:
    blockers: List[Dict[str, Any]] = []
    if mode not in JOURNEY_MODES:
        blockers.append(
            {
                "category": "mode",
                "summary": "unknown evidence mode: %s" % mode,
                "action": "park",
            }
        )

    if mode in ("responsive-cross-browser", "journey") and not browser_available:
        _unavailable(unavailable, "browser", "no browser evidence available")
        if mode == "responsive-cross-browser":
            blockers.append(
                {
                    "category": "browser",
                    "summary": "responsive/cross-browser mode requires browser evidence",
                    "action": "record-unavailable",
                }
            )

    if mode == "accessibility-journey" and not keyboard and not browser_available:
        _unavailable(unavailable, "keyboard-journey", "no keyboard or browser observations supplied")
        blockers.append(
            {
                "category": "accessibility",
                "summary": "accessibility journey requires keyboard or browser evidence",
                "action": "record-unavailable",
            }
        )

    if mode == "error-experience":
        error_steps = [s for s in steps if s.get("expectsError") or s.get("recoveryState")]
        if not error_steps:
            blockers.append(
                {
                    "category": "error-experience",
                    "summary": "error mode requires expected/recovery states on steps",
                    "action": "park",
                }
            )

    return blockers


def _map_journey_step(idx: int, step: Dict[str, Any]) -> Dict[str, Any]:
    return {
        "index": idx,
        "action": step.get("action") or "",
        "expectedState": step.get("expectedState") or "",
        "errorState": step.get("errorState"),
        "recoveryState": step.get("recoveryState"),
        "expectsError": bool(step.get("expectsError")),
        "responsiveNote": step.get("responsiveNote"),
        "keyboardNote": step.get("keyboardNote"),
    }


def journey_map(raw: Dict[str, Any]) -> Dict[str, Any]:
    persona = (raw.get("persona") or "").strip()
    goal = (raw.get("goal") or "").strip()
    starting = (raw.get("startingState") or "").strip()
    steps = list(raw.get("steps") or [])
    mode = (raw.get("evidenceMode") or "journey").strip()
    browser = raw.get("browserEvidence") or {}
    browser_available = bool(browser.get("available"))
    surfaces = list(browser.get("surfaces") or [])
    responsive = list(raw.get("responsiveTargets") or [])
    keyboard = list(raw.get("keyboardObservations") or [])

    unavailable: List[Dict[str, Any]] = []
    blockers = _journey_required_blockers(persona, goal, starting, steps)
    blockers.extend(_journey_mode_blockers(mode, steps, browser_available, keyboard, unavailable))

    mapped_steps = [_map_journey_step(idx, step) for idx, step in enumerate(steps)]

    for target in responsive:
        if not browser_available:
            _unavailable(unavailable, "responsive:%s" % target, "browser evidence unavailable")

    ready = not blockers and bool(persona and goal and starting and steps)
    return {
        "schemaVersion": SCHEMA_VERSION,
        "kind": "journey-map",
        "persona": persona,
        "goal": goal,
        "startingState": starting,
        "evidenceMode": mode,
        "steps": mapped_steps,
        "browserEvidenceAvailable": browser_available,
        "browserSurfaces": surfaces,
        "responsiveTargets": responsive,
        "keyboardObservations": keyboard,
        "unavailableSurfaces": unavailable,
        "blockers": blockers,
        "ready": ready,
        "wholeProductCertificationAllowed": False,
        "platformClaimAllowed": browser_available,
        "humanReviewRequired": mode == "accessibility-journey" or bool(keyboard),
    }


def _journey_gap_ending(gaps: List[Any], actionable: List[Any]) -> str:
    if gaps and not actionable:
        return "complete"
    if actionable:
        return "work-remaining"
    return "no-gaps"


def journey_gap(raw: Dict[str, Any]) -> Dict[str, Any]:
    gaps: List[Dict[str, Any]] = []
    for g in raw.get("gaps") or []:
        reproducible = bool(g.get("reproducible"))
        entry = {
            "stepIndex": g.get("stepIndex"),
            "summary": g.get("summary") or "",
            "reproducible": reproducible,
            "severity": g.get("severity") or "medium",
            "fixableInRepo": bool(g.get("fixableInRepo", True)),
            "retestRequired": reproducible,
            "browserRequired": bool(g.get("browserRequired")),
        }
        if entry["browserRequired"] and not raw.get("browserEvidenceAvailable"):
            entry["status"] = "unavailable"
            entry["reason"] = "browser evidence unavailable — gap recorded, not verified"
        elif reproducible:
            entry["status"] = "actionable"
        else:
            entry["status"] = "park"
        gaps.append(entry)

    actionable = [g for g in gaps if g.get("status") == "actionable"]
    return {
        "schemaVersion": SCHEMA_VERSION,
        "kind": "journey-gap",
        "gaps": gaps,
        "actionableCount": len(actionable),
        "wholeProductCertificationAllowed": False,
        "ending": _journey_gap_ending(gaps, actionable),
    }


def journey_retest(raw: Dict[str, Any]) -> Dict[str, Any]:
    results: List[Dict[str, Any]] = []
    for r in raw.get("retests") or []:
        results.append(
            {
                "gapId": r.get("gapId"),
                "passed": bool(r.get("passed")),
                "evidence": r.get("evidence") or [],
                "browserUsed": bool(r.get("browserUsed")),
                "humanObserved": bool(r.get("humanObserved")),
            }
        )
    open_items = [r for r in results if not r["passed"]]
    return {
        "schemaVersion": SCHEMA_VERSION,
        "kind": "journey-retest",
        "retests": results,
        "openCount": len(open_items),
        "journeyComplete": len(results) > 0 and not open_items,
        "wholeProductCertificationAllowed": False,
        "shiftLogLine": "journey retest · %d/%d passed" % (
            len(results) - len(open_items),
            len(results),
        ),
    }


def _has_evidence(evidence: Dict[str, Any], *keys: str) -> bool:
    return all(bool(evidence.get(k)) for k in keys)


def _gate_authority_controlled(
    present: bool,
    missing: List[str],
    selection: str,
    authority: bool,
) -> tuple[bool, bool, str]:
    if not present:
        return False, False, "missing required evidence: %s" % ", ".join(missing)
    automatic_allowed = present and authority
    if selection == "automatic" and not automatic_allowed:
        return False, False, "automatic selection requires explicit evidence and owner authority"
    return True, automatic_allowed, EVIDENCE_PRESENT


def _gate_named_kind(kind: str, present: bool, _missing: List[str]) -> Optional[tuple[bool, bool, str]]:
    if kind == "product-analytics":
        reason = EVIDENCE_PRESENT if present else "product analytics requires owner question and supplied export scope"
        return present, False, reason
    if kind == "competitive-landscape":
        reason = EVIDENCE_PRESENT if present else "competitive landscape requires named research sources"
        return present, False, reason
    if kind == "license-compliance":
        return present, False, "license work inventories evidence but never gives legal conclusions"
    return None


def _specialist_gate_selection(
    kind: str,
    present: bool,
    missing: List[str],
    selection: str,
    authority: bool,
) -> tuple[bool, bool, str]:
    if kind in AUTHORITY_GATED:
        return _gate_authority_controlled(present, missing, selection, authority)
    named = _gate_named_kind(kind, present, missing)
    if named is not None:
        return named
    selectable = present
    automatic_allowed = present and selection != "automatic"
    reason = EVIDENCE_PRESENT if present else "missing required evidence: %s" % ", ".join(missing)
    return selectable, automatic_allowed, reason


def specialist_gate(raw: Dict[str, Any]) -> Dict[str, Any]:
    kind = (raw.get("specialistKind") or "").strip()
    selection = (raw.get("selectionMode") or "guided").lower()
    evidence = raw.get("evidence") or {}
    authority = bool(raw.get("ownerAuthorityGranted"))

    if kind not in GATED_SPECIALISTS:
        return {
            "schemaVersion": SCHEMA_VERSION,
            "kind": "specialist-gate",
            "specialistKind": kind,
            "selectable": False,
            "automaticAllowed": False,
            "reason": "unknown specialist kind",
            "humanDecisionSurface": True,
        }

    required = SPECIALIST_REQUIREMENTS.get(kind, [])
    missing = [k for k in required if not evidence.get(k)]
    present = _has_evidence(evidence, *required) if required else True

    selectable, automatic_allowed, reason = _specialist_gate_selection(
        kind, present, missing, selection, authority
    )

    return {
        "schemaVersion": SCHEMA_VERSION,
        "kind": "specialist-gate",
        "specialistKind": kind,
        "selectionMode": selection,
        "requiredEvidence": required,
        "missingEvidence": missing,
        "selectable": selectable,
        "automaticAllowed": automatic_allowed,
        "reason": reason,
        "legalConclusionAllowed": False,
        "causalClaimAllowed": False,
        "humanDecisionSurface": kind in ("license-compliance", "support-feedback", "architecture-health"),
    }


def architecture_findings(raw: Dict[str, Any]) -> Dict[str, Any]:
    findings: List[Dict[str, Any]] = []
    for f in raw.get("findings") or []:
        concrete = any(
            f.get(k)
            for k in ("dependency", "boundary", "ownership", "cycleCost", "measuredImpact")
        )
        taste_only = bool(f.get("tasteOnly")) or (
            not concrete and bool(f.get("summary"))
        )
        disposition = "reject-taste" if taste_only else "accepted"
        if concrete and not taste_only:
            findings.append(
                {
                    "id": f.get("id"),
                    "summary": f.get("summary") or "",
                    "dependency": f.get("dependency"),
                    "boundary": f.get("boundary"),
                    "ownership": f.get("ownership"),
                    "cycleCost": f.get("cycleCost"),
                    "disposition": disposition,
                    "directEditAllowed": bool(f.get("smallReversibleEdit")),
                }
            )

    direct_requested = bool(raw.get("directEditRequested"))
    review_first = raw.get("launchMode", "review-first") != "run-direct"
    any_direct = any(x.get("directEditAllowed") for x in findings)
    return {
        "schemaVersion": SCHEMA_VERSION,
        "kind": "architecture-findings",
        "findings": findings,
        "reviewFirstDefault": True,
        "directEditRequested": direct_requested,
        "directEditAllowed": (not review_first) and any_direct and direct_requested,
        "architecturalTastePresentedAsProof": False,
        "acceptedCount": len(findings),
    }


def data_quality_map(raw: Dict[str, Any]) -> Dict[str, Any]:
    domain_rules = (raw.get("domainRules") or "").strip()
    rows: List[Dict[str, Any]] = []
    blockers: List[Dict[str, Any]] = []

    if not domain_rules:
        blockers.append(
            {
                "category": "domain-rules",
                "summary": "missing named domain rules",
                "action": "park",
            }
        )

    for item in raw.get("datasets") or []:
        inferred = bool(item.get("inferredFromTypes"))
        rows.append(
            {
                "dataset": item.get("name") or "",
                "rule": item.get("rule") or "",
                "status": item.get("status") or "unknown",
                "inferredFromTypes": inferred,
                "accepted": bool(item.get("rule")) and not inferred,
            }
        )
        if inferred:
            blockers.append(
                {
                    "category": "inference",
                    "summary": "business rule inferred from types for %s" % item.get("name"),
                    "action": "reject",
                }
            )

    return {
        "schemaVersion": SCHEMA_VERSION,
        "kind": "data-quality-map",
        "domainRules": domain_rules or None,
        "datasets": rows,
        "blockers": blockers,
        "businessRuleInferenceAllowed": False,
        "ready": bool(domain_rules) and not blockers,
    }


def supply_chain_posture(raw: Dict[str, Any]) -> Dict[str, Any]:
    tools = list(raw.get("repositoryTools") or [])
    inventory = list(raw.get("inventory") or [])
    rows: List[Dict[str, Any]] = []
    for item in inventory:
        rows.append(
            {
                "component": item.get("component") or "",
                "source": item.get("source") or "repository-tool",
                "standard": item.get("standard"),
                "status": item.get("status") or "observed",
                "legalConclusion": None,
            }
        )
    return {
        "schemaVersion": SCHEMA_VERSION,
        "kind": "supply-chain-posture",
        "repositoryTools": tools,
        "inventory": rows,
        "legalConclusionAllowed": False,
        "repositoryOwnedOnly": True,
        "ready": bool(tools) and bool(rows),
    }


def analytics_investigation(raw: Dict[str, Any]) -> Dict[str, Any]:
    question = (raw.get("ownerQuestion") or "").strip()
    scope = raw.get("exportScope") or {}
    metrics = list(raw.get("metrics") or [])
    cohorts = list(raw.get("cohorts") or [])
    confounders = list(raw.get("confounders") or [])

    blockers: List[Dict[str, Any]] = []
    if not question:
        blockers.append({"category": "question", "summary": "missing owner question", "action": "park"})
    if not scope.get("connector") and not scope.get("exportPath"):
        blockers.append(
            {"category": "scope", "summary": "missing export or connector scope", "action": "park"}
        )

    semantic_rows = []
    for m in metrics:
        semantic_rows.append(
            {
                "metric": m.get("name") or "",
                "definition": m.get("definition") or "",
                "validated": bool(m.get("definition")) and bool(m.get("source")),
                "source": m.get("source"),
            }
        )

    return {
        "schemaVersion": SCHEMA_VERSION,
        "kind": "analytics-investigation",
        "ownerQuestion": question or None,
        "exportScope": scope,
        "metrics": semantic_rows,
        "cohorts": cohorts,
        "confounders": confounders,
        "blockers": blockers,
        "dashboardBuildingAllowed": False,
        "causalClaimAllowed": False,
        "metricInventionAllowed": False,
        "decisionWithLimits": bool(question) and not blockers,
        "ready": bool(question) and not blockers,
    }


def content_architecture(raw: Dict[str, Any]) -> Dict[str, Any]:
    tree = list(raw.get("documentationTree") or [])
    stale: List[Dict[str, Any]] = []
    for node in tree:
        entry = {
            "path": node.get("path") or "",
            "audience": node.get("audience"),
            "lastReviewed": node.get("lastReviewed"),
            "freshnessPolicy": node.get("freshnessPolicy"),
            "stale": bool(node.get("stale")),
            "orphan": bool(node.get("orphan")),
        }
        if entry["stale"] or entry["orphan"]:
            stale.append(entry)
    return {
        "schemaVersion": SCHEMA_VERSION,
        "kind": "content-architecture",
        "documentationTree": tree,
        "staleOrOrphan": stale,
        "parentContract": "documentation-drift",
        "ready": bool(tree),
    }


def maintainer_health_preset(raw: Dict[str, Any]) -> Dict[str, Any]:
    available = set(raw.get("availableContracts") or [])
    composed: List[Dict[str, Any]] = []
    for item in MAINTAINER_PRESET:
        contract = item["contract"]
        composed.append(
            {
                "contract": contract,
                "helper": item["helper"],
                "available": contract in available,
            }
        )
    ready_count = sum(1 for c in composed if c["available"])
    return {
        "schemaVersion": SCHEMA_VERSION,
        "kind": "maintainer-health-preset",
        "presetContracts": composed,
        "availableCount": ready_count,
        "selectable": ready_count >= 2,
        "catalogSprawl": False,
        "reason": "preset composes existing contracts" if ready_count >= 2 else "insufficient contracts available",
    }


def main(argv: List[str]) -> int:
    p = argparse.ArgumentParser(prog="specialist-evidence.py")
    sub = p.add_subparsers(dest="cmd", required=True)
    commands = (
        "journey-map",
        "journey-gap",
        "journey-retest",
        "specialist-gate",
        "architecture-findings",
        "data-quality-map",
        "supply-chain-posture",
        "analytics-investigation",
        "content-architecture",
        "maintainer-health-preset",
    )
    for name in commands:
        sub.add_parser(name).add_argument("--input", required=True)
    args = p.parse_args(argv)

    with open(args.input, encoding="utf-8") as fh:
        data = json.load(fh)

    dispatch = {
        "journey-map": journey_map,
        "journey-gap": journey_gap,
        "journey-retest": journey_retest,
        "specialist-gate": specialist_gate,
        "architecture-findings": architecture_findings,
        "data-quality-map": data_quality_map,
        "supply-chain-posture": supply_chain_posture,
        "analytics-investigation": analytics_investigation,
        "content-architecture": content_architecture,
        "maintainer-health-preset": maintainer_health_preset,
    }
    doc = dispatch[args.cmd](data)
    sys.stdout.write(json.dumps(doc, indent=2, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
