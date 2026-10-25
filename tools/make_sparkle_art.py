"""Draw Media/Frame/Sparkle.tga, the sparkle Farmer puts over the node you
face: a four-pointed star of light with a smaller, fainter cross turned 45
degrees and a soft glow at its heart; and Media/Frame/Beacon.tga, the
other look: a tall beam of light, brightest at its foot, fading upward.
Also two small marks the kills panel and its banners use: Heart.tga, a
soft heart that floats up the panel, and Laurel.tga, a laurel branch on
each side (left half, right half) that sits round a crown. And
GlowArrow.tga, the arrow by your feet that points at the node you face on
Era: an arrow pointing up, with a soft glow round it.

    python tools/make_sparkle_art.py

White on transparent, so the game tints it (UI/NodeSparkle.lua tints it
gold). Uncompressed 32-bit TGA, 64 x 64, supersampled 4x4 per pixel, like
tools/make_frame_art.py. Rerun it rather than editing the TGA.
"""

import math
import os
import struct

SIZE = 64
SAMPLES = 4

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Media", "Frame", "Sparkle.tga")
BEACON = os.path.join(ROOT, "Media", "Frame", "Beacon.tga")
BEACON_W, BEACON_H = 32, 256
HEART = os.path.join(ROOT, "Media", "Frame", "Heart.tga")
LAUREL = os.path.join(ROOT, "Media", "Frame", "Laurel.tga")
LAUREL_W, LAUREL_H = 128, 64
GLOW_ARROW = os.path.join(ROOT, "Media", "Frame", "GlowArrow.tga")

# The arrow's outline, x and y from -1 to 1, y up, tip at the top.
ARROW = [(0.0, 0.82), (0.62, 0.02), (0.2, 0.02), (0.2, -0.72),
         (-0.2, -0.72), (-0.2, 0.02), (-0.62, 0.02)]

# The long rays reach the edge; the short ones reach this far of it.
SHORT = 0.55
# How fast a ray thins toward its tip; bigger is thinner.
SHARP = 2.4


def ray(u, v, length, width):
    """Light of a ray along u, thinning to a point at `length`."""
    along = abs(u) / length
    if along >= 1:
        return 0.0
    half = width * (1 - along) ** SHARP
    if half <= 0:
        return 0.0
    across = abs(v) / half
    if across >= 1:
        return 0.0
    return (1 - across) ** 1.5 * (1 - along) ** 0.6


def light(x, y):
    """0 to 1 at a point, x and y from -1 to 1."""
    value = max(ray(x, y, 1.0, 0.16), ray(y, x, 1.0, 0.16))
    d1, d2 = (x + y) / math.sqrt(2), (x - y) / math.sqrt(2)
    value = max(value, 0.6 * max(ray(d1, d2, SHORT, 0.12), ray(d2, d1, SHORT, 0.12)))
    r = math.hypot(x, y)
    value = max(value, math.exp(-(r / 0.16) ** 2))
    value += 0.25 * math.exp(-(r / 0.42) ** 2)
    return min(1.0, value)


def beam(x, y):
    """0 to 1 at a point of the beam, x from -1 to 1 across, y 0 at its
    foot to 1 at its top."""
    core = math.exp(-(x / 0.14) ** 2)
    haze = 0.45 * math.exp(-(x / 0.5) ** 2)
    rise = (1 - y) ** 1.6
    foot = 1 if y > 0.03 else y / 0.03
    return min(1.0, (core + haze) * rise * foot)


def heart(x, y):
    """0 to 1 at a point of the heart, x and y from -1 to 1, point down."""
    x, y = x * 1.35, y * 1.35 - 0.12
    inside = (x * x + y * y - 1) ** 3 - x * x * y ** 3
    if inside > 0:
        return 0.0
    # A little lighter in the middle, so the game's tint reads as glossy.
    return min(1.0, 0.85 + 0.15 * math.exp(-((x + 0.35) ** 2 + (y - 0.35) ** 2) / 0.08))


