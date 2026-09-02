#!/bin/sh
# fake-npm.sh — the package manager stand-in for the api-schema recipe fixtures.
#
# Installed into a temporary bin directory by make-project.sh or setup_fake_npm under npm, npx,
# pnpm, and yarn. make-project.sh replaces @EXIT@ with the exit code the case wants: 0 installs,
# anything else reports an index it cannot reach.
#
# NS_FAKE_MODE=findings makes @redocly/cli lint report validation output and exit non-zero, which
# the engine counts as a working red baseline when stderr/stdout is non-empty.
set -u
code=@EXIT@
name="$(basename "$0")"
mode="${NS_FAKE_MODE:-green}"

printf '%s %s\n' "$name" "$*"

if [ "$code" -ne 0 ]; then
  printf '%s: could not reach the package index\n' "$name" >&2
  exit "$code"
fi

case "$name" in
  npm)
    case "$*" in
      *install*)
        if [ -f package-lock.json ]; then
          printf '# development dependency recorded by the fixture manager\n' >>package-lock.json
        fi
        ;;
      *uninstall*) ;;
    esac
    ;;
  npx)
    case "$*" in
      *@redocly/cli*)
        if [ "$mode" = findings ]; then
          printf '[1] openapi.yaml:9:11 at #/paths/~1broken/get/parameters/0/schema\n'
          printf 'Failed to resolve $ref: Missing\n'
          exit 1
        fi
        printf '@redocly/cli lint: no findings\n'
        exit 0
        ;;
    esac
    ;;
  pnpm | yarn) ;;
esac

exit 0
