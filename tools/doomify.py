#!/usr/bin/env python3
"""Turn photographs into Doom-style sprites.

    python tools/doomify.py photo.jpg --preview 6

The pipeline, in order:

  1. cut the background away (stock photos are shot on white)
  2. crop to what is left
  3. downscale to sprite height — Doom's player sprite is ~56px tall
  4. push contrast and saturation, because the palette eats subtle gradients
  5. quantize to the 256-color palette, dithering where the ramps fall short
  6. hard 1-bit alpha, because Doom's sprite format had no partial transparency

Step 5 is what actually sells it. Steps 3 and 6 are what stop it from looking
like an Instagram filter.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from doom_palette import apply_colormap, build_palette, load_playpal  # noqa: E402

# Cheap perceptual weighting for color distance — green matters most to the eye,
# blue least. Plain Euclidean RGB picks visibly wrong palette entries on skin.
CHANNEL_WEIGHTS = np.array([2.0, 4.0, 3.0]) / 9.0

# Doom rendered 320x200 but displayed it at 4:3, so every pixel was drawn 1.2x
# taller than it was wide.
DOOM_PIXEL_ASPECT = 1.2

_MATCH_CHUNK = 8192


# --- background removal -------------------------------------------------

def _edge_connected(mask: np.ndarray) -> np.ndarray:
    """Subset of `mask` reachable from the image border (4-connected).

    Flood fill from the edges rather than thresholding globally. A stock photo
    of someone in a pale gray shirt on a white sweep will lose the shirt to any
    global "is it bright?" test, but the shirt is not connected to the border.
    """
    try:
        from scipy import ndimage  # optional, just faster
    except ImportError:
        ndimage = None

    seeds = np.zeros_like(mask)
    seeds[0, :] = mask[0, :]
    seeds[-1, :] = mask[-1, :]
    seeds[:, 0] = mask[:, 0]
    seeds[:, -1] = mask[:, -1]

    if ndimage is not None:
        return ndimage.binary_propagation(seeds, mask=mask)

    reach = seeds
    for _ in range(mask.shape[0] * mask.shape[1]):
        grown = reach.copy()
        grown[1:, :] |= reach[:-1, :]
        grown[:-1, :] |= reach[1:, :]
        grown[:, 1:] |= reach[:, :-1]
        grown[:, :-1] |= reach[:, 1:]
        grown &= mask
        if grown.sum() == reach.sum():
            return grown
        reach = grown
    return reach


def cut_background(rgb: np.ndarray, tolerance: int) -> np.ndarray:
    """Return an alpha channel with the border-connected backdrop removed."""
    corners = np.stack([rgb[0, 0], rgb[0, -1], rgb[-1, 0], rgb[-1, -1]]).astype(np.float64)
    backdrop = corners.mean(axis=0)

    distance = np.abs(rgb.astype(np.float64) - backdrop).max(axis=2)
    background = _edge_connected(distance <= tolerance)

    alpha = np.where(background, 0, 255).astype(np.uint8)

    # Feather one pixel inward so the cut edge downscales without a hard jaggy.
    soft = (distance <= tolerance * 1.6) & ~background
    alpha[soft] = 200
    return alpha


def looks_like_studio_shot(rgb: np.ndarray, tolerance: int) -> bool:
    """True if all four corners agree on a color — i.e. a seamless backdrop."""
    corners = np.stack([rgb[0, 0], rgb[0, -1], rgb[-1, 0], rgb[-1, -1]]).astype(np.float64)
    return bool(np.abs(corners - corners.mean(axis=0)).max() <= tolerance)


# --- resampling ---------------------------------------------------------

def resize_rgba(rgb: np.ndarray, alpha: np.ndarray, size: tuple[int, int]):
    """Downscale, premultiplying so transparent pixels don't bleed their color."""
    a = alpha.astype(np.float64) / 255.0
    premultiplied = rgb.astype(np.float64) * a[..., None]

    rgb_small = np.asarray(
        Image.fromarray(np.clip(premultiplied, 0, 255).astype(np.uint8))
        .resize(size, Image.LANCZOS)
    ).astype(np.float64)
    a_small = np.asarray(
        Image.fromarray(alpha).resize(size, Image.LANCZOS)
    ).astype(np.float64) / 255.0

    with np.errstate(divide="ignore", invalid="ignore"):
        out = np.where(a_small[..., None] > 0.003, rgb_small / a_small[..., None], 0.0)
    return np.clip(out, 0, 255), np.clip(a_small * 255.0, 0, 255).astype(np.uint8)


# --- grading ------------------------------------------------------------

