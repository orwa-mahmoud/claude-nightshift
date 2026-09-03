#!/usr/bin/env python3
"""pr-readiness-evidence.py — pull-request readiness evidence helpers."""
from __future__ import annotations

import argparse
import json
import re
import sys
from typing import Any, Dict, List, Optional, Tuple

SCHEMA_VERSION = 1

ISSUE_URL = re.compile(r"https://github\.com/(?P<owner>[^/]+)/(?P<repo>[^/]+)/issues/(?P<num>\d+)")

OWNER_ONLY_ACTIONS = frozenset(
    {"approve", "push", "merge", "close-issue", "submit-review", "open-pr"}
)

FINDING_DISPOSITIONS = frozenset({"fixed", "rejected", "parked", "unsupported", "out-of-scope"})


def _acceptance_anchor_blockers(
    branch: str,
    issue_url: str,
    work_mode: str,
    routes: List[Dict[str, Any]],
) -> List[Dict[str, Any]]:
    blockers: List[Dict[str, Any]] = []
    if work_mode != "repository":
        routes.append({"route": "artifact-review", "reason": "repository-mode-required"})
        blockers.append(
            {"category": "work-mode", "summary": "repository mode only", "action": "route-elsewhere"}
        )
    if not branch:
        blockers.append({"category": "anchor", "summary": "missing named branch", "action": "park"})
    if not issue_url:
        blockers.append({"category": "issue", "summary": "missing issue anchor", "action": "park"})
    elif not ISSUE_URL.match(issue_url):
        blockers.append({"category": "issue", "summary": "issue URL not parseable", "action": "park"})
    return blockers


def _map_acceptance_criterion(
    c: Dict[str, Any],
    routes: List[Dict[str, Any]],
    blockers: List[Dict[str, Any]],
) -> Dict[str, Any]:
    text = c.get("text") or ""
    status = (c.get("status") or "unmet").lower()
    evidence = c.get("evidence") or []
    entry: Dict[str, Any] = {
        "id": c.get("id"),
        "text": text,
        "status": status,
        "evidence": evidence,
        "met": status == "met",
    }
    if status == "ambiguous":
        entry["route"] = "park-with-default"
        routes.append(
            {"route": "ambiguous-criterion", "criterion": c.get("id"), "reason": text[:80]}
        )
    elif status in ("unmet", "partial"):
        blockers.append(
            {
                "category": "acceptance",
                "summary": text[:120],
                "action": "fix-or-park",
                "criterion": c.get("id"),
            }
        )
    return entry


def _acceptance_ci_blockers(ci_status: Dict[str, Any]) -> List[Dict[str, Any]]:
    blockers: List[Dict[str, Any]] = []
    ci_state = ci_status.get("state")
    if ci_state == "failure":
        blockers.append({"category": "ci", "summary": "containing checks failed", "action": "fix-or-park"})
    elif ci_state == "unknown":
        blockers.append(
            {"category": "ci", "summary": "CI state not measured", "action": "record-unavailable"}
        )
    return blockers


def _acceptance_verdict(blockers: List[Dict[str, Any]]) -> str:
    fixable = [b for b in blockers if b.get("action") in ("fix-or-park", "fix-or-disposition")]
    if not blockers:
        return "ready-for-human-review"
    if fixable:
        return "not-ready"
    return "blocked"


