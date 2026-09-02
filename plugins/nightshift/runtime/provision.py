#!/usr/bin/env python3
"""Transactional Auto-add provisioning. Never writes the punch list. Never pushes."""
from __future__ import print_function

import base64
import hashlib
import json
import os
import shutil
import subprocess
import sys
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
PLUGIN = os.path.dirname(HERE)
SCHEMA_PATH = os.path.join(
    PLUGIN, "skills", "nightshift", "references", "schemas", "v1", "capability-recipe.json"
)
POLICY_SH = os.path.join(HERE, "shift-policy.sh")

REQUIRED = (
    "capabilityId",
    "ecosystems",
    "versionConstraints",
    "detect",
    "probe",
    "packageManagerAdditions",
    "allowedFiles",
    "minimalConfig",
    "smoke",
    "rollback",
    "enabledShifts",
    "safetyClass",
    "permissionRequirements",
    "recipeVersion",
)
SAFE = ("local-dev-free", "local-dev-with-config")
DEFAULT_BUDGET = 120
SETUP_PREFIX = "chore(tooling):"
STAGES = (
    "authorize",
    "capture-baseline",
    "apply",
    "smoke",
    "record",
    "commit-tooling",
)
NS_LOCKED = (
    "punch-list.md",
    "parking-lot.md",
    "drafting-table.md",
    "work-orders.md",
    "capability-policy.json",
    "shift-policy.json",
    "shift-defaults.json",
)
STACK_SIGNALS = (
    ("javascript-typescript", ("package.json",)),
    ("python", ("pyproject.toml", "requirements.txt", "setup.cfg", "setup.py")),
    ("go", ("go.mod",)),
    ("rust", ("Cargo.toml",)),
    ("shell-plugin", (".claude-plugin", ".codex-plugin")),
    ("make", ("Makefile",)),
)
GLOBAL_MARKS = (
    "sudo ",
    "npm i -g",
    "npm install -g",
    "pnpm add -g",
    "yarn global",
    "pip install --user",
    "pip3 install --user",
    "brew install",
    "apt-get",
    "apt install",
    "dnf ",
    "yum ",
    "choco ",
    "winget ",
    "systemctl",
)
PAID_MARKS = ("paid", "account", "login", "subscription", "billing", "license-key")
DAEMON_MARKS = (
    "daemon",
    "docker",
    "container",
    "compose",
    "cloud",
    "kubernetes",
    "k8s",
    "postgres",
    "mysql",
    "redis",
    "mongodb",
    "systemd",
)
PROMPT_MARKS = ("prompt", "interactive", "confirm", "tty")


def utcnow():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def ns_dir(project):
    return os.path.join(os.path.abspath(project), ".nightshift")


def tx_path(ns):
    return os.path.join(ns, "provision-transaction.json")


def baseline_dir(ns):
    return os.path.join(ns, "provision-baseline")


def blob_id_for(rel):
    return digest_bytes(norm_rel(rel).encode("utf-8"))


def clear_baseline_store(ns):
    path = baseline_dir(ns)
    if os.path.isdir(path) or os.path.islink(path):
        shutil.rmtree(path)


def atomic_write(path, doc):
    tmp = path + ".tmp"
    try:
        with open(tmp, "w") as fh:
            json.dump(doc, fh, indent=2, sort_keys=True)
            fh.write("\n")
            fh.flush()
            os.fsync(fh.fileno())
        os.replace(tmp, path)
    except Exception:
        try:
            os.remove(tmp)
        except OSError:
            pass
        raise


def read_json(path):
    with open(path) as fh:
        return json.load(fh)


def load_contract():
    try:
        data = read_json(SCHEMA_PATH)
    except (OSError, ValueError):
        return None
    return data if isinstance(data, dict) else None


def required_fields():
    data = load_contract()
    fields = (data or {}).get("requiredRecipeFields")
    if isinstance(fields, list) and fields:
        return tuple(fields)
    return REQUIRED


def default_budget():
    data = load_contract()
    n = (data or {}).get("preflightBudgetSecondsDefault")
    try:
        return int(n)
    except (TypeError, ValueError):
        return DEFAULT_BUDGET