LUMA = np.array([0.299, 0.587, 0.114])

# Doom's world is rust, dust and dried blood. Even neutral surfaces sit warm.
SEPIA = np.array([1.20, 0.98, 0.70])


def grade(rgb: np.ndarray, saturation: float, contrast: float,
          gamma: float, warmth: float) -> np.ndarray:
    x = np.clip(rgb / 255.0, 0.0, 1.0) ** gamma

    luma = (x * LUMA).sum(axis=-1, keepdims=True)
    x = luma + (x - luma) * saturation

    if warmth > 0.0:
        # Drag everything toward the earth-tone ramps. Without this a gray shirt
        # lands in the 32-step grayscale ramp and reads as a modern photo that
        # merely lost some colors, rather than as Doom art.
        x = x * (1.0 - warmth) + np.clip(luma * SEPIA, 0.0, 1.0) * warmth

    x = (x - 0.5) * contrast + 0.5
    return np.clip(x, 0.0, 1.0) * 255.0


# --- quantization -------------------------------------------------------

def nearest_index(pixels: np.ndarray, palette: np.ndarray) -> np.ndarray:
    """Index of the closest palette entry for each of N pixels."""
    flat = pixels.reshape(-1, 3)
    pal = palette.astype(np.float64)
    out = np.empty(flat.shape[0], dtype=np.int32)
    for i in range(0, flat.shape[0], _MATCH_CHUNK):
        block = flat[i:i + _MATCH_CHUNK]
        d2 = ((block[:, None, :] - pal[None, :, :]) ** 2 * CHANNEL_WEIGHTS).sum(axis=2)
        out[i:i + _MATCH_CHUNK] = d2.argmin(axis=1)
    return out.reshape(pixels.shape[:2])


