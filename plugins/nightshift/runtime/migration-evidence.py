#!/usr/bin/env python3
"""migration-evidence.py — guarded migration, config parity, and data safety evidence."""
from __future__ import annotations

import argparse
import json
import sys
from typing import Any, Dict, List, Optional, Tuple

SCHEMA_VERSION = 1

CHANGE_KINDS = frozenset({"additive", "breaking", "deprecated", "compatible"})
ENV_CLASSES = frozenset({"disposable", "staging", "production", "owner-approved", "local-dev"})


def _inventory_blockers(
    name: str,
    guidance: str,
    consumers: List[Any],
    persisted: List[Any],
    backfill: bool,
    overlap: Dict[str, Any],
) -> List[Dict[str, Any]]:
    blockers: List[Dict[str, Any]] = []
    if not name:
        blockers.append({"category": "anchor", "summary": "missing named migration", "action": "park"})
    if not guidance:
        blockers.append(
            {
                "category": "authority",
                "summary": "missing authoritative migration guidance",
                "action": "park",
            }
        )
    if not consumers:
        blockers.append({"category": "consumers", "summary": "no consumers inventoried", "action": "record"})
    if not persisted and backfill:
        blockers.append(
            {"category": "persisted-state", "summary": "backfill without persisted state map", "action": "park"}
        )
    if overlap.get("dualWrite") and not overlap.get("readFallback"):
        blockers.append(
            {
                "category": "overlap",
                "summary": "dual-write without read fallback",
                "action": "park",
            }
        )
    return blockers


def _inventory_action(complete: bool, blockers: List[Dict[str, Any]]) -> str:
    if complete and not blockers:
        return "proceed"
    if blockers:
        return "park"
    return "record"


def _compatibility_action(compatibility_maintained: bool, breaking: List[Any]) -> str:
    if compatibility_maintained:
        return "proceed"
    if breaking:
        return "park"
    return "repair"


def _data_safety_action(proceed: bool, refused: List[Any]) -> str:
    if proceed:
        return "proceed"
    if refused:
        return "refuse"
    return "park"


def migration_inventory(raw: Dict[str, Any]) -> Dict[str, Any]:
    name = (raw.get("migrationName") or "").strip()
    guidance = (raw.get("authoritativeGuidance") or "").strip()
    consumers = list(raw.get("consumers") or [])
    persisted = list(raw.get("persistedState") or [])
    ordering = list(raw.get("ordering") or [])
    defaults = list(raw.get("defaultsNullability") or [])
    backfill = bool(raw.get("backfillRequired"))
    locks = list(raw.get("locks") or [])
    overlap = raw.get("oldNewOverlap") or {}
    idempotent = bool(raw.get("idempotent"))
    rollback = list(raw.get("rollbackSteps") or [])
    staged = list(raw.get("stagedChanges") or [])
    representative = raw.get("representativeData") or {}

    blockers = _inventory_blockers(name, guidance, consumers, persisted, backfill, overlap)

    inventory = {
        "consumers": consumers,
        "persistedState": persisted,
        "ordering": ordering,
        "defaultsNullability": defaults,
        "backfillRequired": backfill,
        "locks": locks,
        "oldNewOverlap": overlap,
        "idempotent": idempotent,
        "rollbackSteps": rollback,
        "stagedChanges": staged,
        "representativeData": representative,
    }

    complete = bool(name and guidance and ordering and rollback)

    return {
        "schemaVersion": SCHEMA_VERSION,
        "kind": "migration-inventory",
        "migrationName": name or None,
        "authoritativeGuidance": guidance or None,
        "inventory": inventory,
        "inventoryComplete": complete and not any(b.get("action") == "park" for b in blockers),
        "blockers": blockers,
        "action": _inventory_action(complete, blockers),
        "legalAuthorityGuessed": False,
    }


