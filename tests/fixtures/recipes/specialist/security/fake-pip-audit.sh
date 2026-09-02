#!/bin/sh
# fake-pip-audit.sh — pip-audit stand-in for the Python security recipe fixture.
#
#   NS_FAKE_MODE=green      no advisories
#   NS_FAKE_MODE=findings   one advisory on stdout, exit 1
#   NS_FAKE_MODE=missing    PATH miss
set -u
mode="${NS_FAKE_MODE:-green}"

if [ -n "${NS_FAKE_LOG:-}" ]; then
  if [ "$#" -eq 0 ]; then
    printf 'pip-audit\n' >>"$NS_FAKE_LOG"
  else
    printf 'pip-audit %s\n' "$*" >>"$NS_FAKE_LOG"
  fi
fi

if [ "$mode" = missing ]; then
  printf 'pip-audit: command not found\n' >&2
  exit 127
fi

if [ "$mode" = findings ]; then
  printf '%s\n' 'Found 1 known vulnerability in 1 package'
  printf '%s\n' 'Name  Version ID                  Fix Versions'
  printf '%s\n' '----  ------- -------------------  ------------'
  printf '%s\n' 'demo  1.0.0   PYSEC-2024-FIXTURE  1.0.1'
  exit 1
fi

printf '%s\n' 'No known vulnerabilities found'
exit 0
