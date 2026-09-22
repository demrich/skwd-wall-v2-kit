#!/usr/bin/env bash
# Install the KDE Plasma theming layer in this kit on top of skwd-wall v2.
#
#   ./install.sh              interactive install
#   ./install.sh --yes        don't prompt (skip optional browser integration)
#
# skwd-wall v2 itself (the Distrobox, the Copr packages, the renderers and
# the Plasma wallpaper plugin on the host, the daemon unit, and updates) is
# installed and kept current by skwd-bazzite, which has to be installed first.
#
# Re-running after a partial or failed install won't duplicate anything or
# clobber existing config; each step checks first.
set -euo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSUME_YES=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --yes|-y) ASSUME_YES=1; shift ;;
        -h|--help) sed -n '2,12p' "$0" | sed 's/^# \?//'; exit 0 ;;
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
command -v systemctl >/dev/null 2>&1 || die "systemctl not found - this kit needs systemd --user units"
command -v jq >/dev/null 2>&1 || die "jq not found - install it (dnf install jq, or via a distrobox/flatpak-exported copy on PATH)"
command -v python3 >/dev/null 2>&1 || die "python3 not found - install it (dnf install python3); needed by skwd-theme validate's contrast check"
SKWD_BAZZITE="$(command -v skwd-bazzite || echo "$HOME/.local/bin/skwd-bazzite")"
[ -x "$SKWD_BAZZITE" ] && [ -f "${XDG_CONFIG_HOME:-$HOME/.config}/skwd-bazzite/config" ] \
    || die "skwd-bazzite is not installed. Install it first (skwd-bazzite install), then re-run this."

if [ "${XDG_SESSION_DESKTOP:-}" != "KDE" ] && [ "${DESKTOP_SESSION:-}" != "plasma" ] && [ -z "${KDE_FULL_SESSION:-}" ]; then
    warn "This doesn't look like a KDE Plasma session (XDG_SESSION_DESKTOP=${XDG_SESSION_DESKTOP:-unset})."
    warn "The theming hooks (kwriteconfig6, plasma-apply-colorscheme) need Plasma 6."
    if [ "$ASSUME_YES" -eq 1 ]; then
        warn "--yes given, continuing anyway."
    else
        ask "Continue anyway?" || exit 1
    fi
fi

if systemctl --user is-enabled skwd-daemon.service >/dev/null 2>&1; then
    die "legacy skwd-daemon.service is enabled. Two units racing to restore the theme on login is a known cause of logout freezes. Run: systemctl --user disable --now skwd-daemon.service, then re-run this installer."
fi

info "Installing host-side scripts to ~/.local/bin and ~/.local/lib"
mkdir -p "$HOME/.local/bin" "$HOME/.local/lib/skwd-wall-v2"
install -m 755 "$KIT/bin/skwd-wall-v2-session" "$HOME/.local/bin/skwd-wall-v2-session"
install -m 755 "$KIT/bin/skwd-plasma-scheme"   "$HOME/.local/bin/skwd-plasma-scheme"
install -m 755 "$KIT/bin/skwd-plasma-surfaces" "$HOME/.local/bin/skwd-plasma-surfaces"
install -m 755 "$KIT/bin/skwd-theme"           "$HOME/.local/bin/skwd-theme"
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

info "Installing the login theme-restore unit"
mkdir -p "$HOME/.config/systemd/user"
# The unit this kit used to install started skwd-walld itself; skwd-bazzite's
# skwd-walld.service does that now, and two units starting it race.
if [ -f "$HOME/.config/systemd/user/skwd-wall-v2.service" ]; then
    systemctl --user disable skwd-wall-v2.service >/dev/null 2>&1 || true
    rm -f "$HOME/.config/systemd/user/skwd-wall-v2.service"
fi
install -m 644 "$KIT/systemd/skwd-wall-v2-theme.service" "$HOME/.config/systemd/user/skwd-wall-v2-theme.service"
systemctl --user daemon-reload
systemctl --user enable skwd-wall-v2-theme.service

echo
info "Done."
cat <<EOF

Next steps:
  1. Log out and back in. The theme restore runs on graphical-session.target,
     right after skwd-bazzite's skwd-walld.service.
  2. Open the 'skwd-wall v2' picker from your app launcher and apply a
     wallpaper.
  3. Run:  skwd-theme current
           skwd-theme validate
EOF
