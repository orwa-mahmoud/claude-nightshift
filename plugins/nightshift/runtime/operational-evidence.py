#!/usr/bin/env python3
"""operational-evidence.py — measured performance and evidence-gated operational helpers."""
from __future__ import annotations

import argparse
import json
import statistics
import sys
from typing import Any, Dict, List, Optional, Tuple


SCHEMA_VERSION = 1

PERF_SOURCES = frozenset(
    {"benchmark", "profiler", "lighthouse", "trace", "load-test", "owner-supplied"}
)
INCIDENT_EVIDENCE = frozenset(
    {"postmortem", "timeline", "logs", "issues", "owner-narrative"}
)
DESTRUCTIVE_STEP_MARKERS = frozenset(
    {"drop-database", "purge-queue", "delete-production", "emergency-failover"}
)


def _distribution(samples: List[float]) -> Dict[str, Any]:
    if not samples:
        return {"count": 0}
    ordered = sorted(float(x) for x in samples)
    return {
        "count": len(ordered),
        "min": ordered[0],
        "max": ordered[-1],
        "mean": round(statistics.mean(ordered), 4),
        "p50": ordered[len(ordered) // 2],
    }


def _perf_compare_reasons(
    raw: Dict[str, Any],
    baseline: Dict[str, Any],
    candidate: Dict[str, Any],
    b_samples: List[Any],
    c_samples: List[Any],
    same_source: bool,
    source: Any,
    env: Dict[str, Any],
    correctness: Dict[str, Any],
) -> List[str]:
    reasons: List[str] = []
    if not raw.get("baselineRef") or not raw.get("baselinePresent"):
        reasons.append("missing-baseline")
    if source not in PERF_SOURCES:
        reasons.append("unsupported-measurement-source")
    if not env.get("stable"):
        reasons.append("unstable-environment")
    if len(b_samples) < 2 or len(c_samples) < 2:
        reasons.append("single-run-not-a-distribution")
    if baseline.get("unit") and candidate.get("unit") and baseline["unit"] != candidate["unit"]:
        reasons.append("unit-mismatch")
    if baseline.get("sourceId") and candidate.get("sourceId") and not same_source:
        reasons.append("source-mismatch")
    if correctness.get("baseline") == "pass" and correctness.get("candidate") != "pass":
        reasons.append("correctness-regression")
    return reasons


def _perf_compare_outcome(
    b_samples: List[Any],
    c_samples: List[Any],
    reasons: List[str],
) -> Tuple[str, bool, bool, str]:
    verdict = "unmeasured"
    action = "park"
    faster_claim_allowed = False
    regression_claim_allowed = False

    if not reasons and b_samples and c_samples:
        b_dist = _distribution(b_samples)
        c_dist = _distribution(c_samples)
        b_mean = float(b_dist["mean"])
        c_mean = float(c_dist["mean"])
        if c_mean > b_mean * 1.05:
            verdict = "regression"
            regression_claim_allowed = True
            action = "investigate-one-cause"
        elif c_mean < b_mean * 0.95:
            verdict = "improvement"
            faster_claim_allowed = True
            action = "record-with-provenance"
        else:
            verdict = "unchanged"
            action = "record-with-provenance"
    elif "missing-baseline" in reasons:
        verdict = "unmeasured"
        action = "park"

    return verdict, faster_claim_allowed, regression_claim_allowed, action


def perf_compare(raw: Dict[str, Any]) -> Dict[str, Any]:
    baseline_ref = raw.get("baselineRef")
    baseline_present = bool(raw.get("baselinePresent"))
    source = raw.get("source")
    env = raw.get("environment") or {}
    baseline = raw.get("baseline") or {}
    candidate = raw.get("candidate") or {}
    correctness = raw.get("correctness") or {}

    b_samples = list(baseline.get("samples") or [])
    c_samples = list(candidate.get("samples") or [])
    same_source = (
        baseline.get("sourceId") is not None
        and baseline.get("sourceId") == candidate.get("sourceId")
    )

    reasons = _perf_compare_reasons(
        raw, baseline, candidate, b_samples, c_samples, same_source, source, env, correctness
    )
    verdict, faster_claim_allowed, regression_claim_allowed, action = _perf_compare_outcome(
        b_samples, c_samples, reasons
    )

    return {
        "schemaVersion": SCHEMA_VERSION,
        "kind": "perf-compare",
        "baselineRef": baseline_ref,
        "baselinePresent": baseline_present,
        "source": source,
        "environmentStable": bool(env.get("stable")),
        "sameSourceCompared": same_source if baseline.get("sourceId") else None,
        "baselineDistribution": _distribution(b_samples),
        "candidateDistribution": _distribution(c_samples),
        "coherentCause": raw.get("coherentCause"),
        "correctnessPreserved": correctness.get("candidate") == correctness.get("baseline") == "pass",
        "verdict": verdict,
        "fasterClaimAllowed": faster_claim_allowed,
        "regressionClaimAllowed": regression_claim_allowed,
        "reasons": reasons,
        "action": action,
        "oneChangeAtATime": bool(raw.get("coherentCause")),
    }


def _route_incident_action(act: Dict[str, Any]) -> Tuple[str, Dict[str, Any]]:
    target = act.get("target") or "owner"
    entry = {
        "id": act.get("id"),
        "summary": act.get("summary"),
        "verified": bool(act.get("verified")),
        "action": act.get("action") or "park",
    }
    if target == "repository" and act.get("verified"):
        return "repository", entry
    if target == "repository":
        return "owner", {**entry, "reason": "needs-verification"}
    if target == "system":
        return "system", {**entry, "status": "open"}
    return "owner", entry


def _partition_incident_actions(actions: List[Dict[str, Any]]) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]], List[Dict[str, Any]]]:
    repository: List[Dict[str, Any]] = []
    owner: List[Dict[str, Any]] = []
    system: List[Dict[str, Any]] = []
    for act in actions:
        bucket, entry = _route_incident_action(act)
        if bucket == "repository":
            repository.append(entry)
        elif bucket == "system":
            system.append(entry)
        else:
            owner.append(entry)
    return repository, owner, system


