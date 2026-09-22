#!/usr/bin/env bash
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
. "$KIT/tests/lib/harness.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp"
export PATH="$KIT/tests/stubs:$PATH"
unset XDG_SESSION_DESKTOP DESKTOP_SESSION KDE_FULL_SESSION XDG_CONFIG_HOME

cd "$KIT" || exit 1

# skwd-bazzite owns skwd-wall v2 itself; without it the theming layer has
# nothing to theme, so install.sh must refuse rather than half-install.
if ./install.sh --yes >"$tmp/refuse.log" 2>&1; then
    fail "install.sh ran without skwd-bazzite installed"
fi
grep -q 'skwd-bazzite is not installed' "$tmp/refuse.log" || fail "refusal does not name skwd-bazzite"
assert_missing "$HOME/.local/bin/skwd-theme"
pass "install.sh refuses without skwd-bazzite"

mkdir -p "$HOME/.config/skwd-bazzite" "$HOME/.config/systemd/user"
echo 'box=skwd-test-box' > "$HOME/.config/skwd-bazzite/config"
# A unit left by an earlier version of this kit, which started walld itself.
echo '[Service]' > "$HOME/.config/systemd/user/skwd-wall-v2.service"
mkdir -p "$HOME/.cache/skwd-test-systemctl"
: > "$HOME/.cache/skwd-test-systemctl/skwd-wall-v2.service.enabled"

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
assert_file "$HOME/.config/systemd/user/skwd-wall-v2-theme.service"
assert_file "$HOME/.cache/skwd-test-systemctl/skwd-wall-v2-theme.service.enabled"
assert_missing "$HOME/.config/systemd/user/skwd-wall-v2.service"
assert_missing "$HOME/.cache/skwd-test-systemctl/skwd-wall-v2.service.enabled"
# Everything skwd-bazzite owns stays out of this kit.
assert_missing "$HOME/.local/libexec"
assert_missing "$HOME/.local/lib64"
assert_missing "$HOME/.local/share/applications"
CONF="$HOME/.config/skwd-wall-v2/config.json"
assert_file "$CONF"

for t in "$KIT"/matugen/templates/*; do
    assert_file "$HOME/.config/skwd-wall-v2/matugen/templates/$(basename "$t")"
done

grep -q '__HOME__' "$CONF" && fail "config.json still has an unsubstituted __HOME__"
jq empty "$CONF" || fail "config.json is not valid JSON"

pass "install.sh --yes lays down the theming layer and retires the old unit"

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

# The restore script finds the container through skwd-bazzite's config.
SKWD_TEST_HELM_CURRENT_PATH="$HOME/wall.jpg" "$HOME/.local/bin/skwd-wall-v2-session" >/dev/null 2>&1 \
    || fail "skwd-wall-v2-session exited non-zero"
grep -q 'skwd-helm apply' "$HOME/.cache/skwd-test-distrobox/enter.log" || fail "restore did not apply"
pass "skwd-wall-v2-session re-applies the current wallpaper"

if ! ./uninstall.sh --purge -y >"$tmp/uninstall.log" 2>&1; then
    cat "$tmp/uninstall.log" >&2
    fail "uninstall.sh --purge -y exited non-zero"
fi

for f in skwd-wall-v2-session skwd-plasma-scheme skwd-plasma-surfaces skwd-theme; do
    assert_missing "$HOME/.local/bin/$f"
done
assert_missing "$HOME/.local/lib/skwd-wall-v2"
assert_missing "$HOME/.config/systemd/user/skwd-wall-v2-theme.service"
assert_missing "$HOME/.config/skwd-wall-v2"
assert_file "$HOME/.config/skwd-bazzite/config"

pass "uninstall.sh --purge -y removes everything install.sh laid down, and nothing of skwd-bazzite's"

tmp2="$(mktemp -d)"
trap 'rm -rf "$tmp" "$tmp2"' EXIT
export HOME="$tmp2"
mkdir -p "$HOME/.var/app/app.zen_browser.zen/.zen/xyz.Default" "$HOME/.config/skwd-bazzite"
echo 'box=skwd-test-box' > "$HOME/.config/skwd-bazzite/config"

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
