#!/usr/bin/env python3

import json
import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter

THEME = {
    "bg": "#0c0c14",
    "green": "#4ade80",
    "cyan": "#22d3ee",
    "purple": "#a78bfa",
    "amber": "#fbbf24",
    "pink": "#f472b6",
    "white": "#f0f0f0",
    "muted": "#6b7280",
    "frame": "#1e293b",
}

SCALE = 2

ICON_CACHE = {}
ICON_DIR = Path(__file__).parent.parent / "icons"


def c(v):
    return int(round(v * SCALE))


def hex_rgba(hex_color, alpha=255):
    h = hex_color.lstrip("#")
    r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
    return (r, g, b, alpha)


def load_icon(name, size=32):
    key = (name, size)
    if key in ICON_CACHE:
        return ICON_CACHE[key]

    icon_path = ICON_DIR / f"{name}.png"
    if icon_path.exists():
        try:
            img = Image.open(icon_path).convert("RGBA")
            img = img.resize((c(size), c(size)), Image.Resampling.LANCZOS)
            ICON_CACHE[key] = img
            return img
        except:
            pass

    ICON_CACHE[key] = None
    return None


def load_font(size, bold=False):
    """Load a font at scaled size."""
    candidates = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
        if bold
        else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf"
        if bold
        else "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
    ]
    for path in candidates:
        try:
            return ImageFont.truetype(path, c(size))
        except OSError:
            continue
    return ImageFont.load_default()


def draw_text(draw, text, x, y, size, color=THEME["white"], bold=False, anchor="lt"):
    """Draw text with specified font size."""
    if not text:
        return
    font = load_font(size, bold)
    draw.text((c(x), c(y)), text, fill=hex_rgba(color), font=font, anchor=anchor)


def draw_rect(draw, x, y, w, h, stroke, fill=None, width=2, radius=8):
    """Draw rounded rectangle."""
    draw.rounded_rectangle(
        [c(x), c(y), c(x + w), c(y + h)],
        radius=c(radius),
        outline=hex_rgba(stroke),
        fill=hex_rgba(fill) if fill else None,
        width=max(1, c(width)),
    )


