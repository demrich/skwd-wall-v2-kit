#!/usr/bin/env bash
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
. "$KIT/tests/lib/harness.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp"
export PATH="$KIT/tests/stubs:$PATH"
export SKWD_WALL_V2_BOX="skwd-test-box"
unset XDG_SESSION_DESKTOP DESKTOP_SESSION KDE_FULL_SESSION

cd "$KIT" || exit 1
if ! ./install.sh --yes >"$tmp/install.log" 2>&1; then
    cat "$tmp/install.log" >&2
    fail "install.sh --yes exited non-zero"
fi

assert_file "$HOME/.local/bin/skwd-wall-v2-session"
assert_file "$HOME/.local/bin/skwd-plasma-scheme"
assert_file "$HOME/.local/bin/skwd-plasma-surfaces"
assert_file "$HOME/.local/bin/skwd-theme"
assert_file "$HOME/.local/lib/skwd-wall-v2/theme-lib.sh"
assert_file "$HOME/.local/lib/skwd-wall-v2/check-contrast.py"
assert_file "$HOME/.local/bin/skwd-paper-v2"
assert_file "$HOME/.local/libexec/skwd-wall-still"
assert_file "$HOME/.local/libexec/skwd-wall-vk"
assert_file "$HOME/.config/systemd/user/skwd-wall-v2.service"
# Without this the picker GUI stays invisible to the host app launcher, which
# is exactly where install.sh and the README tell you to look for it.
assert_file "$HOME/.local/share/applications/skwd-wall-v2-kit.desktop"
CONF="$HOME/.config/skwd-wall-v2/config.json"
assert_file "$CONF"

for t in "$KIT"/matugen/templates/*; do
    assert_file "$HOME/.config/skwd-wall-v2/matugen/templates/$(basename "$t")"
done

grep -q '__HOME__' "$CONF" && fail "config.json still has an unsubstituted __HOME__"
jq empty "$CONF" || fail "config.json is not valid JSON"

pass "install.sh --yes lays down the full expected tree"

echo '{"marker": true}' > "$CONF"
TMPL="$HOME/.config/skwd-wall-v2/matugen/templates/ghostty.conf"
echo 'marker-edit' > "$TMPL"
if ! ./install.sh --yes >"$tmp/reinstall.log" 2>&1; then
    cat "$tmp/reinstall.log" >&2
    fail "re-running install.sh --yes exited non-zero"
fi
grep -q '"marker": true' "$CONF" || fail "re-install clobbered an existing config.json"
grep -q 'marker-edit' "$TMPL" || fail "re-install clobbered an existing matugen template"
pass "re-running install.sh --yes is idempotent and leaves existing config.json and templates alone"

# A re-install must not accumulate launchers: the fixed filename is the whole
# reason install.sh writes this by hand instead of calling distrobox-export.
n_desktop="$(find "$HOME/.local/share/applications" -maxdepth 1 -name '*skwd-wall-v2*.desktop' | wc -l)"
assert_eq "$n_desktop" "1" "picker launchers present after a re-install"
grep -q 'enter -n skwd-test-box -- skwd-wall-v2' \
    "$HOME/.local/share/applications/skwd-wall-v2-kit.desktop" \
    || fail "picker launcher Exec does not target the configured box"
pass "the picker launcher is written once and points at the configured box"

if ! ./uninstall.sh --purge -y >"$tmp/uninstall.log" 2>&1; then
    cat "$tmp/uninstall.log" >&2
    fail "uninstall.sh --purge -y exited non-zero"
fi

for f in skwd-wall-v2-session skwd-plasma-scheme skwd-plasma-surfaces skwd-theme skwd-paper-v2; do
    assert_missing "$HOME/.local/bin/$f"
done
assert_missing "$HOME/.local/lib/skwd-wall-v2"
assert_missing "$HOME/.config/systemd/user/skwd-wall-v2.service"
assert_missing "$HOME/.local/share/applications/skwd-wall-v2-kit.desktop"
assert_missing "$HOME/.config/skwd-wall-v2"

pass "uninstall.sh --purge -y removes everything install.sh laid down"

tmp2="$(mktemp -d)"
trap 'rm -rf "$tmp" "$tmp2"' EXIT
export HOME="$tmp2"
mkdir -p "$HOME/.var/app/app.zen_browser.zen/.zen/xyz.Default"

if ! ./install.sh --yes >"$tmp2/install.log" 2>&1; then
    cat "$tmp2/install.log" >&2
    fail "install.sh --yes exited non-zero with an existing Zen profile present"
fi

CONF2="$HOME/.config/skwd-wall-v2/config.json"
assert_file "$CONF2"
count="$(jq '.integrations | length' "$CONF2")"
assert_eq "$count" "8" "integrations count with --yes and a Zen profile present"
jq -e '.integrations[] | select(.name == "zen")' "$CONF2" >/dev/null \
    && fail "--yes should not have added the optional zen integration"

pass "install.sh --yes completes and skips the optional Zen prompt when a profile is present"
