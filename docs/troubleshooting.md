# Troubleshooting

skwd-wall v2 itself (the container, the packages, the renderers and Plasma
wallpaper plugin on the host, `skwd-walld.service`, and updates) is managed by
skwd-bazzite; start with `skwd-bazzite status` for anything in that list.
This page covers the theming layer this kit adds.

The login workaround below was first verified against beta.11 and re-checked
against the beta.12-beta.18 release notes on 2026-09-21, which never claim
either bug fixed. If a future upstream release fixes one, delete the
workaround rather than keeping both; check the comment at the top of
`bin/skwd-wall-v2-session`.

## Why does this kit re-apply the theme at login?

Two upstream gaps, both reproducible:

1. **skwd-walld's own startup restore never runs theme steps.** It re-applies
   the wallpaper on login, but no integrations, no post-processing, so you
   get the right wallpaper and the *previous session's* colors.
2. **`skwd-helm retheme` can't see a restored wallpaper.** It answers "no
   current wallpaper to retheme" right after a restore, because the restore
   path never populates the in-memory current wallpaper.

`bin/skwd-wall-v2-session` (run by `skwd-wall-v2-theme.service` right after
`skwd-walld.service`) works around both: it waits for walld to report a
current wallpaper, then does an explicit `skwd-helm apply <that wallpaper>`.
It has to be `apply`, not `retheme`, because `apply` is what actually runs
integrations and post-processing.

It is its own unit rather than a step inside `skwd-walld.service`, so a slow
restore can only time out itself, never the daemon.

## Logout takes a moment, or the whole session freezes on logout/login

A `PartOf=graphical-session.target` unit that is slow to stop, or whose start
job is still pending, can race the *next* login's start transaction and
freeze the session. Both units involved are bounded for that reason
(`TimeoutStopSec=5s`; `TimeoutStartSec` 30s for walld, 60s for the theme
restore), and walld is stopped with a targeted `pkill`, never a Distrobox
teardown.

The unit this kit used to install, `skwd-wall-v2.service`, also started
walld. `install.sh` disables and removes it, because two units starting walld
is the same race. If `install.sh` refused to run because it found
`skwd-daemon.service` enabled, that's this exact failure mode too: disable
that unit first (`systemctl --user disable --now skwd-daemon.service`).

## The picker applies a wallpaper but the desktop doesn't change

The Plasma wallpaper plugin is missing, stale, or not selected. Run
`skwd-bazzite status`: it shows the installed plugin version and whether a
newer one is waiting. The plugin takes effect at the next login. If it is
installed, right-click the desktop and set the wallpaper type to
`Skwd Paper`; confirm with
`grep wallpaperplugin ~/.config/plasma-org.kde.plasma.desktop-appletsrc`,
which should show `org.skwd.wall.plasma` for your desktop containments.

## Wallpaper changes but colors don't

Check `~/.cache/skwd-wall-v2/hooks.log`. Each post-processing hook
(`skwd-plasma-scheme`, `skwd-plasma-surfaces`) logs one line per run, so a
hook that quietly exited on a guard is distinguishable from one that never
ran at all. Common causes:
- `theme.policy` in `config.json` is `fixed` instead of `wallpaper`.
- `integrations` is empty, or every integration's `output` path is wrong.
- `timed out waiting for ...SkwdMatugen.colors` in the log means no render
  happened at all: check `theme.policy` again, and that walld is running
  (`systemctl --user status skwd-walld.service`).

## Colors are right after a wallpaper change but wrong after login

The login restore did not run or failed:
`journalctl --user -b -u skwd-wall-v2-theme.service`. "no wallpaper to
restore" means walld had not published a current wallpaper within 30s.

## `Plasma wallpaper script exited with signal: 13 (SIGPIPE)`

Plasma's wallpaper containment got wedged, usually after a bad `paths.*`
value in `config.json` (they must be **absolute host paths**; `~` does not
expand there, see comments in `config/config.json.tmpl`). skwd-bazzite also
passes the same host paths to walld through the environment, which overrides
`paths.*`. Fix the path, then `systemctl --user restart skwd-walld.service`.

## Config edits do nothing

`skwd-walld` reads `config.json` at its own startup, inside the container.
Restart it to pick up an edit: `systemctl --user restart skwd-walld.service`.

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
- **Lock screen wallpaper sync** writes `plasma.lockScreen` (see
  `config/config.json.tmpl`) straight into your live `kscreenlockerrc`,
  overwriting `WallpaperPlugin` - if you use a different lock-screen
  wallpaper plugin, set `plasma.lockScreen.mode` to `"off"` instead.
  skwd-bazzite installs `kwriteconfig6` in the container for it.
- Bazzite/Kinoite's Breeze package sometimes ships without the default
  Alt+Tab window switcher (`kwriteconfig6 --file kwinrc --group TabBox --key
  LayoutName thumbnail_grid` fixes it). Unrelated to this kit, just a common
  trip-up on the same image.