def leaf(x, y, cx, cy, angle, length, width):
    """1 inside a pointed leaf centred on (cx, cy), lying along `angle`."""
    dx, dy = x - cx, y - cy
    u = dx * math.cos(angle) + dy * math.sin(angle)
    v = -dx * math.sin(angle) + dy * math.cos(angle)
    along = u / length
    if abs(along) >= 1:
        return 0.0
    half = width * (1 - along * along)
    return 1.0 if abs(v) < half else 0.0


def branch(x, y):
    """0 to 1 at a point of the left branch, x and y from 0 to 1, y up: a
    stem curving up the left side from the foot, leaves along it."""
    cx, cy, rx, ry = 1.0, 0.53, 0.7, 0.37
    low, high = -1.75, -4.25

    def at(ang):
        return cx + rx * math.cos(ang), cy + ry * math.sin(ang)

    value = 0.0
    # The stem, by its nearest point.
    for i in range(41):
        px, py = at(low + (high - low) * i / 40)
        if math.hypot(x - px, y - py) < 0.03:
            value = 1.0
            break
    # Leaves on both sides of it, bigger near the foot.
    steps = 6
    for i in range(steps):
        t = i / (steps - 1)
        ang = low + (high - low) * t
        px, py = at(ang)
        tangent = math.atan2(ry * math.cos(ang), -rx * math.sin(ang))
        normal = tangent - math.pi / 2
        size = 0.14 - 0.035 * t
        for side in (-1, 1):
            lx = px + side * 0.075 * math.cos(normal)
            ly = py + side * 0.075 * math.sin(normal)
            value = max(value, leaf(x, y, lx, ly, tangent + math.pi + side * 0.55, size, size * 0.42))
    return value


def laurel(u, v):
    """The two branches side by side: the left in the left half, the right
    its mirror in the right half."""
    if u < 0.5:
        return branch(u * 2, v)
    return branch((1 - u) * 2, v)


def inside(x, y, points):
    """Is (x, y) inside the polygon?"""
    hit = False
    for i, (ax, ay) in enumerate(points):
        bx, by = points[i - 1]
        if (ay > y) != (by > y) and x < (bx - ax) * (y - ay) / (by - ay) + ax:
            hit = not hit
    return hit


def edge(x, y, points):
    """How far (x, y) is from the polygon's edge."""
    best = float("inf")
    for i, (ax, ay) in enumerate(points):
        bx, by = points[i - 1]
        dx, dy = bx - ax, by - ay
        t = max(0.0, min(1.0, ((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy)))
        best = min(best, math.hypot(x - ax - t * dx, y - ay - t * dy))
    return best


def glow_arrow(x, y):
    """0 to 1 at a point of the arrow, x and y from -1 to 1, tip up: solid
    inside, a soft glow outside."""
    d = edge(x, y, ARROW)
    if inside(x, y, ARROW):
        return 1.0
    return 0.55 * math.exp(-(d / 0.12) ** 2)


def write(path, width, height, shade):
    pixels = []
    # TGA rows run bottom up (descriptor 8), so row 0 is the foot.
    for row in range(height):
        for column in range(width):
            total = 0.0
            for sy in range(SAMPLES):
                for sx in range(SAMPLES):
                    total += shade((column + (sx + 0.5) / SAMPLES) / width, (row + (sy + 0.5) / SAMPLES) / height)
            alpha = int(round(total / (SAMPLES * SAMPLES) * 255))
            pixels.append(bytes((255, 255, 255, alpha)))
    header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, width, height, 32, 8)
    with open(path, "wb") as handle:
        handle.write(header)
        handle.write(b"".join(pixels))
    print("wrote %s (%d bytes)" % (os.path.relpath(path, ROOT), os.path.getsize(path)))


def main():
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    write(OUT, SIZE, SIZE, lambda u, v: light(u * 2 - 1, v * 2 - 1))
    write(BEACON, BEACON_W, BEACON_H, lambda u, v: beam(u * 2 - 1, v))
    write(HEART, SIZE, SIZE, lambda u, v: heart(u * 2 - 1, v * 2 - 1))
    write(LAUREL, LAUREL_W, LAUREL_H, laurel)
    write(GLOW_ARROW, SIZE, SIZE, lambda u, v: glow_arrow(u * 2 - 1, v * 2 - 1))


if __name__ == "__main__":
    main()
