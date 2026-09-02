#!/bin/sh
# fake-cargo.sh — the scripted Cargo the recipe suite runs against, installed on a controlled
# PATH as `cargo`.
#
# A suite that shells out to the real toolchain reads differently on every host and cannot
# describe a crate whose lint components were never installed. So the recipes are proven against
# a script whose answers the test chooses:
#
#   NS_FAKE_MODE=green      every command succeeds with the output a clean crate produces
#   NS_FAKE_MODE=findings   the commands run and report findings — the red baseline the engine
#                           counts as a working capability
#   NS_FAKE_MODE=component  cargo answers, but clippy and rustfmt are not installed: those two
#                           subcommands fail the way a missing component fails, with a message
#                           on stderr and a status that is not a PATH miss
#   NS_FAKE_MODE=missing    no toolchain at all: every invocation is a PATH miss
#
# Every invocation is appended to $NS_FAKE_LOG when that is set, as the command line the engine
# ran, so a test can assert the exact command a recipe reached for and nothing more.
set -u
mode="${NS_FAKE_MODE:-green}"

if [ -n "${NS_FAKE_LOG:-}" ]; then
  if [ "$#" -eq 0 ]; then
    printf 'cargo\n' >>"$NS_FAKE_LOG"
  else
    printf 'cargo %s\n' "$*" >>"$NS_FAKE_LOG"
  fi
fi

if [ "$mode" = missing ]; then
  printf 'cargo: command not found\n' >&2
  exit 127
fi

sub="${1:-}"

if [ "$mode" = component ]; then
  case "$sub" in
    clippy | fmt)
      printf 'error: no such command: `%s`\n' "$sub" >&2
      exit 101
      ;;
  esac
fi

for arg in "$@"; do
  case "$arg" in
    --version | -V)
      case "$sub" in
        clippy) printf 'clippy 0.1.79 (fixture)\n' ;;
        fmt) printf 'rustfmt 1.7.0-stable (fixture)\n' ;;
        *) printf 'cargo 1.79.0 (fixture)\n' ;;
      esac
      exit 0
      ;;
    --help | -h)
      printf 'cargo %s: fixture help\n' "$sub"
      exit 0
      ;;
  esac
done

case "$sub" in
  test)
    if [ "$mode" = findings ]; then
      printf '%s\n' 'failures:'
      printf '%s\n' '    tests::counts_runes'
      printf '%s\n' 'test result: FAILED. 1 passed; 1 failed; 0 ignored'
      exit 1
    fi
    printf '%s\n' 'test result: ok. 2 passed; 0 failed; 0 ignored'
    exit 0
    ;;
  fmt)
    if [ "$mode" = findings ]; then
      printf '%s\n' 'Diff in src/lib.rs at line 4:'
      printf '%s\n' '-pub fn count(text:&str)->usize{text.chars().count()}'
      printf '%s\n' '+pub fn count(text: &str) -> usize {'
      exit 1
    fi
    exit 0
    ;;
  clippy)
    if [ "$mode" = findings ]; then
      printf '%s\n' 'warning: this expression creates a reference which is immediately dereferenced'
      printf '%s\n' '  --> src/lib.rs:4:31'
      exit 1
    fi
    printf '%s\n' 'Finished dev [unoptimized + debuginfo] target(s)'
    exit 0
    ;;
  check)
    if [ "$mode" = findings ]; then
      printf '%s\n' 'error[E0308]: mismatched types'
      printf '%s\n' '  --> src/lib.rs:4:31'
      exit 1
    fi
    printf '%s\n' 'Finished dev [unoptimized + debuginfo] target(s)'
    exit 0
    ;;
  doc)
    if [ "$mode" = findings ]; then
      printf '%s\n' 'error: unresolved link to `Missing`'
      printf '%s\n' '  --> src/lib.rs:5:11'
      exit 1
    fi
    printf '%s\n' 'Documenting nightshift-fixture v0.0.0'
    exit 0
    ;;
esac

printf 'error: no such command: `%s`\n' "$sub" >&2
exit 127
