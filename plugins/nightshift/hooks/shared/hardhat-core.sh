#!/usr/bin/env bash
# Shared hardhat decisions. Host wrappers own payload parsing and deny response emission.

ns_hardhat_active() {
  [ -f "$NS/.shift-armed" ] && [ -f "$PUNCH" ] && [ ! -f "$ENDED" ] \
    && [ "$(ns_open_boxes "$PUNCH")" -gt 0 ]
}

ns_hardhat_binding_probe() { # $1 = canonical tool name, $2 = command
  [ "$1" = "Bash" ] && [ "$2" = ": nightshift-binding-probe" ]
}

ns_hardhat_rules_targeted() {
  local normalized
  normalized="$(printf '%s' "$1" | sed 's#\\/#/#g')"
  printf '%s' "$normalized" | grep -qE '\.nightshift/rules\.json|nightshift-rules\.json' \
    || {
      printf '%s' "$normalized" | grep -q '\.nightshift' \
        && printf '%s' "$normalized" | grep -q 'rules\.json'
    }
}

ns_hardhat_lease_targeted() {
  local normalized nightshift_context=0
  normalized="$(printf '%s' "$1" | sed "s#\\\\/#/#g; s#[\"']##g")"
  if printf '%s' "$normalized" |
      grep -qE '(^|/)(\.shift-lease|\.mutex-scope)($|[^[:alnum:]_-])|(^|/)\.lease-lock\.d($|/)'; then
    return 0
  fi
  case "$normalized" in *'.nightshift/'*) nightshift_context=1 ;; esac
  if printf '%s' "$normalized" |
      grep -qE '(^|[;&|()[:space:]])(cd|pushd)[[:space:]]+([^;&|()[:space:]]*/)?\.nightshift/?([;&|()[:space:]]|$)'; then
    nightshift_context=1
  fi
  if [ "$nightshift_context" -eq 1 ]; then
    case "$normalized" in
      *'.shift-*'* | *'.shift-?'* | *'.shift-['* | *'.shift-{'* | *'.shift-$'* | *'.shift-`'* \
        | *'.lease-*'* | *'.lease-?'* | *'.lease-['* | *'.lease-{'* | *'.lease-$'* | *'.lease-`'* \
        | *'.mutex-*'* | *'.mutex-?'* | *'.mutex-['* | *'.mutex-{'* | *'.mutex-$'* | *'.mutex-`'* \
        | *'.nightshift/*'* | *'.nightshift/.*'* | *'.nightshift/.?'* \
        | *'{'*'shift-lease'* | *'{'*'lease-lock'* | *'{'*'mutex-scope'* ) return 0 ;;
    esac
  fi
  if printf '%s' "$normalized" | grep -qE '(^|[;&|[:space:]])(rm|rmdir|unlink|mv)([[:space:]]|$)' \
    && printf '%s' "$normalized" | grep -qE '(^|[[:space:]])(\./)?\.nightshift/?([[:space:]]|$)'; then
    return 0
  fi
  if printf '%s' "$normalized" | grep -qE '(^|[;&|[:space:]])find([[:space:]]|$)' \
    && printf '%s' "$normalized" | grep -qE '(^|[[:space:]])(\./)?\.nightshift/?([[:space:]]|$)' \
    && printf '%s' "$normalized" | grep -qE '(^|[[:space:]])(-delete|-exec)([[:space:]]|$)'; then
    return 0
  fi
  return 1
}

ns_hardhat_payload_targets() { # $1 = tool, $2 = raw payload, $3 = command/patch, $4 = predicate
  local targets="" predicate="$4" decoder="" encoded record_type
  case "$1" in
    Bash | PowerShell)
      "$predicate" "$3"
      return
      ;;
    apply_patch)
      targets="$(printf '%s\n' "$3" \
        | grep -E '^\*\*\* (Add|Update|Delete) File:|^\*\*\* Move to:' 2>/dev/null || true)"
      ;;
    *)
      if command -v jq >/dev/null 2>&1; then
        targets="$(printf '%s' "$2" | jq -r '
          def string_values: .. | strings;
          .tool_input
          | ..
          | objects
          | . as $object
          | (
              (
                $object
                | to_entries[]
                | select(.key | test("((^|_)(path|filepath|file|filename|directory|dir|uri|name)$|^(target|destination|dest|source|src)$)"; "i"))
                | .value
                | string_values
                | if contains("\n") then @base64 | "P\t\(.)" else "p\t\(.)" end
              ),
              (
                $object
                | to_entries[]
                | select(.key | test("(^|_)(command|cmd|script)$"; "i"))
                | .value
                | string_values
                | if contains("\n") then @base64 | "C\t\(.)" else "c\t\(.)" end
              ),
              (
                [$object | to_entries[] | select(.key | test("^(directory|dir)$"; "i")) | .value | string_values] as $dirs
                | [$object | to_entries[] | select(.key | test("^(name|filename|file)$"; "i")) | .value | string_values] as $names
                | $dirs[] as $dir
                | $names[] as $name
                | "\($dir)/\($name)"
                | if contains("\n") then @base64 | "P\t\(.)" else "p\t\(.)" end
              )
            )
        ' 2>/dev/null)" || return 2
        decoder=jq
      elif command -v python3 >/dev/null 2>&1; then
        targets="$(printf '%s' "$2" | python3 -c 'import base64,json,re,sys
