# skwd-wall-v2-kit

Wire [skwd-wall v2](https://copr.fedorainfracloud.org/coprs/piixini/skwd-wall-v2/)
(wallpaper-derived theming) straight into KDE Plasma on a Fedora Atomic
(Bazzite, Kinoite, ...) or any other Fedora + Plasma 6 host, in one script,
without manual container setup or hand-edited config.

skwd-wall v2 itself is upstream; this kit doesn't fork or bundle its code.
What's here is the Distrobox definition and the KDE Plasma integration layer
on top of it: a login/logout service that survives skwd-walld's current
startup quirks, two hooks that push generated colors into places
`kdeglobals` doesn't reach (notifications, the window ring), and a `skwd-theme`
CLI to inspect and validate what's currently applied. Personal cosmetic
extras (custom window decorations, a compiled pager, widgets) are left out
on purpose; none of that is needed for theme switching to work.

## Prerequisites

- KDE Plasma 6, Wayland
- [Distrobox](https://distrobox.it/)
- `jq`, `python3`

Your host distro doesn't matter: `install.sh` always builds a `fedora:44`
Distrobox container (see `distrobox-assemble.ini`) and does the Copr
enable/install inside it, so this works the same on Bazzite, Kinoite, plain
Fedora, or any other Linux with Plasma 6 + Distrobox. Nothing here is
Bazzite-specific, and nothing on the host itself needs to be Fedora - only
Plasma 6 (for the D-Bus/`kwriteconfig6` integration) and Distrobox (for
running on a read-only `/usr`, or any host at all).

## Install

```bash
git clone <this-repo-url> skwd-wall-v2-kit
cd skwd-wall-v2-kit
./install.sh
```

Then **log out and back in**. The theming service runs on
`graphical-session.target`, and the login path is what's actually been
tested, not a manual `systemctl --user start`.

Add wallpapers to `~/Pictures/Wallpapers` (or drop them in from a file
manager or browser at any time, skwd-wall v2 watches that folder live), then
open the `skwd-wall v2` picker from your app launcher to browse and apply
one.

```bash
skwd-theme current           # what's applied, and whether every integration caught up
skwd-theme validate          # structural + WCAG contrast check on the generated scheme
```

These two are diagnostics, not another way to switch wallpapers; the picker
GUI already does that. `current` tells you if an integration (Ghostty, qt6ct,
...) fell behind the last apply, and `validate` catches a malformed or
low-contrast generated scheme before you notice it live.

## What integrations are wired up

By default: KDE color scheme, qt6ct, Ghostty, btop, yazi, Vesktop, Spicetify
(colors + CSS). Delete any block from `integrations` in
`~/.config/skwd-wall-v2/config.json` for an app you don't have; a missing
output directory just makes an apply noisy, it doesn't fail it. Zen browser
theming is offered during install if a Zen profile is detected, since its
integration needs your actual profile directory name to point at.

skwd-wall v2 also syncs the KDE Plasma lock screen (`plasma.lockScreen` in
`config.json`, default `{"dynamic": "poster", "mode": "follow"}`) - this kit
installs `kwriteconfig6` in the container for it. It overwrites your lock
screen's `WallpaperPlugin`; set `mode` to `"off"` if you use a different
lock-screen wallpaper plugin. See
[docs/troubleshooting.md](docs/troubleshooting.md) if it isn't syncing.

## Uninstall

```bash
./uninstall.sh            # stop the service, remove installed scripts/unit
./uninstall.sh --purge    # also remove config + the Distrobox container
```

## Troubleshooting

See [docs/troubleshooting.md](docs/troubleshooting.md), in particular why
this kit runs its own login script instead of just enabling `skwd-walld`
directly, and why the systemd unit's stop timeout matters.

## Testing

CI (shellcheck, an `install.sh`/`uninstall.sh` round trip, and unit tests for
the trickier logic) runs on every push and PR. See
[docs/testing.md](docs/testing.md) for what it covers, what still needs a
real Plasma session before a release, and how to run it yourself with
`tests/run.sh`.

## License

MIT, see [LICENSE](LICENSE). skwd-wall v2 itself has its own license; see
`skwd-paper`'s bundled licenses inside the Distrobox container
(`/usr/share/licenses/skwd-paper`).
