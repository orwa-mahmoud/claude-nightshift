#!/usr/bin/env python3
"""owner-work-evidence.py — evidence helpers for owner-defined work shifts."""
from __future__ import annotations

import argparse
import json
import math
import re
import sys
from typing import Any, Dict, List, Optional, Set, Tuple

SCHEMA_VERSION = 1
OPEN_ENDED_MIN_MINUTES = 60
VERIFICATION_RESERVE_RATIO = 0.10
VERIFICATION_RESERVE_FLOOR = 30

ISSUE_URL = re.compile(r"https://github\.com/(?P<owner>[^/]+)/(?P<repo>[^/]+)/issues/(?P<num>\d+)")


def verification_reserve_minutes(hours: float) -> int:
    return max(VERIFICATION_RESERVE_FLOOR, int(math.ceil(hours * 60 * VERIFICATION_RESERVE_RATIO)))


def time_fit_score(effort: int, remaining: int) -> int:
    if effort <= 0:
        return 5
    if effort <= remaining:
        return 5
    if effort <= int(remaining * 1.15):
        return 2
    return 0


def issue_repo(source_url: str) -> Optional[str]:
    m = ISSUE_URL.match(source_url or "")
    if not m:
        return None
    return "%s/%s" % (m.group("owner"), m.group("repo"))


def normalize_title(title: str) -> str:
    return re.sub(r"\s+", " ", (title or "").strip().lower())