def acceptance_map(raw: Dict[str, Any]) -> Dict[str, Any]:
    branch = (raw.get("branch") or "").strip()
    base = (raw.get("baseBranch") or "main").strip()
    issue_url = (raw.get("issueUrl") or "").strip()
    work_mode = raw.get("workMode") or "repository"
    criteria = raw.get("acceptanceCriteria") or []
    rules = list(raw.get("repositoryRules") or [])
    comments = raw.get("reviewComments") or []
    ci_status = raw.get("ciStatus") or {}

    routes: List[Dict[str, Any]] = []
    blockers = _acceptance_anchor_blockers(branch, issue_url, work_mode, routes)

    mapped = [_map_acceptance_criterion(c, routes, blockers) for c in criteria]

    for comment in comments:
        if comment.get("unresolved"):
            blockers.append(
                {
                    "category": "review-comment",
                    "summary": comment.get("summary") or (comment.get("body") or "")[:120],
                    "action": "fix-or-disposition",
                    "author": comment.get("author"),
                }
            )

    blockers.extend(_acceptance_ci_blockers(ci_status))

    return {
        "schemaVersion": SCHEMA_VERSION,
        "kind": "acceptance-map",
        "branch": branch,
        "baseBranch": base,
        "issueUrl": issue_url or None,
        "workMode": work_mode,
        "repositoryRules": rules,
        "acceptanceCriteria": mapped,
        "reviewCommentCount": len(comments),
        "routes": routes,
        "blockers": blockers,
        "verdict": _acceptance_verdict(blockers),
        "agentApprovalAllowed": False,
        "humanDecisionSurface": True,
    }


def _path_in_scope(path: str, scope_paths: List[str]) -> bool:
    for prefix in scope_paths:
        p = prefix.rstrip("/")
        if path == p or path.startswith(p + "/"):
            return True
    return False


def _classify_changed_paths(
    changed: List[str],
    unrelated: List[str],
    effective_scope: List[str],
) -> Tuple[List[str], List[str]]:
    in_scope: List[str] = []
    out_of_scope: List[str] = []
    for path in changed:
        if path in unrelated:
            out_of_scope.append(path)
        elif effective_scope and not _path_in_scope(path, effective_scope):
            out_of_scope.append(path)
        else:
            in_scope.append(path)
    return in_scope, out_of_scope


def diff_scope(raw: Dict[str, Any]) -> Dict[str, Any]:
    branch = (raw.get("branch") or "").strip()
    base = (raw.get("baseBranch") or "main").strip()
    changed = list(raw.get("changedFiles") or [])
    unrelated = list(raw.get("unrelatedChanges") or [])
    scope_paths = list(raw.get("scopePaths") or [])
    issue_paths = list(raw.get("issueScopePaths") or [])
    dirty = bool(raw.get("dirtyWorktree"))

    effective_scope = scope_paths or issue_paths
    in_scope, out_of_scope = _classify_changed_paths(changed, unrelated, effective_scope)

    blockers: List[Dict[str, Any]] = []
    if dirty:
        blockers.append(
            {
                "category": "worktree",
                "summary": "dirty worktree outside scoped commits",
                "action": "isolate-or-park",
            }
        )
    if unrelated:
        blockers.append(
            {
                "category": "unrelated",
                "summary": "%d unrelated paths" % len(unrelated),
                "action": "exclude-or-park",
            }
        )
    if not branch:
        blockers.append({"category": "anchor", "summary": "missing branch anchor", "action": "park"})

    scoped_clean = len(out_of_scope) == 0 and not dirty and bool(branch)
    return {
        "schemaVersion": SCHEMA_VERSION,
        "kind": "diff-scope",
        "branch": branch,
        "baseBranch": base,
        "changedFileCount": len(changed),
        "inScope": in_scope,
        "outOfScope": out_of_scope,
        "unrelatedChanges": unrelated,
        "dirtyWorktree": dirty,
        "scopedClean": scoped_clean,
        "blockers": blockers,
        "routeGenericCodeReview": len(out_of_scope) > 0 and not effective_scope,
    }


def _collect_finding_dispositions(findings: List[Any]) -> Tuple[List[Dict[str, Any]], int]:
    dispositions: List[Dict[str, Any]] = []
    open_findings = 0
    for f in findings:
        disp = (f.get("disposition") or "open").lower()
        dispositions.append(
            {
                "id": f.get("id"),
                "summary": f.get("summary"),
                "disposition": disp,
                "reason": f.get("reason"),
            }
        )
        if disp == "open":
            open_findings += 1
    return dispositions, open_findings


def _checks_label(containing_green: Optional[bool]) -> str:
    if containing_green:
        return "green"
    if containing_green is False:
        return "failed"
    return "unknown"


