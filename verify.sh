#!/bin/zsh
# Regression check against the running backend through the CLI. Reports every
# failure instead of stopping at the first one.
set -uo pipefail

ROOT="${0:A:h}"
CLI="$ROOT/kiln"
export KILN_API_KEY_FILE="${KILN_API_KEY_FILE:-$HOME/.config/kiln/api-key}"
export KILN_MODEL="${KILN_MODEL:-ornith-ai--Ornith-1.5-35B-A3B-MLX-4bit}"
export KILN_OCR_MODEL="${KILN_OCR_MODEL:-Unlimited-OCR-mxfp8}"
export KILN_EMBEDDING_MODEL="${KILN_EMBEDDING_MODEL:-mlx-community--Qwen3-Embedding-4B-4bit-DWQ}"
export KILN_TRANSLATE_MODEL="${KILN_TRANSLATE_MODEL:-Hy-MT2-1.8B-4bit}"

failures=0
pass() { print "  ok    $*" }
fail() { print -u2 "  FAIL  $*"; (( failures++ )) || true; }

check() {
  local name="$1"; shift
  if "$@" >/dev/null 2>&1; then pass "$name"; else fail "$name"; fi
}

print "syntax"
check "kiln" zsh -n "$CLI"

print "\ndoctor"
check "doctor reaches the backend" "$CLI" doctor

print "\nmodels"
if "$CLI" models 2>/dev/null | grep -q .; then
  pass "lists models"
else
  fail "lists models"
fi

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

print "\nembed"
if "$CLI" embed 'regression probe' 2>/dev/null | python3 -c '
import json, sys
vector = json.load(sys.stdin)["data"][0]["embedding"]
assert len(vector) > 0 and all(isinstance(x, float) for x in vector)
' 2>/dev/null; then
  pass "vector"
else
  fail "vector"
fi

print "\ntranslate"
if [[ -n "$("$CLI" translate --lang 中文 'hello, world' 2>/dev/null)" ]]; then
  pass "outputs a translation"
else
  fail "outputs a translation"
fi

print "\nocr (sends an image over the API)"
work="$(mktemp -d -t kiln-verify)"
cp "$ROOT/test-data/paddleocr_vl_demo.png" "$work/sample.png"
if [[ -f "$work/sample.png" ]]; then
  if out="$("$CLI" ocr "$work/sample.png" 2>/dev/null)" && [[ -n "$out" ]]; then
    pass "returns recognition text"
  else
    fail "returns recognition text"
  fi
else
  fail "missing OCR fixture"
fi

print "\nerrors"
"$CLI" bogus >/dev/null 2>&1
(( $? == 2 )) && pass "unknown command exits 2" || fail "unknown command exits 2"

empty_output="$(print -n '' | "$CLI" chat 2>&1)"
if [[ "$empty_output" == *'needs a message'* ]]; then pass "empty input"; else fail "empty input"; fi

if "$CLI" ocr "$work/does-not-exist.png" 2>/dev/null; then
  fail "missing ocr input errors"
else
  pass "missing ocr input errors"
fi

rm -rf "$work"

if (( failures )); then
  print -u2 "\n$failures check(s) failed"
  exit 1
fi
print "\nall checks passed"
