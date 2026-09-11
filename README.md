# skwd-wall-v2-kit

Wire [skwd-wall v2](https://copr.fedorainfracloud.org/coprs/piixini/skwd-wall-v2/)
(wallpaper-derived theming) straight into KDE Plasma on a Fedora Atomic
(Bazzite, Kinoite, ...) or any other Fedora + Plasma 6 host, in one script.
No manual container setup, no hand-edited config.

skwd-wall v2 itself is upstream — this kit doesn't fork or bundle its code.
What's here is the Distrobox definition and the KDE Plasma integration layer
on top of it: a login/logout service that survives skwd-walld's current
startup quirks, two hooks that push generated colors into places
`kdeglobals` doesn't reach (notifications, the window ring), and a `skwd-theme`
CLI to list/apply/validate themes.

## Prerequisites

- Fedora Atomic (Bazzite, Kinoite, ...) or any Fedora install
- KDE Plasma 6, Wayland
- [Distrobox](https://distrobox.it/)
- `jq`

Nothing here is Bazzite-specific — it's Fedora (for the Copr repo) + Plasma 6
(for the D-Bus/`kwriteconfig6` integration) + Distrobox (for running on a
read-only `/usr`).

## Install

```bash
git clone <this-repo-url> skwd-wall-v2-kit
cd skwd-wall-v2-kit
./install.sh
```

Then **log out and back in** — the theming service runs on
`graphical-session.target`, and the login path is what's actually been
tested, not a manual `systemctl --user start`.

Add wallpapers to `~/Pictures/Wallpapers`, then:

```bash
skwd-theme list              # what can be applied
skwd-theme apply <name>      # apply one, live
skwd-theme current           # what's applied, and whether every integration caught up
skwd-theme validate          # structural + WCAG contrast check on the generated scheme
```

`skwd-theme apply` looks for `rice-backup`/`rice-restore` on PATH to snapshot
before it writes and give you an undo — those are a separate personal
project, not part of this kit, so apply still works fine without them, it
just can't be undone automatically.

## What integrations are wired up

By default: KDE color scheme, qt6ct, Ghostty, btop, yazi, Vesktop, Spicetify
(colors + CSS). Delete any block from `integrations` in
`~/.config/skwd-wall-v2/config.json` for an app you don't have — a missing
output directory just makes an apply noisy, it doesn't fail it. Zen browser
theming is offered during install if a Zen profile is detected, since its
integration needs your actual profile directory name to point at.

## Uninstall

```bash
./uninstall.sh            # stop the service, remove installed scripts/unit
./uninstall.sh --purge    # also remove config + the Distrobox container
```

## Not included

Personal cosmetic setup — custom window border/decoration styling, a
compiled Plasma pager, personal widgets — is intentionally out of scope.
None of it is required for theme switching to work; it's a different project.

## Troubleshooting

See [docs/troubleshooting.md](docs/troubleshooting.md) — in particular, why
this kit runs its own login script instead of just enabling `skwd-walld`
directly, and why the systemd unit's stop timeout matters.

## License

MIT, see [LICENSE](LICENSE). skwd-wall v2 itself has its own license — see
`skwd-paper`'s bundled licenses inside the Distrobox container
(`/usr/share/licenses/skwd-paper`).
