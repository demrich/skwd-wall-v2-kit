#!/usr/bin/env bash
# Remove what install.sh put in place.
#
#   ./uninstall.sh            stop the service, remove installed scripts/unit
#   ./uninstall.sh --purge    also remove ~/.config/skwd-wall-v2 and the
#                             Distrobox container (destroys your themes/config)
set -euo pipefail

BOX="${SKWD_WALL_V2_BOX:-skwd-wall-v2-fedora}"
PURGE=0
[ "${1:-}" = "--purge" ] && PURGE=1

info() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }

info "Stopping and disabling the systemd unit"
systemctl --user disable --now skwd-wall-v2.service 2>/dev/null || true
rm -f "$HOME/.config/systemd/user/skwd-wall-v2.service"
systemctl --user daemon-reload

info "Removing installed scripts"
rm -f "$HOME/.local/bin/skwd-wall-v2-session" \
      "$HOME/.local/bin/skwd-plasma-scheme" \
      "$HOME/.local/bin/skwd-plasma-surfaces" \
      "$HOME/.local/bin/skwd-theme" \
      "$HOME/.local/bin/skwd-paper-v2"
rm -rf "$HOME/.local/lib/skwd-wall-v2"
rm -f "$HOME/.local/libexec/skwd-paper-v2" \
      "$HOME/.local/libexec/skwd-wall-still" \
      "$HOME/.local/libexec/skwd-wall-vk"
rm -rf "$HOME/.local/lib/skwd-paper"

if [ "$PURGE" -eq 1 ]; then
    read -rp "This deletes ~/.config/skwd-wall-v2 (your themes/config) and the '$BOX' container. Continue? [y/N] " ans
    [[ "$ans" == [yY]* ]] || { info "Purge cancelled; everything else above is already done."; exit 0; }
    info "Purging config and the Distrobox container"
    rm -rf "$HOME/.config/skwd-wall-v2"
    distrobox rm -f "$BOX" 2>/dev/null || true
else
    info "Left in place: ~/.config/skwd-wall-v2 (your config + generated colour schemes)"
    info "Left in place: Distrobox container '$BOX'"
    info "Re-run with --purge to remove those too."
fi