def _classify_change(change: Dict[str, Any]) -> Tuple[str, Dict[str, Any]]:
    kind = (change.get("kind") or "additive").lower()
    entry = {
        "surface": change.get("surface") or "",
        "description": change.get("description") or "",
        "kind": kind,
        "consumersAffected": change.get("consumersAffected") or [],
    }
    if kind == "breaking":
        entry["action"] = "park-for-owner"
        entry["reviewFirstRequired"] = True
        return "breaking", entry
    if kind == "deprecated":
        entry["action"] = "document-and-stage"
        return "deprecated", entry
    entry["action"] = "proceed-with-tests"
    return "additive", entry


def _classify_changes(changes: List[Dict[str, Any]]) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]], List[Dict[str, Any]]]:
    additive: List[Dict[str, Any]] = []
    breaking: List[Dict[str, Any]] = []
    deprecated: List[Dict[str, Any]] = []
    for change in changes:
        bucket, entry = _classify_change(change)
        if bucket == "breaking":
            breaking.append(entry)
        elif bucket == "deprecated":
            deprecated.append(entry)
        else:
            additive.append(entry)
    return additive, breaking, deprecated


def _compatibility_routes(
    failed_tests: List[Dict[str, Any]],
    breaking: List[Dict[str, Any]],
    review_first: bool,
) -> List[Dict[str, Any]]:
    routes: List[Dict[str, Any]] = []
    for test in failed_tests:
        routes.append(
            {
                "route": "compatibility-test-failed",
                "name": test.get("name") or "",
                "action": "fix-or-rollback",
            }
        )
    if breaking and review_first:
        routes.append({"route": "review-first", "reason": "breaking-change-present"})
    return routes


def compatibility_assess(raw: Dict[str, Any]) -> Dict[str, Any]:
    changes = list(raw.get("changes") or [])
    consumers = list(raw.get("consumers") or [])
    tests = list(raw.get("compatibilityTests") or [])
    overlap = raw.get("oldNewOverlap") or {}
    review_first = bool(raw.get("reviewFirstDefault", True))

    additive, breaking, deprecated = _classify_changes(changes)

    failed_tests = [t for t in tests if (t.get("status") or "").lower() != "passed"]
    overlap_ok = True
    if overlap.get("dualWrite"):
        overlap_ok = bool(overlap.get("readFallback")) and bool(overlap.get("duration"))

    routes = _compatibility_routes(failed_tests, breaking, review_first)

    compatibility_maintained = not breaking and not failed_tests and overlap_ok

    return {
        "schemaVersion": SCHEMA_VERSION,
        "kind": "compatibility-assess",
        "additive": additive,
        "breaking": breaking,
        "deprecated": deprecated,
        "consumerCount": len(consumers),
        "compatibilityTests": tests,
        "failedCompatibilityTests": failed_tests,
        "oldNewOverlap": overlap,
        "overlapPlanValid": overlap_ok,
        "compatibilityMaintained": compatibility_maintained,
        "reviewFirstRequired": bool(breaking) and review_first,
        "routes": routes,
        "action": _compatibility_action(compatibility_maintained, breaking),
    }


def _compare_config_key(
    key: str,
    environments: List[Dict[str, Any]],
) -> Tuple[Dict[str, Any], List[Dict[str, Any]], List[Dict[str, Any]]]:
    gaps: List[Dict[str, Any]] = []
    hidden: List[Dict[str, Any]] = []
    shapes: Dict[str, Any] = {}
    present_in: List[str] = []

    for env in environments:
        name = env.get("name") or "unknown"
        var = (env.get("variables") or {}).get(key) or {}
        if var.get("secret"):
            hidden.append(
                {
                    "key": key,
                    "environment": name,
                    "present": bool(var.get("present")),
                    "shape": var.get("shape"),
                    "valuesCompared": False,
                }
            )
        if var.get("present"):
            present_in.append(name)
            shapes[name] = var.get("shape")
        else:
            gaps.append(
                {
                    "key": key,
                    "environment": name,
                    "kind": "missing",
                    "action": "document-or-align",
                }
            )

    unique_shapes = set(shapes.values())
    match = len(unique_shapes) <= 1 and len(present_in) == len(environments)
    compared = {
        "key": key,
        "presentIn": present_in,
        "shapeMatch": match,
        "shapes": shapes,
        "secret": any(
            ((env.get("variables") or {}).get(key) or {}).get("secret")
            for env in environments
        ),
    }
    if present_in and not match:
        gaps.append(
            {
                "key": key,
                "kind": "shape-mismatch",
                "shapes": shapes,
                "action": "align-shape-not-value",
            }
        )
    return compared, gaps, hidden


