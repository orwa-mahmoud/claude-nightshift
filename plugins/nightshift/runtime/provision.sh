#!/usr/bin/env bash
# provision.sh — transactional Auto-add engine.
#
#   provision.sh --project DIR plan|apply|recover|rollback \
#     [--recipe PATH] [--capability ID] [--budget-seconds N]
#
# Stages: authorize → capture-baseline → apply → smoke → record → commit-tooling
# Incomplete work is recorded only in .nightshift/provision-transaction.json.
# recover and rollback are native bash: provision-recover.sh settles the transaction and
# proves the restore, so a workspace is never left half-installed for want of a runtime.
# Never writes the punch list. Never pushes.
# Exit: 0 ok · 1 usage/runtime failure · 2 refused, or a malformed transaction naming the
#       field · 3 the restore is unproven
set -u
_here="${BASH_SOURCE[0]%/*}"
[ "$_here" != "${BASH_SOURCE[0]}" ] || _here=.

# recover and rollback keep their place on the CLI; the work happens next door.
_project=""
_budget=""
_verb=""
_engine=0
_argv=("$@")
_n=$#
_i=0
while [ "$_i" -lt "$_n" ]; do
  case "${_argv[$_i]}" in
    --project)
      _i=$((_i + 1))
      if [ "$_i" -lt "$_n" ]; then _project="${_argv[$_i]}"; else _engine=1; fi
      ;;
    --budget-seconds)
      _i=$((_i + 1))
      if [ "$_i" -lt "$_n" ]; then _budget="${_argv[$_i]}"; else _engine=1; fi
      ;;
    --recipe | --capability)
      _i=$((_i + 1))
      [ "$_i" -lt "$_n" ] || _engine=1
      ;;
    recover | rollback)
      if [ -z "$_verb" ]; then _verb="${_argv[$_i]}"; else _engine=1; fi
      ;;
    *) _engine=1 ;;
  esac
  _i=$((_i + 1))
done

if [ "$_engine" -eq 0 ] && [ -n "$_verb" ] && [ -n "$_project" ]; then
  set -- --project "$_project"
  [ -z "$_budget" ] || set -- "$@" --budget-seconds "$_budget"
  [ "$_verb" != rollback ] || set -- "$@" --rollback
  exec bash "$_here/provision-recover.sh" "$@"
fi

exec python3 "$_here/provision.py" "$@"
