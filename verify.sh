#!/bin/zsh
# Regression check against the running server. Reports every failure instead of
# stopping at the first one, so one run tells you everything that is broken.
set -uo pipefail

source "${0:A:h}/config.sh"
CLI="$MLX_VLM_ROOT/mlx-local"

failures=0
pass() { print "  ok    $*" }
fail() { print -u2 "  FAIL  $*"; (( failures++ )) }

check() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then pass "$name"; else fail "$name"; fi
}

# These commands are expected to exit non-zero, so match on their message
# rather than piping into grep, which pipefail would report as a failure.
expect_error() {
  local name="$1" pattern="$2" output
  shift 2
  output="$("$@" 2>&1)"
  if [[ "$output" == *"$pattern"* ]]; then pass "$name"; else fail "$name"; fi
}

print "syntax"
for f in "$MLX_VLM_ROOT"/*.sh "$CLI"; do
  check "${f:t}" zsh -n "$f"
done
for f in "$MLX_VLM_ROOT"/launchd/*.plist.in; do
  check "${f:t}" plutil -lint "$f"
done

print "\nservice"
check "doctor" "$CLI" doctor

print "\nchat"
if [[ "$("$CLI" chat '只回复 OK' 2>/dev/null)" == OK ]]; then
  pass "argument"
else
  fail "argument"
fi
if [[ "$(print '只回复 OK' | "$CLI" chat 2>/dev/null)" == OK ]]; then
  pass "stdin"
else
  fail "stdin"
fi

print "\nembedding"
if "$CLI" embed 'regression probe' 2>/dev/null | python3 -c '
import json, sys
vector = json.load(sys.stdin)["data"][0]["embedding"]
assert len(vector) > 0 and all(isinstance(x, float) for x in vector)
' 2>/dev/null; then
  pass "vector"
else
  fail "vector"
fi

print "\nocr (slow, loads a second model)"
work="$(mktemp -d -t mlx-local-verify)"
"$MLX_PADDLE_PYTHON" - "$work/sample.png" <<'PY' 2>/dev/null
import sys
from PIL import Image, ImageDraw
image = Image.new("RGB", (1000, 400), "white")
draw = ImageDraw.Draw(image)
draw.text((60, 80), "Local MLX regression sample", fill="black")
draw.text((60, 160), "Invoice total: 1234.56 USD", fill="black")
draw.text((60, 240), "PaddleOCR VL document parsing", fill="black")
image.save(sys.argv[1])
PY
if [[ -f "$work/sample.png" ]]; then
  if "$CLI" ocr "$work/sample.png" --output "$work/out" >/dev/null 2>&1; then
    pass "run"
    for pattern in '*.md' '*_res.json' '*.docx' '*_layout_det_res.png'; do
      matches=("$work"/out/${~pattern}(N))
      if (( ${#matches} )); then
        pass "produced $pattern"
      else
        fail "produced $pattern"
      fi
    done
  else
    fail "run"
  fi
else
  fail "could not render a sample image"
fi

print "\nrecovery"
if [[ "$("$CLI" chat '只回复 OK' 2>/dev/null)" == OK ]]; then
  pass "chat after model switch"
else
  fail "chat after model switch"
fi
if "$CLI" unload 2>/dev/null | grep -Eq 'loaded +none'; then
  pass "unload"
else
  fail "unload"
fi
if [[ "$("$CLI" chat '只回复 OK' 2>/dev/null)" == OK ]]; then
  pass "chat reloads after unload"
else
  fail "chat reloads after unload"
fi

print "\nerrors"
expect_error "missing input" 'OCR input not found' "$CLI" ocr "$work/does-not-exist.pdf"
expect_error "unknown ocr option" 'unknown ocr option' "$CLI" ocr "$work/sample.png" --bogus
expect_error "unknown service action" 'unknown service action' "$CLI" service bogus

"$CLI" bogus >/dev/null 2>&1
(( $? == 2 )) && pass "unknown command exits 2" || fail "unknown command exits 2"

empty_output="$(print -n '' | "$CLI" chat 2>&1)"
if [[ "$empty_output" == *'needs text'* ]]; then pass "empty input"; else fail "empty input"; fi

rm -rf "$work"

if (( failures )); then
  print -u2 "\n$failures check(s) failed"
  exit 1
fi
print "\nall checks passed"