def config_parity(raw: Dict[str, Any]) -> Dict[str, Any]:
    environments = list(raw.get("environments") or [])
    compare_keys = list(raw.get("compareKeys") or [])
    secret_values_requested = bool(raw.get("retrieveSecretValues"))

    if secret_values_requested:
        return {
            "schemaVersion": SCHEMA_VERSION,
            "kind": "config-parity",
            "secretValuesRetrieved": False,
            "secretValueRetrievalRefused": True,
            "action": "refuse",
            "reason": "secret values must never be retrieved or copied",
            "legalAuthorityGuessed": False,
        }

    env_by_name = {e.get("name"): e for e in environments if e.get("name")}
    keys = compare_keys or sorted(
        {k for env in environments for k in (env.get("variables") or {}).keys()}
    )

    gaps: List[Dict[str, Any]] = []
    hidden: List[Dict[str, Any]] = []
    compared: List[Dict[str, Any]] = []

    for key in keys:
        key_compared, key_gaps, key_hidden = _compare_config_key(key, environments)
        compared.append(key_compared)
        gaps.extend(key_gaps)
        hidden.extend(key_hidden)

    parity_ok = not gaps

    return {
        "schemaVersion": SCHEMA_VERSION,
        "kind": "config-parity",
        "environmentsCompared": list(env_by_name.keys()),
        "compareKeys": keys,
        "compared": compared,
        "gaps": gaps,
        "mismatchCount": len(gaps),
        "hiddenSecrets": hidden,
        "secretValuesRetrieved": False,
        "neverRetrieveSecretValues": True,
        "parityMaintained": parity_ok,
        "action": "proceed" if parity_ok else "repair-or-park",
        "legalAuthorityGuessed": False,
    }


def _data_safety_refusals(
    environment: str,
    destructive: bool,
    owner_approved: bool,
) -> List[Dict[str, Any]]:
    refused: List[Dict[str, Any]] = []
    if environment == "production":
        if not owner_approved:
            refused.append(
                {
                    "category": "production",
                    "summary": "live production data work refused without owner approval",
                    "action": "refuse",
                }
            )
        elif destructive:
            refused.append(
                {
                    "category": "destructive-production",
                    "summary": "destructive production work remains outside direct-mode authority",
                    "action": "refuse",
                }
            )
    if destructive and environment not in ("disposable", "owner-approved"):
        refused.append(
            {
                "category": "destructive",
                "summary": "destructive data operations require disposable or owner-approved environment",
                "action": "refuse",
            }
        )
    return refused


def _data_safety_blockers(
    environment: str,
    legal_required: bool,
    legal_provided: str,
    unsupported: List[Any],
) -> List[Dict[str, Any]]:
    blockers: List[Dict[str, Any]] = []
    if environment not in ENV_CLASSES:
        blockers.append(
            {"category": "environment", "summary": "unknown environment class", "action": "park"}
        )
    if legal_required and not legal_provided:
        blockers.append(
            {
                "category": "legal-authority",
                "summary": "legal or data authority required but not supplied",
                "action": "park",
            }
        )
    for sem in unsupported:
        blockers.append(
            {
                "category": "unsupported-semantics",
                "summary": sem if isinstance(sem, str) else sem.get("summary") or "unsupported data semantics",
                "action": "park",
            }
        )
    return blockers


def _process_data_operations(
    operations: List[Any],
    environment: str,
    owner_approved: bool,
) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]]]:
    safe_ops: List[Dict[str, Any]] = []
    refused: List[Dict[str, Any]] = []
    for op in operations:
        entry = dict(op)
        if op.get("requiresProduction") and not owner_approved:
            entry["action"] = "refuse"
            refused.append(entry)
        else:
            entry["action"] = "proceed" if environment in ("disposable", "staging", "local-dev", "owner-approved") else "park"
            safe_ops.append(entry)
    return safe_ops, refused


