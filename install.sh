#!/usr/bin/env bash
# Install skwd-wall v2 + the KDE Plasma integration layer in this kit.
#
#   ./install.sh              interactive install
#   ./install.sh --yes        don't prompt (skip optional browser integration)
#   ./install.sh --box NAME   use a Distrobox name other than skwd-wall-v2-fedora
#
# Re-running after a partial or failed install won't duplicate anything or
# clobber existing config; each step checks first.
set -euo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOX="${SKWD_WALL_V2_BOX:-skwd-wall-v2-fedora}"
ASSUME_YES=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --yes|-y) ASSUME_YES=1; shift ;;
        --box) BOX="$2"; shift 2 ;;
        -h|--help) sed -n '2,9p' "$0" | sed 's/^# \?//'; exit 0 ;;
        *) echo "install.sh: unknown option $1" >&2; exit 2 ;;
    esac
done

die() { echo "install.sh: $*" >&2; exit 1; }
info() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*"; }

ask() {
    [ "$ASSUME_YES" -eq 1 ] && return 1
    local prompt="$1" ans
    read -rp "$prompt [y/N] " ans
    [[ "$ans" == [yY]* ]]
}

info "Checking prerequisites"
command -v distrobox >/dev/null 2>&1 || die "distrobox not found - install it first (it's how skwd-wall v2 runs on an immutable host)"
command -v systemctl >/dev/null 2>&1 || die "systemctl not found - this kit needs systemd --user units"
command -v jq >/dev/null 2>&1 || die "jq not found - install it (dnf install jq, or via a distrobox/flatpak-exported copy on PATH)"
command -v python3 >/dev/null 2>&1 || die "python3 not found - install it (dnf install python3); needed by skwd-theme validate's contrast check"

if [ "${XDG_SESSION_DESKTOP:-}" != "KDE" ] && [ "${DESKTOP_SESSION:-}" != "plasma" ] && [ -z "${KDE_FULL_SESSION:-}" ]; then
    warn "This doesn't look like a KDE Plasma session (XDG_SESSION_DESKTOP=${XDG_SESSION_DESKTOP:-unset})."
    warn "skwd-wall v2's Plasma integration hooks (kwriteconfig6, plasma-apply-colorscheme) need Plasma 6."
    if [ "$ASSUME_YES" -eq 1 ]; then
        warn "--yes given, continuing anyway."
    else
        ask "Continue anyway?" || exit 1
    fi
fi

if systemctl --user is-enabled skwd-daemon.service >/dev/null 2>&1; then
    die "legacy skwd-daemon.service is enabled. Two units racing to restore the theme on login is a known cause of logout freezes. Run: systemctl --user disable --now skwd-daemon.service, then re-run this installer."
fi

# Package versions pinned here on purpose: skwd-wall-v2-session's login
# workaround targets specific daemon-restore bugs (see docs/troubleshooting.md).
# An unversioned `dnf install` on an existing box would silently upgrade past
# the version this kit was verified against.
#
# Bumped beta.11 -> beta.17 on 2026-09-20. The login workaround is retained:
# no release note between beta.12 and beta.17 claims the startup restore now
# runs theme steps, nor that `skwd-helm retheme` can see a restored wallpaper.
# Re-test those two directly before dropping it.
SKWD_NVRS=(
    skwd-wall-v2-1.0.0~beta.17-4.fc44
    skwd-paper-1.0.0~beta.17-4.fc44
    skwd-deck-1.0.0~beta.17-4.fc44
    skwd-lens-1.0.0~beta.17-4.fc44
    skwd-lens-model-1.0.0-1.fc44
)

box_exists() {
    distrobox list --no-color 2>/dev/null \
        | awk -F'|' 'NR>1{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}' \
        | grep -qx "$1"
}

info "Assembling Distrobox container '$BOX'"
if box_exists "$BOX"; then
    info "container '$BOX' already exists, reusing it"
else
    ASSEMBLE_FILE="$(mktemp)"
    trap 'rm -f "$ASSEMBLE_FILE"' EXIT
    sed "s/__BOX__/$BOX/" "$KIT/distrobox-assemble.ini" > "$ASSEMBLE_FILE"
    distrobox assemble create --file "$ASSEMBLE_FILE" \
        || die "distrobox assemble create failed - see output above"
fi

info "Enabling the Copr repo and installing pinned packages"
distrobox enter -n "$BOX" -- sudo dnf -y copr enable piixini/skwd-wall-v2 >/dev/null \
    || die "copr enable failed inside '$BOX' - is dnf5-plugins present? (see distrobox-assemble.ini)"
distrobox enter -n "$BOX" -- sudo dnf -y install "${SKWD_NVRS[@]}" >/dev/null \
    || die "package install inside '$BOX' failed - the pinned NVRs in install.sh may no longer be in the Copr repo; check https://copr.fedorainfracloud.org/coprs/piixini/skwd-wall-v2/ for current versions"

# Not a Copr pin (plain Fedora repo, unversioned on purpose) - walld shells
# out to kwriteconfig6 from inside the container to sync the KDE Plasma
# lock-screen wallpaper, and the bare fedora:44 base image doesn't have it.
# Without this, every apply logs "could not synchronize KDE Plasma
# lock-screen wallpaper" and silently falls back to a static poster.
info "Installing kwriteconfig6 (KDE lock-screen sync)"
distrobox enter -n "$BOX" -- sudo dnf -y install kf6-kconfig >/dev/null \
    || die "kf6-kconfig install inside '$BOX' failed"

