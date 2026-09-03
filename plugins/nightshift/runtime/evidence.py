#!/usr/bin/env python3
"""Versioned evidence ledger. Validates JSON Lines; never claims to verify a Nightshift tick."""
from __future__ import print_function

import hashlib
import json
import os
import re
import sys
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
PLUGIN = os.path.dirname(HERE)
SCHEMA_PATH = os.path.join(
    PLUGIN, "skills", "nightshift", "references", "schemas", "v1", "finding.json"
)
LADDER_RANK = {
    "declared": 0,
    "observed": 1,
    "reproduced": 2,
    "measured": 3,
    "verified-after-change": 4,
    "human-accepted": 5,
}

SECRET = re.compile(
    r"(?i)(api[_-]?key|secret|token|password|authorization:\s*bearer)\s*[:=]\s*\S+"
    r"|-----BEGIN [A-Z ]*PRIVATE KEY-----"
)

EVIDENCE_PREFIX = "evidence: %s"
EVIDENCE_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]*$")


def utcnow():
    fixed = os.environ.get("NIGHTSHIFT_EVIDENCE_NOW")
    if fixed:
        return fixed
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def load_schema():
    with open(SCHEMA_PATH) as fh:
        return json.load(fh)


def ns_dir(project):
    return os.path.join(os.path.abspath(project), ".nightshift")


def ledger_paths(ns):
    evidence = os.path.join(ns, "evidence")
    return {
        "dir": evidence,
        "jsonl": os.path.join(evidence, "findings.jsonl"),
        "md": os.path.join(evidence, "findings.md"),
        "raw": os.path.join(evidence, "raw"),
        "version": os.path.join(evidence, "schema-version"),
    }


def fail(msg, code=2):
    print(EVIDENCE_PREFIX % msg, file=sys.stderr)
    return code


def valid_evidence_id(eid):
    return isinstance(eid, str) and bool(EVIDENCE_ID.match(eid))


def join_leaf(base, name):
    """Join without treating name as a path, even when it looks absolute."""
    if not base:
        return name
    if base.endswith(os.sep):
        return base + name
    return base + os.sep + name


def contained_raw_path(ns, eid):
    """Relative and absolute raw paths under .nightshift/, or None if unsafe."""
    if not valid_evidence_id(eid):
        return None
    raw_dir = os.path.join(ns, "evidence", "raw")
    os.makedirs(raw_dir, exist_ok=True)
    parent = os.path.realpath(raw_dir)
    ns_real = os.path.realpath(ns)
    if parent != ns_real and not parent.startswith(ns_real + os.sep):
        return None
    dest = join_leaf(parent, eid + ".txt")
    dest_parent = os.path.realpath(os.path.dirname(dest))
    if dest_parent != parent:
        return None
    return join_leaf(join_leaf("evidence", "raw"), eid + ".txt"), dest