def data_safety(raw: Dict[str, Any]) -> Dict[str, Any]:
    environment = (raw.get("environment") or "disposable").lower()
    destructive = bool(raw.get("destructive"))
    operations = list(raw.get("dataOperations") or [])
    owner_approved = bool(raw.get("ownerApprovedProduction"))
    legal_required = bool(raw.get("legalAuthorityRequired"))
    legal_provided = (raw.get("legalAuthority") or "").strip()
    unsupported = list(raw.get("unsupportedSemantics") or [])

    refused = _data_safety_refusals(environment, destructive, owner_approved)
    blockers = _data_safety_blockers(environment, legal_required, legal_provided, unsupported)
    safe_ops, op_refused = _process_data_operations(operations, environment, owner_approved)
    refused.extend(op_refused)

    proceed = not refused and not blockers

    return {
        "schemaVersion": SCHEMA_VERSION,
        "kind": "data-safety",
        "environment": environment,
        "destructive": destructive,
        "dataOperations": safe_ops,
        "mayExecuteDataOperations": proceed,
        "productionRefused": any(r.get("category") == "production" for r in refused),
        "destructiveRefused": any(r.get("category") == "destructive" for r in refused),
        "refused": refused,
        "blockers": blockers,
        "legalAuthorityGuessed": False,
        "legalAuthoritySupplied": bool(legal_provided),
        "action": _data_safety_action(proceed, refused),
    }


def production_refusal(raw: Dict[str, Any]) -> Dict[str, Any]:
    doc = data_safety(raw)
    doc["kind"] = "production-refusal"
    doc["directModeProductionAllowed"] = bool(raw.get("ownerApprovedProduction")) and not doc.get(
        "destructiveRefused"
    )
    return doc


def _failed_recovery_actions(
    failed_step: Any,
    rollback: List[Any],
    idempotent: bool,
) -> List[Dict[str, Any]]:
    actions: List[Dict[str, Any]] = [
        {
            "step": "halt-writes",
            "reason": f"failed at {failed_step}",
            "action": "execute-immediately",
        }
    ]
    if rollback:
        actions.append(
            {
                "step": "rollback",
                "steps": rollback,
                "action": "execute-in-order",
            }
        )
    if idempotent:
        actions.append(
            {
                "step": "idempotent-retry",
                "from": failed_step,
                "action": "retry-after-rollback",
            }
        )
    else:
        actions.append(
            {
                "step": "manual-intervention",
                "reason": "migration is not idempotent",
                "action": "park-for-owner",
            }
        )
    return actions


def _recovery_lock_warnings(locks: List[Dict[str, Any]], state: str) -> List[Dict[str, Any]]:
    warnings: List[Dict[str, Any]] = []
    if state != "failed":
        return warnings
    for lock in locks:
        if lock.get("active"):
            warnings.append(
                {
                    "lock": lock.get("name") or "unknown",
                    "action": "release-before-retry",
                }
            )
    return warnings


def recovery_plan(raw: Dict[str, Any]) -> Dict[str, Any]:
    state = (raw.get("migrationState") or "in-progress").lower()
    completed = list(raw.get("completedSteps") or [])
    failed_step = raw.get("failedStep")
    rollback = list(raw.get("rollbackSteps") or [])
    idempotent = bool(raw.get("idempotent"))
    locks = list(raw.get("locks") or [])
    staged = list(raw.get("stagedChanges") or [])

    actions: List[Dict[str, Any]] = []
    if state == "failed" and failed_step:
        actions = _failed_recovery_actions(failed_step, rollback, idempotent)
    elif state == "in-progress":
        actions.append(
            {
                "step": "checkpoint",
                "completed": completed,
                "action": "record-before-next-stage",
            }
        )

    lock_warnings = _recovery_lock_warnings(locks, state)

    recoverable = bool(rollback) or (idempotent and state == "failed")

    return {
        "schemaVersion": SCHEMA_VERSION,
        "kind": "recovery-plan",
        "migrationState": state,
        "completedSteps": completed,
        "failedStep": failed_step,
        "rollbackSteps": rollback,
        "stagedChanges": staged,
        "idempotent": idempotent,
        "recoveryActions": actions,
        "lockWarnings": lock_warnings,
        "midMigrationRecoveryAvailable": recoverable,
        "action": "proceed" if recoverable or state != "failed" else "park",
    }