d=json.load(sys.stdin).get("tool_input",{})
k=re.compile(r"((^|_)(path|filepath|file|filename|directory|dir|uri|name)$|^(target|destination|dest|source|src)$)",re.I)
c=re.compile(r"(^|_)(command|cmd|script)$",re.I)
def emit(kind,item):
    if "\n" in item:
        encoded=base64.b64encode(item.encode()).decode()
        print(f"{kind.upper()}\t{encoded}")
    else:
        print(f"{kind.lower()}\t{item}")
def strings(v):
    out=[]
    if isinstance(v,str): out.append(v)
    elif isinstance(v,list):
        for x in v: out.extend(strings(x))
    elif isinstance(v,dict):
        for x in v.values(): out.extend(strings(x))
    return out
def walk(v):
    if isinstance(v,dict):
        dirs=[]
        names=[]
        for key,value in v.items():
            values=strings(value)
            if c.search(key):
                for item in values: emit("C",item)
            elif k.search(key):
                for item in values: emit("P",item)
            if re.fullmatch(r"(directory|dir)",key,re.I): dirs.extend(values)
            if re.fullmatch(r"(name|filename|file)",key,re.I): names.extend(values)
            walk(value)
        for directory in dirs:
            for name in names: emit("P",f"{directory}/{name}")
    elif isinstance(v,list):
        for x in v: walk(x)
walk(d)' 2>/dev/null)" || return 2
        decoder=python3
      else
        return 2
      fi
      ;;
  esac
  while IFS= read -r target; do
    [ -n "$target" ] || continue
    if [ -n "$decoder" ]; then
      case "$target" in
        p$'\t'*) target="${target#*$'\t'}" ;;
        c$'\t'*) target="$(ns_hardhat_scrub "${target#*$'\t'}")" ;;
        P$'\t'* | C$'\t'*)
          record_type="${target%%$'\t'*}"
          encoded="${target#*$'\t'}"
          if [ "$decoder" = "jq" ]; then
            target="$(
              printf '%s' "$encoded" | jq -jRr '@base64d' 2>/dev/null || exit
              printf '\034'
            )" || return 2
          else
            target="$(python3 -c 'import base64,sys
sys.stdout.buffer.write(base64.b64decode(sys.argv[1])+b"\x1c")' "$encoded" 2>/dev/null)" || return 2
          fi
          target="${target%$'\034'}"
          if [ "$record_type" = "C" ]; then
            target="$(
              ns_hardhat_scrub "$target"
              printf '\034'
            )"
            target="${target%$'\034'}"
          fi
          ;;
        *) return 2 ;;
      esac
    fi
    if "$predicate" "$target"; then return 0; fi
  done <<<"$targets"
  return 1
}

ns_hardhat_payload_targets_rules() {
  ns_hardhat_payload_targets "$1" "$2" "$3" ns_hardhat_rules_targeted
}

ns_hardhat_payload_targets_lease() {
  local rc
  ns_hardhat_payload_targets "$1" "$2" "$3" ns_hardhat_lease_targeted
  rc=$?
  [ "$rc" -eq 0 ] && return 0
  [ "$rc" -eq 2 ] || return 1
  # Start requires jq or python3. If that parser disappears mid-shift, unknown local tools fail
  # closed rather than letting a helper conversation address the lease through an opaque payload.
  case "$1" in
    AskUserQuestion | request_user_input | WebFetch | WebSearch | Task | TodoWrite) return 1 ;;
    *) return 0 ;;
  esac
}

