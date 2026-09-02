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
LIB_SH = os.path.join(PLUGIN, "lib", "lib.sh")
EVIDENCE_SH = os.path.join(HERE, "evidence.sh")

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
ELEVATION_CATEGORIES = (
    "sudo",
    "containers",
    "global-packages",
    "daemons",
    "external-services",
)
REFUSAL_REASONS = (
    "policy-not-auto-add",
    "artifact-mode",
    "elevation-denied:sudo",
    "elevation-denied:containers",
    "elevation-denied:global-packages",
    "elevation-denied:daemons",
    "elevation-denied:external-services",
    "incompatible-ecosystem",
    "permission-prompt-required",
    "provisioning-runtime-unavailable",
    "owner-dirty-conflict",
    "safety-forbidden",
)
DENIED_PREFIX = "elevation-denied:"
EVIDENCE_DOMAIN = "provisioning"
EVIDENCE_SOURCE_CLASS = "provisioning-engine"

# The engine authorizes elevation through the same shell functions the command guard uses, so
# the two can never disagree about what a command needs or about what tonight allows.
WORKSPACE_SH = '. "$1"; ns_workspace_root "$2"'
MATCH_SH = r'''. "$1"
patterns="$(ns_policy_elevation_patterns "$2")" || exit 3
while IFS="$(printf '\t')" read -r category pattern; do
  [ -n "$category" ] && [ -n "$pattern" ] || continue
  if ! valid_ere "$pattern"; then
    printf 'invalid\t%s\n' "$category"
    continue
  fi
  printf '%s' "$3" | grep -qE "$pattern" || continue
  ns_policy_allowed "$2" "$category" "$3"
  printf '%s\t%s\n' "$?" "$category"
done <<EOF
$patterns
EOF
exit 0
'''


def utcnow():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


_WORKSPACE = {}


def workspace_root(project):
    """The workspace .nightshift belongs to: the project, or where a .nightshift-link points.

    One authority answers — `ns_workspace_root` in lib/paths.sh, the same function the helpers
    and the guards read — so a linked workspace cannot resolve two ways. A link file that is not
    usable raises: Nightshift does not guess a workspace.
    """
    key = os.path.abspath(project)
    if key in _WORKSPACE:
        return _WORKSPACE[key]
    try:
        out = subprocess.check_output(
            ["bash", "-c", WORKSPACE_SH, "provision", LIB_SH, key],
            stderr=subprocess.DEVNULL,
        )
    except (OSError, subprocess.CalledProcessError):
        raise ValueError("invalid .nightshift-link — Nightshift will not guess a workspace")
    root = out.decode("utf-8", "replace").strip()
    if not root:
        raise ValueError("invalid .nightshift-link — Nightshift will not guess a workspace")
    _WORKSPACE[key] = root
    return root


def ns_dir(project):
    return os.path.join(workspace_root(project), ".nightshift")


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


def contract_list(key, fallback):
    data = load_contract()
    names = (data or {}).get(key)
    if isinstance(names, list) and names and all(isinstance(n, str) and n for n in names):
        return tuple(names)
    return fallback


def elevation_categories():
    return contract_list("elevationCategories", ELEVATION_CATEGORIES)


def refusal_order():
    return contract_list("refusalReasons", REFUSAL_REASONS)


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
    """Tooling policy and elevation from the one resolved view (rules, defaults, tonight)."""
    out = subprocess.check_output(
        ["bash", POLICY_SH, "--project", project, "resolve", "--json"],
        stderr=subprocess.DEVNULL,
    )
    resolved = json.loads(out.decode())
    settings = resolved.get("settings")
    if not isinstance(settings, dict):
        raise ValueError("resolved view has no settings")
    setting = settings.get("toolingPolicy")
    if not isinstance(setting, dict) or not isinstance(setting.get("value"), str):
        raise ValueError("resolved view has no toolingPolicy")
    return {"policy": setting["value"], "refused": False, "settings": settings}


