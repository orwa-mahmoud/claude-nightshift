#!/usr/bin/env python3
"""build-onboarding-evidence.py — build reproducibility and developer onboarding evidence."""
from __future__ import annotations

import argparse
import json
import sys
from typing import Any, Dict, List, Optional, Set, Tuple


def _artifact_key(path: str) -> str:
    return path.replace("\\", "/")


def _append_run_artifact(
    art: Dict[str, Any],
    run: Dict[str, Any],
    package_contents: Set[str],
    artifacts: List[Dict[str, Any]],
    hidden: List[Dict[str, Any]],
    owner_only: List[Dict[str, Any]],
    digest_by_path: Dict[str, List[Tuple[str, str]]],
) -> None:
    path = _artifact_key(art.get("path") or "")
    digest = art.get("digest") or ""
    det = bool(art.get("determinismExpected", True))
    generated = bool(art.get("generated"))
    if generated:
        det = False
    run_id = run.get("runId") or "run"
    cache_state = run.get("cacheState") or "unknown"
    env = run.get("environment") or {}
    entry = {
        "path": path,
        "digest": digest,
        "runId": run_id,
        "cacheState": cache_state,
        "determinismExpected": det,
        "generated": generated,
        "includedInPackage": path in package_contents if package_contents else art.get("includedInPackage"),
        "environment": env,
    }
    artifacts.append(entry)
    digest_by_path.setdefault(path, []).append((run_id, digest))
    for assumption in art.get("hiddenAssumptions") or []:
        hidden.append(
            {
                "path": path,
                "kind": assumption.get("kind") or "environment",
                "detail": assumption.get("detail") or "",
                "action": assumption.get("action") or "record",
            }
        )
    if art.get("ownerOnlyInstall"):
        owner_only.append(
            {
                "path": path,
                "reason": art.get("ownerOnlyReason") or "install-decision",
                "action": "refuse",
            }
        )


def _collect_run_artifacts(
    run: Dict[str, Any],
    package_contents: Set[str],
) -> Tuple[List[Dict[str, Any]], Dict[str, List[Tuple[str, str]]], List[Dict[str, Any]], List[Dict[str, Any]]]:
    artifacts: List[Dict[str, Any]] = []
    hidden: List[Dict[str, Any]] = []
    owner_only: List[Dict[str, Any]] = []
    digest_by_path: Dict[str, List[Tuple[str, str]]] = {}

    for art in run.get("artifacts") or []:
        _append_run_artifact(
            art, run, package_contents, artifacts, hidden, owner_only, digest_by_path
        )

    return artifacts, digest_by_path, hidden, owner_only


def _compare_digest_paths(
    digest_by_path: Dict[str, List[Tuple[str, str]]],
    artifacts: List[Dict[str, Any]],
) -> Tuple[List[Dict[str, Any]], List[Dict[str, Any]], str]:
    comparisons: List[Dict[str, Any]] = []
    hidden: List[Dict[str, Any]] = []
    verdict = "reproducible"

    for path, pairs in digest_by_path.items():
        if len(pairs) < 2:
            continue
        first = pairs[0][1]
        same = all(d == first for _, d in pairs)
        det_expected = any(a["path"] == path and a["determinismExpected"] for a in artifacts)
        if not det_expected:
            comparisons.append(
                {
                    "path": path,
                    "determinismExpected": False,
                    "match": same,
                    "action": "skip-compare",
                }
            )
            continue
        comparisons.append(
            {
                "path": path,
                "determinismExpected": True,
                "match": same,
                "runs": [r for r, _ in pairs],
                "action": "repair" if not same else "pass",
            }
        )
        if not same:
            cache_states = {a["cacheState"] for a in artifacts if a["path"] == path}
            if len(cache_states) > 1:
                verdict = "cache-dependent"
                hidden.append(
                    {
                        "path": path,
                        "kind": "cache",
                        "detail": "digest changed across cache states",
                        "action": "document-or-isolate",
                    }
                )
            else:
                verdict = "non-deterministic"

    return comparisons, hidden, verdict