def work_mode(project):
    path = os.path.join(ns_dir(project), "work-mode")
    if not os.path.isfile(path):
        return "repository"
    try:
        with open(path) as fh:
            mode = fh.read().strip()
    except OSError:
        return "repository"
    return mode if mode in ("repository", "artifact") else "repository"


def work_target(project):
    path = os.path.join(ns_dir(project), "work-target")
    if os.path.isfile(path):
        try:
            with open(path) as fh:
                target = fh.read().strip()
            if target and os.path.isdir(target):
                return os.path.abspath(target)
        except OSError:
            pass
    return os.path.abspath(project)


def policy_get(project, mode):
    """Tooling policy from the one resolved view (rules, shift defaults, one-shift policy)."""
    out = subprocess.check_output(
        ["bash", POLICY_SH, "--project", project, "resolve", "--json"],
        stderr=subprocess.DEVNULL,
    )
    resolved = json.loads(out.decode())
    setting = (resolved.get("settings") or {}).get("toolingPolicy")
    if not isinstance(setting, dict) or not isinstance(setting.get("value"), str):
        raise ValueError("resolved view has no toolingPolicy")
    return {"policy": setting["value"], "refused": False}


def inventory_path(project):
    return os.path.join(ns_dir(project), "capabilities.json")


def inventory_get(project):
    path = inventory_path(project)
    if not os.path.isfile(path):
        return {"schemaVersion": 1, "source": "default", "items": [], "updatedAt": None, "tickProof": False}
    data = read_json(path)
    if not isinstance(data, dict):
        raise ValueError("inventory must be an object")
    return data


def inventory_set(project, doc):
    doc = dict(doc)
    doc["schemaVersion"] = 1
    doc["updatedAt"] = utcnow()
    doc["tickProof"] = False
    atomic_write(inventory_path(project), doc)


def load_recipe(path):
    data = read_json(path)
    if not isinstance(data, dict):
        raise ValueError("recipe must be an object")
    missing = [k for k in required_fields() if k not in data]
    if missing:
        raise ValueError("missing fields: %s" % ", ".join(missing))
    allowed = data.get("allowedFiles")
    if not isinstance(allowed, list) or not all(isinstance(x, str) and x for x in allowed):
        raise ValueError("allowedFiles must be a list of relative paths")
    return data


def digest_bytes(data):
    return hashlib.sha256(data).hexdigest()


def digest_file(path):
    with open(path, "rb") as fh:
        return digest_bytes(fh.read())


def norm_rel(rel):
    return rel.replace("\\", "/").lstrip("./")


def under_allowed(rel, allowed):
    rel = norm_rel(rel)
    for raw in allowed:
        a = norm_rel(raw)
        if rel == a or rel.startswith(a.rstrip("/") + "/"):
            return True
    return False


def resolve_in_target(target, rel):
    rel = norm_rel(rel)
    if not rel or rel.startswith("/") or any(p == ".." for p in rel.split("/")):
        raise ValueError("path outside work target: %s" % rel)
    if os.path.basename(rel) in NS_LOCKED:
        raise ValueError("refuses to write Nightshift owner files")
    abs_path = os.path.abspath(os.path.join(target, rel))
    root = os.path.abspath(target)
    if abs_path != root and not abs_path.startswith(root + os.sep):
        raise ValueError("path outside work target: %s" % rel)
    return abs_path


def text_blob(value):
    if isinstance(value, (dict, list)):
        return json.dumps(value, indent=2, sort_keys=True) + "\n"
    return value if isinstance(value, str) else str(value)


def contains_any(text, marks):
    low = text.lower()
    return any(m in low for m in marks)


def flatten_text(*parts):
    chunks = []
    for part in parts:
        if part is None:
            continue
        if isinstance(part, str):
            chunks.append(part)
        else:
            try:
                chunks.append(json.dumps(part))
            except (TypeError, ValueError):
                chunks.append(str(part))
    return " ".join(chunks)


