#!/usr/bin/bash
# Shared helpers for the skwd-wall v2 post-processing hooks on KDE Plasma.
# Sourced, never executed. Every function here is safe to call on a host that
# is missing the thing it drives; the caller is expected to exit 0 quietly.

# ---------------------------------------------------------------- host hop
# walld runs inside a Distrobox where the Plasma tools do not exist. Anything
# that touches the live session has to be run on the host.
if [ -n "${CONTAINER_ID:-}" ] && command -v distrobox-host-exec >/dev/null 2>&1; then
    host() { distrobox-host-exec "$@"; }
else
    host() { "$@"; }
fi

SCHEME_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/color-schemes"
# The file v2 renders from its kde-colors.colors template. Read colours from
# here, not from the SkwdWallA/B copies: those are skwd-plasma-scheme's private
# A/B flip, so depending on them would order these hooks against each other.
SCHEME_SRC="$SCHEME_DIR/SkwdMatugen.colors"
SKWD_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/skwd-wall-v2"

# Mtime of the rendered scheme as it stood the moment this hook started, taken
# here because sourcing this library is the first thing every hook does. It is
# the "before" side of the render wait below, and it has to be sampled at entry
# rather than at the wait call: a hook that does a few distrobox-host-exec
# round-trips first (skwd-plasma-surfaces does) would otherwise sample a file
# the renderer had already rewritten, and then wait out its whole timeout for a
# second change that never comes.
SKWD_ENTRY_MTIME="$(stat -c %.Y "$SCHEME_SRC" 2>/dev/null || echo 0)"

# -------------------------------------------------------------------- log
# One line per hook run, so a hook that silently exits 0 on a guard can still
# be told apart from one that never ran. Truncated, never rotated-into-infinity.
SKWD_LOG="$SKWD_CACHE/hooks.log"
skwd_log() {
    mkdir -p "$SKWD_CACHE" 2>/dev/null
    [ -f "$SKWD_LOG" ] && [ "$(wc -l <"$SKWD_LOG" 2>/dev/null || echo 0)" -gt 500 ] && \
        tail -n 200 "$SKWD_LOG" >"$SKWD_LOG.tmp" && mv "$SKWD_LOG.tmp" "$SKWD_LOG"
    printf '%s %s: %s\n' "$(date +%T.%3N)" "${0##*/}" "$*" >>"$SKWD_LOG" 2>/dev/null || true
}

# ------------------------------------------------- wait for the render (!!)
# skwd-walld spawns post-processing hooks BEFORE it renders the integration
# templates. Measured on 1.0.0-beta.11, 2026-09-10: a hook launched at
# 10:17:39.505 read a SkwdMatugen.colors last written at 10:17:18 — the
# PREVIOUS wallpaper's palette. Any hook that reads a rendered file has to
# block until that file has actually been rewritten, or the desktop lags one
# wallpaper behind.
#
# Two obvious rules for "rewritten" are both wrong, and each was caught here:
#
#   mtime >= my start time      Wrong. The hooks are spawned concurrently and
#                               are not ordered against the renderer, so a hook
#                               scheduled late finds the render already done,
#                               waits out its whole timeout, and skips.
#   mtime != last one I saw     Wrong on a cold start. With no state file
#                               anything on disk counts as fresh, so the first
#                               apply after install uses the previous palette.
#
# What works is the two combined: wait for the mtime to differ from the last
# one this hook acted on, and when there is no such record yet, seed it from
# whatever is on disk at entry. Correct in all four cases — cold start, render
# already landed, render still pending, and a re-apply of the same wallpaper
# (the file is rewritten, so the mtime still moves).
#
# Bounded, and falls through rather than failing: stale colour beats no colour,
# and theme.policy=off legitimately never rewrites the file. A manual run
# outside an apply therefore always times out; set SKWD_HOOK_NO_WAIT=1 to skip
# the wait when testing a hook by hand.
skwd_wait_for_render() {
    local file="${1:-$SCHEME_SRC}" timeout="${2:-10}"
    local state="$SKWD_CACHE/${0##*/}.last-render"
    local last cur start now
    [ -n "${SKWD_HOOK_NO_WAIT:-}" ] && return 0
    mkdir -p "$SKWD_CACHE" 2>/dev/null
    last="$(cat "$state" 2>/dev/null)"
    # No record yet: seed from the file as it stood at hook entry, so the wait
    # below is for the render that is about to happen and is not satisfied by
    # the stale file already on disk.
    [ -n "$last" ] || last="$SKWD_ENTRY_MTIME"
    start=$(date +%s.%N)
    while :; do
        cur="$(stat -c %.Y "$file" 2>/dev/null || echo 0)"
        if [ "$cur" != "0" ] && [ "$cur" != "$last" ]; then
            printf '%s' "$cur" >"$state" 2>/dev/null || true
            return 0
        fi
        now=$(date +%s.%N)
        awk -v a="$now" -v b="$start" -v t="$timeout" \
            'BEGIN{exit !(a-b >= t)}' && return 1
        sleep 0.1
    done
}

# --------------------------------------------------------------- colour I/O
# Reads "R,G,B" out of a KDE .colors ini section.
skwd_scheme_rgb() {
    local file="$1" group="$2" key="$3"
    awk -v g="$group" -v k="$key" '
        $0 == "[" g "]" { p=1; next }
        p && /^\[/ { exit }
        p && $0 ~ "^" k "=" { sub(/^[^=]+=/, ""); gsub(/ /, ""); print; exit }
    ' "$file"
}

skwd_rgb_to_hex() {
    local IFS=','
    # shellcheck disable=SC2086
    set -- $(printf '%s' "$1" | tr -d ' ')
    printf '#%02x%02x%02x' "$1" "$2" "$3"
}

# Rough integer sRGB luminance, 0-255. Good enough to pick black-or-white text.
skwd_lum() {
    local IFS=','
    # shellcheck disable=SC2086
    set -- $(printf '%s' "$1" | tr -d ' ')
    echo $(( (2126 * $1 + 7152 * $2 + 722 * $3) / 10000 ))
}