def _migration_verdict_blockers(
    inventory: Dict[str, Any],
    compatibility: Dict[str, Any],
    config: Dict[str, Any],
    data: Dict[str, Any],
    recovery: Dict[str, Any],
    review_first: bool,
) -> List[str]:
    blockers: List[str] = []
    if inventory.get("action") == "park":
        blockers.append("incomplete-inventory")
    if compatibility.get("breaking"):
        blockers.append("breaking-change")
    if compatibility.get("reviewFirstRequired") and review_first:
        blockers.append("review-first-required")
    if config.get("parityMaintained") is False:
        blockers.append("config-parity-gap")
    if data.get("productionRefused"):
        blockers.append("production-refused")
    if data.get("action") == "refuse":
        blockers.append("data-safety-refused")
    if data.get("blockers"):
        blockers.append("unsupported-data-semantics")
    if recovery.get("migrationState") == "failed" and not recovery.get("midMigrationRecoveryAvailable"):
        blockers.append("no-recovery-path")
    return blockers


def _migration_verdict_status(blockers: List[str], run_direct: bool) -> str:
    if not blockers:
        return "ready-bounded" if run_direct else "ready-review-first"
    if any(b in blockers for b in ("production-refused", "data-safety-refused", "no-recovery-path")):
        return "refused"
    if "review-first-required" in blockers and run_direct:
        return "blocked"
    return "parked"


def verdict(raw: Dict[str, Any]) -> Dict[str, Any]:
    inventory = raw.get("inventory") or {}
    compatibility = raw.get("compatibility") or {}
    config = raw.get("configParity") or {}
    data = raw.get("dataSafety") or {}
    recovery = raw.get("recovery") or {}
    review_first = bool(raw.get("reviewFirstDefault", True))
    run_direct = bool(raw.get("runDirectBounded"))

    blockers = _migration_verdict_blockers(
        inventory, compatibility, config, data, recovery, review_first
    )
    status = _migration_verdict_status(blockers, run_direct)

    return {
        "schemaVersion": SCHEMA_VERSION,
        "kind": "verdict",
        "status": status,
        "blockers": blockers,
        "reviewFirstRequired": "review-first-required" in blockers,
        "runDirectAllowed": run_direct and not blockers,
        "rollbackDocumented": bool(inventory.get("inventory", {}).get("rollbackSteps") or recovery.get("rollbackSteps")),
        "productionAuthorityRefused": data.get("productionRefused", False),
        "legalAuthorityGuessed": False,
        "finiteEndingReached": status in ("ready-bounded", "ready-review-first", "refused", "parked"),
        "humanDecisionSurface": True,
    }


def main(argv: List[str]) -> int:
    p = argparse.ArgumentParser(prog="migration-evidence.py")
    sub = p.add_subparsers(dest="cmd", required=True)
    for name in (
        "migration-inventory",
        "compatibility-assess",
        "config-parity",
        "data-safety",
        "production-refusal",
        "recovery-plan",
        "verdict",
    ):
        sub.add_parser(name).add_argument("--input", required=True)
    args = p.parse_args(argv)

    with open(args.input, encoding="utf-8") as fh:
        data = json.load(fh)

    dispatch = {
        "migration-inventory": migration_inventory,
        "compatibility-assess": compatibility_assess,
        "config-parity": config_parity,
        "data-safety": data_safety,
        "production-refusal": production_refusal,
        "recovery-plan": recovery_plan,
        "verdict": verdict,
    }
    doc = dispatch[args.cmd](data)
    sys.stdout.write(json.dumps(doc, indent=2, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