def digest_text(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def redact_text(text):
    return SECRET.sub("[redacted]", text)


def validate_required_fields(rec, schema):
    errors = []
    if not isinstance(rec, dict):
        return ["record is not an object"]
    for key in schema["required"]:
        if key not in rec:
            errors.append("missing %s" % key)
    return errors


def validate_enum_fields(rec, schema):
    errors = []
    if rec.get("schemaVersion") != 1:
        errors.append("unsupported schemaVersion")
    if rec.get("severity") not in schema["severity"]:
        errors.append("invalid severity")
    if rec.get("confidence") not in schema["confidence"]:
        errors.append("invalid confidence")
    if rec.get("impact") not in schema["impact"]:
        errors.append("invalid impact")
    if rec.get("status") not in schema["status"]:
        errors.append("invalid status")
    if rec.get("ladder") not in schema["ladder"]:
        errors.append("invalid ladder")
    return errors


def validate_locator_and_secrets(rec):
    errors = []
    locator = rec.get("locator") or ""
    if "://" in locator and not rec.get("untrusted"):
        errors.append("remote locator requires untrusted=true")
    raw = json.dumps(rec, sort_keys=True, separators=(",", ":"))
    if SECRET.search(raw):
        errors.append("record contains a secret pattern")
    return errors


def validate_ladder_promotion(rec, prev):
    if prev is None:
        return []
    old_l = prev.get("ladder")
    new_l = rec.get("ladder")
    if old_l in LADDER_RANK and new_l in LADDER_RANK:
        if LADDER_RANK[new_l] > LADDER_RANK[old_l] and rec.get("promoteBy") == "prose":
            return ["ladder must not be promoted by prose"]
    return []


def validate_record(rec, schema, prev=None):
    errors = validate_required_fields(rec, schema)
    if errors:
        return errors
    errors.extend(validate_enum_fields(rec, schema))
    if "id" in rec and not valid_evidence_id(rec.get("id")):
        errors.append("invalid id")
    errors.extend(validate_locator_and_secrets(rec))
    errors.extend(validate_ladder_promotion(rec, prev))
    return errors


def read_records(path):
    if not os.path.isfile(path):
        return []
    out = []
    with open(path) as fh:
        for i, line in enumerate(fh, 1):
            line = line.strip()
            if not line:
                continue
            try:
                out.append(json.loads(line))
            except ValueError:
                raise SystemExit("evidence: malformed JSON on line %s" % i)
    return out


def write_jsonl(path, records):
    tmp = path + ".tmp"
    with open(tmp, "w") as fh:
        for rec in records:
            fh.write(json.dumps(rec, sort_keys=True, separators=(",", ":")) + "\n")
    os.rename(tmp, path)


def cmd_init(project, quiet=False):
    ns = ns_dir(project)
    if not os.path.isdir(ns):
        return fail("no .nightshift/ at %s" % project, 1)
    paths = ledger_paths(ns)
    os.makedirs(paths["raw"], exist_ok=True)
    if not os.path.isfile(paths["jsonl"]):
        open(paths["jsonl"], "a").close()
    if not os.path.isfile(paths["version"]):
        with open(paths["version"], "w") as fh:
            fh.write("1\n")
    if not quiet:
        print(paths["jsonl"])
    return 0


def cmd_validate(project):
    ns = ns_dir(project)
    paths = ledger_paths(ns)
    if not os.path.isfile(paths["jsonl"]):
        print("evidence: no ledger (valid empty workspace)")
        return 0
    schema = load_schema()
    records = read_records(paths["jsonl"])
    by_id = {}
    rc = 0
    for rec in records:
        err = validate_record(rec, schema, by_id.get(rec.get("id")))
        if err:
            rc = 2
            for e in err:
                print(EVIDENCE_PREFIX % ("%s: %s" % (rec.get("id") or "?", e)), file=sys.stderr)
        if rec.get("id"):
            by_id[rec["id"]] = rec
    return rc


def cmd_append(project, record_json, raw_text=None):
    ns = ns_dir(project)
    paths = ledger_paths(ns)
    cmd_init(project, quiet=True)
    rec = json.loads(record_json)
    rec.setdefault("schemaVersion", 1)
    rec.setdefault("firstSeen", utcnow())
    rec.setdefault("lastChecked", rec["firstSeen"])
    rec.setdefault("digest", digest_text(json.dumps(rec, sort_keys=True, separators=(",", ":"))))
    rec.setdefault("action", "")
    rec.setdefault("fix", "")
    rec.setdefault("verificationLocator", "")
    rec.setdefault("disposition", "")
    rec.setdefault("rollback", "")
    rec["source"] = rec.get("source") or rec.get("sourceCommand") or ""
    rec["sourceClass"] = rec.get("sourceClass") or rec.get("sourceTool") or "unknown"
    schema = load_schema()
    records = read_records(paths["jsonl"])
    prev = None
    for existing in records:
        if existing.get("id") == rec.get("id"):
            prev = existing
            break
    errors = validate_record(rec, schema, prev)
    if errors:
        for e in errors:
            print(EVIDENCE_PREFIX % e, file=sys.stderr)
        return 2
    if raw_text:
        contained = contained_raw_path(ns, rec.get("id"))
        if contained is None:
            print(EVIDENCE_PREFIX % "invalid id", file=sys.stderr)
            return 2
        rec["rawPath"] = contained[0]
        raw_abs = contained[1]
        redacted = redact_text(raw_text)
        with open(raw_abs, "w") as fh:
            fh.write(redacted)
            if not redacted.endswith("\n"):
                fh.write("\n")
        rec["rawDigest"] = digest_text(redacted)
    records.append(rec)
    write_jsonl(paths["jsonl"], records)
    print(rec["id"])
    return 0


def cmd_disposition(project, finding_id, disposition, ladder=None):
    ns = ns_dir(project)
    paths = ledger_paths(ns)
    records = read_records(paths["jsonl"])
    found = False
    schema = load_schema()
    for rec in records:
        if rec.get("id") != finding_id:
            continue
        found = True
        prev = dict(rec)
        rec["disposition"] = disposition
        rec["lastChecked"] = utcnow()
        if ladder:
            rec["ladder"] = ladder
        errors = validate_record(rec, schema, prev)
        if errors:
            for e in errors:
                print(EVIDENCE_PREFIX % e, file=sys.stderr)
            return 2
    if not found:
        return fail("unknown id %s" % finding_id)
    write_jsonl(paths["jsonl"], records)
    return 0


def cmd_render(project):
    ns = ns_dir(project)
    paths = ledger_paths(ns)
    records = read_records(paths["jsonl"]) if os.path.isfile(paths["jsonl"]) else []
    lines = [
        "# Evidence ledger",
        "",
        "Machine source: `evidence/findings.jsonl`. Helpers validate records; they do not",
        "verify a Nightshift tick or interpret domain meaning.",
        "",
        "| ID | Domain | Severity | Ladder | Status | Locator |",
        "| --- | --- | --- | --- | --- | --- |",
    ]
    for rec in records:
        lines.append(
            "| %s | %s | %s | %s | %s | %s |"
            % (
                rec.get("id"),
                rec.get("domain"),
                rec.get("severity"),
                rec.get("ladder"),
                rec.get("status"),
                rec.get("locator"),
            )
        )
    if not records:
        lines.append("| — | — | — | — | — | empty |")
    text = "\n".join(lines) + "\n"
    os.makedirs(paths["dir"], exist_ok=True)
    with open(paths["md"], "w") as fh:
        fh.write(text)
    sys.stdout.write(text)
    return 0


def cmd_export_tsv(project):
    ns = ns_dir(project)
    paths = ledger_paths(ns)
    records = read_records(paths["jsonl"]) if os.path.isfile(paths["jsonl"]) else []
    cols = [
        "id",
        "domain",
        "sourceClass",
        "source",
        "scope",
        "severity",
        "confidence",
        "impact",
        "status",
        "ladder",
        "locator",
        "host",
    ]
    print("\t".join(cols))
    for rec in records:
        print("\t".join(str(rec.get(c, "")).replace("\t", " ") for c in cols))
    return 0


def cmd_migrate(project):
    ns = ns_dir(project)
    paths = ledger_paths(ns)
    if not os.path.isdir(paths["dir"]) and not os.path.isfile(paths["jsonl"]):
        print("evidence: nothing to migrate")
        return 0
    version = "0"
    if os.path.isfile(paths["version"]):
        version = open(paths["version"]).read().strip() or "0"
    if version in ("", "0", "1"):
        os.makedirs(paths["raw"], exist_ok=True)
        with open(paths["version"], "w") as fh:
            fh.write("1\n")
        if not os.path.isfile(paths["jsonl"]):
            open(paths["jsonl"], "a").close()
        print("evidence: schema-version 1")
        return 0
    return fail("unsupported evidence schema-version %s" % version)


def usage():
    print(
        "usage: evidence.sh --project DIR "
        "{init|validate|append|disposition|render|export-tsv|migrate} ...",
        file=sys.stderr,
    )
    return 1


def parse_project_and_rest(argv):
    project = None
    args = argv[1:]
    i = 0
    rest = []
    while i < len(args):
        a = args[i]
        if a == "--project":
            if i + 1 >= len(args):
                return None, []
            project = args[i + 1]
            i += 2
            continue
        rest = args[i:]
        break
    return project, rest


def parse_append_args(rest):
    raw = None
    record = None
    j = 1
    while j < len(rest):
        if rest[j] == "--record" and j + 1 < len(rest):
            record = rest[j + 1]
            j += 2
            continue
        if rest[j] == "--raw" and j + 1 < len(rest):
            raw = rest[j + 1]
            j += 2
            continue
        return None, None
    if not record:
        return None, None
    return record, raw


def dispatch_command(project, rest):
    cmd = rest[0]
    if cmd == "init":
        return cmd_init(project)
    if cmd == "validate":
        return cmd_validate(project)
    if cmd == "append":
        record, raw = parse_append_args(rest)
        if not record:
            return usage()
        return cmd_append(project, record, raw)
    if cmd == "disposition":
        if len(rest) < 3:
            return usage()
        ladder = rest[3] if len(rest) > 3 else None
        return cmd_disposition(project, rest[1], rest[2], ladder)
    if cmd == "render":
        return cmd_render(project)
    if cmd == "export-tsv":
        return cmd_export_tsv(project)
    if cmd == "migrate":
        return cmd_migrate(project)
    return usage()


def main(argv):
    project, rest = parse_project_and_rest(argv)
    if not project or not rest:
        return usage()
    return dispatch_command(project, rest)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
