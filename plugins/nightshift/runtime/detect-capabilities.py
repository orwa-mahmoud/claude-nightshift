#!/usr/bin/env python3
"""Read-only capability detector. Never writes, installs, or mutates the work target."""
from __future__ import print_function

import json
import os
import re
import stat
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PLUGIN = os.path.dirname(HERE)
SCHEMA = os.path.join(
    PLUGIN, "skills", "nightshift", "references", "schemas", "v1"
)


def load(name):
    with open(os.path.join(SCHEMA, name)) as fh:
        return json.load(fh)


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
            for ext in (".exe", ".cmd", ".bat"):
                alt = candidate + ext
                if os.path.isfile(alt):
                    return alt
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
            "package.json",
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
    if os.path.isfile(os.path.join(pkg, "package.json")):
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
    data = read_json(os.path.join(pkg, "package.json")) or {}
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
            if lower.endswith(".md") or lower.endswith(".markdown"):
                md.append(path)
            elif lower.endswith(".html") or lower.endswith(".htm"):
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

    scripts = []
    for pkg in packages:
        for name in script_names(pkg):
            scripts.append("%s:%s" % (os.path.relpath(pkg, target), name))
        for name in makefile_targets(pkg):
            scripts.append("make:%s" % name)
    if scripts:
        caps["scripts"] = result(
            "available-and-verified", "declared scripts: %s" % ", ".join(scripts[:12]), target, "declared"
        )
        caps["task-runner"] = caps["scripts"]
    else:
        caps["scripts"] = result("unavailable", "no package.json scripts or Makefile targets", target, "observed")
        caps["task-runner"] = caps["scripts"]

    ci_hits = []
    for rel in (".github/workflows", ".gitlab-ci.yml", "azure-pipelines.yml"):
        path = os.path.join(target, rel)
        if os.path.exists(path):
            ci_hits.append(path)
    caps["ci"] = (
        result("available-and-verified", "CI config present", ci_hits[0], "observed")
        if ci_hits
        else result("unavailable", "no CI config", target, "observed")
    )

    command_map = {
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

    # package.json script names can verify a capability without PATH proof of a binary
    # but a script name is still not a binary. Treat npm scripts as declared, then
    # prefer a PATH binary for verified.
    script_hints = {
        "test": "test",
        "lint": "lint",
        "typecheck": "typecheck",
        "coverage": "coverage",
        "build": "build",
    }

    stacks = topology["stacks"]
    for cap, probes in command_map.items():
        found = []
        for cmd, stack in probes:
            if stack and stack not in stacks and cap != "connector":
                # still allow generic tools
                if stack not in ("javascript-typescript", "python", "go", "rust", "shell-plugin"):
                    continue
                if stack not in stacks:
                    continue
            found.append(probe_command(cmd, env_path, target))
        # declared scripts
        if cap in script_hints:
            key = script_hints[cap]
            if any(key in script_names(pkg) for pkg in packages):
                found.append(
                    result(
                        "available-and-verified",
                        "package.json scripts.%s is declared; not proof of a binary" % key,
                        os.path.join(packages[0], "package.json"),
                        "declared",
                    )
                )
        if cap == "test" and any("test" in makefile_targets(pkg) for pkg in packages):
            found.append(
                result("available-and-verified", "Makefile test target declared", target, "declared")
            )
        if cap == "structured-results":
            hits = []
            for name in ("junit.xml", "coverage.lcov", "lcov.info"):
                hits.extend(scan_files(target, {name}))
            if hits:
                found.append(result("available-and-verified", "structured result file present", hits[0], "observed"))
        if cap == "api-schema":
            for name in ("openapi.yaml", "openapi.yml", "openapi.json", "schema.graphql"):
                path = os.path.join(target, name)
                if os.path.isfile(path):
                    found.append(result("available-and-verified", "schema file present", path, "observed"))
        if cap == "localization":
            for rel in ("locales", "i18n", "translations"):
                path = os.path.join(target, rel)
                if os.path.isdir(path):
                    found.append(result("available-and-verified", "locale directory present", path, "observed"))
        caps[cap] = merge_status(found)

    return caps, topology


def evaluate_contract(req, caps, work_mode):
    if req.get("artifact") is False and work_mode == "artifact":
        return {
            "applies": False,
            "reason": "contract is skipped in artifact mode",
            "missing": [],
            "fallback": req.get("fallback"),
        }
    missing = []
    for cap in req.get("requires") or []:
        item = caps.get(cap) or result("unavailable", "not detected", "", "declared")
        if item["status"] in ("unavailable", "provisionable"):
            missing.append(cap)
    any_ok = True
    requires_any = req.get("requiresAny") or []
    if requires_any:
        any_ok = False
        for cap in requires_any:
            item = caps.get(cap) or result("unavailable", "not detected", "", "declared")
            if item["status"] in ("available-and-verified", "available-but-failing", "fallback-only"):
                any_ok = True
                break
        if not any_ok:
            missing.extend(requires_any)
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


def main(argv):
    project = None
    host = "claude"
    do_norm = False
    args = argv[1:]
    i = 0
    while i < len(args):
        a = args[i]
        if a in ("--project", "-p"):
            if i + 1 >= len(args):
                return usage()
            project = args[i + 1]
            i += 2
            continue
        if a == "--host":
            if i + 1 >= len(args):
                return usage()
            host = args[i + 1]
            i += 2
            continue
        if a == "--normalize":
            do_norm = True
            i += 1
            continue
        if a in ("-h", "--help"):
            return usage()
        return usage()
    if not project:
        return usage()
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
