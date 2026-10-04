#!/usr/bin/env python3
"""Prepares the wiki pictures fetch.mjs downloaded for the lore pages.

Each picture is cropped to a 2:1 banner, tinted a touch toward the parchment it sits on, thinned
to the paper toward its edges and written as a DXT1 BLP to addons/SpokenZones/Textures/Pictures/.
The edges themselves, where the paint fails in dry-brush streaks, specks and spatters, are mask
textures (Mask1.tga...) the game cuts each picture with, so a picture costs no alpha. Writes
Data/Pictures.lua (which picture and mask each place has) and CREDITS.md (each picture's wiki
file, author and licence).

Usage: python tools/pictures/prepare.py [--only ID[,ID...]] [--force]
  --only   just these places (manifest ids, such as zone-1411 or 1411-razor-hill); the data then
           names only them, for a trial in the game
  --force  write pictures again that are already there
"""

import argparse
import json
import os
import struct
import sys
import zlib

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", "..", "..", ".."))
RAW = os.path.join(ROOT, "pipelines/zones/tools/cache/pictures/raw")
OUT = os.path.join(ROOT, "addons/SpokenZones/Textures/Pictures")
LUA = os.path.join(ROOT, "addons/SpokenZones/Data/Pictures.lua")

# Shipped at twice the size the frame draws them (about 320 wide), so the game shrinks a picture
# rather than stretching it: stretched, a 256-wide picture looked soft.
W, H = 512, 256
# The edge masks, at the size of the pictures; there are MASKS of them.
MASK_W, MASK_H = 512, 256
MASKS = 4
MIN_W, MIN_H = 400, 200  # smaller than this is an icon or a thumbnail, not a picture
# The page under the picture, as the game draws it (sampled from a screenshot of the panel), and
# how far the picture is tinted toward it.
PARCHMENT = np.array([0.88, 0.68, 0.41])
WARMTH = 0.12
# The paper's grain over the picture: how strong, and how big a grain is in the shipped picture's
# pixels (the game draws it at about two thirds of its size, so a grain of one pixel vanished);
# then how much shallower the left edge's fraying is.
GRAIN, GRAIN_SIZE, LEFT_SHALLOWER = 0.08, 1.5, 0.5


def seeded(name):
    return np.random.default_rng(zlib.crc32(name.encode()))


