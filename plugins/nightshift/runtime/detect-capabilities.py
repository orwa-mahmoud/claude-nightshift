#!/usr/bin/env python3
"""Read-only capability detector. Never writes, installs, or mutates the work target."""
from __future__ import print_function

import argparse
import json
import os
import re
import stat
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PLUGIN = os.path.dirname(HERE)
PACKAGE_JSON = "package.json"
SCHEMA = os.path.join(
    PLUGIN, "skills", "nightshift", "references", "schemas", "v1"
)


def load(name):
    with open(os.path.join(SCHEMA, name)) as fh:
        return json.load(fh)


def nt_executable(candidate):
    for ext in (".exe", ".cmd", ".bat"):
        alt = candidate + ext
        if os.path.isfile(alt):
            return alt
    return None


def which(cmd, env_path):
    if not cmd or cmd.startswith("-"):
        return None
    for directory in env_path.split(os.pathsep):
        if not directory:
            continue
        candidate = os.path.join(directory, cmd)
        if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
            return candidate
        if os.name == "nt":
            found = nt_executable(candidate)
            if found:
                return found
    return None


def version_probe(path):
    """Return (ok, detail). Never runs the tool's real work command."""
    try:
        p = subprocess.Popen(
            [path, "--version"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        out, err = p.communicate()
        text = (out or b"").decode("utf-8", "replace") + (err or b"").decode("utf-8", "replace")
        text = text.strip().splitlines()[0] if text.strip() else ""
        if p.returncode == 0:
            return "available-and-verified", text[:200]
        return "available-but-failing", "exit %s: %s" % (p.returncode, text[:200])
    except OSError as exc:
        return "available-but-failing", str(exc)


def result(status, reason, locator, evidence_ladder="observed"):
    return {
        "status": status,
        "reason": reason,
        "locator": locator,
        "evidenceLadder": evidence_ladder,
    }


def read_json(path):
    try:
        with open(path) as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return None


def list_packages(target):
    """Root plus immediate child dirs that look like packages. Skip symlink children."""
    found = [target]
    try:
        names = sorted(os.listdir(target))
    except OSError:
        return found
    for name in names:
        if name.startswith("."):
            continue
        path = os.path.join(target, name)
        try:
            st = os.lstat(path)
        except OSError:
            continue
        if stat.S_ISLNK(st.st_mode):
            continue
        if not stat.S_ISDIR(st.st_mode):
            continue
        signals = (
            PACKAGE_JSON,
            "pyproject.toml",
            "requirements.txt",
            "go.mod",
            "Cargo.toml",
            "Makefile",
            ".claude-plugin",
            ".codex-plugin",
        )
        if any(os.path.exists(os.path.join(path, s)) for s in signals):
            found.append(path)
    return found


def file_cap(path, label):
    if os.path.isfile(path):
        return result("available-and-verified", "%s present" % label, path, "observed")
    return None


def scan_files(root, names):
    hits = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = sorted(d for d in dirnames if d not in (".git", "node_modules", "vendor", "target"))
        for name in sorted(filenames):
            if name in names:
                hits.append(os.path.join(dirpath, name))
        if len(hits) >= 20:
            break
    return hits


def detect_stack(pkg):
    stacks = []
    if os.path.isfile(os.path.join(pkg, PACKAGE_JSON)):
        stacks.append("javascript-typescript")
    if os.path.isfile(os.path.join(pkg, "pyproject.toml")) or os.path.isfile(
        os.path.join(pkg, "requirements.txt")
    ):
        stacks.append("python")
    if os.path.isfile(os.path.join(pkg, "go.mod")):
        stacks.append("go")
    if os.path.isfile(os.path.join(pkg, "Cargo.toml")):
        stacks.append("rust")
    plugin = False
    for rel in (".claude-plugin", ".codex-plugin", os.path.join("plugins")):
        if os.path.exists(os.path.join(pkg, rel)):
            plugin = True
    if plugin:
        stacks.append("shell-plugin")
    if os.path.isfile(os.path.join(pkg, "Makefile")):
        stacks.append("make")
    return stacks


def probe_command(cmd, env_path, locator):
    path = which(cmd, env_path)
    if not path:
        return result("unavailable", "command %s is not on PATH" % cmd, locator, "observed")
    status, detail = version_probe(path)
    reason = "%s -> %s (%s)" % (cmd, path, detail or "no version text")
    return result(status, reason, path, "measured" if status == "available-and-verified" else "observed")


def script_names(pkg):
    data = read_json(os.path.join(pkg, PACKAGE_JSON)) or {}
    scripts = data.get("scripts") or {}
    if not isinstance(scripts, dict):
        return []
    return sorted(scripts.keys())


def makefile_targets(pkg):
    path = os.path.join(pkg, "Makefile")
    if not os.path.isfile(path):
        return []
    try:
        text = open(path).read()
    except OSError:
        return []
    return sorted(set(re.findall(r"^([A-Za-z0-9][^:\n]*)\:", text, re.M)))


def owner_gates(ns):
    punch = os.path.join(ns, "punch-list.md")
    if not os.path.isfile(punch):
        return result("unavailable", "no punch-list.md", punch, "declared")
    text = open(punch).read()
    if "## Gates" not in text:
        return result("unavailable", "punch list has no Gates block", punch, "declared")
    return result("available-and-verified", "owner Gates block present", punch, "declared")


def merge_status(results):
    """Best available status among probes for one capability id."""
    rank = {
        "available-and-verified": 5,
        "available-but-failing": 4,
        "fallback-only": 3,
        "provisionable": 2,
        "unavailable": 1,
    }
    best = None
    for item in results:
        if best is None or rank[item["status"]] > rank[best["status"]]:
            best = item
    return best or result("unavailable", "not probed", "", "declared")


def artifact_caps(target):
    caps = {}
    md, html = [], []
    for dirpath, dirnames, filenames in os.walk(target):
        dirnames[:] = sorted(d for d in dirnames if d not in (".git", "node_modules"))
        for name in sorted(filenames):
            path = os.path.join(dirpath, name)
            lower = name.lower()
            if lower.endswith((".md", ".markdown")):
                md.append(path)
            elif lower.endswith((".html", ".htm")):
                html.append(path)
        if len(md) + len(html) > 40:
            break
    if md:
        caps["local-markdown"] = result(
            "available-and-verified", "%s markdown files" % len(md), md[0], "observed"
        )
        caps["source-export"] = result(
            "available-and-verified", "local files can be cited", md[0], "observed"
        )
    else:
        caps["local-markdown"] = result("unavailable", "no markdown files", target, "observed")
        caps["source-export"] = result("unavailable", "no local source files", target, "observed")
    if html:
        caps["local-html"] = result(
            "available-and-verified", "%s html files" % len(html), html[0], "observed"
        )
    else:
        caps["local-html"] = result("unavailable", "no html files", target, "observed")
    return caps


def collect_declared_scripts(packages, target):
    scripts = []
    for pkg in packages:
        for name in script_names(pkg):
            scripts.append("%s:%s" % (os.path.relpath(pkg, target), name))
        for name in makefile_targets(pkg):
            scripts.append("make:%s" % name)
    return scripts


def script_runner_caps(target, scripts):
    if scripts:
        entry = result(
            "available-and-verified", "declared scripts: %s" % ", ".join(scripts[:12]), target, "declared"
        )
        return entry, entry
    entry = result("unavailable", "no package.json scripts or Makefile targets", target, "observed")
    return entry, entry


def ci_cap(target):
    ci_hits = []
    for rel in (".github/workflows", ".gitlab-ci.yml", "azure-pipelines.yml"):
        path = os.path.join(target, rel)
        if os.path.exists(path):
            ci_hits.append(path)
    if ci_hits:
        return result("available-and-verified", "CI config present", ci_hits[0], "observed")
    return result("unavailable", "no CI config", target, "observed")


COMMAND_MAP = {
    "lint": [("eslint", "javascript-typescript"), ("ruff", "python"), ("golangci-lint", "go")],
    "typecheck": [("tsc", "javascript-typescript"), ("mypy", "python")],
    "test": [
        ("node", "javascript-typescript"),
        ("pytest", "python"),
        ("go", "go"),
        ("cargo", "rust"),
        ("bats", "shell-plugin"),
    ],
    "coverage": [("c8", "javascript-typescript"), ("pytest", "python"), ("go", "go")],
    "dead-code": [("knip", "javascript-typescript"), ("vulture", "python")],
    "build": [("tsc", "javascript-typescript"), ("go", "go"), ("cargo", "rust")],
    "security": [("npm", "javascript-typescript"), ("pip-audit", "python"), ("govulncheck", "go")],
    "documentation-link": [("markdown-link-check", None)],
    "accessibility": [("axe", None), ("pa11y", None)],
    "api-schema": [],
    "localization": [],
    "benchmark": [],
    "mutation-fuzz": [],
    "seo-performance": [],
    "browser": [("chrome", None), ("chromium", None)],
    "connector": [("gh", None)],
    "structured-results": [],
}

SCRIPT_HINTS = {
    "test": "test",
    "lint": "lint",
    "typecheck": "typecheck",
    "coverage": "coverage",
    "build": "build",
}


def should_probe_stack(stack, stacks, cap):
    if not stack or stack in stacks or cap == "connector":
        return True
    if stack not in ("javascript-typescript", "python", "go", "rust", "shell-plugin"):
        return False
    return stack in stacks


def probe_path_commands(probes, stacks, cap, env_path, target):
    found = []
    for cmd, stack in probes:
        if not should_probe_stack(stack, stacks, cap):
            continue
        found.append(probe_command(cmd, env_path, target))
    return found


def declared_script_probe(cap, packages):
    key = SCRIPT_HINTS.get(cap)
    if not key:
        return None
    if not any(key in script_names(pkg) for pkg in packages):
        return None
    return result(
        "available-and-verified",
        "package.json scripts.%s is declared; not proof of a binary" % key,
                        os.path.join(packages[0], PACKAGE_JSON),
        "declared",
    )


def makefile_test_probe(packages, target):
    if not any("test" in makefile_targets(pkg) for pkg in packages):
        return None
    return result("available-and-verified", "Makefile test target declared", target, "declared")


def structured_results_probe(target):
    hits = []
    for name in ("junit.xml", "coverage.lcov", "lcov.info"):
        hits.extend(scan_files(target, {name}))
    if not hits:
        return None
    return result("available-and-verified", "structured result file present", hits[0], "observed")


def api_schema_probe(target):
    for name in ("openapi.yaml", "openapi.yml", "openapi.json", "schema.graphql"):
        path = os.path.join(target, name)
        if os.path.isfile(path):
            return result("available-and-verified", "schema file present", path, "observed")
    return None


def localization_probe(target):
    for rel in ("locales", "i18n", "translations"):
        path = os.path.join(target, rel)
        if os.path.isdir(path):
            return result("available-and-verified", "locale directory present", path, "observed")
    return None


def probe_capability(cap, probes, stacks, env_path, target, packages):
    found = probe_path_commands(probes, stacks, cap, env_path, target)
    for extra in (
        declared_script_probe(cap, packages),
        makefile_test_probe(packages, target) if cap == "test" else None,
        structured_results_probe(target) if cap == "structured-results" else None,
        api_schema_probe(target) if cap == "api-schema" else None,
        localization_probe(target) if cap == "localization" else None,
    ):
        if extra:
            found.append(extra)
    return merge_status(found)


def repo_caps(target, ns, env_path):
    caps = artifact_caps(target)
    packages = list_packages(target)
    topology = {
        "root": target,
        "packages": packages,
        "monorepo": len(packages) > 1,
        "stacks": sorted({s for pkg in packages for s in detect_stack(pkg)}),
    }
    caps["owner-gates"] = owner_gates(ns)

    scripts = collect_declared_scripts(packages, target)
    caps["scripts"], caps["task-runner"] = script_runner_caps(target, scripts)
    caps["ci"] = ci_cap(target)

    stacks = topology["stacks"]
    for cap, probes in COMMAND_MAP.items():
        caps[cap] = probe_capability(cap, probes, stacks, env_path, target, packages)

    return caps, topology


def _missing_required_caps(req, caps):
    missing = []
    for cap in req.get("requires") or []:
        item = caps.get(cap) or result("unavailable", "not detected", "", "declared")
        if item["status"] in ("unavailable", "provisionable"):
            missing.append(cap)
    return missing


def _requires_any_satisfied(req, caps):
    requires_any = req.get("requiresAny") or []
    if not requires_any:
        return True, []
    for cap in requires_any:
        item = caps.get(cap) or result("unavailable", "not detected", "", "declared")
        if item["status"] in ("available-and-verified", "available-but-failing", "fallback-only"):
            return True, []
    return False, list(requires_any)


def evaluate_contract(req, caps, work_mode):
    if req.get("artifact") is False and work_mode == "artifact":
        return {
            "applies": False,
            "reason": "contract is skipped in artifact mode",
            "missing": [],
            "fallback": req.get("fallback"),
        }
    missing = _missing_required_caps(req, caps)
    any_ok, any_missing = _requires_any_satisfied(req, caps)
    if not any_ok:
        missing.extend(any_missing)
    if missing:
        fallback = req.get("fallback")
        if fallback:
            return {
                "applies": True,
                "reason": "fallback: %s" % fallback,
                "missing": missing,
                "fallback": fallback,
                "status": "fallback-only",
            }
        return {
            "applies": False,
            "reason": "missing capabilities: %s" % ", ".join(missing),
            "missing": missing,
            "fallback": None,
        }
    return {
        "applies": True,
        "reason": "required capabilities are present",
        "missing": [],
        "fallback": req.get("fallback"),
    }


def detect(workspace, host, env_path=None):
    ident = load("identifiers.json")
    if host not in ident["hosts"]:
        raise SystemExit("unknown host: %s" % host)
    ns = os.path.join(workspace, ".nightshift")
    mode_path = os.path.join(ns, "work-mode")
    work_mode = "repository"
    if os.path.isfile(mode_path):
        work_mode = open(mode_path).read().strip() or "repository"
    target_path = os.path.join(ns, "work-target")
    target = workspace
    if os.path.isfile(target_path):
        recorded = open(target_path).read().strip()
        if recorded:
            target = recorded
    env_path = env_path if env_path is not None else os.environ.get("PATH", "")

    topology = {
        "root": target,
        "packages": [target],
        "monorepo": False,
        "stacks": [],
    }
    if work_mode == "artifact":
        caps = artifact_caps(target)
        # Never report repository tools in artifact mode.
        for cap in load("capabilities.json")["capabilities"]:
            if cap in ("local-markdown", "local-html", "source-export"):
                continue
            caps[cap] = result(
                "unavailable",
                "artifact mode does not probe repository tools",
                target,
                "declared",
            )
    else:
        caps, topology = repo_caps(target, ns, env_path)

    reqs = load("catalog-requirements.json")["contracts"]
    contracts = {}
    for cid, req in sorted(reqs.items()):
        contracts[cid] = evaluate_contract(req, caps, work_mode)

    return {
        "schemaVersion": 1,
        "host": host,
        "workMode": work_mode,
        "workTarget": target,
        "topology": topology,
        "capabilities": caps,
        "contracts": contracts,
        "provisioningDefault": load("capabilities.json")["provisioningDefault"],
    }


def normalize(doc):
    """Drop host so fixture/adapter parity can compare Claude/Codex/Cursor outputs."""
    out = json.loads(json.dumps(doc))
    out.pop("host", None)
    return out


def usage():
    print(
        "usage: detect-capabilities.sh --project DIR [--host claude|codex|cursor] [--normalize]",
        file=sys.stderr,
    )
    return 1


def parse_detect_args(argv):
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("-p", "--project")
    parser.add_argument("--host", default="claude")
    parser.add_argument("--normalize", action="store_true")
    parser.add_argument("-h", "--help", action="store_true")
    args, _unknown = parser.parse_known_args(argv[1:])
    if args.help or not args.project:
        return None, args.host, args.normalize, usage()
    return args.project, args.host, args.normalize, 0


def main(argv):
    project, host, do_norm, err = parse_detect_args(argv)
    if err:
        return err
    project = os.path.abspath(project)
    if not os.path.isdir(project):
        print("detect-capabilities: not a directory: %s" % project, file=sys.stderr)
        return 1
    doc = detect(project, host)
    if do_norm:
        doc = normalize(doc)
    json.dump(doc, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