def elevation_setting(settings, category):
    """(value, provenance) for elevation.<category>: allow · deny · exact-plan."""
    row = (settings or {}).get("elevation." + category)
    value = row.get("value") if isinstance(row, dict) else None
    source = row.get("source") if isinstance(row, dict) else None
    if not isinstance(value, str) or not value:
        value = "deny"
    if not isinstance(source, str) or not source:
        source = "built-in"
    return value, source


def command_categories(workspace, command):
    """(status, category) for every elevation pattern this command text matches.

    status is `ns_policy_allowed`'s status as text — 0 allowed, 1 denied, 2 no exact-plan
    allowance binds this command — or `invalid` when the owner's pattern is not an extended
    regular expression the guard can run. Only `0` authorizes the command. The pattern is
    matched before the guard is asked, which is the guard's own contract.
    """
    try:
        p = subprocess.Popen(
            ["bash", "-c", MATCH_SH, "provision", LIB_SH, workspace, command],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )
        out, _ = p.communicate()
    except OSError as exc:
        raise RuntimeError("elevation guard unavailable: %s" % exc)
    if p.returncode != 0:
        raise RuntimeError("elevation guard unavailable: cannot read the elevation patterns")
    rows = []
    for line in out.decode("utf-8", "replace").splitlines():
        if "\t" not in line:
            continue
        status, category = line.split("\t", 1)
        if status and category:
            rows.append((status, category))
    return rows


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


def declared_categories(recipe):
    """The elevation categories the recipe declares, in the contract's order. Absent is empty."""
    raw = recipe.get("elevationCategories")
    if raw is None:
        return []
    if not isinstance(raw, list):
        raise ValueError("elevationCategories must be an array of category names")
    known = elevation_categories()
    for name in raw:
        if not isinstance(name, str) or name not in known:
            raise ValueError("unknown elevation category: %s" % (name,))
    return [name for name in known if name in raw]


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
    declared_categories(data)
    return data


def digest_bytes(data):
    return hashlib.sha256(data).hexdigest()


def digest_file(path):
    with open(path, "rb") as fh:
        return digest_bytes(fh.read())


def norm_rel(rel):
    """One form for a recipe path: forward slashes, no `./` prefix, no leading slash.

    A leading dot that belongs to the filename stays where it is: `.eslintrc.json` is a dotfile,
    not `eslintrc.json`.
    """
    rel = rel.replace("\\", "/")
    while True:
        if rel.startswith("./"):
            rel = rel[2:]
            continue
        if rel.startswith("/"):
            rel = rel[1:]
            continue
        return rel


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


def command_text(spec):
    """The command text of a step, however the recipe spells it. Empty when there is none."""
    if isinstance(spec, dict):
        if isinstance(spec.get("argv"), list):
            return " ".join(str(a) for a in spec["argv"])
        return spec.get("command") or spec.get("cmd") or ""
    if isinstance(spec, list):
        return " ".join(str(a) for a in spec)
    if isinstance(spec, str):
        return spec
    return ""


def addition_commands(recipe):
    adds = recipe.get("packageManagerAdditions") or []
    if isinstance(adds, dict):
        adds = [adds]
    out = []
    if not isinstance(adds, list):
        return out
    for step in adds:
        text = command_text(step)
        if text:
            out.append(text)
    return out


def recipe_commands(recipe):
    """Every command the engine may run: package additions, smoke, rollback."""
    out = []
    for text in addition_commands(recipe):
        if text not in out:
            out.append(text)
    for key in ("smoke", "rollback"):
        text = command_text(recipe.get(key))
        if text and text not in out:
            out.append(text)
    return out


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
    print(json.dumps(doc, sort_keys=True, separators=(",", ":")))
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


def authorize_command(workspace, command):
    """The elevation categories a command needs, once every one of them is authorized.

    Raises ValueError("elevation-denied:<category>") for the first category tonight refuses,
    so a category the recipe never declared cannot slip through on prose.
    """
    needed = []
    for status, category in command_categories(workspace, command):
        if status != "0":
            raise ValueError(DENIED_PREFIX + category)
        if category not in needed:
            needed.append(category)
    return needed


