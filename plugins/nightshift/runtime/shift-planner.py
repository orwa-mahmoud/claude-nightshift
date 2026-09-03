#!/usr/bin/env python3
"""shift-planner.py — deterministic Automatic/Guided shift planner.

Read-only: prints canonical JSON plan on stdout. Launch mode never changes ordering.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import re
import sys
from copy import deepcopy
from datetime import datetime, timezone
from typing import Any, Dict, List, Optional, Set, Tuple


SCHEMA_VERSION = 1
OPEN_ENDED_MIN_MINUTES = 60
VERIFICATION_RESERVE_FLOOR = 30
VERIFICATION_RESERVE_RATIO = 0.10

REJECT_INAPPLICABLE = "inapplicable"
REJECT_OVERLAP = "overlap"
REJECT_TIME = "time-fit"
REJECT_CAPABILITY = "capability-unavailable"
REJECT_BUDGET = "resource-budget"
REJECT_BLOCKER = "blocker"
REJECT_LEARNING = "learning-suppressed"
REJECT_POLICY = "policy"
REJECT_DUPLICATE = "duplicate-finding"


def eprint(msg: str) -> None:
    print(msg, file=sys.stderr)


def usage() -> int:
    eprint(
        "usage: shift-planner.py --input PATH --hours H "
        "[--selection automatic|guided] [--launch review-first|run-direct] "
        "[--selection-ids ID,...]"
    )
    return 1


def verification_reserve_minutes(hours: float) -> int:
    return max(VERIFICATION_RESERVE_FLOOR, int(math.ceil(hours * 60 * VERIFICATION_RESERVE_RATIO)))


def time_fit_score(effort: int, remaining: int, ending: str) -> int:
    if ending == "open-ended":
        return 5 if remaining >= OPEN_ENDED_MIN_MINUTES else 0
    if effort <= 0:
        return 5
    if effort <= remaining:
        return 5
    if effort <= int(remaining * 1.15):
        return 2
    return 0


def scoring_tuple(
    c: Dict[str, Any], remaining: int
) -> Tuple[int, int, int, int, int, int, str]:
    tf = time_fit_score(int(c.get("effortMinutes", 0)), remaining, c["ending"])
    return (
        -int(c.get("impact", 0)),
        -int(c.get("evidenceStrength", 0)),
        -tf,
        -int(c.get("reversibility", 0)),
        -int(c.get("dependencyValue", 0)),
        int(c.get("effortMinutes", 0)),
        str(c["contractId"]),
    )


def visible_scoring(c: Dict[str, Any], remaining: int, learning_adjusted: bool) -> Dict[str, Any]:
    return {
        "impact": int(c.get("impact", 0)),
        "evidenceStrength": int(c.get("evidenceStrength", 0)),
        "confidence": int(c.get("confidence", 0)),
        "effortMinutes": int(c.get("effortMinutes", 0)),
        "timeFit": time_fit_score(int(c.get("effortMinutes", 0)), remaining, c["ending"]),
        "reversibility": int(c.get("reversibility", 0)),
        "dependencyValue": int(c.get("dependencyValue", 0)),
        "recurrence": int(c.get("recurrence", 0)),
        "priorResult": c.get("priorResult"),
        "learningAdjusted": learning_adjusted,
    }


def capability_allowed(c: Dict[str, Any], tooling: str) -> Tuple[bool, Optional[str]]:
    status = c.get("capabilityStatus", "available-and-verified")
    fallback = c.get("fallback")
    if status in ("available-and-verified", "available-but-failing"):
        return True, None
    if status == "provisionable":
        if tooling == "auto-add":
            return True, None
        if tooling == "review-missing":
            return True, "provisionable-under-review"
        return False, "provisionable-but-policy-existing-tools"
    if status == "fallback-only" and fallback:
        return True, fallback
    if status == "unavailable":
        if fallback:
            return True, fallback
        return False, "capability-unavailable"
    return True, None


def apply_learning(candidates: List[Dict[str, Any]], learning: Dict[str, Any]) -> bool:
    adjusted = False
    contracts = learning.get("contracts") or {}
    for c in candidates:
        entry = contracts.get(c["contractId"])
        if not entry:
            continue
        avg = entry.get("averageEffortMinutes")
        if isinstance(avg, int) and avg > 0:
            c["effortMinutes"] = avg
            adjusted = True
        elif entry.get("actualDurationMinutes"):
            vals = [int(x) for x in entry["actualDurationMinutes"] if isinstance(x, int)]
            if vals:
                c["effortMinutes"] = int(round(sum(vals) / len(vals)))
                adjusted = True
    return adjusted


def is_suppressed(c: Dict[str, Any], learning: Dict[str, Any]) -> bool:
    suppressed = set(learning.get("suppressedContracts") or [])
    return c["contractId"] in suppressed


def budget_exceeded(c: Dict[str, Any], budgets: Dict[str, int]) -> Optional[str]:
    needs = c.get("resourceNeeds") or {}
    for key, need in needs.items():
        if not isinstance(need, int):
            continue
        cap = budgets.get(key)
        if isinstance(cap, int) and need > cap:
            return key
    return None


def rejection_entry(
    c: Dict[str, Any], reason: str, detail: Optional[str], remaining: int, learning_adjusted: bool
) -> Dict[str, Any]:
    return {
        "contractId": c["contractId"],
        "title": c["title"],
        "reason": reason,
        "detail": detail,
        "scoring": visible_scoring(c, remaining, learning_adjusted),
    }


def reject_overlap(
    by_id: Dict[str, Dict[str, Any]],
    did: str,
    detail: str,
    removed_ids: Set[str],
    rejected: List[Dict[str, Any]],
) -> None:
    removed_ids.add(did)
    rejected.append(rejection_entry(by_id[did], REJECT_OVERLAP, detail, 10**9, False))


def record_overlap_resolution(
    overlap_records: List[Dict[str, Any]],
    group: str,
    finding: str,
    kept: str,
    removed: List[str],
) -> None:
    overlap_records.append(
        {
            "group": group,
            "finding": finding,
            "kept": kept,
            "removed": removed,
        }
    )


def resolve_overlap_ranking(
    ranked: List[Dict[str, Any]],
    by_id: Dict[str, Dict[str, Any]],
    removed_ids: Set[str],
    rejected: List[Dict[str, Any]],
    overlap_records: List[Dict[str, Any]],
    detail_fmt: str,
    detail_arg: str,
    group: str,
    finding: str,
) -> None:
    if not ranked:
        return
    kept = ranked[0]["contractId"]
    dropped = [x["contractId"] for x in ranked[1:]]
    detail = detail_fmt % (detail_arg, kept)
    for did in dropped:
        reject_overlap(by_id, did, detail, removed_ids, rejected)
    record_overlap_resolution(overlap_records, group, finding, kept, dropped)


def _resolve_static_overlap_groups(
    candidates: List[Dict[str, Any]],
    groups: Dict[str, List[str]],
    by_id: Dict[str, Dict[str, Any]],
    removed_ids: Set[str],
    rejected: List[Dict[str, Any]],
    overlap_records: List[Dict[str, Any]],
) -> None:
    for c in candidates:
        g = c.get("overlapGroup")
        if not g or c["contractId"] in removed_ids:
            continue
        peers = [i for i in groups.get(str(g), []) if i != c["contractId"] and i in by_id]
        if not peers:
            continue
        pool = [c] + [by_id[i] for i in peers if i not in removed_ids]
        if len(pool) < 2:
            continue
        ranked = sorted(pool, key=lambda x: scoring_tuple(x, 10**9))
        kept = ranked[0]["contractId"]
        for x in ranked[1:]:
            if x["contractId"] in removed_ids:
                continue
            reject_overlap(
                by_id,
                x["contractId"],
                "overlap group %s kept %s" % (g, kept),
                removed_ids,
                rejected,
            )
            record_overlap_resolution(
                overlap_records,
                str(g),
                str(g),
                kept,
                [x["contractId"]],
            )


def remove_overlaps(
    candidates: List[Dict[str, Any]], overlaps: List[Dict[str, Any]]
) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]], List[Dict[str, Any]]]:
    by_id = {c["contractId"]: c for c in candidates}
    removed_ids: Set[str] = set()
    overlap_records: List[Dict[str, Any]] = []
    rejected: List[Dict[str, Any]] = []

    groups: Dict[str, List[str]] = {}
    for c in candidates:
        g = c.get("overlapGroup")
        if g:
            groups.setdefault(str(g), []).append(c["contractId"])

    for ov in overlaps or []:
        group = ov.get("group")
        ids = [i for i in ov.get("candidates", []) if i in by_id]
        if group and group in groups:
            ids = groups[group]
        if len(ids) < 2:
            continue
        ranked = sorted(
            [by_id[i] for i in ids if i in by_id and i not in removed_ids],
            key=lambda x: scoring_tuple(x, 10**9),
        )
        resolve_overlap_ranking(
            ranked,
            by_id,
            removed_ids,
            rejected,
            overlap_records,
            "finding %s kept %s",
            ov.get("finding", group or ""),
            str(group or ov.get("finding", "")),
            str(ov.get("finding", group or "")),
        )

    _resolve_static_overlap_groups(
        candidates, groups, by_id, removed_ids, rejected, overlap_records
    )

    kept_candidates = [c for c in candidates if c["contractId"] not in removed_ids]
    return kept_candidates, overlap_records, rejected


def topo_sort(items: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    by_id = {c["contractId"]: c for c in items}
    ids = [c["contractId"] for c in items]
    order: List[str] = []
    seen: Set[str] = set()

    def visit(nid: str, stack: Set[str]) -> None:
        if nid in seen:
            return
        if nid in stack:
            return
        stack.add(nid)
        for pre in by_id.get(nid, {}).get("prerequisites") or []:
            if pre in by_id:
                visit(pre, stack)
        stack.remove(nid)
        seen.add(nid)
        order.append(nid)

    for nid in ids:
        visit(nid, set())
    return [by_id[i] for i in order if i in by_id]


def cluster_items(items: List[Dict[str, Any]]) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]]]:
    clusters: Dict[str, Dict[str, Any]] = {}
    out: List[Dict[str, Any]] = []
    for c in items:
        roots = tuple(sorted(set(c.get("sharedRoots") or [])))
        cid = c.get("clusterId")
        if not cid and roots:
            cid = "root:" + "|".join(roots)
        nc = deepcopy(c)
        if cid:
            nc["clusterId"] = cid
            entry = clusters.setdefault(
                cid, {"clusterId": cid, "contractIds": [], "sharedRoots": list(roots)}
            )
            entry["contractIds"].append(c["contractId"])
        out.append(nc)
    return out, list(clusters.values())


def pack_finite_candidate(
    c: Dict[str, Any],
    remaining: int,
    selected: List[Dict[str, Any]],
    rejected: List[Dict[str, Any]],
) -> Tuple[int, bool]:
    effort = int(c.get("effortMinutes", 0))
    tf = time_fit_score(effort, remaining, "finite")
    la = c.get("_learningAdjusted", False)
    if tf == 0 and effort > 0:
        rejected.append(
            rejection_entry(
                c,
                REJECT_TIME,
                "needs %d min, %d remain" % (effort, remaining),
                remaining,
                la,
            )
        )
        return remaining, False
    if effort > remaining and effort > 0:
        nc = deepcopy(c)
        nc["effortMinutes"] = remaining
        nc["_partial"] = True
        selected.append(nc)
        return 0, True
    selected.append(c)
    remaining -= max(effort, 0)
    return remaining, remaining <= 0


def pack_open_ended_remainder(
    open_ended: List[Dict[str, Any]],
    remaining: int,
    selected: List[Dict[str, Any]],
    rejected: List[Dict[str, Any]],
) -> None:
    if remaining < OPEN_ENDED_MIN_MINUTES or not open_ended:
        return
    ranked = sorted(open_ended, key=lambda x: scoring_tuple(x, remaining))
    selected.append(ranked[0])
    for x in ranked[1:]:
        rejected.append(
            rejection_entry(
                x,
                REJECT_TIME,
                "only one open-ended remainder allowed",
                remaining,
                x.get("_learningAdjusted", False),
            )
        )


def reject_unpacked_finite(
    finite: List[Dict[str, Any]],
    selected: List[Dict[str, Any]],
    rejected: List[Dict[str, Any]],
) -> None:
    selected_ids = {x["contractId"] for x in selected}
    rejected_ids = {x["contractId"] for x in rejected}
    for c in finite:
        if c["contractId"] in selected_ids or c["contractId"] in rejected_ids:
            continue
        rejected.append(
            rejection_entry(
                c,
                REJECT_TIME,
                "lower rank after time packing",
                0,
                c.get("_learningAdjusted", False),
            )
        )


def pack_time(
    finite: List[Dict[str, Any]], open_ended: List[Dict[str, Any]], budget: int
) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]], int]:
    selected: List[Dict[str, Any]] = []
    rejected: List[Dict[str, Any]] = []
    remaining = budget
    exhausted = False

    for c in finite:
        if exhausted:
            break
        remaining, exhausted = pack_finite_candidate(c, remaining, selected, rejected)

    pack_open_ended_remainder(open_ended, remaining, selected, rejected)
    reject_unpacked_finite(finite, selected, rejected)
    return selected, rejected, remaining


def candidate_rejection(
    c: Dict[str, Any],
    la: bool,
    selection: str,
    guided_ids: Optional[List[str]],
    work_mode: str,
    learning: Dict[str, Any],
    tooling: str,
    budgets: Dict[str, int],
) -> Optional[Dict[str, Any]]:
    if selection == "guided":
        if guided_ids is None or c["contractId"] not in guided_ids:
            return rejection_entry(
                c, REJECT_POLICY, "not selected in guided mode", 10**9, la
            )
    if not c.get("applicable", False):
        return rejection_entry(c, REJECT_INAPPLICABLE, None, 10**9, la)
    if c.get("repositoryOnly") and work_mode == "artifact":
        return rejection_entry(
            c, REJECT_INAPPLICABLE, "repository-only in artifact mode", 10**9, la
        )
    if c.get("artifactOnly") and work_mode == "repository":
        return rejection_entry(
            c, REJECT_INAPPLICABLE, "artifact-only in repository mode", 10**9, la
        )
    if is_suppressed(c, learning):
        return rejection_entry(
            c, REJECT_LEARNING, "suppressed by prior outcomes", 10**9, la
        )
    ok, cap_reason = capability_allowed(c, tooling)
    if not ok:
        return rejection_entry(c, REJECT_CAPABILITY, cap_reason, 10**9, la)
    over = budget_exceeded(c, budgets)
    if over:
        return rejection_entry(
            c, REJECT_BUDGET, "exceeds budget %s" % over, 10**9, la
        )
    return None


def build_ordered_items(
    packed: List[Dict[str, Any]], work_budget: int
) -> Tuple[List[Dict[str, Any]], int, List[str], List[str]]:
    ordered: List[Dict[str, Any]] = []
    estimate_total = 0
    all_risks: List[str] = []
    unsupported: List[str] = []

    for c in packed:
        rem = work_budget - estimate_total
        effort = int(c.get("effortMinutes", 0))
        if c["ending"] == "open-ended":
            effort = 0
        estimate_total += effort
        item = {
            "contractId": c["contractId"],
            "title": c["title"],
            "ending": c["ending"],
            "estimateMinutes": effort,
            "scoring": visible_scoring(c, rem, c.get("_learningAdjusted", False)),
            "evidence": list(c.get("evidence") or []),
            "prerequisites": list(c.get("prerequisites") or []),
            "sharedRoots": list(c.get("sharedRoots") or []),
            "clusterId": c.get("clusterId"),
            "capabilityStatus": c.get("capabilityStatus"),
            "fallback": c.get("fallback"),
            "resourceNeeds": dict(c.get("resourceNeeds") or {}),
            "risks": list(c.get("risks") or []),
        }
        ordered.append(item)
        all_risks.extend(item["risks"])
        unsupported.extend(c.get("unsupportedSurfaces") or [])

    return ordered, estimate_total, all_risks, unsupported


def plan_shift(
    discovery: Dict[str, Any],
    hours: float,
    selection: str,
    launch: str,
    guided_ids: Optional[List[str]] = None,
    learning: Optional[Dict[str, Any]] = None,
) -> Dict[str, Any]:
    learning = learning or {}
    tooling = discovery.get("toolingPolicy", "existing-tools")
    work_mode = discovery["workMode"]
    budgets = dict(discovery.get("resourceBudgets") or {})
    candidates = deepcopy(discovery.get("candidates") or [])
    learning_applied = apply_learning(candidates, learning)

    rejected: List[Dict[str, Any]] = []
    eligible: List[Dict[str, Any]] = []

    for c in candidates:
        la = learning_applied and bool((learning.get("contracts") or {}).get(c["contractId"]))
        c["_learningAdjusted"] = la
        rejection = candidate_rejection(
            c, la, selection, guided_ids, work_mode, learning, tooling, budgets
        )
        if rejection is not None:
            rejected.append(rejection)
            continue
        eligible.append(c)

    eligible, overlaps_removed, overlap_rejected = remove_overlaps(
        eligible, discovery.get("overlaps") or []
    )
    rejected.extend(overlap_rejected)

    reserve = verification_reserve_minutes(hours)
    work_budget = max(0, int(hours * 60) - reserve)

    finite = sorted(
        [c for c in eligible if c["ending"] == "finite"],
        key=lambda x: scoring_tuple(x, work_budget),
    )
    open_ended = sorted(
        [c for c in eligible if c["ending"] == "open-ended"],
        key=lambda x: scoring_tuple(x, work_budget),
    )

    if selection == "automatic":
        packed, time_rejected, _rem = pack_time(finite, open_ended, work_budget)
        rejected.extend(time_rejected)
    else:
        packed = topo_sort(finite + open_ended)

    packed = topo_sort(packed)
    packed, clusters = cluster_items(packed)

    ordered, estimate_total, all_risks, unsupported = build_ordered_items(packed, work_budget)

    stopping = (
        "finite entries complete in order; at most one open-ended remainder uses leftover time; "
        "stop at quitting time or convergence"
    )

    return {
        "schemaVersion": SCHEMA_VERSION,
        "selectionMode": selection,
        "launchMode": launch,
        "hours": hours,
        "deadlineEpoch": discovery.get("deadlineEpoch"),
        "workMode": work_mode,
        "workTarget": discovery["workTarget"],
        "branch": discovery.get("branch"),
        "workspace": discovery.get("workspace"),
        "authority": discovery.get("authority"),
        "shiftPolicy": discovery.get("shiftPolicy"),
        "resourceBudgets": budgets,
        "learningApplied": learning_applied,
        "verificationReserveMinutes": reserve,
        "workBudgetMinutes": work_budget,
        "estimateTotalMinutes": estimate_total,
        "stoppingRule": stopping,
        "orderedItems": ordered,
        "rejected": rejected,
        "overlapsRemoved": overlaps_removed,
        "clusters": clusters,
        "provisioningPlan": discovery.get("provisioningPlan"),
        "risks": sorted(set(all_risks)),
        "unsupportedSurfaces": sorted(set(unsupported)),
    }


def canonical_json(doc: Dict[str, Any]) -> str:
    return json.dumps(doc, indent=2, sort_keys=True, ensure_ascii=False) + "\n"


def main(argv: List[str]) -> int:
    p = argparse.ArgumentParser(add_help=False)
    p.add_argument("--input", required=True)
    p.add_argument("--hours", type=float, required=True)
    p.add_argument("--selection", default="automatic")
    p.add_argument("--launch", default="review-first")
    p.add_argument("--learning")
    p.add_argument("--selection-ids")
    args = p.parse_args(argv)

    if args.selection not in ("automatic", "guided"):
        eprint("shift-planner: --selection must be automatic or guided")
        return 1
    if args.launch not in ("review-first", "run-direct"):
        eprint("shift-planner: --launch must be review-first or run-direct")
        return 1
    if args.hours <= 0:
        eprint("shift-planner: --hours must be positive")
        return 1

    try:
        with open(args.input, encoding="utf-8") as fh:
            discovery = json.load(fh)
    except (OSError, json.JSONDecodeError) as exc:
        eprint("shift-planner: cannot read input: %s" % exc)
        return 1

    learning: Dict[str, Any] = {}
    if args.learning:
        try:
            with open(args.learning, encoding="utf-8") as fh:
                learning = json.load(fh)
        except (OSError, json.JSONDecodeError):
            learning = {}

    guided_ids = None
    if args.selection_ids:
        guided_ids = [x.strip() for x in args.selection_ids.split(",") if x.strip()]

    plan = plan_shift(
        discovery,
        args.hours,
        args.selection,
        args.launch,
        guided_ids=guided_ids,
        learning=learning,
    )
    sys.stdout.write(canonical_json(plan))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
