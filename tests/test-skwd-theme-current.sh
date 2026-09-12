#!/usr/bin/env bash
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
. "$KIT/tests/lib/harness.sh"

if [ "${SKWD_TEST_ALLOW_DISTROBOX_STUB:-0}" != "1" ]; then
    skip "set SKWD_TEST_ALLOW_DISTROBOX_STUB=1 in a disposable/root CI container to run this"
fi
if [ -e /usr/bin/distrobox ]; then
    skip "/usr/bin/distrobox already exists - refusing to touch a real install"
fi
if [ ! -w /usr/bin ]; then
    skip "/usr/bin is not writable here"
fi

install -m 755 "$KIT/tests/stubs/distrobox" /usr/bin/distrobox
trap 'rm -f /usr/bin/distrobox' EXIT

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp"
export SKWD_WALL_V2_BOX="skwd-test-box"

mkdir -p "$HOME/.local/share/color-schemes" "$HOME/.config/skwd-wall-v2" "$HOME/Pictures/Wallpapers"
cp "$KIT/tests/fixtures/good.colors" "$HOME/.local/share/color-schemes/SkwdMatugen.colors"
cat > "$HOME/.config/skwd-wall-v2/config.json" <<'EOF'
{"theme": {"policy": "wallpaper", "mode": "auto"}, "integrations": []}
EOF

export SKWD_TEST_HELM_CURRENT_PATH="$HOME/Pictures/Wallpapers/example.jpg"
touch "$SKWD_TEST_HELM_CURRENT_PATH"

out="$("$KIT/bin/skwd-theme" current)"
echo "$out" | grep -q '^wallpaper:    example.jpg$' || { echo "$out" >&2; fail "current: did not report the stubbed wallpaper"; }
echo "$out" | grep -q 'no integrations declared' || { echo "$out" >&2; fail "current: expected 'no integrations declared' for an empty integrations list"; }

pass "skwd-theme current parses a stubbed skwd-helm current --json end to end"