def incident_actions(raw: Dict[str, Any]) -> Dict[str, Any]:
    supplied = set(raw.get("suppliedEvidence") or [])
    invented = not supplied or bool(raw.get("inventedNarrative"))
    missing = sorted(INCIDENT_EVIDENCE - supplied)

    timeline = list(raw.get("timeline") or [])
    impact = raw.get("impact") or {}
    factors = raw.get("factors") or {}
    actions = list(raw.get("proposedActions") or [])

    repository, owner, system = _partition_incident_actions(actions)

    return {
        "schemaVersion": SCHEMA_VERSION,
        "kind": "incident-actions",
        "suppliedEvidence": sorted(supplied),
        "missingEvidence": missing,
        "evidenceIncomplete": bool(missing),
        "inventedIncidentRefused": invented,
        "impactPreserved": bool(impact.get("summary")),
        "timelinePreserved": len(timeline) >= 1,
        "factors": {
            "root": list(factors.get("root") or []),
            "contributing": list(factors.get("contributing") or []),
            "detection": list(factors.get("detection") or []),
            "recovery": list(factors.get("recovery") or []),
        },
        "repositoryActions": repository,
        "ownerActions": owner,
        "systemActions": system,
        "action": "park" if invented else "implement-repository-only",
    }


def _classify_runbook_step(
    step: Dict[str, Any],
    environment: Dict[str, Any],
    safe_env: bool,
) -> Tuple[str, Dict[str, Any]]:
    name = step.get("name") or step.get("id")
    env_req = step.get("environment") or environment.get("name")
    destructive = bool(step.get("destructive")) or any(
        m in (step.get("command") or "").lower() for m in DESTRUCTIVE_STEP_MARKERS
    )
    entry = {"name": name, "environment": env_req, "evidence": step.get("evidence") or []}

    if env_req == "production" and not step.get("ownerApproved"):
        return "production_only", {**entry, "action": "park"}
    if destructive and not step.get("ownerApproved"):
        return "refused", {**entry, "reason": "destructive-emergency-step", "action": "refuse"}
    if not safe_env and env_req not in ("local", "disposable", "staging-approved"):
        return "refused", {**entry, "reason": "unsafe-environment", "action": "refuse"}
    if step.get("evidence"):
        return "verified", {**entry, "action": "verify"}
    return "refused", {**entry, "reason": "missing-step-evidence", "action": "park"}


def runbook_verify(raw: Dict[str, Any]) -> Dict[str, Any]:
    procedure = (raw.get("procedureName") or "").strip()
    environment = raw.get("environment") or {}
    steps = list(raw.get("steps") or [])
    safe_env = bool(environment.get("safe") or environment.get("disposable"))

    verified: List[Dict[str, Any]] = []
    refused: List[Dict[str, Any]] = []
    production_only: List[Dict[str, Any]] = []

    for step in steps:
        bucket, entry = _classify_runbook_step(step, environment, safe_env)
        if bucket == "verified":
            verified.append(entry)
        elif bucket == "production_only":
            production_only.append(entry)
        else:
            refused.append(entry)

    return {
        "schemaVersion": SCHEMA_VERSION,
        "kind": "runbook-verify",
        "procedureName": procedure or None,
        "safeEnvironmentNamed": safe_env,
        "vendorImposed": False,
        "verifiedSteps": verified,
        "refusedSteps": refused,
        "productionOnlySteps": production_only,
        "destructiveEmergencyAllowed": False,
        "action": "verify" if verified and not refused else "park",
    }