distrobox enter -n "$BOX" -- command -v skwd-helm >/dev/null 2>&1 \
    || die "skwd-helm not found inside '$BOX' after install - something upstream changed"

# host-side renderer binaries
# skwd-walld runs in the container, but wallpaper rendering needs direct
# host GPU/Wayland access, so config.json's paths.* must point at HOST copies
# of the renderer. Since Distrobox shares $HOME with the container, copying
# them from inside the container writes straight to the host's $HOME.
info "Copying renderer binaries out to the host (\$HOME is shared with the container)"
mkdir -p "$HOME/.local/libexec" "$HOME/.local/lib/skwd-paper" "$HOME/.local/bin"
distrobox enter -n "$BOX" -- bash -c '
    set -e
    cp -f /usr/bin/skwd-paper-v2   "$HOME/.local/libexec/skwd-paper-v2"
    cp -f /usr/bin/skwd-wall-still "$HOME/.local/libexec/skwd-wall-still"
    cp -f /usr/bin/skwd-wall-vk    "$HOME/.local/libexec/skwd-wall-vk"
    # Whole directory, not just *.so*: skwd-paper also ships a helper binary
    # (skwd-paper-tinier) alongside the ffmpeg libs.
    cp -rf /usr/lib/skwd-paper/. "$HOME/.local/lib/skwd-paper/" 2>/dev/null || true
'

cat > "$HOME/.local/bin/skwd-paper-v2" <<'WRAP'
#!/bin/sh
set -eu
paper_root="$HOME/.local"
paper_lib="$paper_root/lib/skwd-paper"
if [ -n "${LD_LIBRARY_PATH:-}" ]; then
    export LD_LIBRARY_PATH="$paper_lib:$LD_LIBRARY_PATH"
else
    export LD_LIBRARY_PATH="$paper_lib"
fi
exec "$paper_root/libexec/skwd-paper-v2" "$@"
WRAP
chmod +x "$HOME/.local/bin/skwd-paper-v2"

info "Installing host-side scripts to ~/.local/bin and ~/.local/lib"
install -m 755 "$KIT/bin/skwd-wall-v2-session" "$HOME/.local/bin/skwd-wall-v2-session"
install -m 755 "$KIT/bin/skwd-plasma-scheme"   "$HOME/.local/bin/skwd-plasma-scheme"
install -m 755 "$KIT/bin/skwd-plasma-surfaces" "$HOME/.local/bin/skwd-plasma-surfaces"
install -m 755 "$KIT/bin/skwd-theme"           "$HOME/.local/bin/skwd-theme"
mkdir -p "$HOME/.local/lib/skwd-wall-v2"
install -m 644 "$KIT/lib/theme-lib.sh"       "$HOME/.local/lib/skwd-wall-v2/theme-lib.sh"
install -m 755 "$KIT/lib/check-contrast.py"  "$HOME/.local/lib/skwd-wall-v2/check-contrast.py"

case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) warn "\$HOME/.local/bin is not on PATH - add it to your shell rc to use 'skwd-theme'" ;;
esac

info "Installing matugen templates"
TEMPLATE_DIR="$HOME/.config/skwd-wall-v2/matugen/templates"
mkdir -p "$TEMPLATE_DIR"
for tmpl in "$KIT"/matugen/templates/*; do
    dest="$TEMPLATE_DIR/$(basename "$tmpl")"
    if [ -e "$dest" ]; then
        info "$(basename "$tmpl") already exists at $dest - leaving it alone"
    else
        cp "$tmpl" "$dest"
    fi
done

CONF="$HOME/.config/skwd-wall-v2/config.json"
if [ -f "$CONF" ]; then
    info "config.json already exists at $CONF - leaving it alone"
    warn "compare it against config/config.json.tmpl by hand if you want the latest defaults"
else
    info "Generating $CONF"
    sed "s|__HOME__|$HOME|g" "$KIT/config/config.json.tmpl" > "$CONF"

    ZEN_DIR="$(find "$HOME/.var/app/app.zen_browser.zen/.zen" -maxdepth 1 -type d -name '*.Default*' 2>/dev/null | head -1 || true)"
    if [ -n "$ZEN_DIR" ] && ask "Found a Zen browser profile ($ZEN_DIR) - add live theming for it?"; then
        jq --arg out1 "${ZEN_DIR/#$HOME/\~}/chrome/userChrome.css" \
           --arg out2 "${ZEN_DIR/#$HOME/\~}/chrome/userContent.css" \
           '.integrations += [
              {"name":"zen","output":$out1,"template":"zen.css"},
              {"name":"zen-content","output":$out2,"template":"zen-content.css"}
            ]' "$CONF" > "$CONF.tmp" && mv "$CONF.tmp" "$CONF"
    fi
fi

info "Installing the systemd user unit"
mkdir -p "$HOME/.config/systemd/user"
install -m 644 "$KIT/systemd/skwd-wall-v2.service" "$HOME/.config/systemd/user/skwd-wall-v2.service"
systemctl --user daemon-reload
systemctl --user enable skwd-wall-v2.service

echo
info "Done."
cat <<EOF

Next steps:
  1. Log out and back in (this exercises the same graphical-session.target
     path the unit runs on - don't just 'systemctl --user start' it).
  2. Drop some wallpapers in ~/Pictures/Wallpapers, then open the
     'skwd-wall v2' picker from your app launcher to browse and apply one.
  3. Run:  skwd-theme current
           skwd-theme validate

See docs/troubleshooting.md if a theme apply doesn't propagate everywhere,
or if logout takes a moment the first time.
EOF
