#!/usr/bin/env bash
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
. "$KIT/tests/lib/harness.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp"
mkdir -p "$HOME/.local/lib/skwd-wall-v2"
install -m 755 "$KIT/lib/check-contrast.py" "$HOME/.local/lib/skwd-wall-v2/check-contrast.py"

SKWD_THEME="$KIT/bin/skwd-theme"
FIXTURES="$KIT/tests/fixtures"

if "$SKWD_THEME" validate "$FIXTURES/good.colors" >/dev/null; then
    pass "validate: a well-formed, readable scheme passes"
else
    fail "validate: good.colors should have passed"
fi

if "$SKWD_THEME" validate "$FIXTURES/missing-group.colors" >/dev/null 2>&1; then
    fail "validate: missing-group.colors should have failed (missing [WM])"
else
    pass "validate: catches a missing required group"
fi

if "$SKWD_THEME" validate "$FIXTURES/bad-value.colors" >/dev/null 2>&1; then
    fail "validate: bad-value.colors should have failed (out-of-range RGB)"
else
    pass "validate: catches an out-of-range RGB value"
fi

if "$SKWD_THEME" validate "$FIXTURES/low-contrast.colors" >/dev/null 2>&1; then
    fail "validate: low-contrast.colors should have failed the contrast check"
else
    pass "validate: catches unreadable (low-contrast) text"
fi