def draw_diamond(draw, cx, cy, w, h, stroke, fill=None, width=2):
    """Draw diamond shape."""
    pts = [(cx, cy - h // 2), (cx + w // 2, cy), (cx, cy + h // 2), (cx - w // 2, cy)]
    scaled = [(c(x), c(y)) for x, y in pts]
    draw.polygon(
        scaled, outline=hex_rgba(stroke), fill=hex_rgba(fill) if fill else None
    )
    draw.line(scaled + [scaled[0]], fill=hex_rgba(stroke), width=max(1, c(width)))


def draw_line(draw, points, color, width=2, style="solid"):
    """Draw line between points."""
    scaled = [(c(x), c(y)) for x, y in points]
    draw.line(scaled, fill=hex_rgba(color), width=max(1, c(width)), joint="curve")


def draw_icon(draw, kind, x, y, color, size=36, icon_name=None):
    if icon_name:
        icon_img = load_icon(icon_name, size)
        if icon_img:
            draw._image.paste(icon_img, (c(x), c(y)), icon_img)
            return

    s = size // 2
    if kind == "folder":
        draw.rectangle(
            [c(x), c(y + s // 3), c(x + s * 2), c(y + s)],
            outline=hex_rgba(color),
            width=c(2),
        )
        draw.rectangle(
            [c(x), c(y), c(x + s), c(y + s // 3 + 1)],
            outline=hex_rgba(color),
            fill=hex_rgba(color, 60),
            width=c(2),
        )
    elif kind == "shield":
        draw.polygon(
            [
                (c(x + s), c(y)),
                (c(x + s * 2), c(y + s // 2)),
                (c(x + s), c(y + s)),
                (c(x), c(y + s // 2)),
            ],
            outline=hex_rgba(color),
            width=c(2),
        )
    elif kind == "db":
        draw.ellipse(
            [c(x), c(y), c(x + s * 2), c(y + s)], outline=hex_rgba(color), width=c(2)
        )
        draw.ellipse(
            [c(x + s // 2), c(y + s // 2), c(x + s * 1.5), c(y + s)],
            outline=hex_rgba(color),
            width=c(2),
        )
    elif kind == "scan":
        draw.rectangle(
            [c(x), c(y), c(x + s * 2), c(y + s)], outline=hex_rgba(color), width=c(2)
        )
        draw.line(
            [(c(x), c(y + s // 2)), (c(x + s * 2), c(y + s // 2))],
            fill=hex_rgba(color),
            width=c(1),
        )
    elif kind == "package":
        draw.rectangle(
            [c(x), c(y + s // 4), c(x + s * 2), c(y + s)],
            outline=hex_rgba(color),
            width=c(2),
        )
        draw.line(
            [(c(x + s), c(y)), (c(x + s), c(y + s // 4))],
            fill=hex_rgba(color),
            width=c(2),
        )
    else:
        draw.rectangle(
            [c(x), c(y), c(x + s * 2), c(y + s)], outline=hex_rgba(color), width=c(2)
        )


def draw_glow_dot(draw, x, y, color, strength=1.0):
    for radius, alpha in [(10, 40), (6, 100), (3, 200)]:
        a = int(alpha * strength)
        draw.ellipse(
            (c(x - radius), c(y - radius), c(x + radius), c(y + radius)),
            fill=hex_rgba(color, a),
        )
    draw.ellipse(
        (c(x - 2), c(y - 2), c(x + 2), c(y + 2)), fill=hex_rgba(THEME["white"], 255)
    )


def pulse_rect(draw, rect, color, phase, radius=10):
    x1, y1, x2, y2 = rect
    alpha = int(120 + 60 * (0.5 + 0.5 * math.sin(phase)))
    for grow, width in [(0, 2), (3, 2), (6, 1)]:
        draw.rounded_rectangle(
            (c(x1 - grow), c(y1 - grow), c(x2 + grow), c(y2 + grow)),
            radius=c(radius + grow),
            outline=hex_rgba(color, max(20, alpha - grow * 8)),
            width=max(1, c(width)),
        )


def point_at_fraction(points, fraction):
    """Get point along polyline at given fraction."""
    fraction = fraction % 1.0
    total = sum(math.dist(a, b) for a, b in zip(points, points[1:]))
    target = fraction * total
    traveled = 0
    for a, b in zip(points, points[1:]):
        seg = math.dist(a, b)
        if traveled + seg >= target:
            t = (target - traveled) / seg if seg > 0 else 0
            return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)
        traveled += seg
    return points[-1]


def render_pirate_diagram(spec, outdir):
    """Render the pirate architecture diagram."""
    width = spec.get("canvas", {}).get("width", 1210)
    height = spec.get("canvas", {}).get("height", 1138)

    img = Image.new("RGBA", (width * SCALE, height * SCALE), hex_rgba(THEME["bg"]))
    draw = ImageDraw.Draw(img)

    # === TITLE ===
    title = spec.get("title", {})
    draw.line(
        [(c(29), c(31)), (c(29), c(78))], fill=hex_rgba(THEME["purple"]), width=c(11)
    )
    draw_text(draw, title.get("prefix", ""), 45, 30, 28, THEME["muted"], bold=False)
    draw_rect(draw, 250, 20, 550, 85, THEME["green"], THEME["green"], radius=16)
    draw_text(
        draw,
        title.get("highlight", ""),
        525,
        35,
        44,
        THEME["bg"],
        bold=True,
        anchor="mt",
    )
    draw_text(draw, title.get("subtitle", ""), 525, 80, 16, THEME["muted"], anchor="mt")

    # Signature
    draw_text(draw, spec.get("signature", ""), 1080, 30, 18, THEME["muted"])
    for dx, dy, color in [
        (0, 16, THEME["white"]),
        (20, 16, THEME["white"]),
        (30, 24, THEME["green"]),
    ]:
        draw.ellipse(
            (c(955 + dx - 3), c(143 + dy - 3), c(955 + dx + 3), c(143 + dy + 3)),
            fill=hex_rgba(color),
        )

    # === MAIN FRAME ===
    draw_rect(draw, 18, 117, 1174, 994, THEME["frame"], width=2, radius=29)

    # === INPUT STRIP ===
    inputs = spec.get("inputs", [])
    draw_rect(draw, 300, 130, 610, 110, THEME["green"], radius=8)
    draw_text(
        draw,
        spec.get("input_title", ""),
        605,
        145,
        26,
        THEME["white"],
        bold=True,
        anchor="mt",
    )

    input_positions = [380, 510, 640, 770]
    for i, (x, item) in enumerate(zip(input_positions, inputs[:4])):
        icon_kind = item.get("icon", "file")
        color = item.get("color", THEME["cyan"])
        draw_icon(draw, icon_kind, x - 20, 185, color, icon_name=item.get("icon_name"))
        draw_text(
            draw,
            item.get("label", ""),
            x + 25,
            195,
            16,
            THEME["white"],
            bold=True,
            anchor="lt",
        )

    draw_line(draw, [(605, 240), (605, 310)], THEME["white"])

    # === CORE PIPELINE ===
    draw_rect(draw, 50, 310, 1110, 330, THEME["cyan"], "#0c1a2e", radius=20)
    draw_text(
        draw,
        spec.get("core", {}).get("title", ""),
        605,
        320,
        26,
        THEME["white"],
        bold=True,
        anchor="mt",
    )
    draw_text(
        draw,
        spec.get("core", {}).get("subtitle", ""),
        605,
        350,
        14,
        THEME["muted"],
        anchor="mt",
    )

    cards = spec.get("core", {}).get("cards", [])
    card_positions = [100, 470, 840]
    for x, card in zip(card_positions, cards[:3]):
        draw_rect(draw, x, 380, 270, 100, THEME["cyan"], "#0c1a2e", radius=9)
        draw_icon(
            draw,
            card.get("icon", "file"),
            x + 15,
            395,
            card.get("color", THEME["cyan"]),
            icon_name=card.get("icon_name"),
        )
        draw_text(
            draw,
            card.get("title", ""),
            x + 60,
            415,
            24,
            THEME["white"],
            bold=True,
            anchor="lt",
        )

    draw_line(draw, [(370, 430), (470, 430)], THEME["white"])
    draw_line(draw, [(740, 430), (840, 430)], THEME["white"])
    draw_line(draw, [(975, 480), (975, 520), (766, 520), (766, 540)], THEME["white"])

    # === DECISION DIAMOND ===
    draw_diamond(draw, 706, 540, 120, 120, THEME["green"], "#052515")
    draw_text(
        draw,
        spec.get("decision", {}).get("title", "Ready?"),
        706,
        535,
        22,
        THEME["white"],
        bold=True,
        anchor="mm",
    )

    # Output box
    draw_rect(draw, 1020, 500, 110, 90, THEME["cyan"], "#0c1a2e", radius=9)
    draw_icon(
        draw,
        spec.get("output", {}).get("icon", "folder"),
        1040,
        515,
        THEME["cyan"],
        icon_name=spec.get("output", {}).get("icon_name"),
    )
    draw_text(
        draw,
        spec.get("output", {}).get("label", ""),
        1075,
        545,
        20,
        THEME["white"],
        bold=True,
        anchor="mm",
    )

    draw_line(draw, [(766, 540), (1020, 540)], THEME["white"])
    draw_text(draw, "Yes", 920, 520, 16, THEME["white"], anchor="mm")
    draw_line(
        draw,
        [(706, 600), (510, 600), (222, 600), (222, 480)],
        THEME["muted"],
        style="dashed",
    )
    draw_text(
        draw, spec.get("loop_label", ""), 350, 560, 13, THEME["muted"], anchor="mm"
    )

    # === LEFT PANEL ===
    left = spec.get("left_panel", {})
    draw_rect(draw, 39, 680, 281, 400, THEME["green"], "#04200f", radius=14)
    draw_text(draw, left.get("title", ""), 60, 695, 24, THEME["white"], bold=True)
    draw_text(draw, left.get("badge", ""), 280, 720, 12, THEME["green"], anchor="rt")

    for i, card in enumerate(left.get("cards", [])[:3]):
        y = 740 + i * 95
        draw_rect(draw, 51, y, 258, 85, THEME["green"], "#04200f", radius=8)
        draw_icon(
            draw,
            card.get("icon", "file"),
            60,
            y + 12,
            card.get("color", THEME["cyan"]),
            icon_name=card.get("icon_name"),
        )
        draw_text(
            draw, card.get("title", ""), 105, y + 30, 18, THEME["white"], bold=True
        )

    # === CENTER PANEL ===
    center = spec.get("center_panel", {})
    draw_rect(draw, 340, 680, 520, 400, THEME["purple"], "#1a1030", radius=14)
    draw_text(
        draw,
        center.get("title", ""),
        600,
        695,
        24,
        THEME["white"],
        bold=True,
        anchor="mt",
    )
    draw_text(
        draw, center.get("subtitle", ""), 600, 725, 13, THEME["muted"], anchor="mt"
    )

    for i, card in enumerate(center.get("cards", [])[:4]):
        x = 360 + (i % 2) * 250
        y = 750 + (i // 2) * 100
        draw_rect(draw, x, y, 230, 90, THEME["purple"], "#1a1030", radius=8)
        draw_icon(
            draw,
            card.get("icon", "file"),
            x + 10,
            y + 12,
            card.get("color", THEME["cyan"]),
            icon_name=card.get("icon_name"),
        )
        draw_text(
            draw, card.get("title", ""), x + 55, y + 30, 17, THEME["white"], bold=True
        )

    draw_text(
        draw,
        center.get("footer", ""),
        600,
        1050,
        15,
        THEME["purple"],
        bold=True,
        anchor="mt",
    )

    # === RIGHT PANEL ===
    right = spec.get("right_panel", {})
    draw_rect(draw, 880, 680, 290, 400, THEME["green"], "#04200f", radius=14)
    draw_text(
        draw,
        right.get("title", ""),
        1025,
        695,
        24,
        THEME["white"],
        bold=True,
        anchor="mt",
    )

    for i, card in enumerate(right.get("cards", [])[:3]):
        y = 740 + i * 95
        draw_rect(draw, 895, y, 260, 85, THEME["green"], "#04200f", radius=8)
        draw_icon(
            draw,
            card.get("icon", "file"),
            905,
            y + 12,
            card.get("color", THEME["cyan"]),
            icon_name=card.get("icon_name"),
        )
        draw_text(
            draw, card.get("title", ""), 950, y + 30, 17, THEME["white"], bold=True
        )

    return img.convert("RGB")


def animate_frame(base, idx, total):
    """Add animation effects to a frame."""
    frame = base.convert("RGBA")
    overlay = Image.new("RGBA", frame.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    progress = idx / total

    # Glow paths - moved to match new layout
    paths = [
        ([(605, 240), (605, 310)], THEME["green"], 0.00),
        ([(370, 430), (470, 430)], THEME["cyan"], 0.10),
        ([(740, 430), (840, 430)], THEME["cyan"], 0.24),
        ([(970, 480), (970, 540)], THEME["purple"], 0.38),
        ([(826, 540), (1020, 540)], THEME["green"], 0.54),
        ([(706, 600), (350, 600)], THEME["muted"], 0.66),
        ([(100, 700), (600, 700), (1100, 700)], THEME["green"], 0.20),
        ([(100, 900), (600, 900), (1100, 900)], THEME["cyan"], 0.40),
        ([(200, 200), (200, 500), (200, 900)], THEME["purple"], 0.60),
        ([(1000, 200), (1000, 500), (1000, 900)], THEME["amber"], 0.80),
    ]
    for points, color, offset in paths:
        for trail, strength in [(0, 1.0), (-0.03, 0.8), (-0.06, 0.6), (-0.09, 0.4)]:
            x, y = point_at_fraction(points, progress + offset + trail)
            draw_glow_dot(draw, x, y, color, strength)

    # Pulse targets
    pulse_targets = [
        ((300, 130, 910, 240), THEME["green"]),
        ((50, 310, 1160, 640), THEME["cyan"]),
        ((39, 680, 320, 1080), THEME["green"]),
        ((340, 680, 860, 1080), THEME["purple"]),
        ((880, 680, 1170, 1080), THEME["green"]),
    ]
    active = (idx // 8) % len(pulse_targets)
    for pos, (rect, color) in enumerate(pulse_targets):
        if pos == active:
            pulse_rect(draw, rect, color, progress * math.tau * 2, 12)

    frame.alpha_composite(overlay)
    return frame.convert("RGB")


def main():
    import argparse

    parser = argparse.ArgumentParser()
    parser.add_argument("--spec", required=True)
    parser.add_argument("--outdir", required=True)
    parser.add_argument("--basename", default="pirate")
    args = parser.parse_args()

    spec = json.loads(Path(args.spec).read_text())
    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    print("Rendering static...")
    base = render_pirate_diagram(spec, outdir)
    base.save(outdir / f"{args.basename}.png")

    print("Rendering animation...")
    total = spec.get("canvas", {}).get("frames", 41)
    fps = spec.get("canvas", {}).get("fps", 20)
    frames = [animate_frame(base, i, total) for i in range(total)]

    duration = int(1000 / fps)
    frames[0].save(
        outdir / f"{args.basename}.gif",
        save_all=True,
        append_images=frames[1:],
        duration=duration,
        loop=0,
        optimize=False,
    )

    print(f"Done! Files at {outdir}/")
    print(f"  {args.basename}.png")
    print(f"  {args.basename}.gif")


if __name__ == "__main__":
    main()
