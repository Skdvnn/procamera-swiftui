#!/usr/bin/env python3
"""
Widget face preview for the Shutter Home / Lock Screen widgets.

Draws the widget families at 3x using the geometry parsed out of
ShutterWidgets/ShutterWidgetsBundle.swift, so the density of the contact sheet,
week histogram and stat rows can be reviewed without a device. Sizes are the
smallest we support (iPhone SE), which is where the stacks are tightest.

Run:
  python3 scripts/widget_layout_preview.py
"""

from __future__ import annotations

from pathlib import Path
import re
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = Path("/opt/cursor/artifacts/widget-preview")
DOC_DIR = ROOT / "docs" / "widget-preview"
SRC = ROOT / "ShutterWidgets" / "ShutterWidgetsBundle.swift"

S = 3  # points → pixels
SMALL = (155, 155)
MEDIUM = (329, 155)
LARGE = (329, 345)

ACCENT = (255, 217, 89)
# Cull amber — same as DS.accent / WidgetPalette.keep (not a foreign green).
KEEP = ACCENT
INK = (255, 255, 255)
BODY_TOP = (26, 26, 26)
BODY_BOTTOM = (10, 10, 10)
PAPER = (26, 22, 18)
WELL = (10, 10, 10)

MONO = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono"
SANS = "/usr/share/fonts/truetype/dejavu/DejaVuSans"

# Sample content mirrors ShutterStats.placeholder.
STATS = {
    "today": 12,
    "week_total": 47,
    "total": 318,
    "keepers": 96,
    "unculled": 181,
    "top_film": "PORTRA 400",
    "top_count": 84,
    "week": [4, 9, 2, 7, 6, 7, 12],
    "labels": ["S", "M", "T", "W", "T", "F", "S"],
}
EXPOSURE = "1/125 · ISO 400 · ƒ1.8"
FILM = "PORTRA 400"
ROLL = 36


def parse_geometry() -> dict:
    src = SRC.read_text()

    def chunk(start: str, end: str) -> str:
        if start not in src or end not in src.split(start, 1)[-1]:
            print(f"WARN: cannot slice {start} → {end}", file=sys.stderr)
            return ""
        return src.split(start, 1)[1].split(end, 1)[0]

    def num(text: str, pattern: str, fallback: int, last: bool = False) -> int:
        found = re.findall(pattern, text)
        if not found:
            print(f"WARN: {pattern} not found, using {fallback}", file=sys.stderr)
            return fallback
        # Outer container padding is the last one in a body; inner chrome
        # (the shoot button) pads first.
        return int(found[-1] if last else found[0])

    medium = chunk("private var mediumBody", "private var subhead")
    large = chunk("private var largeBody", "private var rollLine")
    small = chunk("private var smallBody", "private var footerLine")
    looks = chunk("struct ShutterLooksView", "// MARK: - Lock Screen")

    return {
        "small_pad": num(small, r"\.padding\((\d+)\)", 12, last=True),
        "small_gap": num(small, r"VStack\(alignment: \.leading, spacing: (\d+)\)", 5),
        "small_bars": num(small, r"barHeight: (\d+)", 14),
        "med_pad": num(medium, r"\.padding\((\d+)\)", 12, last=True),
        "med_gap": num(medium, r"VStack\(alignment: \.leading, spacing: (\d+)\)", 6),
        "med_bars": num(medium, r"barHeight: (\d+)", 24),
        "med_sheet_w": num(medium, r"\.frame\(width: (\d+), height: \d+\)", 122),
        "med_sheet_h": num(medium, r"\.frame\(width: \d+, height: (\d+)\)", 96),
        "large_pad": num(large, r"\.padding\((\d+)\)", 16, last=True),
        "large_gap": num(large, r"VStack\(alignment: \.leading, spacing: (\d+)\)", 9),
        "large_bars": num(large, r"barHeight: (\d+)", 28),
        "looks_pad": num(looks, r"\.padding\((\d+)\)", 12, last=True),
        "looks_gap": num(looks, r"spacing: family == \.systemLarge \? \d+ : (\d+)", 6),
        "chip_med": num(looks, r"minHeight: family == \.systemLarge \? \d+ : (\d+)", 28),
        "chip_large": num(looks, r"minHeight: family == \.systemLarge \? (\d+)", 38),
        "looks_sheet": num(looks, r"\.frame\(height: (\d+)\)", 132),
        "looks_strip": num(looks, r"\.frame\(width: 132, height: (\d+)\)", 34),
        "looks_bars": num(looks, r"barHeight: (\d+)", 22),
    }


