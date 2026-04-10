#!/usr/bin/env python3
import math
import os
import struct
import sys
import zlib


def clamp(value, low=0.0, high=1.0):
    return max(low, min(high, value))


def smoothstep(edge0, edge1, x):
    if edge0 == edge1:
        return 0.0
    t = clamp((x - edge0) / (edge1 - edge0))
    return t * t * (3.0 - 2.0 * t)


def blend(dst, src):
    sr, sg, sb, sa = src
    if sa <= 0.0:
        return dst
    dr, dg, db, da = dst
    out_a = sa + da * (1.0 - sa)
    if out_a <= 0.0:
        return (0.0, 0.0, 0.0, 0.0)
    out_r = (sr * sa + dr * da * (1.0 - sa)) / out_a
    out_g = (sg * sa + dg * da * (1.0 - sa)) / out_a
    out_b = (sb * sa + db * da * (1.0 - sa)) / out_a
    return (out_r, out_g, out_b, out_a)


def rounded_rect_alpha(px, py, x, y, w, h, radius, softness=1.0):
    cx = x + w * 0.5
    cy = y + h * 0.5
    qx = abs(px - cx) - (w * 0.5 - radius)
    qy = abs(py - cy) - (h * 0.5 - radius)
    ox = max(qx, 0.0)
    oy = max(qy, 0.0)
    outside = math.hypot(ox, oy)
    inside = min(max(qx, qy), 0.0)
    distance = outside + inside - radius
    return 1.0 - smoothstep(-softness, softness, distance)


def circle_alpha(px, py, cx, cy, radius, softness=1.0):
    distance = math.hypot(px - cx, py - cy) - radius
    return 1.0 - smoothstep(-softness, softness, distance)


def draw_icon(size):
    pixels = []
    pad = size * 0.08
    softness = max(0.75, size / 256.0)

    for y in range(size):
        row = []
        ny = y / max(1, size - 1)
        for x in range(size):
            nx = x / max(1, size - 1)
            px = x + 0.5
            py = y + 0.5

            base = (
                0.055 + 0.03 * (1.0 - ny),
                0.075 + 0.05 * (1.0 - ny),
                0.11 + 0.10 * (1.0 - ny),
                0.0,
            )

            icon_alpha = rounded_rect_alpha(
                px, py, pad, pad, size - pad * 2, size - pad * 2, size * 0.23, softness
            )
            color = (base[0], base[1], base[2], icon_alpha)

            gloss_alpha = rounded_rect_alpha(
                px, py, pad * 1.2, pad * 1.15, size - pad * 2.4, size * 0.30, size * 0.18, softness
            ) * 0.16 * (1.0 - ny)
            color = blend(color, (0.60, 0.70, 0.82, gloss_alpha))

            rim_alpha = rounded_rect_alpha(
                px, py, pad, pad, size - pad * 2, size - pad * 2, size * 0.23, softness
            ) - rounded_rect_alpha(
                px, py, pad * 1.12, pad * 1.12, size - pad * 2.24, size - pad * 2.24, size * 0.20, softness
            )
            color = blend(color, (0.75, 0.84, 0.95, clamp(rim_alpha * 0.18)))

            panel_x = size * 0.19
            panel_y = size * 0.24
            panel_w = size * 0.62
            panel_h = size * 0.50
            panel_alpha = rounded_rect_alpha(px, py, panel_x, panel_y, panel_w, panel_h, size * 0.12, softness)
            panel_fill = (
                0.12 + 0.04 * (1.0 - ny),
                0.16 + 0.04 * (1.0 - ny),
                0.23 + 0.05 * (1.0 - ny),
                panel_alpha * 0.94,
            )
            color = blend(color, panel_fill)

            panel_rim = panel_alpha - rounded_rect_alpha(
                px,
                py,
                panel_x + size * 0.014,
                panel_y + size * 0.014,
                panel_w - size * 0.028,
                panel_h - size * 0.028,
                size * 0.10,
                softness,
            )
            color = blend(color, (0.56, 0.67, 0.80, clamp(panel_rim * 0.45)))

            dot_alpha = circle_alpha(px, py, size * 0.27, size * 0.35, size * 0.055, softness)
            color = blend(color, (0.17, 0.88, 0.64, dot_alpha * 0.98))
            color = blend(color, (0.85, 1.0, 0.95, dot_alpha * 0.12))

            glow_alpha = circle_alpha(px, py, size * 0.27, size * 0.35, size * 0.095, softness * 1.4) * 0.12
            color = blend(color, (0.17, 0.88, 0.64, glow_alpha))

            line1 = rounded_rect_alpha(px, py, size * 0.35, size * 0.32, size * 0.28, size * 0.048, size * 0.024, softness)
            line2 = rounded_rect_alpha(px, py, size * 0.35, size * 0.42, size * 0.22, size * 0.048, size * 0.024, softness)
            line3 = rounded_rect_alpha(px, py, size * 0.26, size * 0.55, size * 0.48, size * 0.060, size * 0.030, softness)
            color = blend(color, (0.82, 0.90, 0.98, line1 * 0.85))
            color = blend(color, (0.66, 0.77, 0.90, line2 * 0.76))
            color = blend(color, (0.28, 0.58, 0.98, line3 * 0.88))

            accent_alpha = circle_alpha(px, py, size * 0.73, size * 0.55, size * 0.040, softness)
            color = blend(color, (0.97, 0.71, 0.23, accent_alpha * 0.95))

            shadow_alpha = rounded_rect_alpha(
                px, py, size * 0.28, size * 0.78, size * 0.44, size * 0.05, size * 0.025, softness
            ) * 0.18
            color = blend(color, (0.0, 0.0, 0.0, shadow_alpha))

            row.append(
                (
                    int(clamp(color[0]) * 255),
                    int(clamp(color[1]) * 255),
                    int(clamp(color[2]) * 255),
                    int(clamp(color[3]) * 255),
                )
            )
        pixels.append(row)
    return pixels


def write_png(path, pixels):
    height = len(pixels)
    width = len(pixels[0])

    def chunk(tag, data):
        return (
            struct.pack("!I", len(data))
            + tag
            + data
            + struct.pack("!I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    raw = bytearray()
    for row in pixels:
        raw.append(0)
        for r, g, b, a in row:
            raw.extend((r, g, b, a))

    png = bytearray(b"\x89PNG\r\n\x1a\n")
    png.extend(chunk(b"IHDR", struct.pack("!IIBBBBB", width, height, 8, 6, 0, 0, 0)))
    png.extend(chunk(b"IDAT", zlib.compress(bytes(raw), 9)))
    png.extend(chunk(b"IEND", b""))

    with open(path, "wb") as f:
        f.write(png)


def main():
    if len(sys.argv) != 2:
        raise SystemExit("usage: generate_menu_bar_icons.py <output-directory>")

    out_dir = sys.argv[1]
    os.makedirs(out_dir, exist_ok=True)

    for size in (16, 32, 64, 128, 256, 512, 1024):
        pixels = draw_icon(size)
        write_png(os.path.join(out_dir, f"icon_{size}x{size}.png"), pixels)


if __name__ == "__main__":
    main()
