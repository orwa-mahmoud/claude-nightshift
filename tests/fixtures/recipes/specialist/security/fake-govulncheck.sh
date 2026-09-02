#!/bin/sh
# fake-govulncheck.sh — govulncheck stand-in for the Go security recipe fixture.
#
#   NS_FAKE_MODE=green      reports no vulnerabilities
#   NS_FAKE_MODE=findings   reports one module vulnerability
#   NS_FAKE_MODE=missing    PATH miss
set -u
mode="${NS_FAKE_MODE:-green}"

if [ -n "${NS_FAKE_LOG:-}" ]; then
  if [ "$#" -eq 0 ]; then
    printf 'govulncheck\n' >>"$NS_FAKE_LOG"
  else
    printf 'govulncheck %s\n' "$*" >>"$NS_FAKE_LOG"
  fi
fi

if [ "$mode" = missing ]; then
  printf 'govulncheck: command not found\n' >&2
  exit 127
fi

json=0
for arg in "$@"; do
  [ "$arg" = -json ] && json=1
done

if [ "$mode" = findings ]; then
  if [ "$json" -eq 1 ]; then
    printf '%s\n' '{"config":{"protocol_version":"v1.0","scanner_name":"govulncheck","scanner_version":"fixture","db":"https://vuln.go.dev","go_version":"go1.23.6","scan_level":"module","scan_mode":"source","experimental":false}}'
    printf '%s\n' '{"osv":{"schema_version":"1.3.0","id":"GO-2024-0001","modified":"2026-01-01T00:00:00Z","published":"2026-01-01T00:00:00Z","summary":"fixture advisory","details":"fixture only","affected":[{"package":{"name":"example.test/nightshift/fixture","ecosystem":"Go"}}]}}'
    printf '%s\n' '{"finding":{"osv":"GO-2024-0001","fixed_version":"v0.0.1","trace":[{"function":"","position":{"filename":"count.go","line":1,"column":1}}]}}'
  else
    printf '%s\n' 'Vulnerability #1: GO-2024-0001'
    printf '%s\n' '    Found in: example.test/nightshift/fixture'
  fi
  exit 1
fi

if [ "$json" -eq 1 ]; then
  printf '%s\n' '{"config":{"protocol_version":"v1.0","scanner_name":"govulncheck","scanner_version":"fixture","db":"https://vuln.go.dev","go_version":"go1.23.6","scan_level":"module","scan_mode":"source","experimental":false}}'
else
  printf '%s\n' 'No vulnerabilities found.'
fi
exit 0