def repro_compare(raw: Dict[str, Any]) -> Dict[str, Any]:
    declared = list(raw.get("declaredPaths") or [])
    runs = raw.get("runs") or []
    package_contents = {_artifact_key(p) for p in (raw.get("packageContents") or [])}
    impose_stack = list(raw.get("imposeStack") or [])

    artifacts: List[Dict[str, Any]] = []
    all_hidden: List[Dict[str, Any]] = []
    owner_only: List[Dict[str, Any]] = []
    digest_by_path: Dict[str, List[Tuple[str, str]]] = {}

    for run in runs:
        run_artifacts, run_digests, run_hidden, run_owner = _collect_run_artifacts(run, package_contents)
        artifacts.extend(run_artifacts)
        all_hidden.extend(run_hidden)
        owner_only.extend(run_owner)
        for path, pairs in run_digests.items():
            digest_by_path.setdefault(path, []).extend(pairs)

    comparisons, compare_hidden, verdict = _compare_digest_paths(digest_by_path, artifacts)
    all_hidden.extend(compare_hidden)

    missing_from_package = sorted(
        {
            a["path"]
            for a in artifacts
            if package_contents and a.get("includedInPackage") is False and not a.get("generated")
        }
    )
    if missing_from_package and verdict == "reproducible":
        verdict = "package-gap"

    if raw.get("unsupportedPlatform"):
        verdict = "blocked"
    if owner_only:
        verdict = "owner-only" if verdict == "reproducible" else verdict

    return {
        "schemaVersion": 1,
        "kind": "repro-compare",
        "declaredPaths": declared,
        "artifacts": artifacts,
        "comparisons": comparisons,
        "hiddenAssumptions": all_hidden,
        "ownerOnlyActions": owner_only,
        "missingFromPackage": missing_from_package,
        "imposedStackRefused": len(impose_stack) > 0,
        "refusedStack": impose_stack,
        "cleanRoomClaimAllowed": False,
        "environmentTested": raw.get("environmentTested") or "local-isolated",
        "verdict": verdict,
    }


def _process_onboarding_step(step: Dict[str, Any]) -> Tuple[Dict[str, Any], Optional[Dict[str, Any]], Optional[Dict[str, Any]], Optional[Dict[str, Any]]]:
    status = step.get("status") or "pending"
    entry = {
        "phase": step.get("phase") or "setup",
        "command": step.get("command") or "",
        "status": status,
        "notes": step.get("notes") or "",
        "documented": bool(step.get("documented", True)),
    }
    broken = None
    fresh_reader = None
    blocker = None

    if status == "failed":
        broken = {
            "phase": entry["phase"],
            "command": entry["command"],
            "reason": step.get("failureReason") or "command failed",
            "action": "repair-docs" if entry["documented"] else "document-prerequisite",
        }
    if step.get("freshReaderIssue"):
        fresh_reader = {
            "phase": entry["phase"],
            "issue": step.get("freshReaderIssue"),
            "action": step.get("freshReaderAction") or "clarify-docs",
        }
    if status == "blocked":
        blocker = {
            "phase": entry["phase"],
            "reason": step.get("blockerReason") or "environment unavailable",
            "exact": step.get("blockerDetail") or entry["notes"],
        }

    return entry, broken, fresh_reader, blocker


def _onboarding_journey_ending(complete: bool, broken: List[Any], blockers: List[Any]) -> str:
    if complete and not broken and not blockers:
        return "complete"
    if blockers:
        return "blocked"
    return "repair-needed"


def onboarding_journey(raw: Dict[str, Any]) -> Dict[str, Any]:
    steps: List[Dict[str, Any]] = []
    fresh_reader: List[Dict[str, Any]] = []
    blockers: List[Dict[str, Any]] = []
    broken: List[Dict[str, Any]] = []

    for step in raw.get("steps") or []:
        entry, step_broken, step_fresh, step_blocker = _process_onboarding_step(step)
        steps.append(entry)
        if step_broken:
            broken.append(step_broken)
        if step_fresh:
            fresh_reader.append(step_fresh)
        if step_blocker:
            blockers.append(step_blocker)

    complete = all(s["status"] in ("passed", "skipped") for s in steps) if steps else False
    if blockers:
        complete = False

    return {
        "schemaVersion": 1,
        "kind": "onboarding-journey",
        "repositoryOwnedCommands": bool(raw.get("repositoryOwnedCommands", True)),
        "steps": steps,
        "freshReaderIssues": fresh_reader,
        "freshReaderPassRequired": True,
        "freshReaderPassApplied": bool(raw.get("freshReaderPassApplied")),
        "brokenCommands": broken,
        "environmentalBlockers": blockers,
        "journeyComplete": complete and not broken,
        "humanDecisionRequired": bool(blockers or raw.get("humanDecisionRequired")),
        "cleanRoomClaimAllowed": False,
        "ending": _onboarding_journey_ending(complete, broken, blockers),
    }