def bayer_matrix(n: int) -> np.ndarray:
    if n <= 1:
        return np.zeros((1, 1))
    half = bayer_matrix(n // 2)
    return np.block([
        [4 * half, 4 * half + 2],
        [4 * half + 3, 4 * half + 1],
    ])


def palette_step(palette: np.ndarray) -> float:
    """Typical distance between neighbouring palette entries.

    Dither bias has to be scaled to this. Hardcoding a magnitude over-dithers
    the dense ramps (the grays are only ~8 apart) into a visible crosshatch,
    and a real PLAYPAL has different spacing again.
    """
    pal = palette.astype(np.float64)
    d2 = (((pal[:, None, :] - pal[None, :, :]) ** 2) * CHANNEL_WEIGHTS).sum(axis=2)
    np.fill_diagonal(d2, np.inf)
    return float(np.median(np.sqrt(d2.min(axis=1))))


def quantize(rgb: np.ndarray, palette: np.ndarray, mode: str, strength: float) -> np.ndarray:
    """Map to the palette. Returns an index image."""
    if mode == "none":
        return nearest_index(rgb, palette)

    if mode == "bayer":
        # Ordered dithering: nudge each pixel by a fixed screen-space pattern
        # before snapping, so banding breaks into a crosshatch.
        h, w = rgb.shape[:2]
        # An 8x8 cell spans half a 19px-wide sprite and reads as fabric texture
        # instead of as blending, so shrink the matrix on small art.
        n = 4 if min(h, w) < 96 else 8
        m = bayer_matrix(n)
        bias = ((m + 0.5) / (n * n) - 0.5) * (palette_step(palette) * strength)
        tiled = np.tile(bias, (h // n + 1, w // n + 1))[:h, :w]
        return nearest_index(np.clip(rgb + tiled[..., None], 0, 255), palette)

    if mode == "floyd":
        # Error diffusion: cleaner on skin and gradients, but the noise is
        # unstructured, so an animated sprite will crawl between frames.
        work = rgb.astype(np.float64).copy()
        pal = palette.astype(np.float64)
        h, w = work.shape[:2]
        idx = np.zeros((h, w), dtype=np.int32)
        for y in range(h):
            for x in range(w):
                old = np.clip(work[y, x], 0.0, 255.0)
                i = int((((old - pal) ** 2) * CHANNEL_WEIGHTS).sum(axis=1).argmin())
                idx[y, x] = i
                # Clamp before diffusing. This palette has big gaps between the
                # earth ramps, so an unclamped error compounds across a flat
                # region until it tips whole pixels into saturated red.
                err = np.clip(old - pal[i], -48.0, 48.0) * strength
                if x + 1 < w:
                    work[y, x + 1] += err * 7 / 16
                if y + 1 < h:
                    if x > 0:
                        work[y + 1, x - 1] += err * 3 / 16
                    work[y + 1, x] += err * 5 / 16
                    if x + 1 < w:
                        work[y + 1, x + 1] += err * 1 / 16
        return idx

    raise ValueError(f"unknown dither mode: {mode}")


# --- extras -------------------------------------------------------------

def add_outline(rgb: np.ndarray, alpha: np.ndarray, palette: np.ndarray):
    """Ring the sprite in the palette's darkest color so it reads on any wall."""
    solid = alpha > 0
    grown = solid.copy()
    grown[1:, :] |= solid[:-1, :]
    grown[:-1, :] |= solid[1:, :]
    grown[:, 1:] |= solid[:, :-1]
    grown[:, :-1] |= solid[:, 1:]
    edge = grown & ~solid

    darkest = int(palette.astype(np.float64).sum(axis=1).argmin())
    rgb = rgb.copy()
    alpha = alpha.copy()
    rgb[edge] = palette[darkest]
    alpha[edge] = 255
    return rgb, alpha


def emit_lut(path: Path, size: int, palette: np.ndarray, args) -> None:
    """Bake grade + palette snap into a color LUT for the Godot shader.

    An unrolled 3D LUT: `size` slices of size x size laid out left to right, so
    a 32-slice LUT is a 1024x32 image. Doing the 32768 nearest-color searches
    here in numpy keeps them out of GDScript, where the same loop would stall
    the load by several seconds every run.

    Baking the grade in too means the world and the sprites go through exactly
    the same transform and cannot drift apart.
    """
    axis = np.linspace(0.0, 255.0, size)
    b, g, r = np.meshgrid(axis, axis, axis, indexing="ij")
    grid = np.stack([r, g, b], axis=-1)  # (size, size, size, 3), indexed [b][g][r]

    graded = grade(grid.reshape(-1, 1, 3), args.saturation, args.contrast,
                   args.gamma, args.warmth).reshape(size, size, size, 3)

    idx = nearest_index(graded.reshape(size, size * size, 3), palette)
    mapped = palette[idx]  # (size, size*size, 3) indexed [b][g*?]

    # Lay out as (row = green, column = blue_slice * size + red).
    out = np.zeros((size, size * size, 3), dtype=np.uint8)
    for bi in range(size):
        out[:, bi * size:(bi + 1) * size, :] = mapped[bi].reshape(size, size, 3)

    Image.fromarray(out, mode="RGB").save(path)
    print(f"LUT -> {path}  {size * size}x{size} ({size}^3 entries)")


def trim(rgb: np.ndarray, alpha: np.ndarray, pad: int = 1):
    rows = np.any(alpha > 0, axis=1)
    cols = np.any(alpha > 0, axis=0)
    if not rows.any() or not cols.any():
        return rgb, alpha
    y0, y1 = np.where(rows)[0][[0, -1]]
    x0, x1 = np.where(cols)[0][[0, -1]]
    y0 = max(0, y0 - pad)
    x0 = max(0, x0 - pad)
    y1 = min(alpha.shape[0] - 1, y1 + pad)
    x1 = min(alpha.shape[1] - 1, x1 + pad)
    return rgb[y0:y1 + 1, x0:x1 + 1], alpha[y0:y1 + 1, x0:x1 + 1]


# --- driver -------------------------------------------------------------

def doomify(path: Path, args, palette: np.ndarray) -> tuple[Image.Image, dict]:
    source = Image.open(path).convert("RGBA")
    rgb = np.asarray(source)[..., :3].astype(np.uint8)
    alpha = np.asarray(source)[..., 3].astype(np.uint8)
    info: dict = {"source": f"{source.width}x{source.height}"}

    fully_opaque = bool((alpha == 255).all())
    if not args.keep_bg and fully_opaque:
        if args.force_cutout or looks_like_studio_shot(rgb, args.bg_tolerance):
            alpha = cut_background(rgb, args.bg_tolerance)
            info["background"] = "cut"
        else:
            info["background"] = "kept (no seamless backdrop detected)"
    else:
        info["background"] = "kept"

    rgb, alpha = trim(rgb, alpha)

    # Target size.
    src_h, src_w = alpha.shape
    scale = args.height / src_h
    out_w = max(1, int(round(src_w * scale)))
    out_h = max(1, args.height)
    if args.doom_aspect:
        out_h = max(1, int(round(out_h / DOOM_PIXEL_ASPECT)))
    info["sprite"] = f"{out_w}x{out_h}"

    rgb_small, alpha_small = resize_rgba(rgb, alpha, (out_w, out_h))
    rgb_small = grade(rgb_small, args.saturation, args.contrast, args.gamma, args.warmth)

    working = apply_colormap(palette, args.light) if args.light else palette
    idx = quantize(rgb_small, working, args.dither, args.dither_strength)
    out_rgb = working[idx]

    # 1-bit alpha, like the real sprite format.
    out_alpha = np.where(alpha_small >= args.alpha_threshold, 255, 0).astype(np.uint8)

    if args.outline:
        out_rgb, out_alpha = add_outline(out_rgb, out_alpha, working)

    info["colors"] = int(len(np.unique(idx[out_alpha > 0]))) if (out_alpha > 0).any() else 0

    rgba = np.dstack([out_rgb.astype(np.uint8), out_alpha])
    return Image.fromarray(rgba, mode="RGBA"), info


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(
        description="Turn photographs into Doom-style sprites.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    p.add_argument("inputs", nargs="*", type=Path)
    p.add_argument("-o", "--output", type=Path, help="output file (single input only)")
    p.add_argument("--outdir", type=Path, default=Path("."), help="output directory")

    p.add_argument("--height", type=int, default=64,
                   help="sprite height in pixels; Doom's marine is ~56")
    p.add_argument("--doom-aspect", action="store_true",
                   help="squash vertically by 1.2 for real 320x200 WAD sprites; "
                        "leave off for modern square-pixel engines")

    p.add_argument("--dither", choices=["none", "bayer", "floyd"], default="bayer")
    p.add_argument("--dither-strength", type=float, default=1.0,
                   help="scaled against the palette's own spacing; >2 gets crunchy")
    p.add_argument("--light", type=int, default=0,
                   help="COLORMAP darkness, 0 fullbright to 31 black")

    p.add_argument("--saturation", type=float, default=1.3)
    p.add_argument("--contrast", type=float, default=1.25)
    p.add_argument("--gamma", type=float, default=1.05)
    p.add_argument("--warmth", type=float, default=0.35,
                   help="0..1 pull toward Doom's rust/tan ramps; 0 keeps true color")

    p.add_argument("--keep-bg", action="store_true", help="skip background removal")
    p.add_argument("--force-cutout", action="store_true",
                   help="cut the background even if it doesn't look seamless")
    p.add_argument("--bg-tolerance", type=int, default=32)
    p.add_argument("--alpha-threshold", type=int, default=128)
    p.add_argument("--outline", action="store_true", help="add a dark 1px outline")

    p.add_argument("--playpal", type=Path, help="use a real 768-byte PLAYPAL lump")
    p.add_argument("--playpal-index", type=int, default=0)
    p.add_argument("--preview", type=int, default=0,
                   help="also write a NxN nearest-neighbor upscale for eyeballing")
    p.add_argument("--emit-lut", type=Path,
                   help="write a color LUT for the in-engine shader and exit")
    p.add_argument("--lut-size", type=int, default=32, help="LUT edge, 16 or 32")

    args = p.parse_args(argv)

    if args.output and len(args.inputs) > 1:
        p.error("--output takes a single input; use --outdir for batches")
    if not args.inputs and not args.emit_lut:
        p.error("nothing to do: pass an image, or --emit-lut PATH")

    palette = load_playpal(str(args.playpal), args.playpal_index) if args.playpal else build_palette()
    print(f"palette: {'PLAYPAL ' + str(args.playpal) if args.playpal else 'reconstructed'} "
          f"({len(palette)} colors)")

    if args.emit_lut:
        args.emit_lut.parent.mkdir(parents=True, exist_ok=True)
        emit_lut(args.emit_lut, args.lut_size, palette, args)
        if not args.inputs:
            return 0

    args.outdir.mkdir(parents=True, exist_ok=True)
    failed = 0

    for path in args.inputs:
        if not path.exists():
            print(f"  {path}: not found", file=sys.stderr)
            failed += 1
            continue
        try:
            image, info = doomify(path, args, palette)
        except Exception as exc:  # noqa: BLE001 - keep batches going
            print(f"  {path}: {exc}", file=sys.stderr)
            failed += 1
            continue

        dest = args.output or (args.outdir / f"{path.stem}_doom.png")
        image.save(dest)
        detail = "  ".join(f"{k}={v}" for k, v in info.items())
        print(f"  {path.name} -> {dest}  {detail}")

        if args.preview > 1:
            big = image.resize(
                (image.width * args.preview, image.height * args.preview), Image.NEAREST
            )
            preview_path = dest.with_name(f"{dest.stem}_x{args.preview}{dest.suffix}")
            big.save(preview_path)
            print(f"    preview -> {preview_path}")

    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
