#!/usr/bin/env bash
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
. "$KIT/tests/lib/harness.sh"

LIB="$KIT/lib/theme-lib.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# ---------------------------------------------------------- pure functions

out="$(bash -c ". \"$LIB\"; skwd_rgb_to_hex \"255,0,128\"")"
assert_eq "$out" "#ff0080" "skwd_rgb_to_hex"

out="$(bash -c ". \"$LIB\"; skwd_lum \"255,255,255\"")"
assert_eq "$out" "255" "skwd_lum white"

out="$(bash -c ". \"$LIB\"; skwd_lum \"0,0,0\"")"
assert_eq "$out" "0" "skwd_lum black"

cat > "$tmp/sample.colors" <<'EOF'
[Colors:Window]
BackgroundNormal=10,20,30
[WM]
frame=1,2,3
EOF
out="$(bash -c ". \"$LIB\"; skwd_scheme_rgb \"$tmp/sample.colors\" \"Colors:Window\" BackgroundNormal")"
assert_eq "$out" "10,20,30" "skwd_scheme_rgb"

pass "pure helpers (skwd_rgb_to_hex, skwd_lum, skwd_scheme_rgb)"

d1="$tmp/case1"; mkdir -p "$d1/data/color-schemes"
echo old > "$d1/data/color-schemes/SkwdMatugen.colors"
if XDG_DATA_HOME="$d1/data" XDG_CACHE_HOME="$d1/cache" bash -c '
    set -u
    . "'"$LIB"'"
    sleep 0.2
    echo new > "$SCHEME_SRC"
    skwd_wait_for_render "$SCHEME_SRC" 3
' case1-hook; then
    pass "wait: detects a render that landed before the wait call"
else
    fail "wait: should have detected the already-changed file"
fi

d2="$tmp/case2"; mkdir -p "$d2/data/color-schemes"
if XDG_DATA_HOME="$d2/data" XDG_CACHE_HOME="$d2/cache" bash -c '
    set -u
    . "'"$LIB"'"
    ( sleep 0.3; echo rendered > "$SCHEME_SRC" ) &
    skwd_wait_for_render "$SCHEME_SRC" 3
' case2-hook; then
    pass "wait: cold start succeeds once the render appears"
else
    fail "wait: cold start should succeed once the file appears"
fi

d3="$tmp/case3"; mkdir -p "$d3/data/color-schemes" "$d3/cache/skwd-wall-v2"
echo v1 > "$d3/data/color-schemes/SkwdMatugen.colors"
if XDG_DATA_HOME="$d3/data" XDG_CACHE_HOME="$d3/cache" bash -c '
    set -u
    . "'"$LIB"'"
    mkdir -p "$SKWD_CACHE"
    stat -c %.Y "$SCHEME_SRC" > "$SKWD_CACHE/${0##*/}.last-render"
    ( sleep 0.3; echo v2 > "$SCHEME_SRC" ) &
    skwd_wait_for_render "$SCHEME_SRC" 3
' case3-hook; then
    pass "wait: a pending render against a recorded state succeeds once it lands"
else
    fail "wait: should have succeeded once the file changed"
fi

d4="$tmp/case4"; mkdir -p "$d4/data/color-schemes"
echo same > "$d4/data/color-schemes/SkwdMatugen.colors"
if XDG_DATA_HOME="$d4/data" XDG_CACHE_HOME="$d4/cache" bash -c '
    set -u
    . "'"$LIB"'"
    skwd_wait_for_render "$SCHEME_SRC" 1
' case4-hook; then
    fail "wait: expected a timeout when the render never lands"
else
    pass "wait: times out when the render never lands"
fi

# The leftover case the quiet window exists for: an unconsumed render from a
# previous apply is already on disk and differs from this hook's recorded
# state, so the bare mtime-differs check would accept it and lag one wallpaper
# behind. The real render lands mid-window and must win.
d5="$tmp/case5"; mkdir -p "$d5/data/color-schemes" "$d5/cache/skwd-wall-v2"
echo leftover > "$d5/data/color-schemes/SkwdMatugen.colors"
stale_mtime="$(stat -c %.Y "$d5/data/color-schemes/SkwdMatugen.colors")"
accepted="$(XDG_DATA_HOME="$d5/data" XDG_CACHE_HOME="$d5/cache" bash -c '
    set -u
    . "'"$LIB"'"
    mkdir -p "$SKWD_CACHE"
    # Any value the leftover does not match, so it reads as a fresh render.
    echo 1 > "$SKWD_CACHE/${0##*/}.last-render"
    ( sleep 0.15; echo real > "$SCHEME_SRC" ) &
    skwd_wait_for_render "$SCHEME_SRC" 5
    cat "$SKWD_CACHE/${0##*/}.last-render"
' case5-hook)"
real_mtime="$(stat -c %.Y "$d5/data/color-schemes/SkwdMatugen.colors")"
if [ "$accepted" = "$real_mtime" ] && [ "$accepted" != "$stale_mtime" ]; then
    pass "wait: a superseded leftover render is discarded for the real one"
else
    fail "wait: accepted '$accepted', expected the real render '$real_mtime' (stale was '$stale_mtime')"
fi