def review_map(raw: Dict[str, Any]) -> Dict[str, Any]:
    changed_areas = list(raw.get("changedAreas") or [])
    acceptance_evidence = list(raw.get("acceptanceEvidence") or [])
    remaining_risks = list(raw.get("remainingRisks") or [])
    unsupported = list(raw.get("unsupportedSurfaces") or [])
    commits = list(raw.get("commits") or [])
    rollback = raw.get("rollback") or ""
    reviewer_decisions = list(raw.get("reviewerDecisions") or [])
    findings = raw.get("findings") or []
    containing_green = raw.get("containingChecksGreen")

    dispositions, open_findings = _collect_finding_dispositions(findings)

    if containing_green is False:
        open_findings += 1

    finite_end = open_findings == 0 and all(
        d.get("disposition") in FINDING_DISPOSITIONS for d in dispositions
    )

    checks_label = _checks_label(containing_green)
    shift_log_line = "branch %s · %d commits · %d areas · %d risks · checks %s" % (
        raw.get("branch") or "?",
        len(commits),
        len(changed_areas),
        len(remaining_risks),
        checks_label,
    )

    return {
        "schemaVersion": SCHEMA_VERSION,
        "kind": "review-map",
        "changedAreas": changed_areas,
        "acceptanceEvidence": acceptance_evidence,
        "remainingRisks": remaining_risks,
        "unsupportedSurfaces": unsupported,
        "commits": commits,
        "rollback": rollback,
        "reviewerDecisions": reviewer_decisions,
        "findings": dispositions,
        "openFindings": open_findings,
        "containingChecksGreen": containing_green,
        "finiteEndingReached": finite_end,
        "agentApprovalAllowed": False,
        "humanDecisionSurface": True,
        "shiftLogLine": shift_log_line,
    }


def owner_action_refusal(raw: Dict[str, Any]) -> Dict[str, Any]:
    action = (raw.get("requestedAction") or "").lower().strip()
    authorized = bool(raw.get("authorityGranted"))
    context = raw.get("context") or ""

    if action not in OWNER_ONLY_ACTIONS:
        return {
            "schemaVersion": SCHEMA_VERSION,
            "kind": "owner-action-refusal",
            "requestedAction": action,
            "refused": False,
            "reason": "unknown-action-not-owner-only",
            "authorityBoundary": "coding-work-only",
        }

    if authorized:
        return {
            "schemaVersion": SCHEMA_VERSION,
            "kind": "owner-action-refusal",
            "requestedAction": action,
            "refused": False,
            "reason": "explicit-owner-authority-granted",
            "authorityBoundary": "owner-authorized",
            "context": context,
        }

    reasons = {
        "approve": "Nightshift never approves pull requests — human reviewer required",
        "push": "push requires explicit owner authorization",
        "merge": "merge requires explicit owner authorization",
        "close-issue": "closing issues requires explicit owner authorization",
        "submit-review": "submitting a review requires explicit owner authorization",
        "open-pr": "opening a pull request requires explicit owner authorization",
    }

    return {
        "schemaVersion": SCHEMA_VERSION,
        "kind": "owner-action-refusal",
        "requestedAction": action,
        "refused": True,
        "reason": reasons.get(action, "owner-only action without authority"),
        "authorityBoundary": "coding-work-only",
        "context": context,
        "writeBackAllowed": False,
        "humanDecisionSurface": True,
    }


def main(argv: List[str]) -> int:
    p = argparse.ArgumentParser(prog="pr-readiness-evidence.py")
    sub = p.add_subparsers(dest="cmd", required=True)
    for name in ("acceptance-map", "review-map", "diff-scope", "owner-action-refusal"):
        sub.add_parser(name).add_argument("--input", required=True)
    args = p.parse_args(argv)

    with open(args.input, encoding="utf-8") as fh:
        data = json.load(fh)

    if args.cmd == "acceptance-map":
        doc = acceptance_map(data)
    elif args.cmd == "review-map":
        doc = review_map(data)
    elif args.cmd == "diff-scope":
        doc = diff_scope(data)
    elif args.cmd == "owner-action-refusal":
        doc = owner_action_refusal(data)
    else:
        return 1

    sys.stdout.write(json.dumps(doc, indent=2, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