def topo_sort_issues(items: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    by_url = {i["sourceUrl"]: i for i in items if i.get("sourceUrl")}
    order: List[str] = []
    seen: Set[str] = set()

    def visit(url: str, stack: Set[str]) -> None:
        if url in seen or url not in by_url:
            return
        if url in stack:
            return
        stack.add(url)
        for dep in by_url[url].get("dependencies") or []:
            visit(dep, stack)
        stack.remove(url)
        seen.add(url)
        order.append(url)

    for url in by_url:
        visit(url, set())
    return [by_url[u] for u in order if u in by_url]


def issue_graph(manifest: Dict[str, Any]) -> Dict[str, Any]:
    authorized = manifest.get("authorizedRepo")
    hours = float(manifest.get("hours") or 0)
    work_budget = 0
    if hours > 0:
        work_budget = max(0, int(hours * 60) - verification_reserve_minutes(hours))

    eligible: List[Dict[str, Any]] = []
    rejected: List[Dict[str, Any]] = []
    conflicts: List[Dict[str, Any]] = []
    titles_seen: Dict[str, str] = {}

    for raw in manifest.get("issues") or []:
        url = raw.get("sourceUrl") or ""
        repo = raw.get("repo") or issue_repo(url)
        flags = list(raw.get("flags") or [])
        entry = {
            "sourceUrl": url,
            "number": raw.get("number"),
            "title": raw.get("title"),
            "repo": repo,
            "effortMinutes": int(raw.get("effortMinutes") or 0),
            "sharedRoots": list(raw.get("sharedRoots") or []),
            "dependencies": list(raw.get("dependencies") or []),
            "flags": flags,
        }
        if authorized and repo and repo != authorized:
            rejected.append({**entry, "reason": "repo-mismatch", "detail": "outside authorized repo"})
            continue
        if flags:
            rejected.append({**entry, "reason": "flagged", "detail": ",".join(flags)})
            continue
        dup_of = raw.get("duplicateOf")
        norm = normalize_title(raw.get("title") or "")
        if dup_of:
            conflicts.append(
                {"kind": "duplicate", "kept": dup_of, "removed": url, "reason": "explicit duplicateOf"}
            )
            rejected.append({**entry, "reason": "duplicate", "detail": "duplicate of %s" % dup_of})
            continue
        if norm and norm in titles_seen:
            kept = titles_seen[norm]
            conflicts.append(
                {"kind": "duplicate", "kept": kept, "removed": url, "reason": "same normalized title"}
            )
            rejected.append({**entry, "reason": "duplicate", "detail": "same title as %s" % kept})
            continue
        if norm:
            titles_seen[norm] = url
        eligible.append(entry)

    ordered = topo_sort_issues(eligible)
    groups: Dict[str, Dict[str, Any]] = {}
    for issue in ordered:
        roots = tuple(sorted(set(issue.get("sharedRoots") or [])))
        gid = "root:" + "|".join(roots) if roots else "ungrouped"
        grp = groups.setdefault(
            gid,
            {"groupId": gid, "sharedRoots": list(roots), "issues": [], "effortMinutes": 0},
        )
        grp["issues"].append(issue["sourceUrl"])
        grp["effortMinutes"] += issue.get("effortMinutes") or 0

    selected: List[str] = []
    time_rejected: List[Dict[str, Any]] = []
    remaining = work_budget
    if work_budget > 0:
        for issue in ordered:
            effort = int(issue.get("effortMinutes") or 0)
            tf = time_fit_score(effort, remaining)
            if tf == 0 and effort > 0:
                time_rejected.append(
                    {
                        **issue,
                        "reason": "time-fit",
                        "detail": "needs %d min, %d remain" % (effort, remaining),
                    }
                )
                continue
            selected.append(issue["sourceUrl"])
            remaining -= max(effort, 0)
            if remaining <= 0:
                break
        for issue in ordered:
            if issue["sourceUrl"] not in selected and issue["sourceUrl"] not in {
                x["sourceUrl"] for x in time_rejected
            }:
                time_rejected.append(
                    {**issue, "reason": "time-fit", "detail": "lower rank after time packing"}
                )
        rejected.extend(time_rejected)

    repo_fit = [
        {
            "sourceUrl": i["sourceUrl"],
            "authorizedRepo": authorized,
            "repo": i.get("repo"),
            "fits": not authorized or i.get("repo") == authorized,
        }
        for i in eligible
    ]

    return {
        "schemaVersion": SCHEMA_VERSION,
        "kind": "issue-graph",
        "authorizedRepo": authorized,
        "workBudgetMinutes": work_budget if hours > 0 else None,
        "orderedIssues": [i["sourceUrl"] for i in ordered],
        "orderedGroups": list(groups.values()),
        "selectedIssues": selected if work_budget > 0 else [i["sourceUrl"] for i in ordered],
        "conflicts": conflicts,
        "repoFit": repo_fit,
        "rejected": rejected,
        "importedOnly": True,
        "writeBackAllowed": False,
    }


def walkthrough_plan(brief: Dict[str, Any]) -> Dict[str, Any]:
    objective = (brief.get("objective") or "").strip()
    hours = float(brief.get("hours") or 0)
    evidence = list(brief.get("evidence") or [])
    underspecified = list(brief.get("underspecified") or [])
    work_budget = 0
    if hours > 0:
        work_budget = max(0, int(hours * 60) - verification_reserve_minutes(hours))

    acceptance = brief.get("acceptanceCriteria") or [
        "Objective remains verbatim: %s" % objective,
        "Item gate green at every commit or artifact receipt",
        "Delivered scope verifiable from work-target tests and tooling",
    ]
    dependencies = list(brief.get("dependencies") or [])
    if evidence and not dependencies:
        dependencies = ["Inspect work-target evidence: %s" % ", ".join(evidence[:3])]

    checkpoints = [
        {"phase": "plan", "action": "Record acceptance, non-goals, and time-fit plan before cutting"},
        {"phase": "implement", "action": "Complete one coherent unit end-to-end"},
        {"phase": "verify", "action": "Run item gate and refresh continuation record"},
    ]
    non_goals = list(brief.get("nonGoals") or [])
    if not non_goals:
        non_goals = [
            "Push, merge, deploy, publish, or mutate external services without explicit owner authorization",
            "Replace the owner objective with an easier adjacent goal",
            "Begin a unit that cannot be left reviewable within remaining time",
        ]

    unit_effort = max(30, work_budget // 3) if work_budget else 45
    units = brief.get("units") or [
        {"title": "First coherent unit", "effortMinutes": unit_effort},
        {"title": "Verification and continuation refresh", "effortMinutes": min(30, unit_effort)},
    ]
    selected_units: List[Dict[str, Any]] = []
    remaining = work_budget or sum(int(u.get("effortMinutes") or 0) for u in units)
    for unit in units:
        effort = int(unit.get("effortMinutes") or 0)
        tf = time_fit_score(effort, remaining) if work_budget else 5
        if tf == 0 and effort > 0:
            continue
        selected_units.append({**unit, "timeFit": tf})
        remaining -= max(effort, 0)

    defaults = []
    for topic in underspecified:
        defaults.append(
            {
                "topic": topic,
                "default": brief.get("defaults", {}).get(topic, "reversible conservative default"),
                "recorded": True,
                "authorityBoundary": "coding-work only",
            }
        )

    return {
        "schemaVersion": SCHEMA_VERSION,
        "kind": "walkthrough-plan",
        "objective": objective,
        "acceptanceCriteria": acceptance,
        "dependencies": dependencies,
        "checkpoints": checkpoints,
        "evidence": evidence,
        "nonGoals": non_goals,
        "workBudgetMinutes": work_budget if hours > 0 else None,
        "timeFitPlan": {"units": selected_units, "remainingMinutes": max(0, remaining)},
        "reversibleDefaults": defaults,
        "planBeforeCutting": True,
    }


def evolution_hypothesis(raw: Dict[str, Any]) -> Dict[str, Any]:
    prior = raw.get("priorReceipts") or []
    avoid = [
        {
            "area": p.get("area"),
            "reason": p.get("reason") or p.get("outcome"),
            "source": "prior-receipt",
        }
        for p in prior
        if p.get("outcome") in ("rejected", "disproved", "parked") or p.get("reason")
    ]
    rejected_alts = []
    for alt in raw.get("alternatives") or []:
        if alt.get("rejectedReason"):
            rejected_alts.append(
                {
                    "name": alt.get("name"),
                    "rejectedReason": alt.get("rejectedReason"),
                }
            )

    hypothesis = {
        "user": raw.get("user"),
        "problem": raw.get("problem"),
        "evidence": list(raw.get("evidence") or []),
        "expectedOutcome": raw.get("expectedOutcome"),
        "reversibility": raw.get("reversibility"),
        "measurement": raw.get("measurement"),
        "rejectionReason": raw.get("rejectionReason"),
    }
    slice_minutes = int(raw.get("sliceMinutes") or 60)
    return {
        "schemaVersion": SCHEMA_VERSION,
        "kind": "evolution-hypothesis",
        "hypothesis": hypothesis,
        "validatedSlice": {
            "maxMinutes": slice_minutes,
            "goal": "smallest end-to-end slice that can confirm or reject the hypothesis",
            "rollbackBoundary": raw.get("rollbackBoundary") or "feature-flag or isolated branch",
        },
        "rejectedAlternatives": rejected_alts,
        "avoidAreas": avoid,
        "preferSmallValidatedSlices": True,
    }


def receipt_link(raw: Dict[str, Any]) -> Dict[str, Any]:
    url = raw.get("sourceUrl") or ""
    commit = raw.get("commit") or raw.get("receiptId") or ""
    verification = raw.get("verification") or ""
    scope = raw.get("scope") or ""
    divergence = raw.get("divergence")
    m = ISSUE_URL.match(url)
    issue_ref = "#%s" % m.group("num") if m else url
    line = "issue %s · commit %s · scope: %s · verify: %s" % (issue_ref, commit, scope, verification)
    if divergence:
        line += " · divergence: %s" % divergence
    return {
        "schemaVersion": SCHEMA_VERSION,
        "kind": "receipt-link",
        "sourceUrl": url,
        "commit": commit,
        "verification": verification,
        "scope": scope,
        "divergence": divergence,
        "shiftLogLine": line,
        "traceability": {
            "issue": url,
            "commit": commit,
            "closesHint": "Closes %s" % issue_ref if m else None,
            "mergeReviewFields": ["sourceUrl", "commit", "verification", "scope"],
        },
        "writeBackAllowed": False,
    }


def main(argv: List[str]) -> int:
    p = argparse.ArgumentParser(prog="owner-work-evidence.py")
    sub = p.add_subparsers(dest="cmd", required=True)
    for name in ("issue-graph", "walkthrough-plan", "evolution-hypothesis", "receipt-link"):
        sub.add_parser(name).add_argument("--input", required=True)
    args = p.parse_args(argv)

    with open(args.input, encoding="utf-8") as fh:
        data = json.load(fh)

    if args.cmd == "issue-graph":
        doc = issue_graph(data)
    elif args.cmd == "walkthrough-plan":
        doc = walkthrough_plan(data)
    elif args.cmd == "evolution-hypothesis":
        doc = evolution_hypothesis(data)
    elif args.cmd == "receipt-link":
        doc = receipt_link(data)
    else:
        return 1

    sys.stdout.write(json.dumps(doc, indent=2, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
