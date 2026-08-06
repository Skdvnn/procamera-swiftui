#!/usr/bin/env python3
"""
Layout visual regression for Shutter camera chrome.

Parses CollapsedChrome constants from ContentView.swift, models expanded /
collapsed / landscape frames across several device sizes, asserts hit-test and
overlap invariants, and writes labeled PNG diagrams + an HTML index for review.

Run:
  python3 scripts/visual_layout_regression.py
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
import re
import sys

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = Path("/opt/cursor/artifacts/visual-regression")
DOC_DIR = ROOT / "docs" / "visual-regression"

# Fallback mirrors ContentView.CollapsedChrome (overridden by parse_chrome_constants).
DECK_H = 88.0
LANDSCAPE_DECK_H = 72.0
FADE_H = 48.0
INFO_BAR_H = 56.0
HIST_PAD_EXPANDED = 14.0
VF_TO_DECK_GAP = 5.0
CHROME_INSET = 16.0
CHROME_BTN = 32.0
CHROME_STACK_GAP = 8.0
# Trailing chrome column: Film / FX / Looks (ViewfinderOverlay)
TRAILING_CHROME_COUNT = 3
# Leading chrome column: Aspect / Flip / Peaking
LEADING_CHROME_COUNT = 3
# Open film dock approximate size (LeicaFilmPicker)
FILM_DOCK_W = 168.0
FILM_DOCK_H = 280.0


def parse_chrome_constants() -> dict[str, float]:
    """Keep the model honest — read CollapsedChrome from ContentView.swift."""
    src = (ROOT / "ContentView.swift").read_text()
    block = re.search(
        r"private enum CollapsedChrome \{(.*?)^\s{4}\}",
        src,
        re.S | re.M,
    )
    if not block:
        return {}
    body = block.group(1)
    keys = {
        "deckHeight": "deck_h",
        "landscapeDeckHeight": "landscape_deck_h",
        "fadeHeight": "fade_h",
        "infoBarHeight": "info_bar_h",
        "expandedHistogramBottomPad": "hist_pad_expanded",
        "viewfinderToDeckGap": "vf_to_deck_gap",
    }
    out: dict[str, float] = {}
    for swift, py in keys.items():
        m = re.search(rf"static let {swift}: CGFloat = ([0-9.]+)", body)
        if m:
            out[py] = float(m.group(1))
    return out


def apply_constants(parsed: dict[str, float]) -> None:
    global DECK_H, LANDSCAPE_DECK_H, FADE_H, INFO_BAR_H
    global HIST_PAD_EXPANDED, VF_TO_DECK_GAP
    if "deck_h" in parsed:
        DECK_H = parsed["deck_h"]
    if "landscape_deck_h" in parsed:
        LANDSCAPE_DECK_H = parsed["landscape_deck_h"]
    if "fade_h" in parsed:
        FADE_H = parsed["fade_h"]
    if "info_bar_h" in parsed:
        INFO_BAR_H = parsed["info_bar_h"]
    if "hist_pad_expanded" in parsed:
        HIST_PAD_EXPANDED = parsed["hist_pad_expanded"]
    if "vf_to_deck_gap" in parsed:
        VF_TO_DECK_GAP = parsed["vf_to_deck_gap"]


def bottom_pad(safe_bottom: float) -> float:
    return max(safe_bottom * 0.55, 8.0)


@dataclass
class Rect:
    name: str
    x: float
    y: float
    w: float
    h: float
    color: tuple
    z: int = 0

    @property
    def left(self):
        return self.x

    @property
    def right(self):
        return self.x + self.w

    @property
    def top(self):
        return self.y

    @property
    def bottom(self):
        return self.y + self.h

    def overlaps(self, other: "Rect") -> bool:
        return not (
            self.right <= other.left
            or other.right <= self.left
            or self.bottom <= other.top
            or other.bottom <= self.top
        )

    def contains_point(self, px: float, py: float) -> bool:
        return self.left <= px <= self.right and self.top <= py <= self.bottom

    def center(self) -> tuple[float, float]:
        return (self.x + self.w / 2, self.y + self.h / 2)


@dataclass
class Device:
    name: str
    w: float
    h: float
    safe_top: float
    safe_bottom: float


DEVICES_PORTRAIT = [
    Device("se", 375, 667, 20, 0),
    Device("iphone15", 390, 844, 59, 34),
    Device("pro_max", 430, 932, 59, 34),
]

DEVICES_LANDSCAPE = [
    Device("se_land", 667, 375, 0, 0),
    Device("iphone15_land", 844, 390, 0, 21),
    Device("pro_max_land", 932, 430, 0, 21),
]


def chrome_column(
    x: float,
    y: float,
    count: int,
    prefix: str,
    color: tuple,
    z: int = 40,
) -> list[Rect]:
    panels = []
    cy = y
    for i in range(count):
        panels.append(Rect(f"{prefix}_{i}", x, cy, CHROME_BTN, CHROME_BTN, color, z))
        cy += CHROME_BTN + CHROME_STACK_GAP
    return panels


def layout_expanded(
    device: Device,
    *,
    deck_h: float | None = None,
    top_panel: float = 110.0,
    margin: float = 10.0,
    film_dock_open: bool = False,
) -> tuple[list[Rect], dict]:
    W, H = device.w, device.h
    safe_top, safe_bottom = device.safe_top, device.safe_bottom
    deck_h = DECK_H if deck_h is None else deck_h
    panels: list[Rect] = []

    y = safe_top
    panels.append(Rect("top_panel", margin, y, W - 2 * margin, top_panel, (40, 40, 48), 1))
    y += top_panel + 4

    bottom_pad_v = bottom_pad(safe_bottom)
    shutter_top = H - bottom_pad_v - deck_h
    deck = Rect("shutter_deck", 0, shutter_top, W, deck_h, (30, 30, 34), 10)

    vf_top = y
    vf_h = shutter_top - VF_TO_DECK_GAP - vf_top
    vf = Rect("viewfinder", margin, vf_top, W - 2 * margin, vf_h, (10, 10, 12), 1)
    panels.append(vf)

    hist_bottom = vf.bottom - HIST_PAD_EXPANDED
    hist = Rect(
        "histogram",
        vf.x + 8,
        hist_bottom - INFO_BAR_H,
        vf.w - 16,
        INFO_BAR_H,
        (180, 160, 60),
        5,
    )
    panels.append(hist)
    panels.append(deck)

    # Leading + trailing chrome inside viewfinder (ViewfinderOverlay)
    lead_x = vf.x + CHROME_INSET
    trail_x = vf.right - CHROME_INSET - CHROME_BTN
    chrome_y = vf.top + CHROME_INSET
    panels.extend(chrome_column(lead_x, chrome_y, LEADING_CHROME_COUNT, "lead", (160, 140, 90)))
    panels.extend(chrome_column(trail_x, chrome_y, TRAILING_CHROME_COUNT, "film", (80, 180, 220)))

    if film_dock_open:
        dock = Rect(
            "film_dock",
            vf.right - 16 - FILM_DOCK_W,
            vf.top + 100,
            FILM_DOCK_W,
            FILM_DOCK_H,
            (90, 70, 40),
            45,
        )
        panels.append(dock)

    return panels, {
        "mode": "expanded",
        "device": device.name,
        "hist_shutter_gap": deck.top - hist.bottom,
        "vf_height": vf.h,
        "shutter_z": deck.z,
        "chrome_z": 40,
        "hist_z": hist.z,
        "film_dock_open": film_dock_open,
    }


def layout_collapsed(
    device: Device,
    *,
    deck_h: float | None = None,
    top_panel: float = 50.0,
    margin: float = 6.0,
    film_dock_open: bool = False,
    compact_chrome: bool = False,
) -> tuple[list[Rect], dict]:
    W, H = device.w, device.h
    safe_top, safe_bottom = device.safe_top, device.safe_bottom
    deck_h = DECK_H if deck_h is None else deck_h
    panels: list[Rect] = []

    y = safe_top
    panels.append(Rect("top_panel", margin, y, W - 2 * margin, top_panel, (40, 40, 48), 1))
    y += top_panel + 4

    bottom_pad_v = bottom_pad(safe_bottom)
    underlay_h = FADE_H + deck_h + bottom_pad_v
    underlay_top = H - underlay_h
    gradient = Rect("gradient_underlay", 0, underlay_top, W, underlay_h, (20, 20, 60), 1)
    deck = Rect("shutter_deck", 0, H - bottom_pad_v - deck_h, W, deck_h, (30, 30, 34), 10)
    fade = Rect("fade_band", 0, underlay_top, W, FADE_H, (50, 50, 120), 1)
    vf = Rect("viewfinder", margin, y, W - 2 * margin, H - y, (10, 10, 12), 0)
    panels.extend([vf, gradient, fade, deck])
    # Build 121 — collapsed / swiped-down has no histogram; shutter dock only.

    inset = 10 if compact_chrome else CHROME_INSET
    lead_x = margin + inset
    trail_x = W - margin - inset - CHROME_BTN
    chrome_y = y + inset
    panels.extend(chrome_column(lead_x, chrome_y, LEADING_CHROME_COUNT, "lead", (160, 140, 90)))
    panels.extend(chrome_column(trail_x, chrome_y, TRAILING_CHROME_COUNT, "film", (80, 180, 220)))

    if film_dock_open:
        dock_top = y + (48 if compact_chrome else 100)
        dock = Rect(
            "film_dock",
            W - margin - (10 if compact_chrome else 16) - FILM_DOCK_W,
            dock_top,
            FILM_DOCK_W,
            min(FILM_DOCK_H, deck.top - dock_top - 8),
            (90, 70, 40),
            45,
        )
        panels.append(dock)

    return panels, {
        "mode": "collapsed",
        "device": device.name,
        "has_histogram": False,
        "vf_height": vf.h,
        "gradient_covers_deck": gradient.top <= deck.top and gradient.bottom >= deck.bottom,
        "fade_above_deck": fade.bottom <= deck.top + 0.5,
        "shutter_z": deck.z,
        "film_dock_open": film_dock_open,
    }


def assert_common(panels: list[Rect], meta: dict, label: str) -> list[str]:
    errors: list[str] = []
    by = {p.name: p for p in panels}
    hist = by.get("histogram")
    deck = by["shutter_deck"]

    if hist is not None:
        if hist.overlaps(deck):
            errors.append(
                f"{label}: histogram overlaps shutter "
                f"(hist.bottom={hist.bottom:.1f} deck.top={deck.top:.1f})"
            )

        # Expanded: shutter deck is a sibling below the viewfinder hist.
        if meta.get("shutter_z", 0) <= meta.get("hist_z", 0):
            errors.append(
                f"{label}: shutter z-order not above histogram "
                f"(shutter={meta.get('shutter_z')} hist={meta.get('hist_z')})"
            )

    if meta.get("vf_height", 999) < 160:
        errors.append(f"{label}: viewfinder too short ({meta['vf_height']:.1f})")

    # Trailing film column must clear bottom chrome
    film_btns = [p for p in panels if p.name.startswith("film_")]
    for btn in film_btns:
        if btn.overlaps(deck):
            errors.append(f"{label}: {btn.name} overlaps shutter deck")
        if hist is not None and btn.overlaps(hist):
            errors.append(f"{label}: {btn.name} overlaps histogram")
        cx, cy = btn.center()
        blocked = deck.contains_point(cx, cy)
        if hist is not None:
            blocked = blocked or hist.contains_point(cx, cy)
        if blocked:
            errors.append(f"{label}: {btn.name} center hit-blocked")

    lead_btns = [p for p in panels if p.name.startswith("lead_")]
    for btn in lead_btns:
        if btn.overlaps(deck):
            errors.append(f"{label}: {btn.name} overlaps shutter deck")

    # Open SCENE/FILM dock must not cover the shutter button center
    if "film_dock" in by:
        dock = by["film_dock"]
        sx, sy = deck.center()
        if dock.contains_point(sx, sy):
            errors.append(f"{label}: open film dock covers shutter center")
        if dock.bottom > deck.top - 4:
            errors.append(
                f"{label}: open film dock reaches into shutter band "
                f"(dock.bottom={dock.bottom:.1f} deck.top={deck.top:.1f})"
            )

    return errors


def assert_expanded(panels: list[Rect], meta: dict) -> list[str]:
    label = f"EXPANDED[{meta['device']}]"
    errors = assert_common(panels, meta, label)
    if "histogram" not in {p.name for p in panels}:
        errors.append(f"{label}: expanded mode missing histogram")
    gap = meta["hist_shutter_gap"]
    if gap < VF_TO_DECK_GAP:
        errors.append(f"{label}: hist↔shutter gap too small ({gap:.1f}pt)")
    return errors


def assert_collapsed(panels: list[Rect], meta: dict) -> list[str]:
    label = f"COLLAPSED[{meta['device']}]"
    errors = assert_common(panels, meta, label)
    by = {p.name: p for p in panels}
    # Build 121 — swiped-down chrome is shutter-only; histogram must stay off.
    if "histogram" in by or meta.get("has_histogram"):
        errors.append(f"{label}: collapsed mode must not show histogram")
    if "shutter_deck" not in by:
        errors.append(f"{label}: collapsed mode missing shutter deck")
    if not meta.get("gradient_covers_deck"):
        errors.append(f"{label}: gradient underlay does not cover shutter deck")
    if not meta.get("fade_above_deck"):
        errors.append(f"{label}: fade band is not above the shutter deck")
    grad = by["gradient_underlay"]
    for btn in (p for p in panels if p.name.startswith("film_")):
        if btn.bottom > grad.top:
            errors.append(f"{label}: {btn.name} intersects bottom gradient band")
    return errors


def draw_diagram(panels, meta, path: Path, title: str, size=None):
    if size is None:
        # Infer from outermost panels
        max_r = max(p.right for p in panels)
        max_b = max(p.bottom for p in panels)
        size = (int(max_r), int(max_b))
    img = Image.new("RGB", size, (18, 18, 20))
    draw = ImageDraw.Draw(img)
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 14)
        font_sm = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 11)
    except Exception:
        font = ImageFont.load_default()
        font_sm = font

    draw.text((12, 8), title, fill=(240, 240, 240), font=font)

    for p in sorted(panels, key=lambda r: r.z):
        draw.rectangle(
            [p.x, p.y, p.right, p.bottom],
            fill=p.color,
            outline=(220, 220, 220),
        )
        draw.text((p.x + 4, p.y + 4), f"{p.name} z{p.z}", fill=(255, 255, 255), font=font_sm)

    y = size[1] - 84
    for k, v in meta.items():
        draw.text((12, y), f"{k}: {v}", fill=(200, 200, 120), font=font_sm)
        y += 13

    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path)
    print(f"wrote {path}")


def write_html_index(cases: list[tuple[str, Path]], report_lines: list[str]) -> None:
    cards = []
    for title, path in cases:
        rel = path.name
        cards.append(
            f'<figure><img src="{rel}" alt="{title}"/'
            f"><figcaption>{title}</figcaption></figure>"
        )
    body = "\n".join(cards)
    report = "<br/>".join(report_lines)
    html = f"""<!DOCTYPE html>
