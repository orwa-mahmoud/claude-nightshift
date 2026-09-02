#!/bin/sh
# fake-vulture.sh — vulture stand-in for the Python dead-code recipe fixture.
#
#   NS_FAKE_MODE=green      no unused code
#   NS_FAKE_MODE=findings   reports one unused function
#   NS_FAKE_MODE=missing    PATH miss
set -u
mode="${NS_FAKE_MODE:-green}"

if [ -n "${NS_FAKE_LOG:-}" ]; then
  if [ "$#" -eq 0 ]; then
    printf 'vulture\n' >>"$NS_FAKE_LOG"
  else
    printf 'vulture %s\n' "$*" >>"$NS_FAKE_LOG"
  fi
fi

if [ "$mode" = missing ]; then
  printf 'vulture: command not found\n' >&2
  exit 127
fi

if [ "$mode" = findings ]; then
  printf '%s\n' 'src/nightshift_fixture/core.py:12: unused function "orphan_helper" (60% confidence)'
  exit 1
fi

printf '%s\n' 'no findings'
exit 0
