#!/usr/bin/env python3
"""
Layout visual regression for ProCamera camera chrome.

Models expanded vs collapsed frames from CollapsedChrome constants and asserts:
  1. Expanded: histogram does not overlap the shutter deck
  2. Collapsed: gradient band sits under the bottom controls; histogram sits above the deck
  3. Film / Lens FX hit targets sit in the top-trailing chrome and are not covered by
     the bottom fade / histogram / shutter layers

Also writes labeled PNG diagrams for human review.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import sys

from PIL import Image, ImageDraw, ImageFont

# Mirrors ContentView.CollapsedChrome
DECK_H = 88.0
FADE_H = 48.0
INFO_BAR_H = 56.0
HIST_DECK_GAP = 8.0
HIST_PAD_EXPANDED = 14.0           # expandedHistogramBottomPad
VF_TO_DECK_GAP = 5.0               # viewfinderToDeckGap
CHROME_INSET = 16.0
CHROME_BTN = 32.0
CHROME_STACK_GAP = 8.0


def bottom_pad(safe_bottom: float) -> float:
    return max(safe_bottom * 0.55, 8.0)


def hist_pad_collapsed(safe_bottom: float) -> float:
    return DECK_H + bottom_pad(safe_bottom) + HIST_DECK_GAP

OUT_DIR = Path("/opt/cursor/artifacts/visual-regression")
DOC_DIR = Path("docs/visual-regression")


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
    def left(self): return self.x
    @property
    def right(self): return self.x + self.w
    @property
    def top(self): return self.y
    @property
    def bottom(self): return self.y + self.h

    def overlaps(self, other: "Rect") -> bool:
        return not (
            self.right <= other.left
            or other.right <= self.left
            or self.bottom <= other.top
            or other.bottom <= self.top
        )

    def contains_point(self, px: float, py: float) -> bool:
        return self.left <= px <= self.right and self.top <= py <= self.bottom


def layout_expanded(W=390.0, H=844.0, safe_top=59.0, safe_bottom=34.0):
    """Portrait iPhone-ish expanded (bottom deck open)."""
    margin = 10.0
    top_panel = 110.0
    y = safe_top
    panels = []

    panels.append(Rect("top_panel", margin, y, W - 2 * margin, top_panel, (40, 40, 48), 1))
    y += top_panel + 4

    deck_block = DECK_H + max(safe_bottom * 0.55, 8) + 4  # deck + safe clear + pad
    vf_bottom = H - safe_bottom - deck_block - VF_TO_DECK_GAP
    # Actually expanded deck is flexible; model shutter row near bottom.
    # Structure: VStack[top, gap, vf(flex), gap5, deck]
    # Put deck at bottom.
    bottom_pad = max(safe_bottom * 0.55, 8)
    shutter_top = H - bottom_pad - DECK_H
    deck = Rect("shutter_deck", 0, shutter_top, W, DECK_H, (30, 30, 34), 2)

    vf_top = y
    vf_h = shutter_top - VF_TO_DECK_GAP - vf_top
    assert vf_h > 200, f"viewfinder too short: {vf_h}"
    vf = Rect("viewfinder", margin, vf_top, W - 2 * margin, vf_h, (10, 10, 12), 1)
    panels.append(vf)

    # Histogram inside viewfinder, bottom-padded
    hist_bottom = vf.bottom - HIST_PAD_EXPANDED
    hist_top = hist_bottom - INFO_BAR_H
    hist = Rect(
        "histogram",
        vf.x + 8,
        hist_top,
        vf.w - 16,
        INFO_BAR_H,
        (180, 160, 60),
        5,
    )
    panels.append(hist)
    panels.append(deck)

    # FX buttons — top trailing inside viewfinder
    fx_x = vf.right - CHROME_INSET - CHROME_BTN
    fx_y = vf.top + CHROME_INSET
    film = Rect("film_btn", fx_x, fx_y, CHROME_BTN, CHROME_BTN, (80, 180, 220), 40)
    shader = Rect(
        "shader_btn",
        fx_x,
        fx_y + CHROME_BTN + CHROME_STACK_GAP,
        CHROME_BTN,
        CHROME_BTN,
        (80, 200, 180),
        40,
    )
    panels.append(film)
    panels.append(shader)

    return panels, {
        "mode": "expanded",
        "hist_shutter_gap": deck.top - hist.bottom,
    }


def layout_collapsed(W=390.0, H=844.0, safe_top=59.0, safe_bottom=34.0):
    margin = 6.0
    top_panel = 52.0
    y = safe_top
    panels = []

    panels.append(Rect("top_panel", margin, y, W - 2 * margin, top_panel, (40, 40, 48), 1))
    y += top_panel + 4

    bottom_pad_v = bottom_pad(safe_bottom)
    underlay_h = FADE_H + DECK_H + bottom_pad_v
    underlay_top = H - underlay_h
    gradient = Rect("gradient_underlay", 0, underlay_top, W, underlay_h, (20, 20, 60), 1)

    deck_top = H - bottom_pad_v - DECK_H
    deck = Rect("shutter_deck", 0, deck_top, W, DECK_H, (30, 30, 34), 2)

    # Fade band is the top of the underlay (above deck)
    fade = Rect("fade_band", 0, underlay_top, W, FADE_H, (50, 50, 120), 1)

    vf = Rect("viewfinder", margin, y, W - 2 * margin, H - y - 0, (10, 10, 12), 0)
    panels.append(vf)
    panels.append(gradient)
    panels.append(fade)
    panels.append(deck)

    hist_bottom = H - hist_pad_collapsed(safe_bottom)
    hist_top = hist_bottom - INFO_BAR_H
    hist = Rect("histogram", margin + 14, hist_top, W - 2 * margin - 28, INFO_BAR_H, (180, 160, 60), 2)
    panels.append(hist)

    # FX above everything
    fx_x = W - margin - CHROME_INSET - CHROME_BTN
    fx_y = y + CHROME_INSET
    film = Rect("film_btn", fx_x, fx_y, CHROME_BTN, CHROME_BTN, (80, 180, 220), 40)
    shader = Rect(
        "shader_btn",
        fx_x,
        fx_y + CHROME_BTN + CHROME_STACK_GAP,
        CHROME_BTN,
        CHROME_BTN,
        (80, 200, 180),
        40,
    )
    panels.append(film)
    panels.append(shader)

    return panels, {
        "mode": "collapsed",
        "hist_deck_gap": deck.top - hist.bottom,
        "gradient_covers_deck": gradient.top <= deck.top and gradient.bottom >= deck.bottom,
        "fade_above_deck": fade.bottom <= deck.top + 0.5,
    }


def assert_invariants(expanded, collapsed):
    e_panels, e_meta = expanded
    c_panels, c_meta = collapsed
    errors = []

    e_hist = next(p for p in e_panels if p.name == "histogram")
    e_deck = next(p for p in e_panels if p.name == "shutter_deck")
    if e_hist.overlaps(e_deck):
        errors.append(
            f"EXPANDED: histogram overlaps shutter "
            f"(hist.bottom={e_hist.bottom:.1f} deck.top={e_deck.top:.1f})"
        )
    gap = e_meta["hist_shutter_gap"]
    if gap < VF_TO_DECK_GAP:
        errors.append(f"EXPANDED: hist↔shutter gap too small ({gap:.1f}pt)")

    for name in ("film_btn", "shader_btn"):
        btn = next(p for p in e_panels if p.name == name)
        if btn.overlaps(e_deck):
            errors.append(f"EXPANDED: {name} overlaps shutter deck")

    c_hist = next(p for p in c_panels if p.name == "histogram")
    c_deck = next(p for p in c_panels if p.name == "shutter_deck")
    c_grad = next(p for p in c_panels if p.name == "gradient_underlay")
    if c_hist.overlaps(c_deck):
        errors.append(
            f"COLLAPSED: histogram overlaps shutter "
            f"(hist.bottom={c_hist.bottom:.1f} deck.top={c_deck.top:.1f})"
        )
    if not c_meta["gradient_covers_deck"]:
        errors.append("COLLAPSED: gradient underlay does not cover shutter deck")
    if not c_meta["fade_above_deck"]:
        errors.append("COLLAPSED: fade band is not above the shutter deck")

    # FX buttons must sit above the bottom chrome band (y < gradient top)
    for name in ("film_btn", "shader_btn"):
        btn = next(p for p in c_panels if p.name == name)
        if btn.bottom > c_grad.top:
            errors.append(f"COLLAPSED: {name} intersects bottom gradient band")
        if btn.overlaps(c_hist):
            errors.append(f"COLLAPSED: {name} overlaps histogram")
        if btn.overlaps(c_deck):
            errors.append(f"COLLAPSED: {name} overlaps shutter")

    # Hit-test: center of film/shader must not fall inside deck/hist/gradient
    for name in ("film_btn", "shader_btn"):
        btn = next(p for p in c_panels if p.name == name)
        cx, cy = btn.x + btn.w / 2, btn.y + btn.h / 2
        for blocker in (c_deck, c_hist):
            if blocker.contains_point(cx, cy):
                errors.append(f"COLLAPSED: {name} center hit-blocked by {blocker.name}")

    return errors


def draw_diagram(panels, meta, path: Path, title: str, size=(390, 844)):
    img = Image.new("RGB", size, (18, 18, 20))
    draw = ImageDraw.Draw(img, "RGBA")
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 14)
        font_sm = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 11)
    except Exception:
        font = ImageFont.load_default()
        font_sm = font

    draw.text((12, 8), title, fill=(240, 240, 240), font=font)

    for p in sorted(panels, key=lambda r: r.z):
        rgba = (*p.color, 200 if p.name != "viewfinder" else 255)
        # PIL rectangle wants RGB for simple draw; use outline + fill
        fill = p.color
        draw.rectangle([p.x, p.y, p.right, p.bottom], fill=fill, outline=(220, 220, 220))
        label = f"{p.name} z{p.z}"
        draw.text((p.x + 4, p.y + 4), label, fill=(255, 255, 255), font=font_sm)

    # Legend / metrics
    y = size[1] - 70
    for k, v in meta.items():
        draw.text((12, y), f"{k}: {v}", fill=(200, 200, 120), font=font_sm)
        y += 14

    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path)
    print(f"wrote {path}")


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    DOC_DIR.mkdir(parents=True, exist_ok=True)

    expanded = layout_expanded()
    collapsed = layout_collapsed()

    errors = assert_invariants(expanded, collapsed)

    draw_diagram(
        expanded[0],
        expanded[1],
        OUT_DIR / "expanded-layout.png",
        "EXPANDED — hist must clear shutter",
    )
    draw_diagram(
        collapsed[0],
        collapsed[1],
        OUT_DIR / "collapsed-layout.png",
        "COLLAPSED — gradient under controls; FX top-right",
    )
    # Mirror into docs for the repo
    draw_diagram(
        expanded[0],
        expanded[1],
        DOC_DIR / "expanded-layout.png",
        "EXPANDED — hist must clear shutter",
    )
    draw_diagram(
        collapsed[0],
        collapsed[1],
        DOC_DIR / "collapsed-layout.png",
        "COLLAPSED — gradient under controls; FX top-right",
    )

    report = OUT_DIR / "report.txt"
    lines = []
    if errors:
        lines.append("FAIL")
        lines.extend(f" - {e}" for e in errors)
    else:
        lines.append("PASS")
        lines.append(f"expanded hist↔shutter gap: {expanded[1]['hist_shutter_gap']:.1f}pt")
        lines.append(f"collapsed hist↔deck gap: {collapsed[1]['hist_deck_gap']:.1f}pt")
        lines.append("gradient covers deck: yes")
        lines.append("film/shader clear of bottom chrome: yes")
    report.write_text("\n".join(lines) + "\n")
    print(report.read_text())

    # Also copy report to docs
    (DOC_DIR / "report.txt").write_text(report.read_text())

    if errors:
        sys.exit(1)


if __name__ == "__main__":
    main()