def noise(rng, h, w, octaves=5, base=4):
    """Fractal value noise in 0..1."""
    total = np.zeros((h, w))
    amp, weight = 1.0, 0.0
    for o in range(octaves):
        gh, gw = base * 2 ** o, base * 2 ** o * max(1, w // h)
        grid = rng.random((gh + 1, gw + 1)).astype(np.float32)
        layer = np.asarray(Image.fromarray(grid).resize((w, h), Image.BICUBIC))
        total += amp * layer
        weight += amp
        amp *= 0.5
    total /= weight
    return (total - total.min()) / max(1e-6, total.max() - total.min())


def stretched(rng, h, w, along_x, octaves=4):
    """Noise drawn out along one direction: dry-brush streaks."""
    if along_x:
        small = noise(rng, h, max(8, w // 12), octaves, 8)
    else:
        small = noise(rng, max(8, h // 12), w, octaves, 8)
    return np.asarray(Image.fromarray(small.astype(np.float32)).resize((w, h), Image.BICUBIC))


def make_mask(index):
    """Where the paint reaches: solid in the middle, failing toward each edge in dry-brush streaks
    that run along that side, broken into specks, with a few spatters past it."""
    rng = seeded(f"mask{index}")
    pw, ph = MASK_W, MASK_H
    yy, xx = np.mgrid[0:ph, 0:pw].astype(np.float64)
    across = np.minimum(xx, pw - 1 - xx)   # in from the left or right side
    down = np.minimum(yy, ph - 1 - yy)     # in from the top or bottom
    inset = np.minimum(across, down)

    # Streaks along the top and bottom run left to right, along the sides top to bottom.
    along = np.clip((across - down) / 24 + 0.5, 0, 1)
    streak = along * stretched(rng, ph, pw, True) + (1 - along) * stretched(rng, ph, pw, False)
    # How far in the failing reaches, uneven round the edge.
    # Shallower along the left side, which lines up with the text below: there a deep edge read as
    # the picture sitting out of line with the words.
    left = (1 - along) * np.clip((pw / 2 - xx) / 24, 0, 1)
    scale = 1 - LEFT_SHALLOWER * left
    depth = (3 + noise(rng, ph, pw, 3, 2) * 16) * scale
    reach = np.clip((inset - depth + (streak - 0.5) * 26 * scale) / (14 * scale), 0, 1)

    # The dry brush skipping over the paper's tooth: the band broken into specks, the middle whole.
    tooth = noise(rng, ph, pw, 2, 96)
    tooth = 0.6 * tooth + 0.4 * rng.random((ph, pw))
    mask = np.clip((reach - 0.55 * tooth) / 0.45, 0, 1)

    # Spatters flicked past the edge.
    for _ in range(40):
        cx, cy = rng.random() * pw, rng.random() * ph
        if not (reach[int(cy), int(cx)] < 0.4 and inset[int(cy), int(cx)] > 2):
            continue
        r = 0.6 + rng.random() ** 4 * 2.5
        d = np.hypot(xx - cx, yy - cy)
        mask = np.maximum(mask, np.clip(r - d + 0.5, 0, 1) * (0.5 + 0.5 * rng.random()))
    return mask


def save_mask(mask, path):
    alpha = (mask * 255).astype(np.uint8)
    rgba = np.dstack([np.full_like(alpha, 255)] * 3 + [alpha])
    Image.fromarray(rgba, "RGBA").save(path)


def crop(im):
    """A 2:1 banner: the full width where the picture is taller, cut a little above the middle,
    where a screenshot's sky gives way to the place."""
    w, h = im.size
    if w / h > 2:
        cw = int(h * 2)
        left = (w - cw) // 2
        return im.crop((left, 0, left + cw, h))
    ch = int(w / 2)
    top = int((h - ch) * 0.45)
    return im.crop((0, top, w, top + ch))


def prepare(im, mask):
    """The banner at the shipped size, warmed a touch toward the parchment, and thinning to the
    paper where the paint runs out at the edges (the mask's fading band)."""
    img = np.asarray(crop(im).resize((W, H), Image.LANCZOS)).astype(np.float64) / 255.0
    img = img * (1 - WARMTH + WARMTH * PARCHMENT / PARCHMENT.max())
    # The paper's grain: fine noise and a coarser mottle under it, as the parchment has.
    rng = seeded("grain")
    speck = rng.random((int(H / GRAIN_SIZE), int(W / GRAIN_SIZE))).astype(np.float32)
    speck = np.asarray(Image.fromarray(speck).resize((W, H), Image.BICUBIC))
    grain = 0.65 * speck + 0.35 * noise(rng, H, W, 3, 16)
    img *= (1 - GRAIN * (grain - 0.5) * 2)[..., None]
    mask = np.asarray(Image.fromarray(mask.astype(np.float32)).resize((W, H), Image.BILINEAR))
    soft = ndimage.gaussian_filter(mask, 3 * W / MASK_W)
    thin = np.clip(1 - soft, 0, 1) ** 0.8
    img = img + (PARCHMENT - img) * (0.75 * thin)[..., None]
    out = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8))
    return out.filter(ImageFilter.UnsharpMask(radius=1, percent=40, threshold=2))


# --- DXT1 BLP ---------------------------------------------------------------------------------

def to565(c):
    c = np.clip(np.rint(c), 0, 255).astype(np.int32)
    return ((c[..., 0] >> 3) << 11) | ((c[..., 1] >> 2) << 5) | (c[..., 2] >> 3)


def from565(v):
    r = (v >> 11) & 31
    g = (v >> 5) & 63
    b = v & 31
    return np.stack([(r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2)], axis=-1).astype(np.float64)


def dxt1(rgb):
    """DXT1 blocks for an RGB array whose sides are multiples of 4 (or smaller than 4)."""
    h, w, _ = rgb.shape
    bh, bw = max(1, (h + 3) // 4), max(1, (w + 3) // 4)
    padded = np.pad(rgb, ((0, bh * 4 - h), (0, bw * 4 - w), (0, 0)), mode="edge").astype(np.float64)
    blocks = padded.reshape(bh, 4, bw, 4, 3).transpose(0, 2, 1, 3, 4).reshape(bh * bw, 16, 3)
    mean = blocks.mean(axis=1, keepdims=True)
    centred = blocks - mean
    cov = np.einsum("npi,npj->nij", centred, centred)
    axis = np.ones((len(blocks), 3)) / np.sqrt(3)
    for _ in range(6):
        axis = np.einsum("nij,nj->ni", cov, axis)
        length = np.linalg.norm(axis, axis=1, keepdims=True)
        axis = np.where(length > 1e-9, axis / np.maximum(length, 1e-9), np.ones_like(axis) / np.sqrt(3))
    t = np.einsum("npi,ni->np", centred, axis)
    lo, hi = t.min(axis=1), t.max(axis=1)
    inset = (hi - lo) / 32
    lo, hi = lo + inset, hi - inset
    c0 = mean[:, 0] + hi[:, None] * axis
    c1 = mean[:, 0] + lo[:, None] * axis
    v0, v1 = to565(c0), to565(c1)
    swap = v0 < v1
    v0, v1 = np.where(swap, v1, v0), np.where(swap, v0, v1)
    e0, e1 = from565(v0), from565(v1)
    palette = np.stack([e0, e1, (2 * e0 + e1) / 3, (e0 + 2 * e1) / 3], axis=1)
    dist = ((blocks[:, :, None, :] - palette[:, None, :, :]) ** 2).sum(axis=3)
    idx = dist.argmin(axis=2)
    idx = np.where((v0 == v1)[:, None], 0, idx)
    bits = (idx.astype(np.uint64) << (2 * np.arange(16, dtype=np.uint64))).sum(axis=1)
    out = np.zeros(len(blocks), dtype=[("c0", "<u2"), ("c1", "<u2"), ("bits", "<u4")])
    out["c0"], out["c1"], out["bits"] = v0, v1, bits.astype(np.uint32)
    return out.tobytes()


def save_blp(im, path):
    """A BLP2 of DXT1 blocks, with its smaller sizes for the game to draw it small."""
    mips = []
    level = im
    while True:
        mips.append(dxt1(np.asarray(level.convert("RGB"))))
        if level.size == (1, 1) or len(mips) == 16:
            break
        level = level.resize((max(1, level.size[0] // 2), max(1, level.size[1] // 2)), Image.LANCZOS)
    header = 4 + 4 + 4 + 8 + 64 + 64 + 1024
    offsets, sizes, at = [], [], header
    for data in mips:
        offsets.append(at)
        sizes.append(len(data))
        at += len(data)
    offsets += [0] * (16 - len(mips))
    sizes += [0] * (16 - len(mips))
    with open(path, "wb") as f:
        f.write(b"BLP2")
        f.write(struct.pack("<I", 1))
        f.write(struct.pack("<BBBB", 2, 0, 0, 1))  # DXT, no alpha, DXT1, mipmaps
        f.write(struct.pack("<II", *im.size))
        f.write(struct.pack("<16I", *offsets))
        f.write(struct.pack("<16I", *sizes))
        f.write(b"\0" * 1024)
        for data in mips:
            f.write(data)


# --- Lua and credits ----------------------------------------------------------------------------

def lua_string(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def write_lua(placed):
    by_parent = {}
    for p in placed:
        by_parent.setdefault(p["parent"], []).append(p)
    lines = [
        "-- AUTO-GENERATED by pipelines/zones/tools/pictures/prepare.py. Do not edit by hand.",
        "--",
        "-- A picture of each place, from its warcraft.wiki.gg page (credits in",
        "-- Textures/Pictures/CREDITS.md). Keyed as the lore is: parent uiMapID, then the normalised",
        "-- subzone name, with \"\" for the zone itself. Each is { texture, mask }: the picture under",
        "-- Textures/Pictures and which of its edge masks (Mask1..Mask%d) cuts it." % MASKS,
        "",
        "local _, SpokenZones = ...",
        "",
        "SpokenZones.pictures = {",
    ]
    for parent in sorted(by_parent):
        lines.append("\t[%d] = {" % parent)
        for p in sorted(by_parent[parent], key=lambda p: p.get("key") or ""):
            lines.append("\t\t[%s] = { %s, %d }," % (lua_string(p.get("key") or ""), lua_string(p["texture"]), p["mask"]))
        lines.append("\t},")
    lines.append("}")
    with open(LUA, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


def write_credits(placed):
    seen = {}
    for p in placed:
        seen.setdefault(p["texture"], p)
    lines = [
        "# Zone pictures",
        "",
        "Cropped, tinted and edged by `pipelines/zones/tools/pictures/prepare.py` from the pictures on",
        "these warcraft.wiki.gg pages. Each source file's page gives its own terms; the screenshots are",
        "of World of Warcraft, (c) Blizzard Entertainment.",
        "",
        "| Picture | Wiki page | Source file | Author | Licence |",
        "| --- | --- | --- | --- | --- |",
    ]
    cell = lambda s: (s or "").replace("|", "/").replace("\n", " ").strip()
    for texture in sorted(seen):
        p = seen[texture]
        lines.append("| %s | %s | [%s](%s) | %s | %s |" % (texture, cell(p["title"]), cell(p["file"].replace("File:", "")),
                                                        p["page"], cell(p.get("artist")) or "-", cell(p.get("license")) or "-"))
    with open(os.path.join(OUT, "CREDITS.md"), "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only")
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()

    manifest = json.load(open(os.path.join(HERE, "manifest.json"), encoding="utf-8"))["pictures"]
    only = set(args.only.split(",")) if args.only else None
    os.makedirs(OUT, exist_ok=True)
    masks = [make_mask(i + 1) for i in range(MASKS)]
    for i, mask in enumerate(masks):
        save_mask(mask, os.path.join(OUT, "Mask%d.tga" % (i + 1)))

    placed, written, skipped, by_file = [], 0, [], {}
    for pid, p in manifest.items():
        if only and pid not in only:
            continue
        path = p.get("raw") and os.path.join(RAW, p["raw"])
        if not path or not os.path.exists(path):
            continue
        # One texture for a picture several places share.
        if p["file"] in by_file:
            placed.append({**p, **by_file[p["file"]]})
            continue
        im = Image.open(path)
        if im.size[0] < MIN_W or im.size[1] < MIN_H:
            skipped.append(pid)
            continue
        chosen = {"texture": pid, "mask": zlib.crc32(pid.encode()) % MASKS + 1}
        out = os.path.join(OUT, pid + ".blp")
        if args.force or not os.path.exists(out):
            save_blp(prepare(im.convert("RGB"), masks[chosen["mask"] - 1]), out)
            written += 1
        by_file[p["file"]] = chosen
        placed.append({**p, **chosen})
        sys.stdout.write("\r  %d placed" % len(placed))
    sys.stdout.write("\n")

    write_lua(placed)
    write_credits(placed)
    total = sum(os.path.getsize(os.path.join(OUT, f)) for f in os.listdir(OUT))
    print("written %d, placed %d, too small %d, folder %.1f MB" % (written, len(placed), len(skipped), total / 1e6))
    if skipped:
        print("too small:", ", ".join(skipped[:20]) + (" ..." if len(skipped) > 20 else ""))


if __name__ == "__main__":
    main()