def observability_surface(raw: Dict[str, Any]) -> Dict[str, Any]:
    surfaces: List[Dict[str, Any]] = []
    for item in raw.get("signals") or []:
        kind = item.get("kind")
        present = bool(item.get("present"))
        reached_production = bool(item.get("reachedProduction"))
        surfaces.append(
            {
                "kind": kind,
                "present": present,
                "reachedProduction": reached_production if present else False,
                "failureSurface": item.get("failureSurface"),
                "measured": present and bool(item.get("sample")),
                "action": "use" if present and item.get("sample") else "record-absent",
            }
        )
    absent = [s for s in surfaces if not s["present"]]
    assumed = [s for s in surfaces if s["present"] and s["reachedProduction"] and not s["measured"]]
    return {
        "schemaVersion": SCHEMA_VERSION,
        "kind": "observability-surface",
        "surfaces": surfaces,
        "absentCount": len(absent),
        "assumedInProductionRefused": len(assumed) > 0,
        "telemetryInProductionAssumed": False,
        "action": "diagnose-with-evidence" if any(s["measured"] for s in surfaces) else "park",
    }


def toil_assess(raw: Dict[str, Any]) -> Dict[str, Any]:
    candidates: List[Dict[str, Any]] = []
    for task in raw.get("tasks") or []:
        frequency = task.get("frequencyPerMonth")
        failure_cost = task.get("failureCost") or "unknown"
        one_time = bool(task.get("oneTime"))
        manual_minutes = task.get("manualMinutes")
        entry = {
            "name": task.get("name"),
            "frequencyPerMonth": frequency,
            "failureCost": failure_cost,
            "manualMinutes": manual_minutes,
            "oneTime": one_time,
        }
        if one_time:
            entry["action"] = "refuse-automate"
            entry["reason"] = "one-time-annoyance"
        elif frequency is None or frequency < 2:
            entry["action"] = "park"
            entry["reason"] = "insufficient-repetition-evidence"
        else:
            entry["action"] = "automate-bounded"
            entry["reason"] = "repeated-manual-work"
        candidates.append(entry)
    return {
        "schemaVersion": SCHEMA_VERSION,
        "kind": "toil-assess",
        "candidates": candidates,
        "falseRepetitionRefused": any(c.get("reason") == "insufficient-repetition-evidence" for c in candidates),
        "oneTimeAutomateRefused": any(c.get("action") == "refuse-automate" for c in candidates),
        "action": "automate-bounded" if any(c.get("action") == "automate-bounded" for c in candidates) else "park",
    }


def capacity_guard(raw: Dict[str, Any]) -> Dict[str, Any]:
    target = raw.get("target") or {}
    env = raw.get("environment") or {}
    budgets = raw.get("budgets") or {}
    requested = int(raw.get("requestedRps") or target.get("rps") or 0)
    cap = budgets.get("maxRps")
    safe = bool(env.get("safe") or env.get("disposable"))
    production = (env.get("name") or "").lower() == "production"

    reasons: List[str] = []
    if production and not raw.get("ownerApproved"):
        reasons.append("unsafe-load-target-production")
    if not safe:
        reasons.append("environment-not-declared-safe")
    if isinstance(cap, int) and requested > cap:
        reasons.append("resource-budget-exceeded")

    allowed = not reasons
    return {
        "schemaVersion": SCHEMA_VERSION,
        "kind": "capacity-guard",
        "requestedRps": requested,
        "budgetMaxRps": cap,
        "environmentSafe": safe,
        "productionLoadAllowed": False,
        "allowed": allowed,
        "reasons": reasons,
        "action": "proceed-bounded" if allowed else "refuse",
    }


def measured_summary(raw: Dict[str, Any]) -> Dict[str, Any]:
    rows: List[Dict[str, Any]] = []
    for item in raw.get("rows") or []:
        rows.append(
            {
                "surface": item.get("surface"),
                "measured": bool(item.get("measured")),
                "reason": item.get("reason") or ("measured" if item.get("measured") else "not measured"),
                "provenance": item.get("provenance"),
            }
        )
    measured = [r for r in rows if r["measured"]]
    unmeasured = [r for r in rows if not r["measured"]]
    return {
        "schemaVersion": SCHEMA_VERSION,
        "kind": "measured-summary",
        "rows": rows,
        "measuredCount": len(measured),
        "unmeasuredCount": len(unmeasured),
        "statesMeasuredVersusUnmeasured": True,
    }


def main(argv: List[str]) -> int:
    p = argparse.ArgumentParser(prog="operational-evidence.py")
    sub = p.add_subparsers(dest="cmd", required=True)
    for name in (
        "perf-compare",
        "incident-actions",
        "runbook-verify",
        "observability-surface",
        "toil-assess",
        "capacity-guard",
        "measured-summary",
    ):
        sub.add_parser(name).add_argument("--input", required=True)
    args = p.parse_args(argv)

    with open(args.input, encoding="utf-8") as fh:
        data = json.load(fh)

    handlers = {
        "perf-compare": perf_compare,
        "incident-actions": incident_actions,
        "runbook-verify": runbook_verify,
        "observability-surface": observability_surface,
        "toil-assess": toil_assess,
        "capacity-guard": capacity_guard,
        "measured-summary": measured_summary,
    }
    doc = handlers[args.cmd](data)
    sys.stdout.write(json.dumps(doc, indent=2, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