def _process_discovered_prerequisite(
    item: Dict[str, Any],
    declared_set: Set[str],
) -> Tuple[Optional[Dict[str, Any]], Optional[Dict[str, Any]]]:
    name = item.get("name") or ""
    documented = name.lower() in declared_set or bool(item.get("documented"))
    blocking = bool(item.get("blocking", True))

    if item.get("ownerOnly"):
        return {
            "name": name,
            "reason": item.get("reason") or "install-decision",
            "action": "refuse",
        }, None

    if not documented:
        return None, {
            "name": name,
            "documented": False,
            "blocking": blocking,
            "detail": item.get("detail") or "",
            "action": "document" if blocking else "note",
        }

    return None, None


def _platform_support_block(platform: Dict[str, Any], requested: str) -> Dict[str, Any]:
    supported = platform.get("supported")
    if supported is False:
        return {
            "requested": requested,
            "supported": False,
            "reason": platform.get("reason") or "unsupported platform",
            "action": "park",
        }
    return {
        "requested": requested,
        "supported": True if supported is None else supported,
        "reason": platform.get("reason"),
        "action": "proceed",
    }


def _broken_command_entries(commands: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    broken: List[Dict[str, Any]] = []
    for cmd in commands:
        if cmd.get("status") != "broken":
            continue
        broken.append(
            {
                "command": cmd.get("command") or "",
                "documentedIn": cmd.get("documentedIn") or "",
                "reason": cmd.get("reason") or "command failed",
                "action": "repair-docs",
            }
        )
    return broken


def prerequisite_map(raw: Dict[str, Any]) -> Dict[str, Any]:
    declared = list(raw.get("declaredPrerequisites") or [])
    discovered = list(raw.get("discoveredPrerequisites") or [])
    commands = raw.get("commands") or []
    platform = raw.get("platform") or {}

    missing: List[Dict[str, Any]] = []
    owner_only: List[Dict[str, Any]] = []

    declared_set = {d.lower() for d in declared}
    for item in discovered:
        owner_entry, missing_entry = _process_discovered_prerequisite(item, declared_set)
        if owner_entry:
            owner_only.append(owner_entry)
        if missing_entry:
            missing.append(missing_entry)

    broken = _broken_command_entries(commands)

    requested = platform.get("requested") or raw.get("requestedPlatform") or ""
    platform_block = _platform_support_block(platform, requested)

    return {
        "schemaVersion": 1,
        "kind": "prerequisite-map",
        "declaredPrerequisites": declared,
        "discoveredPrerequisites": discovered,
        "missingPrerequisites": missing,
        "brokenCommands": broken,
        "ownerOnlyInstalls": owner_only,
        "platformSupport": platform_block,
        "neverImposeStack": True,
        "humanDecisionRequired": bool(owner_only or platform_block.get("supported") is False),
    }


def main(argv: List[str]) -> int:
    p = argparse.ArgumentParser(prog="build-onboarding-evidence.py")
    sub = p.add_subparsers(dest="cmd", required=True)
    for name in ("repro-compare", "onboarding-journey", "prerequisite-map"):
        sub.add_parser(name).add_argument("--input", required=True)
    args = p.parse_args(argv)

    with open(args.input, encoding="utf-8") as fh:
        data = json.load(fh)

    if args.cmd == "repro-compare":
        doc = repro_compare(data)
    elif args.cmd == "onboarding-journey":
        doc = onboarding_journey(data)
    elif args.cmd == "prerequisite-map":
        doc = prerequisite_map(data)
    else:
        return 1

    sys.stdout.write(json.dumps(doc, indent=2, sort_keys=True) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
