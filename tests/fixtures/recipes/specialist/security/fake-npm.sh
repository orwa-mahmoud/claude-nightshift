#!/bin/sh
# fake-npm.sh — npm stand-in for specialist security and dead-code recipe fixtures.
#
#   NS_FAKE_MODE=green      audit and install succeed with clean output
#   NS_FAKE_MODE=findings   npm audit reports advisories; knip reports unused exports
#   NS_FAKE_MODE=missing    every invocation is a PATH miss
set -u
tool="${0##*/}"
mode="${NS_FAKE_MODE:-green}"

if [ -n "${NS_FAKE_LOG:-}" ]; then
  if [ "$#" -eq 0 ]; then
    printf '%s\n' "$tool" >>"$NS_FAKE_LOG"
  else
    printf '%s %s\n' "$tool" "$*" >>"$NS_FAKE_LOG"
  fi
fi

not_found() {
  printf '%s: command not found\n' "$tool" >&2
  exit 127
}

[ "$mode" != missing ] || not_found

case "$tool" in
  node)
    printf 'v20.11.0\n'
    exit 0
    ;;
esac

[ "$tool" = npm ] || not_found

sub="${1:-}"
shift || true

case "$sub" in
  audit)
    if [ "$mode" = findings ]; then
      printf '%s\n' '{"vulnerabilities":{"semver":{"name":"semver","severity":"moderate","via":["GHSA-c2qf-rxjj-qqgw"],"effects":[],"range":">=7.0.0 <7.5.2","nodes":["node_modules/semver"],"fixAvailable":{"name":"semver","version":"7.5.4","isSemVerMajor":false}}},"metadata":{"vulnerabilities":{"info":0,"low":0,"moderate":1,"high":0,"critical":0,"total":1}}}'
      exit 1
    fi
    printf '%s\n' '{"vulnerabilities":{},"metadata":{"vulnerabilities":{"info":0,"low":0,"moderate":0,"high":0,"critical":0,"total":0}}}'
    exit 0
    ;;
  install)
    exit 0
    ;;
  uninstall)
    exit 0
    ;;
  exec)
    inner="${1:-}"
    shift || true
    case "$inner" in
      knip)
        if [ "$mode" = findings ]; then
          printf '%s\n' 'Unused file: orphan.js'
          exit 1
        fi
        printf '%s\n' 'no findings'
        exit 0
        ;;
    esac
    not_found
    ;;
  help)
    exit 0
    ;;
  view)
    exit 0
    ;;
esac

printf 'npm %s: unknown command\n' "$sub" >&2
exit 127
