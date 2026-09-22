#!/usr/bin/env bash
# Remove what install.sh put in place.
#
#   ./uninstall.sh              stop the theme unit, remove installed scripts
#   ./uninstall.sh --purge      also remove ~/.config/skwd-wall-v2 (your themes
#                               and config)
#   ./uninstall.sh --purge -y   purge without the confirmation prompt
#
# skwd-wall v2 itself stays; remove it with: skwd-bazzite uninstall
set -euo pipefail

PURGE=0
ASSUME_YES=0
for arg in "$@"; do
    case "$arg" in
        --purge) PURGE=1 ;;
        -y|--yes) ASSUME_YES=1 ;;
        *) echo "uninstall.sh: unknown option $arg" >&2; exit 2 ;;
    esac
done

info() { printf '\033[1;36m==>\033[0m %s\n' "$*"; }

info "Stopping and disabling the systemd unit"
systemctl --user disable --now skwd-wall-v2-theme.service 2>/dev/null || true
rm -f "$HOME/.config/systemd/user/skwd-wall-v2-theme.service"
systemctl --user daemon-reload

info "Removing installed scripts"
rm -f "$HOME/.local/bin/skwd-wall-v2-session" \
      "$HOME/.local/bin/skwd-plasma-scheme" \
      "$HOME/.local/bin/skwd-plasma-surfaces" \
      "$HOME/.local/bin/skwd-theme"
rm -rf "$HOME/.local/lib/skwd-wall-v2"

if [ "$PURGE" -eq 1 ]; then
    if [ "$ASSUME_YES" -ne 1 ]; then
        if [ ! -t 0 ]; then
            info "Refusing to purge non-interactively without -y/--yes; everything else above is already done."
            exit 0
        fi
        read -rp "This deletes ~/.config/skwd-wall-v2 (your themes/config). Continue? [y/N] " ans
        [[ "$ans" == [yY]* ]] || { info "Purge cancelled; everything else above is already done."; exit 0; }
    fi
    info "Purging config"
    rm -rf "$HOME/.config/skwd-wall-v2"
else
    info "Left in place: ~/.config/skwd-wall-v2 (your config + generated colour schemes)"
    info "Re-run with --purge to remove it too."
fi
info "skwd-wall v2 itself is untouched; remove it with: skwd-bazzite uninstall"
