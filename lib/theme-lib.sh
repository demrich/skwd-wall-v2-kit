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
# skwd-walld spawns post-processing hooks concurrently with, not strictly
# after, the render. A hook that reads a rendered file therefore has to block
# until that file has actually been rewritten, or the desktop lags one
# wallpaper behind.
#
# Two obvious rules for "rewritten" are both wrong, and each was caught here:
#
#   mtime >= my start time      Wrong. The hooks are not ordered against the
#                               renderer, so a hook scheduled late finds the
#                               render already done, waits out its whole
#                               timeout, and skips.
#   mtime != last one I saw     Wrong on a cold start. With no state file
#                               anything on disk counts as fresh, so the first
#                               apply after install uses the previous palette.
#
# Combining the two (wait for an mtime differing from the last one this hook
# acted on, seeded at entry when there is no record yet) covers the cold
# start, the render that already landed, the render still pending, and a
# re-apply of the same wallpaper. It is still not enough on its own.
#
# The remaining case: walld can spawn this apply's hook before this apply's
# render starts, while the PREVIOUS apply's render is still on disk
# unconsumed, because a faster hook exited first or the previous apply outran
# its own hook. That leftover differs from what this hook last recorded, so it
# looks exactly like a fresh render and gets consumed. The result is a
# deterministic one-apply lag, not an occasional race: the colour always
# arrives one selection late, which is what "press Enter twice" actually is.
#
# No state available to a shell hook separates "this mtime is mine" from "this
# is an older apply's unconsumed render"; both are only "different from what I
# recorded". The fix is time rather than bookkeeping. Do not trust the first
# differing mtime, wait for it to stop changing for a moment. A genuinely
# fresh render lands within a few hundred ms and its write supersedes whatever
# stale mtime was first seen, restarting the quiet timer on the real one. A
# long-settled leftover is never superseded during that window, which is
# indistinguishable from a real render that is quiet because it is finished,
# so it is still accepted, just after confirming nothing newer is landing.
#
# Bounded, and falls through rather than failing: stale colour beats no colour,
# and theme.policy=off legitimately never rewrites the file. A manual run
# outside an apply therefore always times out; set SKWD_HOOK_NO_WAIT=1 to skip
# the wait when testing a hook by hand.
skwd_wait_for_render() {
    local file="${1:-$SCHEME_SRC}" timeout="${2:-10}" quiet="${3:-0.3}"
    local state="$SKWD_CACHE/${0##*/}.last-render"
    local last cur start now settle quiet_since resets=0
    [ -n "${SKWD_HOOK_NO_WAIT:-}" ] && return 0
    mkdir -p "$SKWD_CACHE" 2>/dev/null
    last="$(cat "$state" 2>/dev/null)"
    # No record yet: seed from the file as it stood at hook entry, so the wait
    # below is for the render that is about to happen and is not satisfied by
    # the stale file already on disk.
    [ -n "$last" ] || last="$SKWD_ENTRY_MTIME"
    start=$(date +%s.%N)
    settle=""
    while :; do
        cur="$(stat -c %.Y "$file" 2>/dev/null || echo 0)"
        if [ "$cur" != "0" ] && [ "$cur" != "$last" ]; then
            if [ "$cur" != "$settle" ]; then
                # First sighting of this value, or a newer write just
                # superseded the one being watched. Either way, restart the
                # quiet window on it rather than trusting it yet.
                [ -n "$settle" ] && resets=$((resets + 1))
                settle="$cur"
                quiet_since=$(date +%s.%N)
            else
                now=$(date +%s.%N)
                if awk -v a="$now" -v b="$quiet_since" -v q="$quiet" \
                    'BEGIN{exit !(a-b >= q)}'; then
                    printf '%s' "$cur" >"$state" 2>/dev/null || true
                    # Low-noise trail for next time this lags: which render
                    # this hook accepted, and whether it discarded an earlier
                    # (possibly stale) one first.
                    skwd_log "render accepted mtime=$cur superseded=$resets waited=$(awk -v a="$now" -v b="$start" 'BEGIN{printf "%.3f", a-b}')s"
                    return 0
                fi
            fi
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
    # shellcheck disable=SC2046,SC2086
    set -- $(printf '%s' "$1" | tr -d ' ')
    printf '#%02x%02x%02x' "$1" "$2" "$3"
}

# Rough integer sRGB luminance, 0-255. Good enough to pick black-or-white text.
skwd_lum() {
    local IFS=','
    # shellcheck disable=SC2046,SC2086
    set -- $(printf '%s' "$1" | tr -d ' ')
    echo $(( (2126 * $1 + 7152 * $2 + 722 * $3) / 10000 ))
}
