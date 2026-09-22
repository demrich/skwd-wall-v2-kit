# skwd-wall-v2-kit

My personal setup for [skwd-wall v2](https://copr.fedorainfracloud.org/coprs/piixini/skwd-wall-v2/)
(wallpaper-derived theming) on KDE Plasma: the Plasma theming layer and the
matugen templates for the apps I run.

**Scope: this is a personal setup repo, not a distributable installer.** It is
built and tested against exactly one machine, a `bazzite-nvidia-open` host
running Plasma 6 on Wayland. It is public because the pieces are useful to
read, not because it is expected to work unmodified anywhere else. The
`integrations` list and the matugen templates target my app set (Zen browser,
Vesktop, Spicetify, Ghostty, btop, yazi, ...), and
`bin/skwd-wall-v2-session` works around specific skwd-wall v2 daemon bugs.
Expect to edit both.

skwd-wall v2 itself is upstream, and installing it is not this repo's job any
more. skwd-bazzite installs it into a Distrobox without layering, copies the
renderers and the Plasma wallpaper plugin out to the host, runs
`skwd-walld.service`, and keeps all of that current. What's here sits on top:
a login unit that re-applies the theme walld's startup restore skips, two
hooks that push generated colors into places `kdeglobals` doesn't reach
(notifications, the window ring), and a `skwd-theme` CLI to inspect and
validate what's currently applied. Personal cosmetic extras (custom window
decorations, a compiled pager, widgets) are left out on purpose; none of that
is needed for theme switching to work.

## Prerequisites

- KDE Plasma 6, Wayland
- skwd-bazzite, installed (`skwd-bazzite install`)
- `jq`, `python3`

## Install

```bash
git clone <this-repo-url> skwd-wall-v2-kit
cd skwd-wall-v2-kit
./install.sh
```

Then **log out and back in**: the theme restore runs on
`graphical-session.target`, right after skwd-bazzite's `skwd-walld.service`,
and the login path is what's actually been tested rather than a manual
`systemctl --user start`.

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
`config.json`, default `{"dynamic": "poster", "mode": "follow"}`). It
overwrites your lock screen's `WallpaperPlugin`; set `mode` to `"off"` if you
use a different lock-screen wallpaper plugin. See
[docs/troubleshooting.md](docs/troubleshooting.md) if it isn't syncing.

## Uninstall

```bash
./uninstall.sh            # stop the theme unit, remove installed scripts
./uninstall.sh --purge    # also remove ~/.config/skwd-wall-v2
```

skwd-wall v2 itself stays installed; `skwd-bazzite uninstall` removes it.

## Troubleshooting

See [docs/troubleshooting.md](docs/troubleshooting.md), in particular why
this kit re-applies the theme at login, and why the units' timeouts matter.

## Testing

CI (shellcheck, an `install.sh`/`uninstall.sh` round trip, and unit tests for
the trickier logic) runs on every push and PR. See
[docs/testing.md](docs/testing.md) for what it covers, what still needs a
real Plasma session to check by hand, and how to run it yourself with
`tests/run.sh`.

## License

MIT, see [LICENSE](LICENSE). skwd-wall v2 itself has its own license; see
`/usr/share/licenses/skwd-paper` inside the Distrobox container.
