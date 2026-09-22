# Testing

## What CI actually covers

There's no Wayland session, no live Plasma, and no GPU on a GitHub Actions
runner, so CI can't drive the real thing end to end. What it *can* do, and
does on every push/PR (`.github/workflows/ci.yml`):

- **shellcheck** and `bash -n` on every script, `python3 -m py_compile` on
  `lib/check-contrast.py`.
- **`install.sh` -> `uninstall.sh` round trip** into a throwaway `$HOME`,
  using the documented `--yes` invocation, with `distrobox`/`systemctl`
  replaced by stubs (`tests/stubs/`). Confirms every file `install.sh` is
  supposed to write actually lands, `config.json` is generated and valid,
  re-running doesn't clobber an existing config, and `uninstall.sh --purge`
  removes everything again.
- **Cross-file consistency**: every `integrations[].template` in
  `config/config.json.tmpl` exists under `matugen/templates/`, every
  `postProcessing[].command` and `paths.*` matches a location `install.sh`
  actually writes. Catches a rename that would otherwise only show up as a
  silently-broken integration for a downloader.
- **`skwd_wait_for_render`** (the subtlest logic in the repo - see the
  comment above it in `lib/theme-lib.sh`) against all four documented cases:
  cold start, render already landed, render pending then arrives, timeout.
- **`skwd-theme validate`** and `check-contrast.py`'s WCAG contrast math
  against fixture `.colors` files (good, missing group, out-of-range RGB,
  low contrast).
- **`skwd-theme current`**, by stubbing `/usr/bin/distrobox` - but only
  inside the CI job's disposable, root, Fedora 44 *container* (see the guard
  at the top of `tests/test-skwd-theme-current.sh`). This never runs
  anywhere else; it refuses to touch a path that already exists.

Run the whole local/CI-safe suite yourself with:

```bash
tests/run.sh
```

## What still needs a real host

Nothing simulates these; they need an actual Bazzite/Kinoite (or any Fedora
+ Plasma 6 Wayland) session with a GPU. Before tagging a release, on a real
machine:

1. `plasma-apply-colorscheme` actually repaints kdeglobals-driven surfaces.
2. The `SkwdWallA`/`SkwdWallB` A/B flip in `skwd-plasma-scheme` (re-applying
   the same wallpaper still repaints, since plasma-apply-colorscheme refuses
   a scheme that's already current by name).
3. Logout/login timing: enable the unit, log out, log back in, confirm no
   freeze and that the previous theme is restored (see
   [troubleshooting.md](troubleshooting.md) for what a regression here looks
   like).

## Adding a stub or a fixture

- `tests/stubs/distrobox`, `tests/stubs/systemctl` and
  `tests/stubs/skwd-bazzite` fake just enough of
  each command's behavior for `install.sh`/`uninstall.sh`/`skwd-theme` to
  run against a throwaway `$HOME`. They're intentionally not a full
  simulation - extend them only when a real code path needs a new case.
- `tests/fixtures/*.colors` are minimal, hand-built KDE color scheme files.
  `good.colors` is the baseline; the others each break exactly one thing
  (`validate`'s required groups, an out-of-range RGB triple, WCAG contrast).