def elevation_denials(recipe, settings, workspace):
    """Elevation categories this shift does not authorize for this recipe.

    Two gates, both from the resolver. Every command the engine may run is matched against every
    category pattern and cleared through the guard, so an undeclared category is caught by the
    command that needs it rather than by the words the recipe chose. Separately, a recipe declares
    the categories it needs and the resolved view answers for each: `allow` runs, `deny` refuses
    whether or not a command shows it, and `exact-plan` runs only while every command that needs
    the category is one the owner's plan binds.
    """
    denied = []
    matches = {}
    for cmd in recipe_commands(recipe):
        for status, category in command_categories(workspace, cmd):
            matches.setdefault(category, []).append(status)
    for category in declared_categories(recipe):
        value, _ = elevation_setting(settings, category)
        if value == "allow":
            continue
        if value == "exact-plan" and all(s == "0" for s in matches.get(category, [])):
            continue
        denied.append(category)
    for category in matches:
        if any(s != "0" for s in matches[category]) and category not in denied:
            denied.append(category)
    return [DENIED_PREFIX + c for c in denied]


def collect_refusals(project, recipe, mode, pol, target):
    reasons = []
    if mode == "artifact":
        reasons.append("artifact-mode")
    if pol.get("policy") != "auto-add" or pol.get("refused"):
        reasons.append("policy-not-auto-add")

    safety = recipe.get("safetyClass")
    if safety == "forbidden" or safety not in SAFE:
        reasons.append("safety-forbidden")

    reasons.extend(
        elevation_denials(recipe, pol.get("settings"), workspace_root(project))
    )

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

    # unique, stable order from the frozen enum; anything outside it keeps its own order
    seen = []
    for code in refusal_order():
        if code in reasons and code not in seen:
            seen.append(code)
    for code in reasons:
        if code not in seen:
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
        "elevationCategories": recipe.get("elevationCategories") or [],
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
    try:
        reasons = collect_refusals(project, recipe, mode, pol, target)
    except RuntimeError as exc:
        return refuse("policy-not-auto-add", str(exc))
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


def host_name():
    """Which host adapter is driving the shift, for the ledger's host column."""
    env = os.environ
    if env.get("CURSOR_PROJECT_DIR") or env.get("CURSOR_WORKSPACE_DIR"):
        return "cursor"
    if env.get("CODEX_PROJECT_DIR") or env.get("CODEX_SANDBOX") or env.get("CODEX_SANDBOX_MODE"):
        return "codex"
    if env.get("CLAUDE_PROJECT_DIR"):
        return "claude"
    return "unknown"


