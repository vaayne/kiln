#!/bin/zsh
# Regression check against the running server. Reports every failure instead of
# stopping at the first one, so one run tells you everything that is broken.
set -uo pipefail

source "${0:A:h}/config.sh"
CLI="$KILN_ROOT/kiln"

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
for f in "$KILN_ROOT"/*.sh "$CLI"; do
  check "${f:t}" zsh -n "$f"
done
for f in "$KILN_ROOT"/launchd/*.plist.in; do
  check "${f:t}" plutil -lint "$f"
done

print "\nservice"
check "doctor" "$CLI" doctor

print "\nAPI gateway"
if [[ "$(curl -sS -o /dev/null -w '%{http_code}' "$KILN_URL/v1/models")" == 401 ]]; then
  pass "requires API key"
else
  fail "requires API key"
fi
if api_models="$(curl -fsS -H "Authorization: Bearer $(< "$KILN_API_KEY_FILE")" "$KILN_URL/v1/models" 2>/dev/null)" \
  && [[ "$api_models" == *"$KILN_AGENT_MODEL"* ]]; then
  pass "models proxy"
else
  fail "models proxy"
fi

print "\nCLI configuration"
if "$CLI" config show 2>/dev/null | "$KILN_PYTHON" -c 'import sys; text=sys.stdin.read(); assert "[models]" in text and "[runtime]" in text and "api-key =" not in text' 2>/dev/null; then
  pass "show is secret-free"
else
  fail "show is secret-free"
fi
config_copy="$(mktemp -t kiln-config).toml"
cp "$KILN_CONFIG_FILE" "$config_copy"
if "$KILN_PYTHON" "$KILN_ROOT/kiln_config.py" set "$config_copy" runtime.max_tokens 8192 2>/dev/null \
  && "$KILN_PYTHON" - "$config_copy" <<'PYCONFIG'
from kiln_config import load
import sys
assert load(sys.argv[1])["runtime"]["max_tokens"] == 8192
PYCONFIG
then
  pass "validated atomic update"
else
  fail "validated atomic update"
fi
if "$KILN_PYTHON" "$KILN_ROOT/kiln_config.py" set "$config_copy" server.port 9000 >/dev/null 2>&1; then
  fail "rejects network changes"
else
  pass "rejects network changes"
fi
rm -f "$config_copy"

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
work="$(mktemp -d -t kiln-verify)"
"$KILN_PADDLE_PYTHON" - "$work/sample.png" <<'PY' 2>/dev/null
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
