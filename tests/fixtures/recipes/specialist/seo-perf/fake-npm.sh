#!/bin/sh
# fake-npm.sh — npm stand-in for seo-perf recipe fixtures.
#
# make-static-site.sh installs this as npm on PATH. @EXIT@ is replaced with the desired exit
# code before install. A successful install appends to package-lock.json and writes htmlhint and
# serve stubs under the directory named on PATH.
set -u
code=@EXIT@
name="$(basename "$0")"
bin="$(cd "$(dirname "$0")" && pwd)"

printf '%s %s\n' "$name" "$*"

if [ "$code" -ne 0 ]; then
  printf '%s: could not reach the package index\n' "$name" >&2
  exit "$code"
fi

case "$name" in
  npm)
    [ ! -f package-lock.json ] || printf '# development dependency recorded by the fixture manager\n' >>package-lock.json
    for script in htmlhint serve; do
      [ ! -e "$bin/$script" ] || continue
      cat >"$bin/$script" <<'STUB'
#!/bin/sh
case "$(basename "$0")" in
  htmlhint)
    findings=0
    if grep -q '<title></title>' index.html 2>/dev/null; then
      printf 'evidence: html-lint title-require index.html\n'
      findings=1
    fi
    if grep -q '<H1>' index.html 2>/dev/null; then
      printf 'evidence: html-lint tagname-lowercase index.html\n'
      findings=1
    fi
    if [ "$findings" -eq 1 ]; then
      printf 'evidence: html-lint findings reported\n'
    else
      printf 'evidence: html-lint ok\n'
    fi
    exit 0
    ;;
  serve)
    port=3456
    while [ $# -gt 0 ]; do
      case "$1" in
        -l) port="$2"; shift 2 ;;
        *) shift ;;
      esac
    done
    if command -v python3 >/dev/null 2>&1; then
      exec python3 -m http.server "$port"
    fi
    exec sh -c 'sleep 120'
    ;;
esac
exit 0
STUB
      chmod +x "$bin/$script"
    done
    ;;
esac

exit 0
