#!/usr/bin/env python3
"""Render the DevOS wallpapers (SRS DESK-021): three styles in the DevOS palette, 3840x2160.

    scripts/render-wallpapers.py [OUT_DIR]      (default: desktop/wallpapers)

  devos-waves.jpg   soft glowing teal-to-violet waves on deep navy (the default wallpaper)
  devos-glass.jpg   lit, glassy 3D forms
  devos-lines.jpg   minimal geometry around the DevOS mark

Deterministic (fixed seeds). Requires python-numpy and python-pillow. The JPEGs are
committed, so package builds need neither.
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

W, H = 3840, 2160          # output
RW, RH = 1920, 1080        # render size for smooth fields (upscaled; grain added at full size)

NAVY = np.array([7, 10, 17]) / 255
NAVY2 = np.array([12, 17, 30]) / 255
TEAL = np.array([45, 212, 191]) / 255
CYAN = np.array([56, 189, 248]) / 255
VIOLET = np.array([139, 92, 246]) / 255
LILAC = np.array([167, 139, 250]) / 255
WHITE = np.array([230, 237, 247]) / 255


def grid(w=RW, h=RH):
    y, x = np.mgrid[0:h, 0:w].astype(np.float64)
    return x / w, y / h          # 0..1


def mix(a, b, t):
    t = np.clip(t, 0, 1)[..., None]
    return a * (1 - t) + b * t


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def finish(rgb, path, grain=0.018, seed=1):
    """Upscale, add film grain and a gentle vignette, save as JPEG."""
    img = Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8)).resize((W, H), Image.LANCZOS)
    a = np.asarray(img).astype(np.float64) / 255
    x, y = np.meshgrid(np.linspace(-1, 1, W), np.linspace(-1, 1, H))
    vignette = 1 - 0.28 * smoothstep(0.55, 1.45, np.sqrt(x * x * 0.8 + y * y))
    rng = np.random.default_rng(seed)
    noise = rng.normal(0, grain, (H, W, 1))
    a = np.clip(a * vignette[..., None] + noise, 0, 1)
    Image.fromarray((a * 255).astype(np.uint8)).save(path, quality=92, optimize=True, progressive=True)
    print("wrote", path)


# ------------------------------------------------------------------ 1. waves
def waves(path):
    x, y = grid()
    base = mix(NAVY, NAVY2, y * 0.8 + 0.1 * np.sin(x * 3))
    out = base.copy()
    # Each wave: a curve y = c(x); light falls off with distance, brighter on one side.
    layers = [
        # (offset, amp, freq, phase, width, color_left, color_right, strength)
        (0.62, 0.10, 1.6, 0.4, 0.060, TEAL, CYAN, 0.85),
        (0.68, 0.12, 1.3, 2.1, 0.090, CYAN, VIOLET, 0.70),
        (0.74, 0.09, 1.9, 4.0, 0.050, VIOLET, LILAC, 0.75),
        (0.56, 0.07, 2.4, 1.2, 0.030, TEAL, VIOLET, 0.55),
        (0.80, 0.13, 1.1, 5.2, 0.120, VIOLET, TEAL, 0.40),
    ]
    for off, amp, freq, ph, width, ca, cb, k in layers:
        cy = off + amp * np.sin(x * np.pi * freq + ph) + 0.03 * np.sin(x * np.pi * freq * 3.1 + ph * 1.7)
        d = y - cy
        # soft body below the line, crisp glowing edge on the line itself
        body = np.exp(-np.maximum(d, 0) / (width * 2.2)) * (d > 0)
        edge = np.exp(-(d / (width * 0.18)) ** 2)
        col = mix(ca, cb, x)
        out = out + col * (body[..., None] * 0.22 * k + edge[..., None] * 0.55 * k)
    # A distant aurora glow at the top right.
    glow = np.exp(-(((x - 0.78) / 0.35) ** 2 + ((y - 0.18) / 0.22) ** 2))
    out = out + VIOLET * glow[..., None] * 0.10 + TEAL * np.exp(-(((x - 0.15) / 0.3) ** 2 + ((y - 0.85) / 0.2) ** 2))[..., None] * 0.06
    finish(out, path, grain=0.016, seed=11)


# ------------------------------------------------------------------ 2. glass
def glass(path):
    x, y = grid()
    aspect = RW / RH
    px, py = x * aspect, y
    bg = mix(NAVY, NAVY2, y * 0.8 + x * 0.2)
    out = bg.copy()
    light = np.array([-0.5, -0.65, 0.58]); light /= np.linalg.norm(light)
    half = light + np.array([0, 0, 1.0]); half /= np.linalg.norm(half)
    # Separate glass pebbles: (cx, cy, rx, ry, rotation, tint start, tint end)
    pebbles = [
        (1.30, 0.50, 0.33, 0.22, -0.45, TEAL, VIOLET),
        (1.55, 0.25, 0.13, 0.10, 0.6, VIOLET, LILAC),
        (0.98, 0.80, 0.12, 0.08, 0.2, CYAN, TEAL),
        (1.62, 0.78, 0.09, 0.07, -0.3, LILAC, VIOLET),
        (0.42, 0.28, 0.05, 0.05, 0.0, TEAL, CYAN),
    ]
    for cx, cy, rx, ry, rot, ca, cb in pebbles:
        c, s_ = np.cos(rot), np.sin(rot)
        u = ((px - cx) * c + (py - cy) * s_) / rx
        v = (-(px - cx) * s_ + (py - cy) * c) / ry
        r2 = u * u + v * v
        inside = smoothstep(1.0, 0.985, np.sqrt(r2))            # crisp edge
        z = np.sqrt(np.clip(1 - r2, 0, 1))                       # dome
        # Normal of the ellipsoid in screen space.
        nx = (u * c - v * s_) / rx
        ny = (u * s_ + v * c) / ry
        nz = z * 3.2
        n = np.sqrt(nx * nx + ny * ny + nz * nz) + 1e-9
        nx, ny, nz = nx / n, ny / n, nz / n
        diffuse = np.clip(nx * light[0] + ny * light[1] + nz * light[2], 0, 1)
        spec = np.clip(nx * half[0] + ny * half[1] + nz * half[2], 0, 1) ** 140
        rim = smoothstep(0.80, 1.0, np.sqrt(r2))                 # bright thin edge (Fresnel)
        bands = 0.5 + 0.5 * np.sin((u * 0.8 + v * 1.4) * 5.0)    # internal refraction bands
        body = mix(ca, cb, 0.5 + 0.5 * (v - u) / 2)
        col = mix(NAVY2, body, 0.25 + 0.55 * diffuse + 0.08 * bands)
        col = col + WHITE * spec[..., None] * 0.75 + mix(cb, WHITE, 0.4) * rim[..., None] * 0.45
        # Shadow and colored glow cast on the background.
        sd = ((px - cx - 0.03) / (rx * 1.15)) ** 2 + ((py - cy - 0.05) / (ry * 1.15)) ** 2
        out = out * (1 - 0.30 * np.exp(-sd * 1.6))[..., None] + body * np.exp(-sd * 0.7)[..., None] * 0.07
        out = mix(out, col, inside * 0.94)
    finish(out, path, grain=0.012, seed=22)


# ------------------------------------------------------------------ 3. lines
def lines(path):
    x, y = grid()
    aspect = RW / RH
    px, py = x * aspect, y
    out = mix(NAVY, NAVY2, y * 0.7 + x * 0.2)
    # Dot grid, fading toward the left.
    step = 0.022
    gx = np.abs(((px / step) % 1) - 0.5)
    gy = np.abs(((py / step) % 1) - 0.5)
    dots = (np.sqrt(gx * gx + gy * gy) < 0.07) * smoothstep(0.2, 1.3, px / aspect)
    out = out + WHITE * dots[..., None] * 0.07
    # Concentric rounded squares around the DevOS mark (right third).
    cx, cy = 1.30, 0.50

    def rounded_square_sdf(px, py, half, r):
        qx = np.abs(px - cx) - (half - r)
        qy = np.abs(py - cy) - (half - r)
        outside = np.sqrt(np.maximum(qx, 0) ** 2 + np.maximum(qy, 0) ** 2)
        return outside + np.minimum(np.maximum(qx, qy), 0) - r

    for i, half in enumerate([0.11, 0.17, 0.24, 0.32, 0.41]):
        d = np.abs(rounded_square_sdf(px, py, half, half * 0.28))
        w = 0.0016 + 0.0004 * i
        line = np.exp(-(d / w) ** 2)
        fade = 1 - i / 8
        col = mix(TEAL, VIOLET, (py - cy + 0.6) / 1.2 + i * 0.05)
        out = out + col * line[..., None] * 0.55 * fade
    # The mark itself: a chevron and an underscore, glowing.
    def seg(ax, ay, bx, by):
        vx, vy = bx - ax, by - ay
        t = np.clip(((px - ax) * vx + (py - ay) * vy) / (vx * vx + vy * vy), 0, 1)
        return np.sqrt((px - ax - t * vx) ** 2 + (py - ay - t * vy) ** 2)
    d = np.minimum.reduce([seg(1.245, 0.455, 1.29, 0.50), seg(1.29, 0.50, 1.245, 0.545), seg(1.305, 0.548, 1.355, 0.548)])
    core = smoothstep(0.009, 0.006, d)
    halo = np.exp(-(d / 0.03) ** 2)
    col = mix(TEAL, VIOLET, (px - 1.24) / 0.12)
    out = out + col * halo[..., None] * 0.35 + mix(col, WHITE, 0.3) * core[..., None]
    # Soft light behind the mark.
    glow = np.exp(-(((px - 1.30) / 0.22) ** 2 + ((py - 0.50) / 0.22) ** 2))
    out = out + mix(TEAL, VIOLET, py)[...] * glow[..., None] * 0.10
    finish(out, path, grain=0.012, seed=33)


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "desktop/wallpapers"
    out.mkdir(parents=True, exist_ok=True)
    waves(out / "devos-waves.jpg")
    glass(out / "devos-glass.jpg")
    lines(out / "devos-lines.jpg")


if __name__ == "__main__":
    main()