def font(pt: float, mono: bool = True, bold: bool = False) -> ImageFont.FreeTypeFont:
    base = MONO if mono else SANS
    name = f"{base}-Bold.ttf" if bold else f"{base}.ttf"
    try:
        return ImageFont.truetype(name, int(round(pt * S)))
    except Exception:
        return ImageFont.load_default()


class Face:
    """A widget face in points; every draw call scales to pixels."""

    def __init__(self, size: tuple[int, int], gradient=(BODY_TOP, BODY_BOTTOM)):
        self.w, self.h = size
        self.img = Image.new("RGB", (self.w * S, self.h * S), gradient[0])
        top, bottom = gradient
        d = ImageDraw.Draw(self.img)
        for y in range(self.img.height):
            t = y / max(1, self.img.height - 1)
            d.line(
                [(0, y), (self.img.width, y)],
                fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)),
            )
        self.d = ImageDraw.Draw(self.img, "RGBA")

    def rect(self, x, y, w, h, fill=None, outline=None, radius=6, width=1):
        self.d.rounded_rectangle(
            [x * S, y * S, (x + w) * S, (y + h) * S],
            radius=radius * S,
            fill=fill,
            outline=outline,
            width=max(1, int(width * S * 0.6)),
        )

    def text(self, x, y, s, pt=9, fill=INK, alpha=255, bold=True, anchor="la"):
        color = (fill[0], fill[1], fill[2], alpha)
        self.d.text((x * S, y * S), s, font=font(pt, bold=bold), fill=color, anchor=anchor)

    def photo(self, x, y, w, h, seed: int, newest=False, keep=False, number: str | None = None):
        """Stand-in frame: a tinted gradient so the sheet reads as photographs."""
        tile = Image.new("RGB", (int(w * S), int(h * S)))
        td = ImageDraw.Draw(tile)
        hues = [
            ((122, 96, 70), (38, 30, 24)),
            ((78, 96, 118), (24, 30, 40)),
            ((104, 84, 96), (30, 26, 32)),
            ((92, 108, 84), (26, 32, 24)),
            ((120, 104, 78), (34, 30, 22)),
            ((84, 92, 112), (26, 28, 36)),
        ]
        top, bottom = hues[seed % len(hues)]
        for row in range(tile.height):
            t = row / max(1, tile.height - 1)
            td.line(
                [(0, row), (tile.width, row)],
                fill=tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)),
            )
        # A horizon line so the cells don't read as flat swatches.
        td.line(
            [(0, tile.height * 0.62), (tile.width, tile.height * 0.55)],
            fill=(255, 255, 255, 40),
            width=max(1, S // 2),
        )
        mask = Image.new("L", tile.size, 0)
        ImageDraw.Draw(mask).rounded_rectangle(
            [0, 0, tile.width - 1, tile.height - 1], radius=5 * S, fill=255
        )
        self.img.paste(tile, (int(x * S), int(y * S)), mask)
        self.rect(
            x, y, w, h,
            outline=(ACCENT if newest else (255, 255, 255)) + ((165,) if newest else (36,)),
            radius=5,
            width=1.6 if newest else 1,
        )
        if keep:
            cx, cy = (x + 4) * S, (y + 4) * S
            self.d.ellipse([cx, cy, cx + 5 * S, cy + 5 * S], fill=KEEP)
        if number:
            self.text(x + w - 3, y + h - 3, number, pt=7, alpha=140, anchor="rd")

    def empty_cell(self, x, y, w, h, number: str | None = None):
        self.rect(x, y, w, h, fill=(255, 255, 255, 10), outline=(255, 255, 255, 18), radius=5)
        if number:
            self.text(x + w - 3, y + h - 3, number, pt=7, alpha=46, anchor="rd")

    def contact_sheet(self, x, y, w, h, cols, rows, filled, numbered=True, gap=4, sprockets=True):
        # Film paper plate + optional sprocket rails — matches WidgetContactSheet.
        # Compact medium/strip sheets skip sprockets (same as showSprockets: false).
        self.rect(x, y, w, h, fill=PAPER + (255,), outline=(255, 255, 255, 20), radius=6)
        pad = 5 if sprockets else 3
        rail = 5 if sprockets else 0
        rail_gap = 3 if sprockets else 0
        inner_x = x + pad + rail + rail_gap
        inner_y = y + pad
        inner_w = w - (pad + rail + rail_gap) * 2
        inner_h = h - pad * 2
        if inner_w < 8 or inner_h < 8:
            # Degenerate size — draw cells flush (shouldn't happen for SE budgets).
            inner_x, inner_y, inner_w, inner_h = x, y, w, h
            sprockets = False
        if sprockets:
            holes = max(2, rows * 3)
            for side in (0, 1):
                sx = x + pad if side == 0 else x + w - pad - rail
                for i in range(holes):
                    hy = inner_y + (inner_h - 3.5) * (i / max(1, holes - 1))
                    self.rect(sx, hy, rail, 3.5, fill=(0, 0, 0, 160), radius=0.8)
        cw = (inner_w - gap * (cols - 1)) / cols
        ch = (inner_h - gap * (rows - 1)) / rows
        for r in range(rows):
            for c in range(cols):
                i = r * cols + c
                cx = inner_x + c * (cw + gap)
                cy = inner_y + r * (ch + gap)
                num = f"{i + 1:02d}" if numbered else None
                if i < filled:
                    self.photo(cx, cy, cw, ch, seed=i, newest=(i == 0), keep=(i in (1, 3)), number=num)
                else:
                    self.empty_cell(cx, cy, cw, ch, number=num)

    def week_bars(self, x, y, w, bar_h, labels=True):
        week = STATS["week"]
        peak = max(week)
        gap = 4
        bw = (w - gap * (len(week) - 1)) / len(week)
        for i, count in enumerate(week):
            bx = x + i * (bw + gap)
            bh = max(2, bar_h * count / peak)
            today = i == len(week) - 1
            self.rect(
                bx, y + bar_h - bh, bw, bh,
                fill=ACCENT if today else (255, 255, 255, 82 if count else 30),
                radius=1.5,
            )
            if labels:
                self.text(
                    bx + bw / 2, y + bar_h + 3, STATS["labels"][i],
                    pt=7, alpha=150 if today else 70, anchor="ma",
                )

    def stat(self, x, y, value, caption, pt=15, tint=INK):
        self.text(x, y, value, pt=pt, fill=tint)
        self.text(x, y + pt * 1.25 + 1, caption, pt=7, alpha=90)

    def save(self, name: str):
        for dest in (OUT_DIR, DOC_DIR):
            dest.mkdir(parents=True, exist_ok=True)
            self.img.save(dest / name)
        return self.img


def launch_small(g) -> Image.Image:
    f = Face(SMALL)
    p, gap = g["small_pad"], g["small_gap"]
    x, y, w = p, p, SMALL[0] - p * 2
    f.text(x, y, "SHUTTER", pt=9, alpha=235)
    f.text(x + w, y + 1, "TDY", pt=7, alpha=90, anchor="ra")
    f.text(x + w - 18, y, f"{STATS['today']}", pt=11, fill=ACCENT, anchor="ra")
    y += 11 + gap

    # Overlapping recent stack
    stack_h = SMALL[1] - p * 2 - (11 + gap) - (g["small_bars"] + gap) - 12 - 11 - gap
    f.photo(x + 4, y + 6, w * 0.56, stack_h - 10, seed=1)
    f.photo(x + w * 0.30, y, w * 0.60, stack_h - 4, seed=0, newest=True)
    y += stack_h + gap

    f.week_bars(x, y, w, g["small_bars"], labels=False)
    y += g["small_bars"] + gap
    f.text(x, y, EXPOSURE.replace(" · ƒ1.8", ""), pt=8.5, fill=ACCENT)
    y += 11
    f.text(x, y, f"9m · {STATS['week_total']} THIS WEEK", pt=8, alpha=120)
    return f.save("launch-small.png")


def launch_medium(g) -> Image.Image:
    f = Face(MEDIUM)
    p, gap = g["med_pad"], g["med_gap"]
    sheet_w, sheet_h = g["med_sheet_w"], g["med_sheet_h"]
    left_w = MEDIUM[0] - p * 2 - sheet_w - 12
    x, y = p, p

    f.text(x, y, "SHUTTER", pt=10, alpha=235)
    f.text(x + left_w, y, f"{STATS['today']}/{ROLL}", pt=10, fill=ACCENT, anchor="ra")
    y += 13 + gap
    f.week_bars(x, y, left_w, g["med_bars"])
    y += g["med_bars"] + 3 + 9 + gap
    f.text(x, y, EXPOSURE, pt=11, fill=ACCENT)
    y += 15
    f.text(x, y, f"9m AGO · 33mm · {STATS['top_film']}", pt=9, alpha=120)

    # Metal shutter chip — matches WidgetShootButton compact (not a yellow pill).
    cap_h = 26
    cap_y = MEDIUM[1] - p - cap_h
    f.rect(x, cap_y, 86, cap_h, fill=WELL + (255,), outline=ACCENT + (80,), radius=6)
    cx0, cy0 = x + 12, cap_y + cap_h / 2
    f.d.ellipse(
        [(cx0 - 7) * S, (cy0 - 7) * S, (cx0 + 7) * S, (cy0 + 7) * S],
        fill=(40, 40, 42),
        outline=(70, 70, 72),
    )
    f.d.ellipse(
        [(cx0 - 4) * S, (cy0 - 4) * S, (cx0 + 4) * S, (cy0 + 4) * S],
        fill=ACCENT,
    )
    f.text(x + 28, cap_y + cap_h / 2, "SHOOT", pt=11, fill=ACCENT, anchor="lm")

    sx = MEDIUM[0] - p - sheet_w
    f.contact_sheet(sx, p, sheet_w, sheet_h, cols=2, rows=2, filled=4, numbered=False, sprockets=False)
    f.text(
        sx, p + sheet_h + 5,
        f"{STATS['unculled']} UNCULLED · {STATS['keepers']} KEEP",
        pt=8, alpha=110,
    )
    return f.save("launch-medium.png")


def launch_large(g) -> Image.Image:
    f = Face(LARGE)
    p, gap = g["large_pad"], g["large_gap"]
    x, y, w = p, p, LARGE[0] - p * 2

    f.text(x, y, "SHUTTER", pt=11, alpha=140)
    f.text(x, y + 14, FILM, pt=19, fill=ACCENT)
    f.text(x, y + 38, EXPOSURE, pt=11, alpha=205)
    f.text(x, y + 52, "9m AGO · 33mm", pt=9, alpha=105)

    # Round metal shutter face
    br = 34
    bx, by = LARGE[0] - p - br - 4, p + 2
    f.d.ellipse(
        [bx * S, by * S, (bx + br) * S, (by + br) * S],
        fill=WELL,
        outline=ACCENT + (80,),
    )
    f.d.ellipse(
        [(bx + 4) * S, (by + 3) * S, (bx + br - 4) * S, (by + br - 10) * S],
        fill=(45, 45, 48),
        outline=(80, 80, 82),
    )
    f.d.ellipse(
        [(bx + 10) * S, (by + 8) * S, (bx + br - 10) * S, (by + br - 15) * S],
        fill=ACCENT,
    )
    f.text(bx + br / 2, by + br - 2, "SHOOT", pt=8, alpha=180, anchor="ma")

    header_h = 66
    footer_h = 44
    y = p + header_h + gap
    sheet_h = LARGE[1] - p * 2 - header_h - footer_h - gap * 2
    f.contact_sheet(x, y, w, sheet_h, cols=3, rows=2, filled=6)

    y += sheet_h + gap
    f.week_bars(x, y, 116, g["large_bars"])
    tiles = [
        (f"{STATS['today']}", "TODAY", ACCENT),
        (f"{STATS['week_total']}", "WEEK", INK),
        (f"{STATS['keepers']}", "KEEP", INK),
        (f"{STATS['unculled']}", "UNCULLED", INK),
    ]
    tx = x + 126
    tw = (w - 126) / len(tiles)
    for value, caption, tint in tiles:
        f.stat(tx, y, value, caption, tint=tint)
        tx += tw
    f.text(
        x + 126, y + 30,
        f"{STATS['total']} TOTAL · {STATS['top_film']} ×{STATS['top_count']}",
        pt=8, alpha=95,
    )
    return f.save("launch-large.png")


def looks_face(g, large: bool) -> Image.Image:
    size = LARGE if large else MEDIUM
    f = Face(size, gradient=(BODY_TOP, BODY_BOTTOM))
    p = g["looks_pad"]
    gap = 10 if large else g["looks_gap"]
    x, y, w = p, p, size[0] - p * 2

    f.text(x + 4, y, "LOOKS", pt=10, alpha=140)
    f.text(x + w - 4, y, "ARMED PORTRA 400", pt=9, fill=ACCENT, anchor="ra")
    y += 13 + gap

    chip_h = g["chip_large"] if large else g["chip_med"]
    chips = ["PORTRA 400", "TRI-X 400", "VELVIA 50 · DREAM", "CLEAN"]
    cw = (w - 8) / 2
    for i, name in enumerate(chips):
        cx = x + (i % 2) * (cw + 8)
        cy = y + (i // 2) * (chip_h + 8)
        armed = i == 0
        f.rect(
            cx, cy, cw, chip_h,
            fill=WELL + (242 if armed else 190,),
            outline=(ACCENT + (140,)) if armed else (255, 255, 255, 20),
            radius=6,
        )
        f.text(
            cx + 8, cy + chip_h / 2, ("> " if armed else "  ") + name,
            pt=10, fill=ACCENT if armed else INK, anchor="lm",
        )
    y += chip_h * 2 + 8 + gap

    if large:
        f.text(x + 4, y, "RECENTS", pt=10, fill=ACCENT, alpha=215)
        f.text(x + w - 4, y, "TAP THE SHEET", pt=9, alpha=90, anchor="ra")
        y += 13 + 7
        f.contact_sheet(x, y, w, g["looks_sheet"], cols=3, rows=2, filled=5)
        y += g["looks_sheet"] + 7
        f.week_bars(x + 4, y, 110, g["looks_bars"])
        tx = x + 124
        for value, caption, tint in (
            (f"{STATS['today']}", "TODAY", ACCENT),
            (f"{STATS['week_total']}", "WEEK", INK),
            (f"{STATS['unculled']}", "UNCULLED", INK),
        ):
            f.stat(tx, y, value, caption, pt=13, tint=tint)
            tx += (w - 124) / 3
    else:
        strip_h = g["looks_strip"]
        f.contact_sheet(x, y + 2, 132, strip_h, cols=3, rows=1, filled=3, numbered=False, sprockets=False)
        f.text(x + 140, y + 6, f"{STATS['today']} TODAY · {STATS['week_total']} WK", pt=9, fill=ACCENT)
        f.text(x + 140, y + 18, "OPEN DARKROOM", pt=8, alpha=110)
    return f.save("looks-large.png" if large else "looks-medium.png")


def lock_row(g) -> Image.Image:
    """Circular roll gauge, rectangular frame line, inline count."""
    f = Face((329, 122), gradient=((30, 32, 38), (18, 19, 23)))
    f.text(12, 8, "LOCK SCREEN", pt=9, alpha=110)

    # Circular gauge
    cx, cy, r = 46, 52, 25
    f.d.ellipse(
        [(cx - r) * S, (cy - r) * S, (cx + r) * S, (cy + r) * S],
        fill=(255, 255, 255, 28),
    )
    progress = STATS["today"] / ROLL
    f.d.arc(
        [(cx - r + 3) * S, (cy - r + 3) * S, (cx + r - 3) * S, (cy + r - 3) * S],
        start=-90, end=-90 + 360 * progress, fill=INK, width=int(4 * S),
    )
    f.d.arc(
        [(cx - r + 3) * S, (cy - r + 3) * S, (cx + r - 3) * S, (cy + r - 3) * S],
        start=-90 + 360 * progress, end=270, fill=(255, 255, 255, 46), width=int(4 * S),
    )
    f.text(cx, cy, f"{STATS['today']}", pt=15, anchor="mm")

    # Rectangular
    rx = 96
    f.text(rx, 30, "SHUTTER", pt=12)
    f.text(329 - 12, 30, f"{STATS['today']}/{ROLL}", pt=11, anchor="ra")
    f.text(rx, 46, EXPOSURE, pt=11, alpha=225)
    f.text(rx, 60, f"9m · {FILM}", pt=10, alpha=140)

    # Inline (sits above the clock, so give it its own row)
    f.text(12, 100, f"◉ {STATS['today']} today · {EXPOSURE.split(' · ƒ')[0]}", pt=10, alpha=205)
    return f.save("lock-accessories.png")


def sheet(images: list[tuple[str, Image.Image]]) -> None:
    pad = 18
    cols = 2
    rows = (len(images) + cols - 1) // cols
    cw = max(im.width for _, im in images) + pad
    ch = max(im.height for _, im in images) + pad + 22
    board = Image.new("RGB", (cols * cw + pad, rows * ch + pad), (26, 26, 30))
    d = ImageDraw.Draw(board)
    for i, (title, im) in enumerate(images):
        x = pad + (i % cols) * cw
        y = pad + (i // cols) * ch
        d.text((x, y), title, fill=(225, 225, 225), font=font(7, mono=False, bold=True))
        board.paste(im, (x, y + 22))
    for dest in (OUT_DIR, DOC_DIR):
        dest.mkdir(parents=True, exist_ok=True)
        board.save(dest / "widget-preview.png")


def main() -> int:
    g = parse_geometry()
    faces = [
        ("Home · small", launch_small(g)),
        ("Home · medium", launch_medium(g)),
        ("Home · large", launch_large(g)),
        ("Looks · medium", looks_face(g, large=False)),
        ("Looks · large", looks_face(g, large=True)),
        ("Lock Screen accessories", lock_row(g)),
    ]
    sheet(faces)
    print("PASS")
    print(f"geometry: {g}")
    print(f"faces: {len(faces)} → {DOC_DIR}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
