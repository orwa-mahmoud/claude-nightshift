#!/bin/sh
# fake-go.sh — the scripted Go toolchain the recipe suite runs against. Installed on a
# controlled PATH under two names, `go` and `gofmt`, and dispatched on the name it was called by.
#
# A suite that shells out to the real toolchain reads differently on every host and cannot
# describe a toolchain that is absent, or one whose formatter is not installed. So the recipes
# are proven against a script whose answers the test chooses:
#
#   NS_FAKE_MODE=green      every command succeeds with the output a clean module produces
#   NS_FAKE_MODE=findings   the commands run and report findings — the red baseline the engine
#                           counts as a working capability. gofmt lists the file and still
#                           exits 0, exactly as the real one does
#   NS_FAKE_MODE=component  the compiler answers but the formatter is not installed, so `gofmt`
#                           is a PATH miss and `go` is not
#   NS_FAKE_MODE=missing    no toolchain at all: every invocation is a PATH miss
#
# Every invocation is appended to $NS_FAKE_LOG when that is set, as the command line the engine
# ran, so a test can assert the exact command a recipe reached for and nothing more.
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

if [ "$tool" = gofmt ]; then
  [ "$mode" != component ] || not_found
  if [ "$mode" = findings ]; then
    printf 'count.go\n'
  fi
  exit 0
fi

sub="${1:-}"
cover=0
for arg in "$@"; do
  if [ "$arg" = -cover ]; then
    cover=1
  fi
done

case "$sub" in
  version)
    printf 'go version go1.23.6 fixture/amd64\n'
    exit 0
    ;;
  help)
    exit 0
    ;;
  test)
    if [ "$mode" = findings ]; then
      printf '%s\n' '--- FAIL: TestCount (0.00s)'
      printf '%s\n' '    count_test.go:6: Count(night) = 5, want 6'
      printf '%s\n' 'FAIL	example.test/nightshift/fixture	0.011s'
      exit 1
    fi
    if [ "$cover" -eq 1 ]; then
      printf '%s\n' 'ok  	example.test/nightshift/fixture	0.011s	coverage: 100.0% of statements'
    else
      printf '%s\n' 'ok  	example.test/nightshift/fixture	0.011s'
    fi
    exit 0
    ;;
  vet)
    if [ "$mode" = findings ]; then
      printf '%s\n' 'count.go:18:2: fmt.Printf format %d has arg text of wrong type string'
      exit 1
    fi
    exit 0
    ;;
  build)
    if [ "$mode" = findings ]; then
      printf '%s\n' 'count.go:18:2: cannot use text (variable of type string) as int value'
      exit 1
    fi
    exit 0
    ;;
esac

printf 'go %s: unknown command\n' "$sub" >&2
exit 127