<html><head><meta charset="utf-8"/>
<title>Shutter visual regression</title>
<style>
body {{ background:#111; color:#eee; font-family:ui-sans-serif,system-ui,sans-serif; margin:24px; }}
h1 {{ font-weight:600; font-size:20px; }}
.grid {{ display:grid; grid-template-columns:repeat(auto-fill,minmax(280px,1fr)); gap:16px; }}
figure {{ margin:0; background:#1a1a1e; padding:10px; border-radius:8px; }}
img {{ width:100%; height:auto; image-rendering:pixelated; background:#000; }}
figcaption {{ margin-top:8px; font-size:12px; color:#bbb; }}
.report {{ margin:16px 0 28px; padding:12px 14px; background:#1e1e24; border-left:3px solid #c8c060; font-family:ui-monospace,monospace; font-size:13px; }}
</style></head><body>
<h1>Shutter visual regression</h1>
<div class="report">{report}</div>
<div class="grid">
{body}
</div>
</body></html>
"""
    for dest in (OUT_DIR, DOC_DIR):
        dest.mkdir(parents=True, exist_ok=True)
        (dest / "index.html").write_text(html)


@dataclass
class Case:
    key: str
    title: str
    panels: list[Rect]
    meta: dict
    size: tuple[int, int]
    kind: str  # expanded | collapsed


def main() -> int:
    parsed = parse_chrome_constants()
    apply_constants(parsed)
    if not parsed:
        print("WARN: could not parse CollapsedChrome — using fallbacks", file=sys.stderr)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    DOC_DIR.mkdir(parents=True, exist_ok=True)

    cases: list[Case] = []
    errors: list[str] = []

    # Portrait expanded + collapsed across devices
    for device in DEVICES_PORTRAIT:
        e_panels, e_meta = layout_expanded(device)
        errors.extend(assert_expanded(e_panels, e_meta))
        cases.append(
            Case(
                f"expanded-{device.name}",
                f"EXPANDED · {device.name}",
                e_panels,
                e_meta,
                (int(device.w), int(device.h)),
                "expanded",
            )
        )

        c_panels, c_meta = layout_collapsed(device)
        errors.extend(assert_collapsed(c_panels, c_meta))
        cases.append(
            Case(
                f"collapsed-{device.name}",
                f"COLLAPSED · {device.name}",
                c_panels,
                c_meta,
                (int(device.w), int(device.h)),
                "collapsed",
            )
        )

    # Film dock open (iphone15 collapsed) — SCENE/FILM picker must clear shutter
    dock_device = DEVICES_PORTRAIT[1]
    d_panels, d_meta = layout_collapsed(dock_device, film_dock_open=True)
    errors.extend(assert_collapsed(d_panels, d_meta))
    cases.append(
        Case(
            "collapsed-film-dock",
            "COLLAPSED · film dock open",
            d_panels,
            d_meta,
            (int(dock_device.w), int(dock_device.h)),
            "collapsed",
        )
    )

    # Landscape compact (collapsed) + landscape expanded bottom deck
    for device in DEVICES_LANDSCAPE:
        lc_panels, lc_meta = layout_collapsed(
            device,
            deck_h=LANDSCAPE_DECK_H,
            top_panel=44.0,
            compact_chrome=True,
        )
        errors.extend(assert_collapsed(lc_panels, lc_meta))
        cases.append(
            Case(
                f"landscape-collapsed-{device.name}",
                f"LANDSCAPE COLLAPSED · {device.name}",
                lc_panels,
                lc_meta,
                (int(device.w), int(device.h)),
                "collapsed",
            )
        )

        le_panels, le_meta = layout_expanded(
            device,
            deck_h=LANDSCAPE_DECK_H,
            top_panel=44.0,
            margin=6.0,
        )
        errors.extend(assert_expanded(le_panels, le_meta))
        cases.append(
            Case(
                f"landscape-expanded-{device.name}",
                f"LANDSCAPE EXPANDED · {device.name}",
                le_panels,
                le_meta,
                (int(device.w), int(device.h)),
                "expanded",
            )
        )

    # Legacy canonical filenames for stress_test / docs
    canonical = {
        "expanded-layout.png": "expanded-iphone15",
        "collapsed-layout.png": "collapsed-iphone15",
        "landscape-layout.png": "landscape-collapsed-iphone15_land",
    }

    diagram_index: list[tuple[str, Path]] = []
    by_key = {c.key: c for c in cases}

    for case in cases:
        for dest in (OUT_DIR, DOC_DIR):
            path = dest / f"{case.key}.png"
            draw_diagram(case.panels, case.meta, path, case.title, size=case.size)
        diagram_index.append((case.title, OUT_DIR / f"{case.key}.png"))

    for legacy_name, key in canonical.items():
        case = by_key[key]
        for dest in (OUT_DIR, DOC_DIR):
            draw_diagram(
                case.panels,
                case.meta,
                dest / legacy_name,
                case.title,
                size=case.size,
            )

    # Report
    report_lines: list[str] = []
    if errors:
        report_lines.append("FAIL")
        report_lines.extend(f" - {e}" for e in errors)
    else:
        report_lines.append("PASS")
        report_lines.append(f"parsed CollapsedChrome: {parsed or 'fallback'}")
        report_lines.append(f"cases: {len(cases)}")
        # Spotlight metrics from canonical iPhone 15
        e = by_key["expanded-iphone15"].meta
        le = by_key["landscape-expanded-iphone15_land"].meta
        report_lines.append(f"expanded hist↔shutter gap: {e['hist_shutter_gap']:.1f}pt")
        report_lines.append("collapsed histogram: hidden")
        report_lines.append("landscape collapsed histogram: hidden")
        report_lines.append(f"landscape expanded hist↔shutter gap: {le['hist_shutter_gap']:.1f}pt")
        report_lines.append("gradient covers deck: yes")
        report_lines.append("film/shader clear of bottom chrome: yes")
        report_lines.append("collapsed shutter dock: yes")
        report_lines.append("film dock clears shutter: yes")

    report_text = "\n".join(report_lines) + "\n"
    (OUT_DIR / "report.txt").write_text(report_text)
    (DOC_DIR / "report.txt").write_text(report_text)
    print(report_text)

    write_html_index(diagram_index, report_lines)

    if errors:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
