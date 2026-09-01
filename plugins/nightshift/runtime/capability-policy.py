#!/usr/bin/env python3
"""Owner capability policy and inventory cache. Never writes the punch list.

Inventory is a cache the caller re-probes. Storing a row is not proof a tick is
valid, and this helper does not install or provision tools.
"""
from __future__ import print_function

import json
import os
import sys
from datetime import datetime, timezone

POLICIES = ("existing-tools", "auto-add", "review-missing")
DEFAULT = "existing-tools"
REPOSITORY_TOOL_POLICIES = ("auto-add", "review-missing")
ITEM_FIELDS = (
    "capability",
    "command",
    "source",
    "verifiedAt",
    "configFiles",
    "recipeVersion",
    "setupCommit",
)


def utcnow():
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def ns_dir(project):
    return os.path.join(os.path.abspath(project), ".nightshift")


def policy_path(ns):
    return os.path.join(ns, "capability-policy.json")


def inventory_path(ns):
    return os.path.join(ns, "capabilities.json")


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


def schema_ok(value):
    return value in (1, "1", None)


def default_policy(source, updated_at=None, stored=DEFAULT):
    return {
        "schemaVersion": 1,
        "policy": DEFAULT,
        "remember": True,
        "source": source,
        "updatedAt": updated_at,
        "stored": stored,
    }


def load_policy(project):
    path = policy_path(ns_dir(project))
    if not os.path.isfile(path):
        return default_policy("default")
    try:
        data = read_json(path)
    except (OSError, ValueError):
        return default_policy("malformed")
    if not isinstance(data, dict):
        return default_policy("malformed")
    if not schema_ok(data.get("schemaVersion")):
        return default_policy("malformed")
    stored = data.get("policy")
    remember = data.get("remember", True)
    if not isinstance(remember, bool):
        remember = True
    updated = data.get("updatedAt")
    if updated is not None and not isinstance(updated, str):
        updated = None
    if stored not in POLICIES:
        return default_policy("malformed", updated, stored)
    return {
        "schemaVersion": 1,
        "policy": stored,
        "remember": remember,
        "source": "file",
        "updatedAt": updated,
        "stored": stored,
    }


def effective_policy(project, work_mode):
    data = load_policy(project)
    policy = data["policy"]
    refused = False
    if work_mode == "artifact" and data.get("source") == "file" and policy in REPOSITORY_TOOL_POLICIES:
        refused = True
        policy = DEFAULT
    return policy, refused, data


def require_ns(project):
    ns = ns_dir(project)
    if not os.path.isdir(ns):
        print("capability-policy: no .nightshift/", file=sys.stderr)
        return None
    return ns


def save_policy(project, policy, remember=True):
    if policy not in POLICIES:
        print("capability-policy: unknown policy %s" % policy, file=sys.stderr)
        return 2
    ns = require_ns(project)
    if ns is None:
        return 1
    doc = {
        "schemaVersion": 1,
        "policy": policy,
        "remember": bool(remember),
        "updatedAt": utcnow(),
    }
    path = policy_path(ns)
    atomic_write(path, doc)
    print(path)
    return 0


def empty_inventory(source):
    return {
        "schemaVersion": 1,
        "source": source,
        "items": [],
        "updatedAt": None,
        "tickProof": False,
    }


def normalize_item(item):
    if isinstance(item, str):
        return {"capability": item}
    if not isinstance(item, dict):
        return None
    out = {}
    for key in ITEM_FIELDS:
        if key in item:
            out[key] = item[key]
    for key, val in item.items():
        if key not in out:
            out[key] = val
    return out


def load_inventory(project):
    path = inventory_path(ns_dir(project))
    if not os.path.isfile(path):
        return empty_inventory("default")
    try:
        data = read_json(path)
    except (OSError, ValueError):
        return empty_inventory("malformed")
    if isinstance(data, list):
        data = {"items": data}
    if not isinstance(data, dict):
        return empty_inventory("malformed")
    if not schema_ok(data.get("schemaVersion")):
        return empty_inventory("malformed")
    items = data.get("items")
    if items is None:
        items = []
    if not isinstance(items, list):
        return empty_inventory("malformed")
    out = dict(data)
    out["schemaVersion"] = 1
    out["source"] = "file"
    out["items"] = items
    out["tickProof"] = False
    return out


def save_inventory(project, inventory_json):
    ns = require_ns(project)
    if ns is None:
        return 1
    try:
        raw = json.loads(inventory_json)
    except ValueError:
        print("capability-policy: inventory is not JSON", file=sys.stderr)
        return 2
    if isinstance(raw, list):
        raw = {"items": raw}
    if not isinstance(raw, dict):
        print("capability-policy: inventory must be an object or array", file=sys.stderr)
        return 2
    items = raw.get("items")
    if items is None:
        items = []
    if not isinstance(items, list):
        print("capability-policy: items must be an array", file=sys.stderr)
        return 2
    normalized = []
    for item in items:
        row = normalize_item(item)
        if row is None:
            print("capability-policy: inventory item must be an object", file=sys.stderr)
            return 2
        normalized.append(row)
    doc = dict(raw)
    doc["schemaVersion"] = 1
    doc["items"] = normalized
    doc["updatedAt"] = utcnow()
    doc["tickProof"] = False
    path = inventory_path(ns)
    atomic_write(path, doc)
    print(path)
    return 0