def addition_commands(recipe):
    adds = recipe.get("packageManagerAdditions") or []
    if isinstance(adds, dict):
        adds = [adds]
    out = []
    if not isinstance(adds, list):
        return out
    for step in adds:
        if isinstance(step, str):
            out.append(step)
        elif isinstance(step, dict):
            cmd = step.get("command") or step.get("cmd")
            if cmd:
                out.append(cmd)
    return out


def smoke_command(smoke):
    if isinstance(smoke, dict):
        return smoke.get("command") or smoke.get("cmd") or ""
    if isinstance(smoke, str):
        return smoke
    return ""


def detected_stacks(target):
    found = []
    for name, files in STACK_SIGNALS:
        if any(os.path.exists(os.path.join(target, f)) for f in files):
            found.append(name)
    return found


def is_git(target):
    try:
        p = subprocess.Popen(
            ["git", "-C", target, "rev-parse", "--is-inside-work-tree"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        out, _ = p.communicate()
        return p.returncode == 0 and out.decode().strip() == "true"
    except OSError:
        return False


def git_porcelain(target, paths):
    if not is_git(target) or not paths:
        return []
    try:
        p = subprocess.Popen(
            ["git", "-C", target, "status", "--porcelain", "--"] + list(paths),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        out, _ = p.communicate()
        if p.returncode != 0:
            return []
        return [ln for ln in out.decode("utf-8", "replace").splitlines() if ln.strip()]
    except OSError:
        return []


def existing_setup_commit(target, capability_id):
    if not is_git(target) or not capability_id:
        return ""
    subject = "%s %s" % (SETUP_PREFIX, capability_id)
    try:
        p = subprocess.Popen(
            ["git", "-C", target, "log", "--format=%H %s", "-n", "80"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        out, _ = p.communicate()
        if p.returncode != 0:
            return ""
        for line in out.decode("utf-8", "replace").splitlines():
            parts = line.split(" ", 1)
            if len(parts) == 2 and parts[1] == subject:
                return parts[0]
    except OSError:
        return ""
    return ""


def emit(doc, code):
    print(json.dumps(doc, sort_keys=True))
    return code


def refuse(code, detail=None, extra=None):
    doc = {
        "ok": False,
        "refused": True,
        "reason": code,
        "refusalReasons": [code],
    }
    if detail:
        doc["detail"] = detail
    if extra:
        doc.update(extra)
    return emit(doc, 2)


def collect_refusals(project, recipe, mode, pol, target):
    reasons = []
    if mode == "artifact":
        reasons.append("artifact-mode")
    if pol.get("policy") != "auto-add" or pol.get("refused"):
        reasons.append("policy-not-auto-add")

    safety = recipe.get("safetyClass")
    if safety == "forbidden" or safety not in SAFE:
        reasons.append("safety-forbidden")

    perm = flatten_text(recipe.get("permissionRequirements"), recipe.get("safetyClass"))
    cmds = flatten_text(*addition_commands(recipe), smoke_command(recipe.get("smoke")))
    blob = perm + " " + cmds
    if contains_any(blob, GLOBAL_MARKS) or contains_any(blob, ("global", "system-wide")):
        reasons.append("global-or-system")
    if contains_any(perm, PAID_MARKS):
        reasons.append("paid-or-account")
    if contains_any(blob, DAEMON_MARKS):
        reasons.append("daemon-or-cloud")
    if contains_any(perm, PROMPT_MARKS):
        reasons.append("permission-prompt-required")

    ecosystems = recipe.get("ecosystems") or []
    if isinstance(ecosystems, str):
        ecosystems = [ecosystems]
    if isinstance(ecosystems, list) and ecosystems:
        names = [e for e in ecosystems if isinstance(e, str)]
        wild = any(e in ("*", "any") for e in names)
        stacks = detected_stacks(target)
        if names and not wild and stacks and not set(names) & set(stacks):
            reasons.append("incompatible-ecosystem")

    allowed = list(recipe.get("allowedFiles") or [])
    dirty = git_porcelain(target, allowed)
    if dirty:
        reasons.append("owner-dirty-conflict")

    # unique, stable order from the frozen enum
    order = (
        "policy-not-auto-add",
        "artifact-mode",
        "global-or-system",
        "paid-or-account",
        "daemon-or-cloud",
        "incompatible-ecosystem",
        "permission-prompt-required",
        "owner-dirty-conflict",
        "safety-forbidden",
    )
    seen = []
    for code in order:
        if code in reasons and code not in seen:
            seen.append(code)
    return seen


def plan_doc(project, recipe, reasons):
    return {
        "ok": not reasons,
        "refused": bool(reasons),
        "refusalReasons": reasons,
        "reason": (
            "artifact-mode"
            if "artifact-mode" in reasons
            else (reasons[0] if reasons else None)
        ),
        "capabilityId": recipe.get("capabilityId"),
        "recipeVersion": recipe.get("recipeVersion"),
        "allowedFiles": recipe.get("allowedFiles"),
        "safetyClass": recipe.get("safetyClass"),
        "enabledShifts": recipe.get("enabledShifts"),
        "packageManagerAdditions": recipe.get("packageManagerAdditions"),
        "minimalConfig": recipe.get("minimalConfig"),
        "smoke": recipe.get("smoke"),
        "rollback": recipe.get("rollback"),
        "workTarget": work_target(project),
        "stages": list(STAGES),
        "alreadyProvisioned": bool(
            existing_setup_commit(work_target(project), recipe.get("capabilityId"))
        ),
    }


def cmd_plan(project, recipe_path, capability):
    mode = work_mode(project)
    try:
        pol = policy_get(project, mode)
    except (OSError, ValueError, subprocess.CalledProcessError):
        return refuse("policy-not-auto-add", "policy lookup failed")
    try:
        recipe = load_recipe(recipe_path)
    except (OSError, ValueError) as exc:
        return refuse("incompatible-ecosystem", str(exc))
    if capability and recipe.get("capabilityId") != capability:
        return refuse("incompatible-ecosystem", "capability mismatch")
    target = work_target(project)
    reasons = collect_refusals(project, recipe, mode, pol, target)
    doc = plan_doc(project, recipe, reasons)
    return emit(doc, 0 if not reasons else 2)


def encode_content(data):
    if data is None:
        return None
    return base64.b64encode(data).decode("ascii")


def decode_content(blob):
    if not blob:
        return b""
    return base64.b64decode(blob.encode("ascii"))


def capture_baseline(ns, target, allowed):
    store = baseline_dir(ns)
    baseline = {}
    for rel in allowed:
        rel_n = norm_rel(rel)
        abs_path = resolve_in_target(target, rel_n)
        blob = blob_id_for(rel_n)
        if os.path.isfile(abs_path):
            data = open(abs_path, "rb").read()
            os.makedirs(store, exist_ok=True)
            with open(os.path.join(store, blob), "wb") as fh:
                fh.write(data)
            baseline[rel_n] = {
                "existed": True,
                "digest": digest_bytes(data),
                "blob": blob,
                "content": encode_content(data),
            }
        else:
            baseline[rel_n] = {
                "existed": False,
                "digest": None,
                "blob": None,
                "content": None,
            }
    return baseline


def write_tx(ns, doc):
    atomic_write(tx_path(ns), doc)


def clear_tx(ns):
    path = tx_path(ns)
    if os.path.isfile(path):
        os.remove(path)


def run_cmd(cmd, cwd, budget):
    argv = None
    shell = False
    if isinstance(cmd, dict):
        if cmd.get("argv"):
            argv = list(cmd["argv"])
        else:
            argv = cmd.get("command") or cmd.get("cmd") or ""
            shell = True
    elif isinstance(cmd, list):
        argv = cmd
    else:
        argv = cmd
        shell = True
    if not argv:
        return 0, ""
    try:
        p = subprocess.Popen(
            argv,
            shell=shell,
            cwd=cwd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            universal_newlines=True,
        )
        try:
            out, _ = p.communicate(timeout=max(1, int(budget)))
        except subprocess.TimeoutExpired:
            p.kill()
            p.communicate()
            return 124, "timeout"
        return p.returncode, out or ""
    except OSError as exc:
        return 127, str(exc)


def restore_bytes(ns, meta):
    blob = meta.get("blob")
    if blob:
        blob_path = os.path.join(baseline_dir(ns), blob)
        if os.path.isfile(blob_path):
            with open(blob_path, "rb") as fh:
                return fh.read()
    if meta.get("content"):
        return decode_content(meta.get("content"))
    return b""


def rollback_baseline(ns, target, baseline):
    for rel, meta in (baseline or {}).items():
        abs_path = resolve_in_target(target, rel)
        if meta.get("existed"):
            parent = os.path.dirname(abs_path)
            if parent and not os.path.isdir(parent):
                os.makedirs(parent)
            with open(abs_path, "wb") as fh:
                fh.write(restore_bytes(ns, meta))
        else:
            if os.path.isfile(abs_path) or os.path.islink(abs_path):
                os.remove(abs_path)
            parent = os.path.dirname(abs_path)
            root = os.path.abspath(target)
            while parent.startswith(root + os.sep) and parent != root:
                try:
                    os.rmdir(parent)
                except OSError:
                    break
                parent = os.path.dirname(parent)
    clear_baseline_store(ns)


def config_entries(recipe):
    cfg = recipe.get("minimalConfig")
    if cfg is None:
        return []
    if isinstance(cfg, dict):
        return [(k, cfg[k]) for k in cfg]
    if isinstance(cfg, list):
        out = []
        for item in cfg:
            if not isinstance(item, dict):
                raise ValueError("minimalConfig entries must be objects")
            rel = item.get("path") or item.get("file")
            if not rel:
                raise ValueError("minimalConfig entry missing path")
            out.append((rel, item.get("content", "")))
        return out
    raise ValueError("minimalConfig must be an object or array")


def apply_config(target, recipe):
    touched = []
    allowed = recipe["allowedFiles"]
    for rel, content in config_entries(recipe):
        if not under_allowed(rel, allowed):
            raise ValueError("config path outside allowedFiles: %s" % rel)
        abs_path = resolve_in_target(target, rel)
        parent = os.path.dirname(abs_path)
        if parent and not os.path.isdir(parent):
            os.makedirs(parent)
        data = text_blob(content)
        with open(abs_path, "w") as fh:
            fh.write(data)
            if data and not data.endswith("\n"):
                fh.write("\n")
        touched.append(norm_rel(rel))
    return touched


def merge_json_file(path, patch):
    current = {}
    if os.path.isfile(path):
        try:
            current = read_json(path)
        except (OSError, ValueError):
            current = {}
    if not isinstance(current, dict) or not isinstance(patch, dict):
        raise ValueError("json merge requires objects")
    for key, val in patch.items():
        if isinstance(val, dict) and isinstance(current.get(key), dict):
            merged = dict(current[key])
            merged.update(val)
            current[key] = merged
        else:
            current[key] = val
    parent = os.path.dirname(path)
    if parent and not os.path.isdir(parent):
        os.makedirs(parent)
    atomic_write(path, current)


def apply_package_adds(target, recipe, budget):
    adds = recipe.get("packageManagerAdditions") or []
    if isinstance(adds, dict):
        adds = [adds]
    if not isinstance(adds, list):
        raise ValueError("packageManagerAdditions must be an array")
    allowed = recipe["allowedFiles"]
    for step in adds:
        if isinstance(step, str):
            cmd = step
            low = cmd.lower()
            if contains_any(low, GLOBAL_MARKS):
                raise ValueError("global-or-system")
            rc, out = run_cmd(cmd, target, budget)
            if rc != 0:
                raise RuntimeError("package add failed: %s" % out.strip())
            continue
        if not isinstance(step, dict):
            raise ValueError("packageManagerAdditions entry must be a string or object")
        cmd = step.get("command") or step.get("cmd")
        if cmd:
            if contains_any(cmd, GLOBAL_MARKS):
                raise ValueError("global-or-system")
            rc, out = run_cmd(cmd, target, budget)
            if rc != 0:
                raise RuntimeError("package add failed: %s" % out.strip())
        rel = step.get("file") or step.get("path") or step.get("manifest")
        patch = None
        for key in ("merge", "devDependencies", "dependencies", "fields"):
            if key in step and key != "command":
                if key in ("devDependencies", "dependencies"):
                    patch = {key: step[key]}
                elif key == "fields":
                    patch = step[key]
                else:
                    patch = step[key]
                break
        if rel and patch is not None:
            if not under_allowed(rel, allowed):
                raise ValueError("package add path outside allowedFiles: %s" % rel)
            merge_json_file(resolve_in_target(target, rel), patch)


def changed_allowed(target, baseline):
    touched = []
    for rel, meta in baseline.items():
        abs_path = resolve_in_target(target, rel)
        if os.path.isfile(abs_path):
            digest = digest_file(abs_path)
            if not meta.get("existed") or digest != meta.get("digest"):
                touched.append(rel)
        elif meta.get("existed"):
            touched.append(rel)
    return touched


def smoke_result(recipe, target, budget):
    """Red baseline (tool ran, reported findings) is success. Exit 127 is not."""
    smoke = recipe.get("smoke")
    rc, out = run_cmd(smoke, target, budget)
    if rc == 0:
        return
    if rc in (127, 124):
        raise RuntimeError("smoke failed: %s" % (out.strip() or "command missing or timed out"))
    if (out or "").strip():
        return
    raise RuntimeError("smoke failed: %s" % (out.strip() or "exit %s" % rc))


def record_inventory(project, recipe, setup_commit):
    try:
        data = inventory_get(project)
    except (OSError, ValueError, subprocess.CalledProcessError):
        data = {"items": []}
    items = [i for i in (data.get("items") or []) if isinstance(i, dict)]
    cap = recipe["capabilityId"]
    items = [i for i in items if i.get("capability") != cap]
    smoke = recipe.get("smoke")
    command = ""
    if isinstance(smoke, dict):
        command = smoke.get("command") or smoke.get("cmd") or ""
    elif isinstance(smoke, str):
        command = smoke
    items.append(
        {
            "capability": cap,
            "command": command,
            "source": "recipe",
            "verifiedAt": utcnow(),
            "configFiles": list(recipe.get("allowedFiles") or []),
            "recipeVersion": recipe.get("recipeVersion"),
            "setupCommit": setup_commit or "",
        }
    )
    data["items"] = items
    inventory_set(project, data)


def commit_tooling(target, recipe, touched):
    if not is_git(target):
        return ""
    paths = [rel for rel in touched if under_allowed(rel, recipe["allowedFiles"])]
    if not paths:
        return ""
    for rel in paths:
        subprocess.call(
            ["git", "-C", target, "add", "--", rel],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    msg = "%s %s" % (SETUP_PREFIX, recipe["capabilityId"])
    rc = subprocess.call(
        ["git", "-C", target, "commit", "-m", msg, "--"] + paths,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    if rc != 0:
        porcelain = git_porcelain(target, paths)
        if not porcelain:
            return ""
        raise RuntimeError("commit-tooling failed")
    out = subprocess.check_output(
        ["git", "-C", target, "rev-parse", "HEAD"], stderr=subprocess.DEVNULL
    )
    return out.decode().strip()


def load_tx(ns):
    path = tx_path(ns)
    if not os.path.isfile(path):
        return None
    try:
        data = read_json(path)
    except (OSError, ValueError):
        return None
    return data if isinstance(data, dict) else None


def fail_and_rollback(ns, target, tx, exc, refused_code=None):
    tx["failed"] = True
    tx["stage"] = "rollback"
    tx["lastError"] = str(exc)
    tx["updatedAt"] = utcnow()
    write_tx(ns, tx)
    rollback_baseline(ns, target, tx.get("baseline") or {})
    clear_tx(ns)
    if refused_code:
        return refuse(refused_code, str(exc))
    return emit(
        {
            "ok": False,
            "refused": False,
            "failed": True,
            "detail": str(exc),
            "capabilityId": tx.get("capabilityId"),
        },
        1,
    )


def finish_late_stages(project, recipe, tx, ns, target):
    setup = tx.get("setupCommit") or ""
    if tx.get("stage") in ("record", "commit-tooling") and not tx.get("failed"):
        if tx.get("stage") == "record":
            record_inventory(project, recipe, setup)
            tx["stage"] = "commit-tooling"
            tx["updatedAt"] = utcnow()
            write_tx(ns, tx)
        setup = commit_tooling(target, recipe, tx.get("touched") or [])
        if setup:
            record_inventory(project, recipe, setup)
        tx["setupCommit"] = setup
        return setup
    return setup


def cmd_apply(project, recipe_path, capability, budget):
    ns = ns_dir(project)
    if not os.path.isdir(ns):
        print("provision: no .nightshift/", file=sys.stderr)
        return 1
    leftover = load_tx(ns)
    if leftover:
        same = leftover.get("capabilityId") == (
            capability or leftover.get("capabilityId")
        ) or leftover.get("recipePath") == os.path.abspath(recipe_path)
        if leftover.get("failed") and same:
            cmd_rollback(project)
            return emit(
                {
                    "ok": False,
                    "refused": False,
                    "failed": True,
                    "detail": "do not retry the same failure",
                    "capabilityId": leftover.get("capabilityId"),
                },
                1,
            )
        if leftover.get("stage") in ("record", "commit-tooling") and same and not leftover.get(
            "failed"
        ):
            return cmd_recover(project, budget)
        cmd_recover(project, budget)

    mode = work_mode(project)
    try:
        pol = policy_get(project, mode)
    except (OSError, ValueError, subprocess.CalledProcessError):
        return refuse("policy-not-auto-add")
    try:
        recipe = load_recipe(recipe_path)
    except (OSError, ValueError) as exc:
        return refuse("incompatible-ecosystem", str(exc))
    if capability and recipe.get("capabilityId") != capability:
        return refuse("incompatible-ecosystem", "capability mismatch")
    target = work_target(project)
    reasons = collect_refusals(project, recipe, mode, pol, target)
    if reasons:
        return emit(plan_doc(project, recipe, reasons), 2)

    existing = existing_setup_commit(target, recipe["capabilityId"])
    if existing:
        try:
            record_inventory(project, recipe, existing)
        except (OSError, ValueError, subprocess.CalledProcessError):
            pass
        return emit(
            {
                "ok": True,
                "capabilityId": recipe["capabilityId"],
                "setupCommit": existing,
                "skipped": "already-present",
                "touched": [],
            },
            0,
        )
    allowed = [norm_rel(a) for a in recipe["allowedFiles"]]
    baseline = capture_baseline(ns, target, allowed)
    porcelain = git_porcelain(target, allowed)
    tx = {
        "schemaVersion": 1,
        "stage": "capture-baseline",
        "capabilityId": recipe["capabilityId"],
        "recipePath": os.path.abspath(recipe_path),
        "recipeVersion": recipe.get("recipeVersion"),
        "workTarget": target,
        "allowedFiles": allowed,
        "baseline": baseline,
        "gitPorcelain": porcelain,
        "touched": [],
        "failed": False,
        "lastError": None,
        "setupCommit": "",
        "updatedAt": utcnow(),
    }
    write_tx(ns, tx)

    try:
        tx["stage"] = "apply"
        tx["updatedAt"] = utcnow()
        write_tx(ns, tx)
        apply_package_adds(target, recipe, budget)
        apply_config(target, recipe)
        touched = changed_allowed(target, baseline)
        tx["touched"] = touched
        write_tx(ns, tx)

        tx["stage"] = "smoke"
        tx["updatedAt"] = utcnow()
        write_tx(ns, tx)
        smoke_result(recipe, target, budget)

        tx["stage"] = "record"
        tx["updatedAt"] = utcnow()
        write_tx(ns, tx)
        record_inventory(project, recipe, "")

        tx["stage"] = "commit-tooling"
        tx["updatedAt"] = utcnow()
        write_tx(ns, tx)
        setup = commit_tooling(target, recipe, touched)
        if setup:
            record_inventory(project, recipe, setup)
        clear_tx(ns)
        clear_baseline_store(ns)
        return emit(
            {
                "ok": True,
                "capabilityId": recipe["capabilityId"],
                "setupCommit": setup,
                "touched": touched,
            },
            0,
        )
    except ValueError as exc:
        code = str(exc) if str(exc) in (
            "global-or-system",
            "paid-or-account",
            "daemon-or-cloud",
            "owner-dirty-conflict",
            "safety-forbidden",
        ) else "incompatible-ecosystem"
        if str(exc) == "global-or-system":
            code = "global-or-system"
        return fail_and_rollback(ns, target, tx, exc, code)
    except Exception as exc:
        return fail_and_rollback(ns, target, tx, exc)


def cmd_rollback(project):
    ns = ns_dir(project)
    tx = load_tx(ns)
    if tx is None:
        return emit({"ok": True, "rolledBack": False, "detail": "no transaction"}, 0)
    target = tx.get("workTarget") or work_target(project)
    rollback_baseline(ns, target, tx.get("baseline") or {})
    clear_tx(ns)
    return emit(
        {
            "ok": True,
            "rolledBack": True,
            "capabilityId": tx.get("capabilityId"),
            "touched": tx.get("touched") or [],
        },
        0,
    )


def cmd_recover(project, budget):
    ns = ns_dir(project)
    tx = load_tx(ns)
    if tx is None:
        return emit({"ok": True, "recovered": False, "detail": "no transaction"}, 0)
    stage = tx.get("stage")
    if tx.get("failed") or stage in (
        "authorize",
        "capture-baseline",
        "apply",
        "smoke",
        "rollback",
    ):
        result = cmd_rollback(project)
        return result
    recipe_path = tx.get("recipePath")
    target = tx.get("workTarget") or work_target(project)
    try:
        recipe = load_recipe(recipe_path) if recipe_path else None
        if recipe is None:
            raise ValueError("missing recipe for recover")
        setup = finish_late_stages(project, recipe, tx, ns, target)
        clear_tx(ns)
        return emit(
            {
                "ok": True,
                "recovered": True,
                "finished": True,
                "capabilityId": recipe["capabilityId"],
                "setupCommit": setup,
                "touched": tx.get("touched") or [],
            },
            0,
        )
    except Exception:
        return cmd_rollback(project)


def usage():
    print(
        "usage: provision.sh --project DIR plan|apply|recover|rollback "
        "[--recipe PATH] [--capability ID] [--budget-seconds N]",
        file=sys.stderr,
    )
    return 1


def need_arg(args, i):
    return i + 1 < len(args) and not args[i + 1].startswith("-")


def main(argv):
    project = None
    recipe = None
    capability = None
    budget = default_budget()
    positional = []
    args = argv[1:]
    i = 0
    while i < len(args):
        a = args[i]
        if a in ("-h", "--help"):
            return usage()
        if a == "--project":
            if not need_arg(args, i):
                return usage()
            project = args[i + 1]
            i += 2
            continue
        if a == "--recipe":
            if not need_arg(args, i):
                return usage()
            recipe = args[i + 1]
            i += 2
            continue
        if a == "--capability":
            if not need_arg(args, i):
                return usage()
            capability = args[i + 1]
            i += 2
            continue
        if a == "--budget-seconds":
            if not need_arg(args, i):
                return usage()
            try:
                budget = int(args[i + 1])
            except ValueError:
                return usage()
            i += 2
            continue
        if a.startswith("-"):
            return usage()
        positional.append(a)
        i += 1
    if not project or not positional:
        return usage()
    project = os.path.abspath(project)
    if not os.path.isdir(project):
        print("provision: not a directory: %s" % project, file=sys.stderr)
        return 1
    cmd = positional[0]
    if cmd == "plan":
        if not recipe:
            return usage()
        return cmd_plan(project, recipe, capability)
    if cmd == "apply":
        if not recipe:
            return usage()
        return cmd_apply(project, recipe, capability, budget)
    if cmd == "recover":
        return cmd_recover(project, budget)
    if cmd == "rollback":
        return cmd_rollback(project)
    return usage()


if __name__ == "__main__":
    sys.exit(main(sys.argv))
