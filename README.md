# skwd-wall-v2-kit

My personal setup for [skwd-wall v2](https://copr.fedorainfracloud.org/coprs/piixini/skwd-wall-v2/)
(wallpaper-derived theming) on KDE Plasma: the Distrobox definition, the
Plasma integration layer, and the matugen templates for the apps I run.

**Scope: this is a personal setup repo, not a distributable installer.** It is
built and tested against exactly one machine, a `bazzite-nvidia-open` host
running Plasma 6 on Wayland. It is public because the pieces are useful to
read, not because it is expected to work unmodified anywhere else. Two things
in particular will not transfer: the `integrations` list and the matugen
templates target my app set (Zen browser, Vesktop, Spicetify, Ghostty, btop,
yazi, ...), and `bin/skwd-wall-v2-session` works around specific skwd-wall v2
daemon bugs, which is also the only reason the package versions are pinned.
Expect to edit both.

skwd-wall v2 itself is upstream; this kit doesn't fork or bundle its code.
What's here is the Distrobox definition and the KDE Plasma integration layer
on top of it: a login/logout service that survives skwd-walld's current
startup quirks, two hooks that push generated colors into places
`kdeglobals` doesn't reach (notifications, the window ring), and a `skwd-theme`
CLI to inspect and validate what's currently applied.

The split between host and container is not a matter of taste. Plasma owns
the background layer, so upstream ships `skwd-paper-plasma`, a Plasma
wallpaper plugin that plasmashell loads and that spawns the renderer binaries
itself. Anything plasmashell loads or executes has to be on the host, which
is why `install.sh` copies the plugin, its QML module, and the renderers out
of the container, and why `paths.*` in `config.json` are absolute host paths.
Only the daemon, the picker, and the template rendering stay inside. Personal cosmetic
extras (custom window decorations, a compiled pager, widgets) are left out
on purpose; none of that is needed for theme switching to work.

## Prerequisites

- KDE Plasma 6, Wayland
- [Distrobox](https://distrobox.it/)
- `jq`, `python3`

The wallpaper renderers are copied out of the container and run directly on
the host for GPU access, so the host also needs their shared libraries at
runtime: `libshaderc`, `spirv-tools-libs`, `libva`, `libdav1d`, `libdrm`,
`libwayland-client`. Bazzite ships all of these in its base image (verified
on `bazzite-nvidia-open` 44.20260921, none of them layered). A leaner host,
including plain Kinoite or a minimal Fedora install, may be missing
`libshaderc`/`spirv-tools-libs` in particular, and `install.sh` does not
check for them, so a gap shows up later as the renderer failing to start
rather than as an install error. The ffmpeg libraries skwd-paper needs are
bundled by the package itself and copied out alongside the binaries, so
those never have to be present on the host.

`install.sh` always builds a `fedora:44` Distrobox container (see
`distrobox-assemble.ini`) and does the Copr enable/install inside it, so the
host itself does not have to be Fedora. In principle that makes the container
side portable to any Plasma 6 + Distrobox host. In practice only Bazzite has
been tested, and the host still needs Plasma 6 for the D-Bus/`kwriteconfig6`
integration plus the renderer libraries listed above.

## Install

```bash
git clone <this-repo-url> skwd-wall-v2-kit
cd skwd-wall-v2-kit
./install.sh
```

Then **log out and back in**. Two things need it: the theming service runs on
`graphical-session.target`, and the login path is what's actually been tested
rather than a manual `systemctl --user start`; and Plasma only picks up the
QML import path for the wallpaper plugin when `startplasma` sources
`~/.config/plasma-workspace/env/` at session start.

If the desktop still doesn't change when you apply a wallpaper, right-click
the desktop and set the wallpaper type to **Skwd Paper** once.

Add wallpapers to `~/Pictures/Wallpapers` (or drop them in from a file
manager or browser at any time, skwd-wall v2 watches that folder live), then
open the `skwd-wall v2` picker from your app launcher to browse and apply
one. The picker runs inside the container, so `install.sh` writes a host
launcher for it (`~/.local/share/applications/skwd-wall-v2-kit.desktop`) that
enters the container and starts it; `uninstall.sh` removes that again.

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
real Plasma session to check by hand, and how to run it yourself with
`tests/run.sh`.

## License

MIT, see [LICENSE](LICENSE). skwd-wall v2 itself has its own license; see
`skwd-paper`'s bundled licenses inside the Distrobox container
(`/usr/share/licenses/skwd-paper`).