def inspect_version(path, kind):
    if not os.path.isfile(path):
        return "absent"
    try:
        data = read_json(path)
    except (OSError, ValueError):
        return "malformed"
    if kind == "inventory" and isinstance(data, list):
        return 1
    if not isinstance(data, dict):
        return "malformed"
    version = data.get("schemaVersion", 1)
    if not schema_ok(version):
        return version
    if kind == "policy" and data.get("policy") not in POLICIES:
        return "malformed"
    if kind == "inventory" and "items" in data and not isinstance(data.get("items"), list):
        return "malformed"
    return 1


def cmd_migrate(project):
    ns = ns_dir(project)
    policy = inspect_version(policy_path(ns), "policy")
    inventory = inspect_version(inventory_path(ns), "inventory")
    for label, kind in (("policy", policy), ("inventory", inventory)):
        if kind not in ("absent", "malformed", 1):
            print(
                "capability-policy: unsupported %s schema-version %s" % (label, kind),
                file=sys.stderr,
            )
            return 2
    if policy == "absent" and inventory == "absent":
        print("capability-policy: nothing to migrate")
        return 0
    parts = []
    if policy == "absent":
        parts.append("policy absent (valid default)")
    elif policy == "malformed":
        parts.append("policy malformed (left in place)")
    else:
        parts.append("policy schema-version 1")
    if inventory == "absent":
        parts.append("inventory absent (valid empty cache)")
    elif inventory == "malformed":
        parts.append("inventory malformed (left in place)")
    else:
        parts.append("inventory schema-version 1")
    print("capability-policy: %s" % "; ".join(parts))
    return 0


def emit_get(project, work_mode):
    eff, refused, data = effective_policy(project, work_mode)
    print(
        json.dumps(
            {
                "policy": eff,
                "refused": refused,
                "remember": data.get("remember"),
                "schemaVersion": 1,
                "source": data.get("source"),
                "stored": data.get("stored"),
                "updatedAt": data.get("updatedAt"),
                "workMode": work_mode,
            },
            sort_keys=True,
        )
    )
    return 0


def emit_inventory(project):
    data = load_inventory(project)
    print(json.dumps(data, sort_keys=True))
    return 0


def parse_remember(value):
    return value.lower() not in ("false", "0", "no")


def usage():
    print(
        "usage: capability-policy.sh --project DIR "
        "get|set|inventory|migrate [--policy NAME] [--work-mode MODE] "
        "[--remember true|false] [--record JSON]",
        file=sys.stderr,
    )
    return 1


def main(argv):
    project = None
    work_mode = "repository"
    policy = None
    remember = True
    record = None
    positional = []
    args = argv[1:]
    i = 0
    while i < len(args):
        a = args[i]
        if a in ("-h", "--help"):
            return usage()
        if a == "--project":
            if i + 1 >= len(args):
                return usage()
            project = args[i + 1]
            i += 2
            continue
        if a == "--work-mode":
            if i + 1 >= len(args):
                return usage()
            work_mode = args[i + 1]
            i += 2
            continue
        if a == "--policy":
            if i + 1 >= len(args):
                return usage()
            policy = args[i + 1]
            i += 2
            continue
        if a == "--remember":
            if i + 1 >= len(args):
                return usage()
            remember = parse_remember(args[i + 1])
            i += 2
            continue
        if a == "--record":
            if i + 1 >= len(args):
                return usage()
            record = args[i + 1]
            i += 2
            continue
        if a.startswith("-"):
            return usage()
        positional.append(a)
        i += 1
    if not project:
        return usage()
    cmd = positional[0] if positional else "get"
    rest = positional[1:]
    if cmd == "get":
        return emit_get(project, work_mode)
    if cmd == "set":
        if not policy:
            return usage()
        return save_policy(project, policy, remember)
    if cmd == "inventory":
        action = rest[0] if rest else ("set" if record is not None else "get")
        if action == "get":
            return emit_inventory(project)
        if action == "set":
            payload = record
            if payload is None and len(rest) > 1:
                payload = rest[1]
            if payload is None:
                return usage()
            return save_inventory(project, payload)
        if rest and rest[0].lstrip()[:1] in "{[":
            return save_inventory(project, rest[0])
        return usage()
    if cmd == "migrate":
        return cmd_migrate(project)
    return usage()


if __name__ == "__main__":
    sys.exit(main(sys.argv))
