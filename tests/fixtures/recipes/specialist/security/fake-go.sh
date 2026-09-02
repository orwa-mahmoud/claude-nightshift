#!/bin/sh
# fake-go.sh — go/govulncheck stand-in for security recipe fixtures.
set -u
code=@EXIT@
name="$(basename "$0")"

printf '%s %s\n' "$name" "$*"

if [ "$code" -ne 0 ]; then
  exit "$code"
fi

case "$name" in
  go)
    case "$1" in
      version) printf 'go version go1.22.0 darwin/arm64\n'; exit 0 ;;
      test) exit 0 ;;
    esac
    ;;
  govulncheck)
    case "$*" in
      *-version*) exit 0 ;;
      *) printf 'No vulnerabilities found.\n'; exit 0 ;;
    esac
    ;;
esac

exit 0
