#!/usr/bin/env python3
"""shift-preview.py — render an explainable Review-first preview from a shift plan."""
from __future__ import annotations

import argparse
import json
import sys
from typing import Any, Dict, List

NONE_LINE = "_none_\n"


def line(title: str, body: str) -> str:
    return "## %s\n\n%s\n" % (title, body)


def bullet(items: List[str]) -> str:
    if not items:
        return NONE_LINE
    return "\n".join("- %s" % x for x in items) + "\n"


def render_intro(plan: Dict[str, Any]) -> str:
    return (
        "# Shift preview (read-only simulation)\n\n"
        "This preview writes nothing and starts no clock. "
        "Launch mode `%s` does not change the ordered plan.\n"
        % plan.get("launchMode", "")
    )


def render_context(plan: Dict[str, Any]) -> str:
    ctx = [
        "workspace: `%s`" % (plan.get("workspace") or plan.get("workTarget") or "?"),
        "work target: `%s`" % plan.get("workTarget", "?"),
        "branch: `%s`" % (plan.get("branch") or "current"),
        "work mode: `%s`" % plan.get("workMode", "?"),
        "selection: `%s`" % plan.get("selectionMode", "?"),
        "launch: `%s`" % plan.get("launchMode", "?"),
        "hours: `%s`" % plan.get("hours", "?"),
        "authority: `%s`" % (plan.get("authority") or "owner-approved"),
    ]
    return line("Resolved context", bullet(ctx))


def _policy_dict_lines(policy: Dict[str, Any], plan: Dict[str, Any]) -> List[str]:
    pol_lines = []
    for key in ("verificationLevel", "toolingPolicy", "completionMode", "deadlineEpoch"):
        if key in policy:
            pol_lines.append("%s: `%s`" % (key, policy[key]))
    for a in policy.get("allowances") or []:
        if isinstance(a, dict):
            pol_lines.append(
                "allowance: `%s` scope `%s` provenance `%s`"
                % (a.get("category"), a.get("scope"), a.get("provenance"))
            )
    budgets = policy.get("budgets") or plan.get("resourceBudgets") or {}
    if budgets:
        pol_lines.append("resource budgets: `%s`" % json.dumps(budgets, sort_keys=True))
    return pol_lines


def render_policy(plan: Dict[str, Any]) -> str:
    policy = plan.get("shiftPolicy")
    if isinstance(policy, dict):
        return line("Shift policy", bullet(_policy_dict_lines(policy, plan)))
    if plan.get("resourceBudgets"):
        return line(
            "Resource budgets",
            bullet(
                [
                    "%s=%s" % (k, v)
                    for k, v in sorted(plan["resourceBudgets"].items())
                ]
            ),
        )
    return ""


def render_ordered_items(ordered: List[Dict[str, Any]]) -> str:
    item_lines: List[str] = []
    for i, it in enumerate(ordered, 1):
        sc = it.get("scoring") or {}
        item_lines.append(
            "%d. **%s** (`%s`, %s, ~%s min)\n"
            "   - evidence: %s\n"
            "   - scoring: impact=%s evidence=%s confidence=%s effort=%s timeFit=%s reversibility=%s"
            % (
                i,
                it.get("title", it.get("contractId")),
                it.get("contractId"),
                it.get("ending"),
                it.get("estimateMinutes"),
                "; ".join(it.get("evidence") or []) or "—",
                sc.get("impact"),
                sc.get("evidenceStrength"),
                sc.get("confidence"),
                sc.get("effortMinutes"),
                sc.get("timeFit"),
                sc.get("reversibility"),
            )
        )
        if it.get("prerequisites"):
            item_lines.append("   - prerequisites: `%s`" % ", ".join(it["prerequisites"]))
        if it.get("sharedRoots"):
            item_lines.append("   - shared roots: `%s`" % ", ".join(it["sharedRoots"]))
        if it.get("clusterId"):
            item_lines.append("   - cluster: `%s`" % it["clusterId"])
        if it.get("fallback"):
            item_lines.append("   - fallback: %s" % it["fallback"])
    return line("Proposed ordered items", "\n".join(item_lines) if item_lines else NONE_LINE)


