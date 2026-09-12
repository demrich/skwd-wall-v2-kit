#!/usr/bin/env python3
"""Check a generated KDE .colors file for text that cannot be read.

skwd-theme validate already proves a scheme is well-formed: required groups
present, every value an R,G,B triple in range. A scheme can pass all of
that and still render white text on a white button, because structural
validity says nothing about whether a human can read the result. This is
the perceptual half.

Each [Colors:*] group carries its own BackgroundNormal, so the pairs are read
out of the file itself rather than assumed from a table. That keeps this
honest if a template changes which role feeds which key.

Exit 0 = readable, 1 = failures found, 2 = could not parse.
"""

from __future__ import annotations

import sys
from pathlib import Path

TEXT_MIN = 4.5      # WCAG AA, body text
BORDER_MIN = 3.0    # WCAG AA, non-text UI (decorations, inactive separators)

# Keys rendered as text on their group's BackgroundNormal, and the floor each
# one has to clear. ForegroundNormal is body text; Decoration* are borders and
# focus rings; ForegroundInactive is dimmed-but-still-meant-to-be-read.
KEY_MIN = {
    "ForegroundNormal": TEXT_MIN,
    "ForegroundActive": TEXT_MIN,
    "ForegroundLink": TEXT_MIN,
    "ForegroundVisited": TEXT_MIN,
    "ForegroundNegative": TEXT_MIN,
    "ForegroundNeutral": TEXT_MIN,
    "ForegroundPositive": TEXT_MIN,
    "ForegroundInactive": BORDER_MIN,
    "DecorationFocus": BORDER_MIN,
    "DecorationHover": BORDER_MIN,
}


def rel_luminance(rgb: tuple[int, int, int]) -> float:
    def chan(v: int) -> float:
        c = v / 255.0
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    r, g, b = rgb
    return 0.2126 * chan(r) + 0.7152 * chan(g) + 0.0722 * chan(b)


def contrast(a: tuple[int, int, int], b: tuple[int, int, int]) -> float:
    la, lb = rel_luminance(a), rel_luminance(b)
    if la < lb:
        la, lb = lb, la
    return (la + 0.05) / (lb + 0.05)


def parse(path: Path) -> dict[str, dict[str, tuple[int, int, int]]]:
    groups: dict[str, dict[str, tuple[int, int, int]]] = {}
    group = ""
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if line.startswith("["):
            group = line
            groups.setdefault(group, {})
            continue
        if "=" not in line or not group.startswith("[Colors:"):
            continue
        key, _, val = line.partition("=")
        parts = val.split(",")
        if len(parts) != 3:
            continue
        try:
            rgb = tuple(int(p) for p in parts)
        except ValueError:
            continue
        if all(0 <= c <= 255 for c in rgb):
            groups[group][key.strip()] = rgb  # type: ignore[assignment]
    return groups


def check(path: Path) -> int:
    if not path.is_file():
        print(f"  MISSING  {path}")
        return 2
    groups = parse(path)
    fails = []
    for group, keys in groups.items():
        bg = keys.get("BackgroundNormal")
        if bg is None:
            continue
        for key, minimum in KEY_MIN.items():
            fg = keys.get(key)
            if fg is None:
                continue
            ratio = contrast(fg, bg)
            if ratio < minimum:
                fails.append((ratio, group, key, fg, bg, minimum))

    if not fails:
        print(f"  readable {path.name}")
        return 0
    print(f"  UNREADABLE {path.name} - {len(fails)} pair(s) below the floor")
    for ratio, group, key, fg, bg, minimum in sorted(fails):
        mark = "  <-- invisible" if ratio < 1.5 else ""
        print(
            f"    {ratio:5.2f}:1 (need {minimum})  {group} {key}="
            f"{fg[0]},{fg[1]},{fg[2]} on {bg[0]},{bg[1]},{bg[2]}{mark}"
        )
    return 1


def main() -> int:
    if len(sys.argv) < 2:
        print("usage: check-contrast.py <scheme.colors> [...]", file=sys.stderr)
        return 2
    rc = 0
    for arg in sys.argv[1:]:
        rc = max(rc, check(Path(arg)))
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
