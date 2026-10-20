"""Draws CompClean's icon glyphs as plain SVG geometry (no third-party symbols).

Usage: python3 scripts/icon_glyphs.py <out_dir>
Writes one SVG per concept. Each <path> becomes its own Liquid Glass layer.
"""
import math
import pathlib
import sys

SIZE = 512
C = SIZE / 2


def sparkle(cx, cy, r, pinch=0.0):
    """Four-point star with concave sides. pinch pulls the control points off-center for fuller arms."""
    p = r * pinch
    pts = [(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)]
    ctrl = [(cx + p, cy - p), (cx + p, cy + p), (cx - p, cy + p), (cx - p, cy - p)]
    d = f"M{pts[0][0]:.1f},{pts[0][1]:.1f} "
    for i in range(4):
        nx, ny = pts[(i + 1) % 4]
        qx, qy = ctrl[i]
        d += f"Q{qx:.1f},{qy:.1f} {nx:.1f},{ny:.1f} "
    return d + "Z"


def arc_band(cx, cy, r_out, r_in, start_deg, end_deg):
    """Filled ring segment with round ends, angles clockwise from 12 o'clock."""
    def pt(r, deg):
        a = math.radians(deg - 90)
        return cx + r * math.cos(a), cy + r * math.sin(a)

    large = 1 if (end_deg - start_deg) % 360 > 180 else 0
    cap = (r_out - r_in) / 2
    o1, o2 = pt(r_out, start_deg), pt(r_out, end_deg)
    i1, i2 = pt(r_in, start_deg), pt(r_in, end_deg)
    return (
        f"M{o1[0]:.1f},{o1[1]:.1f} A{r_out},{r_out} 0 {large} 1 {o2[0]:.1f},{o2[1]:.1f} "
        f"A{cap},{cap} 0 0 1 {i2[0]:.1f},{i2[1]:.1f} "
        f"A{r_in},{r_in} 0 {large} 0 {i1[0]:.1f},{i1[1]:.1f} "
        f"A{cap},{cap} 0 0 1 {o1[0]:.1f},{o1[1]:.1f} Z"
    )


def circle(cx, cy, r):
    return f"M{cx - r:.1f},{cy:.1f} a{r},{r} 0 1 0 {2 * r:.1f},0 a{r},{r} 0 1 0 {-2 * r:.1f},0 Z"


def svg(paths):
    # Concepts list paths back to front. Icon Composer stacks the first layer on top,
    # so write them front to back.
    body = "\n".join(f'  <path d="{d}" fill="{fill}"/>' for d, fill in reversed(paths))
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {SIZE} {SIZE}">\n{body}\n</svg>\n'


CONCEPTS = {
    # Disk ring: used space in white, the freed slice in teal, sparkle in the middle.
    "ring": [
        (arc_band(C, C, 236, 176, 0, 268), "#FFFFFF"),
        (arc_band(C, C, 236, 176, 292, 344), "#3FE6D6"),
        (sparkle(C, C, 108, pinch=0.24), "#3FE6D6"),
    ],
    # Orb: a big sphere with a sparkle cut into its light.
    "orb": [
        (circle(C, C, 220), "#46D9F0"),
        (sparkle(C - 10, C + 6, 118, pinch=0.08), "#FFFFFF"),
        (sparkle(C + 128, C - 128, 44, pinch=0.08), "#FFFFFF"),
    ],
    # Bubbles: three bubbles rising, one sparkle.
    "bubbles": [
        (circle(C - 70, C + 92, 128), "#FFFFFF"),
        (circle(C + 120, C - 40, 86), "#FFFFFF"),
        (circle(C - 40, C - 150, 52), "#FFFFFF"),
        (sparkle(C + 150, C + 150, 60, pinch=0.08), "#FFFFFF"),
    ],
}

if __name__ == "__main__":
    out = pathlib.Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    for name, paths in CONCEPTS.items():
        (out / f"{name}.svg").write_text(svg(paths))
        print(out / f"{name}.svg")