def render_clusters(clusters: List[Dict[str, Any]]) -> str:
    if not clusters:
        return ""
    cl: List[str] = []
    for c in clusters:
        cl.append(
            "`%s`: contracts %s roots %s"
            % (
                c.get("clusterId"),
                ", ".join(c.get("contractIds") or []),
                ", ".join(c.get("sharedRoots") or []),
            )
        )
    return line("Independent clusters", bullet(cl))


def render_rejected(rejected: List[Dict[str, Any]]) -> str:
    rej_lines: List[str] = []
    for r in rejected:
        sc = r.get("scoring") or {}
        rej_lines.append(
            "- `%s` — **%s**: %s (impact=%s evidence=%s timeFit=%s)"
            % (
                r.get("contractId"),
                r.get("reason"),
                r.get("detail") or r.get("title"),
                sc.get("impact"),
                sc.get("evidenceStrength"),
                sc.get("timeFit"),
            )
        )
    return line("Rejected alternatives", "\n".join(rej_lines) if rej_lines else NONE_LINE)


def render_overlaps(overlaps: List[Dict[str, Any]]) -> str:
    if not overlaps:
        return ""
    ov: List[str] = []
    for o in overlaps:
        ov.append(
            "group `%s` finding `%s`: kept `%s`, removed %s"
            % (
                o.get("group"),
                o.get("finding"),
                o.get("kept"),
                ", ".join(o.get("removed") or []),
            )
        )
    return line("Overlaps removed", bullet(ov))


def render_timing(plan: Dict[str, Any]) -> str:
    timing = [
        "verification reserve: %s min" % plan.get("verificationReserveMinutes"),
        "work budget: %s min" % plan.get("workBudgetMinutes"),
        "estimated finite work: %s min" % plan.get("estimateTotalMinutes"),
        "stopping rule: %s" % plan.get("stoppingRule"),
    ]
    if plan.get("learningApplied"):
        timing.append("learning: applied from project-local receipts")
    return line("Time fit", bullet(timing))


def render_optional_sections(plan: Dict[str, Any]) -> List[str]:
    parts: List[str] = []
    risks = plan.get("risks") or []
    if risks:
        parts.append(line("Risks", bullet(risks)))

    unsupported = plan.get("unsupportedSurfaces") or []
    if unsupported:
        parts.append(line("Unsupported or unmeasured surfaces", bullet(unsupported)))

    prov = plan.get("provisioningPlan")
    if isinstance(prov, dict):
        parts.append(
            line("Provisioning plan", "```json\n%s\n```" % json.dumps(prov, indent=2, sort_keys=True))
        )
    return parts


def render(plan: Dict[str, Any]) -> str:
    parts: List[str] = [
        render_intro(plan),
        render_context(plan),
        render_policy(plan),
        render_ordered_items(plan.get("orderedItems") or []),
        render_clusters(plan.get("clusters") or []),
        render_rejected(plan.get("rejected") or []),
        render_overlaps(plan.get("overlapsRemoved") or []),
        render_timing(plan),
    ]
    parts.extend(render_optional_sections(plan))
    parts.append(
        "\n---\nAccept, edit, or discard this preview. "
        "Review-first writes nothing until approval.\n"
    )
    return "\n".join(parts)


def main(argv: List[str]) -> int:
    p = argparse.ArgumentParser(add_help=False)
    p.add_argument("--input")
    args = p.parse_args(argv)

    try:
        if args.input:
            with open(args.input, encoding="utf-8") as fh:
                plan = json.load(fh)
        else:
            plan = json.load(sys.stdin)
    except (OSError, json.JSONDecodeError) as exc:
        print("shift-preview: cannot read plan: %s" % exc, file=sys.stderr)
        return 1

    sys.stdout.write(render(plan))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