ns_hardhat_scrub() {
  local input="$1" output="" length i=0 j k option_length quote char previous next dynamic closed
  length="${#input}"
  while [ "$i" -lt "$length" ]; do
    char="${input:$i:1}"
    if [ "$i" -eq 0 ]; then previous=""; else previous="${input:$((i - 1)):1}"; fi
    option_length=0
    case "$previous" in
      '' | ' ' | $'\t' | $'\n')
        if [ "${input:$i:9}" = "--message" ]; then
          next="${input:$((i + 9)):1}"
          case "$next" in '' | '=' | ' ' | $'\t' | $'\n' | "'" | '"') option_length=9 ;; esac
        elif [ "${input:$i:2}" = "-m" ]; then
          next="${input:$((i + 2)):1}"
          case "$next" in '' | '=' | ' ' | $'\t' | $'\n' | "'" | '"') option_length=2 ;; esac
        fi
        ;;
    esac
    if [ "$option_length" -eq 0 ]; then
      output="${output}${char}"
      i=$((i + 1))
      continue
    fi

    j=$((i + option_length))
    [ "${input:$j:1}" = "=" ] && j=$((j + 1))
    while [ "$j" -lt "$length" ]; do
      case "${input:$j:1}" in ' ' | $'\t' | $'\n') j=$((j + 1)) ;; *) break ;; esac
    done
    quote="${input:$j:1}"
    case "$quote" in
      "'")
        k=$((j + 1))
        while [ "$k" -lt "$length" ] && [ "${input:$k:1}" != "'" ]; do k=$((k + 1)); done
        if [ "$k" -lt "$length" ]; then
          output="${output}${input:$i:$((j - i))}MSG"
          i=$((k + 1))
          continue
        fi
        ;;
      '"')
        k=$((j + 1))
        dynamic=0
        closed=0
        while [ "$k" -lt "$length" ]; do
          char="${input:$k:1}"
          if [ "$char" = "\\" ]; then
            k=$((k + 2))
            continue
          fi
          if [ "$char" = '"' ]; then closed=1; break; fi
          if [ "$char" = '`' ] \
            || { [ "$char" = '$' ] && [ "${input:$((k + 1)):1}" = '(' ]; }; then
            dynamic=1
          fi
          k=$((k + 1))
        done
        if [ "$closed" -eq 1 ]; then
          if [ "$dynamic" -eq 1 ]; then
            output="${output}${input:$i:$((k - i + 1))}"
          else
            output="${output}${input:$i:$((j - i))}MSG"
          fi
          i=$((k + 1))
          continue
        fi
        ;;
    esac
    output="${output}${input:$i:1}"
    i=$((i + 1))
  done
  printf '%s' "$output"
}

ns_hardhat_rules_has() {
  [ -n "${TOOL_RULES:-}" ] || return 1
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$TOOL_RULES" | jq -e --arg t "$1" 'has($t)' >/dev/null 2>&1
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$TOOL_RULES" | python3 -c 'import json,sys
d=json.load(sys.stdin)
sys.exit(0 if sys.argv[1] in d else 1)' "$1" >/dev/null 2>&1
  else
    return 1
  fi
}

ns_hardhat_rules_msg() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$TOOL_RULES" | jq -r --arg t "$1" '.[$t] // empty' 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$TOOL_RULES" | python3 -c 'import json,sys
d=json.load(sys.stdin)
print(d.get(sys.argv[1],""))' "$1" 2>/dev/null
  else
    return 1
  fi
}

ns_hardhat_tool_deny_broken() {
  [ -n "${TOOL_RULES:-}" ] || return 1
  case "$TOOL_RULES" in
    __nightshift_invalid_tool_rules__ | __nightshift_tool_rules_parser_missing__) return 0 ;;
  esac
  if command -v jq >/dev/null 2>&1; then
    ! printf '%s' "$TOOL_RULES" | jq -e 'type == "object" and all(.[]; type == "string")' >/dev/null 2>&1
  elif command -v python3 >/dev/null 2>&1; then
    ! printf '%s' "$TOOL_RULES" | python3 -c 'import json,sys
d=json.load(sys.stdin)
sys.exit(0 if isinstance(d,dict) and all(isinstance(v,str) for v in d.values()) else 1)' >/dev/null 2>&1
  else
    return 0
  fi
}

ns_hardhat_tool_deny_reason() {
  local m
  [ -n "$1" ] && ns_hardhat_rules_has "$1" || return 1
  m="$(ns_hardhat_rules_msg "$1")"
  [ -n "$m" ] || return 1
  printf '%s' "$m"
}

ns_hardhat_required_tool_deny_reason() {
  if ! ns_hardhat_rules_has "$1"; then
    printf '%s' "BLOCKED: toolDeny is missing the required '$1' entry. Add that exact host tool name to .nightshift/rules.json with a denial message, or use an empty string to allow it; run Setup again (/nightshift:setup on Claude Code; ask Nightshift to set up on Codex) to review the current template."
    return 0
  fi
  ns_hardhat_tool_deny_reason "$1"
}

ns_hardhat_git_verb() {
  printf '%s' "$1" | grep -qE "(^|[^[:alnum:]_-])git([^[:alnum:]]|$)" \
    && printf '%s' "$1" | grep -qE "(^|[^[:alnum:]_-])$2([^[:alnum:]]|$)"
}

ns_hardhat_is_git_write() {
  ns_hardhat_git_verb "$1" add || ns_hardhat_git_verb "$1" commit \
    || ns_hardhat_git_verb "$1" tag || ns_hardhat_git_verb "$1" remote
}

