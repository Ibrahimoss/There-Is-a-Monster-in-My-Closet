"""Doom-style 256 color palette.

The real thing is the PLAYPAL lump inside a Doom IWAD: 768 raw bytes, 256 RGB
triples. If you own a WAD (or grab the BSD-licensed Freedoom one) you can dump
that lump and feed it in with --playpal for byte-exact colors.

What is built below is a *reconstruction*, not those exact bytes. It copies the
structure that gives Doom its look rather than the values: one long grayscale
ramp, a pile of browns/rusts/tans, a blood-red ramp that runs to pure red, and
only a couple of grudging blues and greens. That imbalance is the whole point —
a generic "web safe" 256 palette spreads evenly over the color wheel and
immediately looks like a GIF instead of like Doom.
"""

from __future__ import annotations

import numpy as np

# (name, darkest RGB, brightest RGB, number of steps)
# Counts sum to exactly 256.
RAMPS: list[tuple[str, tuple[int, int, int], tuple[int, int, int], int]] = [
    # The grayscale ramp is the longest one in Doom — walls, metal, shadow.
    ("gray",        (0, 0, 0),      (255, 255, 255), 32),
    # Earth tones dominate. This is most of what you see in E1.
    ("bone",        (47, 43, 35),   (239, 231, 207), 16),
    ("tan",         (43, 35, 23),   (231, 195, 143), 16),
    ("brown",       (31, 23, 11),   (191, 139, 79),  16),
    ("rust",        (27, 15, 7),    (159, 91, 43),   16),
    # Blood, and a lot of it. Runs all the way to saturated red.
    ("red",         (23, 0, 0),     (255, 0, 0),     16),
    ("dark_red",    (15, 0, 0),     (139, 27, 27),   16),
    ("flesh",       (39, 23, 19),   (255, 183, 163), 16),
    # Fire / explosions / lit signage.
    ("orange",      (31, 15, 0),    (255, 135, 27),  16),
    ("gold",        (35, 27, 0),    (255, 231, 75),  16),
    ("fire",        (75, 15, 0),    (255, 255, 191), 16),
    # Slime and army green.
    ("green",       (0, 23, 0),     (63, 255, 63),   16),
    ("olive",       (11, 15, 7),    (123, 135, 71),  16),
    # Blues are rare and mostly dark — Doom barely has a sky color.
    ("blue",        (0, 0, 39),     (91, 91, 255),   16),
    ("steel",       (11, 15, 23),   (135, 155, 191), 8),
    ("teal",        (0, 19, 19),    (95, 175, 175),  8),
]


def build_palette() -> np.ndarray:
    """Return the reconstructed palette as a uint8 array of shape (256, 3)."""
    colors: list[np.ndarray] = []
    for _name, lo, hi, steps in RAMPS:
        t = np.linspace(0.0, 1.0, steps)[:, None]
        ramp = np.array(lo, dtype=np.float64) * (1.0 - t) + np.array(hi, dtype=np.float64) * t
        colors.append(ramp)

    palette = np.concatenate(colors, axis=0)
    if palette.shape[0] != 256:
        raise AssertionError(f"palette ramps sum to {palette.shape[0]}, expected 256")
    return np.clip(np.rint(palette), 0, 255).astype(np.uint8)


def load_playpal(path: str, index: int = 0) -> np.ndarray:
    """Load a real PLAYPAL lump. It holds 14 palettes; 0 is the normal one.

    (The other 13 are the red damage flashes, the item-pickup gold tint, and
    the green radiation-suit tint — Doom switched palettes instead of blending.)
    """
    with open(path, "rb") as fh:
        data = fh.read()

    need = (index + 1) * 768
    if len(data) < need:
        raise ValueError(
            f"{path} is {len(data)} bytes; need at least {need} for palette index {index}"
        )

    block = data[index * 768:(index + 1) * 768]
    return np.frombuffer(block, dtype=np.uint8).reshape(256, 3).copy()


def apply_colormap(palette: np.ndarray, light: int) -> np.ndarray:
    """Darken a palette the way Doom's COLORMAP does, for sector lighting.

    light is 0 (fullbright) to 31 (pitch black). Doom precomputed 32 of these
    and picked one per sector per distance, which is why things get darker in
    visible steps as they recede instead of smoothly.
    """
    light = max(0, min(31, int(light)))
    scale = (31 - light) / 31.0
    return np.clip(np.rint(palette.astype(np.float64) * scale), 0, 255).astype(np.uint8)