def evidence_run(project, args):
    p = subprocess.Popen(
        ["bash", EVIDENCE_SH, "--project", project] + list(args),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    out, err = p.communicate()
    if p.returncode != 0:
        detail = err.decode("utf-8", "replace").strip() or out.decode("utf-8", "replace").strip()
        raise RuntimeError("receipt refused: %s" % (detail or "evidence helper failed"))
    return out.decode("utf-8", "replace").strip()


def receipt_id(capability, category, index):
    slug = "".join(c if (c.isalnum() or c in "._-") else "-" for c in (capability or "capability"))
    return "provisioning-%s-%s-%d" % (slug, category, index)


def record_elevated(ctx, category, command, rc):
    """One ledger line for one elevated action: category, provenance, and the exact command.

    The line is written the moment the command returns, pass or fail, so an elevated action can
    never run unreceipted. The rung stays `observed` until the smoke verifies the change.
    """
    _, provenance = elevation_setting(ctx["settings"], category)
    ident = receipt_id(ctx["capabilityId"], category, len(ctx["receipts"]) + 1)
    outcome = "exit 0" if rc == 0 else "exit %s" % rc
    record = {
        "id": ident,
        "domain": EVIDENCE_DOMAIN,
        "sourceClass": EVIDENCE_SOURCE_CLASS,
        "source": command,
        "scope": "elevation." + category,
        "category": category,
        "provenance": provenance,
        "severity": "info",
        "confidence": "high",
        "impact": "developer",
        "status": "in-progress",
        "ladder": "observed",
        "locator": ctx["locator"],
        "action": "ran an elevated %s command for %s under provenance %s (%s)"
        % (category, ctx["capabilityId"], provenance, outcome),
        "host": host_name(),
        "workTarget": ctx["workTarget"],
    }
    ctx["receipts"].append(
        evidence_run(ctx["workspace"], ["append", "--record", json.dumps(record, sort_keys=True)])
        or ident
    )


def verify_receipts(ctx):
    """Promote every elevated action's rung once the smoke has passed, and only then."""
    for ident in ctx["receipts"]:
        evidence_run(
            ctx["workspace"],
            ["disposition", ident, "smoke verified the elevated change", "verified-after-change"],
        )


def run_recipe_command(ctx, spec, text, cwd, budget):
    """Authorize, run, and receipt one recipe command, in that order.

    The gate sits where the command runs, so no path through the engine can run one ungated.
    """
    categories = authorize_command(ctx["workspace"], text)
    rc, out = run_cmd(spec, cwd, budget)
    for category in categories:
        record_elevated(ctx, category, text, rc)
    return rc, out


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


def apply_package_adds(ctx, target, recipe, budget):
    adds = recipe.get("packageManagerAdditions") or []
    if isinstance(adds, dict):
        adds = [adds]
    if not isinstance(adds, list):
        raise ValueError("packageManagerAdditions must be an array")
    allowed = recipe["allowedFiles"]
    for step in adds:
        if not isinstance(step, (str, dict)):
            raise ValueError("packageManagerAdditions entry must be a string or object")
        cmd = command_text(step)
        if cmd:
            rc, out = run_recipe_command(ctx, step, cmd, target, budget)
            if rc != 0:
                raise RuntimeError("package add failed: %s" % out.strip())
        if isinstance(step, str):
            continue
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


def smoke_result(ctx, recipe, target, budget):
    """Red baseline (tool ran, reported findings) is success. Exit 127 is not."""
    smoke = recipe.get("smoke")
    rc, out = run_recipe_command(ctx, smoke, command_text(smoke), target, budget)
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
    command = command_text(recipe.get("smoke"))
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
    try:
        reasons = collect_refusals(project, recipe, mode, pol, target)
    except RuntimeError as exc:
        return refuse("policy-not-auto-add", str(exc))
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

    # The workspace, not the project: the guard reads its policy there and the ledger keeps its
    # findings there, so a linked workspace lands both in the same place as the rest of the state.
    ctx = {
        "workspace": workspace_root(project),
        "settings": pol.get("settings"),
        "capabilityId": recipe["capabilityId"],
        "locator": os.path.abspath(recipe_path),
        "workTarget": target,
        "receipts": [],
    }

    try:
        tx["stage"] = "apply"
        tx["updatedAt"] = utcnow()
        write_tx(ns, tx)
        apply_package_adds(ctx, target, recipe, budget)
        apply_config(target, recipe)
        touched = changed_allowed(target, baseline)
        tx["touched"] = touched
        write_tx(ns, tx)

        tx["stage"] = "smoke"
        tx["updatedAt"] = utcnow()
        write_tx(ns, tx)
        smoke_result(ctx, recipe, target, budget)
        verify_receipts(ctx)

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
        code = str(exc)
        if not code.startswith(DENIED_PREFIX) and code not in (
            "owner-dirty-conflict",
            "safety-forbidden",
        ):
            code = "incompatible-ecosystem"
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
        clear_baseline_store(ns)
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
    try:
        workspace_root(project)
    except ValueError as exc:
        print("provision: %s" % exc, file=sys.stderr)
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
