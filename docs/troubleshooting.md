# Troubleshooting

Pinned to **skwd-wall v2 1.0.0-beta.18**; the workarounds below were first
verified against beta.11 and re-checked against the beta.12-beta.18 release
notes on 2026-09-21, which never claim either bug fixed. If a future upstream
release fixes one, delete the corresponding workaround from this kit rather
than keeping both; check the comment at the top of the affected script.

## Why does this kit run its own login script instead of just enabling skwd-walld?

Two upstream beta.11 gaps, both reproducible:

1. **skwd-walld's own startup restore never runs theme steps.** It re-applies
   the wallpaper on login, but no integrations, no post-processing, so you
   get the right wallpaper and the *previous session's* colors.
2. **`skwd-helm retheme` can't see a restored wallpaper.** It answers "no
   current wallpaper to retheme" right after a restore, because the restore
   path never populates the in-memory current wallpaper.

`bin/skwd-wall-v2-session` (run by `systemd/skwd-wall-v2.service` on login)
works around both: it starts `skwd-walld`, waits for it to report a current
wallpaper, then does an explicit `skwd-helm apply <that wallpaper>`. It has
to be `apply`, not `retheme`, because `apply` is what actually runs
integrations and post-processing.

## Logout takes a moment, or the whole session freezes on logout/login

The older skwd daemon design held `plasma-workspace.target` teardown open
for several seconds on stop, and a `PartOf=graphical-session.target` unit
that's slow to stop can race the *next* login's start transaction, freezing
the session. `systemd/skwd-wall-v2.service` fixes this with a fast,
targeted `pkill` on stop, capped at `TimeoutStopSec=5s`.

Replacing that stop action with a Distrobox teardown brings the freeze
back (teardown is too slow), and so does raising `TimeoutStopSec` or
enabling a second unit that also tries to own the theme restore.

If `install.sh` refused to run because it found `skwd-daemon.service`
enabled, that's this exact failure mode: disable that unit first
(`systemctl --user disable --now skwd-daemon.service`).

## Wallpaper changes but colors don't

Check `~/.cache/skwd-wall-v2/hooks.log`. Each post-processing hook
(`skwd-plasma-scheme`, `skwd-plasma-surfaces`) logs one line per run, so a
hook that quietly exited on a guard is distinguishable from one that never
ran at all. Common causes:
- `theme.policy` in `config.json` is `fixed` instead of `wallpaper`.
- `integrations` is empty, or every integration's `output` path is wrong.
- `timed out waiting for ...SkwdMatugen.colors` in the log means no render
  happened at all: check `theme.policy` again, and that
  `skwd-wall-v2.service` is actually running (`systemctl --user status
  skwd-wall-v2.service`).

## `skwd-helm` commands hang or fail with "no such container"

The container isn't running or was never assembled. Check
`distrobox enter -n skwd-wall-v2-fedora -- skwd-helm current` directly. If
that alone hangs or errors, the problem is the container/package install,
not this kit's scripts. Re-run `./install.sh`, it's idempotent.

## `Plasma wallpaper script exited with signal: 13 (SIGPIPE)`

Plasma's wallpaper containment got wedged, usually after a bad `paths.*`
value in `config.json` (they must be **absolute host paths**; `~` does not
expand there, see comments in `config/config.json.tmpl`). Fix the path,
then: `systemctl --user stop skwd-wall-v2.service`,
`pkill -f '^/usr/bin/skwd-walld'`, `systemctl --user start
skwd-wall-v2.service`.

## Config edits do nothing

`skwd-walld` reads `config.json` at its own startup, inside the container.
Restart the unit to pick up an edit: `systemctl --user restart
skwd-wall-v2.service`.

## Renderer binary doesn't run after install (glibc / version mismatch)

`install.sh` copies the wallpaper renderer binaries out of the Fedora 44
container onto your host filesystem, because rendering needs direct host
GPU/Wayland access the container can't provide. Those binaries are linked
against Fedora 44's glibc. If your **host** is an older Fedora release than
the container's base image, they may fail to run. Fedora Atomic hosts track
current releases closely so this is unlikely in practice, but if
`skwd-paper-v2`/`skwd-wall-still`/`skwd-wall-vk` fail with a glibc version
error, your host is older than Fedora 44. Update it, or change the `image=`
line in `distrobox-assemble.ini` to match your host's Fedora version (if the
Copr repo publishes packages for it) before re-running `install.sh`.

## Known limitations, not bugs

- **Notifications/KRunner/applet popups** take their chrome from the Plasma
  *desktop theme*, not the color scheme, and `kdeglobals` doesn't reach
  them. This kit doesn't ship a custom desktop theme to fix that (it would
  only look right paired with a specific base theme this kit deliberately
  doesn't assume you have), so those surfaces may not perfectly match your
  generated palette.
- **Custom window border/decoration styling** isn't part of this kit at
  all; it's purely a look-and-feel choice, unrelated to theme switching
  working.
- **Lock screen wallpaper sync failing with `could not synchronize KDE
  Plasma lock-screen wallpaper`** isn't an upstream bug: `skwd-walld` shells
  out to `kwriteconfig6` from inside the Distrobox container to write
  `kscreenlockerrc`, and the bare `fedora:44` base image this kit builds
  doesn't have it. `install.sh` installs `kf6-kconfig` for this now; if
  you're still seeing the warning, run `distrobox enter <box> -- sudo dnf
  install kf6-kconfig` (or re-run `install.sh`) and restart
  `skwd-wall-v2.service`. This writes `plasma.lockScreen` (see
  `config/config.json.tmpl`) straight into your live `kscreenlockerrc`,
  overwriting `WallpaperPlugin` - if you use a different lock-screen
  wallpaper plugin, set `plasma.lockScreen.mode` to `"off"` instead.
- Bazzite/Kinoite's Breeze package sometimes ships without the default
  Alt+Tab window switcher (`kwriteconfig6 --file kwinrc --group TabBox --key
  LayoutName thumbnail_grid` fixes it). Unrelated to this kit, just a common
  trip-up on the same image.