ns_hardhat_is_commit() {
  ns_hardhat_git_verb "$1" commit
}

# Print a deny reason for a Bash-like command, or return 1 to allow.
# Uses globals: SCRUBBED CMD CWD PROJECT_DIR PROTECTED_DIRS EXPECTED_EMAIL
# NEVER_COMMIT_PATTERNS FORBIDDEN_COMMANDS
ns_hardhat_command_reason() {
  local _p _name _pat d _tok _dirs _toks REPO email _scope _diff
  for _p in "FORBIDDEN_COMMANDS:$FORBIDDEN_COMMANDS" "NEVER_COMMIT_PATTERNS:$NEVER_COMMIT_PATTERNS"; do
    _name="${_p%%:*}"
    _pat="${_p#*:}"
    [ -n "$_pat" ] || continue
    valid_ere "$_pat" || {
      printf '%s' "BLOCKED: NIGHTSHIFT_$_name is not a valid extended regular expression, so the guard it configures cannot run. Fix the pattern in your session settings."
      return 0
    }
  done

  if [ -n "$PROTECTED_DIRS" ] && ns_hardhat_is_git_write "$SCRUBBED"; then
    IFS=' |' read -ra _dirs <<<"$PROTECTED_DIRS"
    read -ra _toks <<<"$SCRUBBED"
    for d in "${_dirs[@]}"; do
      [ -n "$d" ] || continue
      for _tok in "${_toks[@]}"; do
        case "$_tok" in
          "$d" | "$d"/* | */"$d" | */"$d"/* | *="$d" | *="$d"/*)
            printf '%s' "BLOCKED: never git add/commit/tag/remote inside '$d' (a protected directory). Do not retry a rephrased form."
            return 0
            ;;
        esac
      done
    done
  fi

  if ns_hardhat_is_commit "$SCRUBBED" && { [ -n "$EXPECTED_EMAIL" ] || [ -n "$NEVER_COMMIT_PATTERNS" ]; }; then
    if printf '%s' "$SCRUBBED" | grep -qE -- '--git-dir|--work-tree'; then
      printf '%s' "BLOCKED: --git-dir/--work-tree point this commit somewhere the configured commit guards cannot verify. Run the commit from inside the repository instead."
      return 0
    fi
    if [ -n "$EXPECTED_EMAIL" ] && printf '%s' "$SCRUBBED" |
      grep -qE -- '-c[[:space:]]*user\.email=|--author|GIT_(AUTHOR|COMMITTER)_EMAIL='; then
      printf '%s' "BLOCKED: this commit overrides the author identity on the command line, which the expected-identity guard cannot verify. Commit with the repository's configured identity."
      return 0
    fi
    REPO="$(target_repo "$CMD" "${CWD:-$PROJECT_DIR}")"
    case "$?" in
      1) printf '%s' "BLOCKED: this commit names a directory that is not a git repository, so the configured commit guards cannot inspect it. Do not retry a rephrased form."
         return 0 ;;
      2) REPO="$(repo_root "$PROJECT_DIR" "$CWD")" || REPO="$(ns_work_target "$PROJECT_DIR")" || {
           printf '%s' "BLOCKED: cannot tell which git repository this commit targets, so the configured commit guards cannot run. Run the commit from inside the repository."
           return 0
         } ;;
    esac
    if [ -n "$EXPECTED_EMAIL" ]; then
      email="$(git -C "$REPO" config user.email 2>/dev/null || true)"
      if [ "$email" != "$EXPECTED_EMAIL" ]; then
        printf '%s' "BLOCKED: committer identity ('$email') is not the expected '$EXPECTED_EMAIL'. Fix git config user.email, then retry."
        return 0
      fi
    fi
    if [ -n "$NEVER_COMMIT_PATTERNS" ]; then
      if commit_stages_implicitly "$CMD"; then
        _scope="the diff this commit would write"
        _diff="$(git -C "$REPO" diff HEAD 2>/dev/null)"
      else
        _scope="the staged diff"
        _diff="$(git -C "$REPO" diff --cached 2>/dev/null)"
      fi
      if printf '%s' "$_diff" | grep -qiE "$NEVER_COMMIT_PATTERNS"; then
        printf '%s' "BLOCKED: $_scope matches a never-commit pattern. Remove it, restage, retry. Do not weaken the pattern list."
        return 0
      fi
    fi
  fi

  if [ -n "$FORBIDDEN_COMMANDS" ] && printf '%s' "$SCRUBBED" | grep -qE "$FORBIDDEN_COMMANDS"; then
    printf '%s' "BLOCKED: the command matches the owner's forbidden list for this shift. Find another way, or park the task with a note in .nightshift/parking-lot.md and keep working. Do not retry a rephrased form."
    return 0
  fi
  return 1
}
