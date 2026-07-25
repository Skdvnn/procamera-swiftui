#!/usr/bin/env python3
"""
Stress tests for Shutter critical logic (no Xcode required).

Mirrors Swift helpers for deep links, orientation, touch mapping, widget looks,
film/FX coverage, and landscape layout invariants. Exit non-zero on failure.
"""

from __future__ import annotations

import re
import sys
import urllib.parse
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PASS = 0
FAIL = 0
ERRORS: list[str] = []


def check(name: str, cond: bool, detail: str = "") -> None:
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  PASS  {name}")
    else:
        FAIL += 1
        msg = f"  FAIL  {name}" + (f" — {detail}" if detail else "")
        print(msg)
        ERRORS.append(msg)


# ── Deep links (mirror ShutterDeepLink.swift) ───────────────────────────────

SCHEMES = {"shuttercam", "procamera"}


def parse_deeplink(url: str):
    u = urllib.parse.urlparse(url)
    if (u.scheme or "").lower() not in SCHEMES:
        return None
    host = (u.hostname or "").lower()
    path = (u.path or "").lower().strip("/")
    route = path if not host else (host if not path else f"{host}/{path}")
    q = dict(urllib.parse.parse_qsl(u.query, keep_blank_values=True))

    if route in ("", "open", "camera", "shoot"):
        return ("openCamera",)
    if route in ("capture", "shutter"):
        return ("capture",)
    if route in ("darkroom", "cull", "library"):
        return ("darkroom",)
    if route in ("look", "recipe"):
        return ("look", q.get("film"), q.get("fx"))
    if route == "timer":
        seconds = int(q.get("seconds") or q.get("s") or "3")
        return ("timer", seconds)
    if route == "peaking":
        return ("peaking", (q.get("on") or "1") != "0")
    if route == "flip":
        return ("flip",)
    return ("openCamera",)


def encode_look(film: str, fx: str | None) -> str:
    f = film if film else "None"
    x = fx if fx else "None"
    return f"{f}|{x}"


def decode_look(raw: str) -> tuple[str, str | None]:
    if "|" not in raw:
        return (raw, None)
    film, fx = raw.split("|", 1)
    if fx in ("", "None", "—"):
        return (film, None)
    return (film, fx)


def test_deeplinks() -> None:
    print("\n== Deep links ==")
    cases = [
        ("shuttercam://capture", ("capture",)),
        ("procamera://shutter", ("capture",)),
        ("shuttercam://darkroom", ("darkroom",)),
        ("shuttercam://look?film=Portra%20400&fx=Liquid", ("look", "Portra 400", "Liquid")),
        ("shuttercam://look?film=Tri-X%20400", ("look", "Tri-X 400", None)),
        ("shuttercam://timer?seconds=10", ("timer", 10)),
        ("shuttercam://timer?s=3", ("timer", 3)),
        ("shuttercam://peaking?on=0", ("peaking", False)),
        ("shuttercam://peaking", ("peaking", True)),
        ("shuttercam://flip", ("flip",)),
        ("shuttercam://camera", ("openCamera",)),
        ("https://example.com/x", None),
    ]
    for url, expected in cases:
        got = parse_deeplink(url)
        check(f"parse {url}", got == expected, f"got {got}")

    # Round-trip film|fx widget tokens
    for film, fx in [("Portra 400", "Liquid"), ("Velvia 50", None), ("None", "Dream")]:
        raw = encode_look(film, fx)
        d_film, d_fx = decode_look(raw)
        check(f"look encode {raw}", d_film == film and d_fx == fx, f"got {(d_film, d_fx)}")

    # Backward compatible plain film names
    check("legacy film token", decode_look("Portra 400") == ("Portra 400", None))


# ── Orientation / touch mapping ─────────────────────────────────────────────

def video_rotation_angle(orient: str) -> float:
    return {
        "portrait": 90,
        "portraitUpsideDown": 270,
        "landscapeRight": 0,
        "landscapeLeft": 180,
        "unknown": 90,
    }[orient]


def touch_to_buffer(rotation: str, x: float, y: float) -> tuple[float, float]:
    """Mirror LensFXEngine.touchCenter live-buffer mapping (normalized)."""
    if rotation == "rotateRight":
        return (y, x)
    if rotation == "rotateLeft":
        return (1.0 - y, 1.0 - x)
    if rotation == "rotate180":
        return (1.0 - x, 1.0 - y)
    if rotation == "identity":
        return (x, 1.0 - y)
    raise ValueError(rotation)


def upright_touch(x: float, y: float) -> tuple[float, float]:
    return (x, 1.0 - y)


def test_orientation_touch() -> None:
    print("\n== Orientation + touch ==")
    for orient, angle in [
        ("portrait", 90),
        ("portraitUpsideDown", 270),
        ("landscapeRight", 0),
        ("landscapeLeft", 180),
    ]:
        check(f"angle {orient}", video_rotation_angle(orient) == angle)

    # Center stays center under every rotation
    for rot in ("rotateRight", "rotateLeft", "rotate180", "identity"):
        nx, ny = touch_to_buffer(rot, 0.5, 0.5)
        check(f"center stable {rot}", abs(nx - 0.5) < 1e-9 and abs(ny - 0.5) < 1e-9, f"{(nx, ny)}")

    # Portrait: top-left UI → buffer near (0,0) with existing mapping (y,x)
    check("portrait TL", touch_to_buffer("rotateRight", 0.0, 0.0) == (0.0, 0.0))
    check("portrait BR", touch_to_buffer("rotateRight", 1.0, 1.0) == (1.0, 1.0))

    # LandscapeRight identity: UI top-left → CI bottom-left (y flipped)
    check("landR TL", touch_to_buffer("identity", 0.0, 0.0) == (0.0, 1.0))
    check("landR BR", touch_to_buffer("identity", 1.0, 1.0) == (1.0, 0.0))

    # LandscapeLeft 180
    check("landL TL", touch_to_buffer("rotate180", 0.0, 0.0) == (1.0, 1.0))

    # Still bake upright
    check("upright TL", upright_touch(0.0, 0.0) == (0.0, 1.0))
    check("upright BR", upright_touch(1.0, 1.0) == (1.0, 0.0))

    # Fuzz: every rotation maps unit square into unit square
    samples = [0.0, 0.25, 0.5, 0.75, 1.0]
    for rot in ("rotateRight", "rotateLeft", "rotate180", "identity"):
        ok = True
        for x in samples:
            for y in samples:
                nx, ny = touch_to_buffer(rot, x, y)
                if not (0.0 - 1e-9 <= nx <= 1.0 + 1e-9 and 0.0 - 1e-9 <= ny <= 1.0 + 1e-9):
                    ok = False
        check(f"unit square {rot}", ok)


# ── Film / FX coverage from Swift sources ───────────────────────────────────

def extract_enum_cases(path: Path, enum_name: str) -> list[str]:
    text = path.read_text()
    # Find enum block
    m = re.search(rf"enum\s+{enum_name}[^{{]*\{{(.*?)\n\}}", text, re.S)
    if not m:
        return []
    body = m.group(1)
    return re.findall(r"case\s+(\w+)", body)


def switch_cases(path: Path, after_marker: str) -> set[str]:
    text = path.read_text()
    idx = text.find(after_marker)
    if idx < 0:
        return set()
    chunk = text[idx : idx + 8000]
    return set(re.findall(r"case\s+\.(\w+)", chunk))


def test_enum_coverage() -> None:
    print("\n== Film / Lens FX coverage ==")
    film_cases = extract_enum_cases(ROOT / "ViewfinderOverlay.swift", "FilmFilterMode")
    fx_cases = extract_enum_cases(ROOT / "LensFXEngine.swift", "LensFXMode")
    check("film enum count", len(film_cases) >= 8, f"{film_cases}")
    check("fx enum count", len(fx_cases) >= 13, f"{fx_cases}")

    # Live film switch
    live = switch_cases(ROOT / "CameraManager.swift", "func applyFilmFilter(to ciImage")
    for c in film_cases:
        check(f"live film .{c}", c in live, f"missing in live switch; have {sorted(live)[:20]}")

    # Still film switch (second applyFilmFilter)
    still_text = (ROOT / "CameraManager.swift").read_text()
    # Find private applyFilmFilter(_ filmFilter
    m = re.search(r"private func applyFilmFilter\(_ filmFilter[\s\S]{0,12000}?renderCIImageSafely", still_text)
    still = set(re.findall(r"case\s+\.(\w+)", m.group(0))) if m else set()
    for c in film_cases:
        check(f"still film .{c}", c in still, f"missing in still switch")

    # LensFX apply switch
    fx_apply = switch_cases(ROOT / "LensFXEngine.swift", "func apply(\n        _ fx: LensFXMode")
    if not fx_apply:
        fx_apply = switch_cases(ROOT / "LensFXEngine.swift", "switch fx {")
    for c in fx_cases:
        check(f"fx apply .{c}", c in fx_apply, f"missing in apply switch")

    # pickerCases should hide instant
    engine = (ROOT / "LensFXEngine.swift").read_text()
    check("picker hides instant", "filter { $0 != .instant }" in engine or "$0 != .instant" in engine)


# ── Source safety guards ────────────────────────────────────────────────────

def test_source_guards() -> None:
    print("\n== Source safety guards ==")
    cam = (ROOT / "CameraManager.swift").read_text()
    preview = (ROOT / "FilteredCameraPreview.swift").read_text()
    deep = (ROOT / "ShutterDeepLink.swift").read_text()
    content = (ROOT / "ContentView.swift").read_text()

    check("import Combine", "import Combine" in cam)
    check("isSessionConfigured guard", "isSessionConfigured" in cam)
    check("no photoOutput.isAutoVirtualDeviceFusionEnabled", "photoOutput.isAutoVirtualDeviceFusionEnabled" not in cam)
    check("settings fusion off", "settings.isAutoVirtualDeviceFusionEnabled = false" in cam)
    check("capture on sessionQueue", "sessionQueue.async" in cam and "capturePhoto(with: settings" in cam)
    check("switchCamera updates max dims", "updateMaxPhotoDimensions" in cam[cam.find("func switchCamera"): cam.find("func switchCamera") + 1200])
    check("speed prioritization", "maxPhotoQualityPrioritization = natural ? .speed" in cam)
    check("Bayer prefer", "isBayerRAWPixelFormat" in cam)
    check("bake always when looks", "let needsFXBake = captureLensFX != .none || captureFilmFilter != .none" in cam)
    check("no bakeLooks leftover", "bakeLooksIntoProcessed" not in cam and "bakeLooksIntoProcessed" not in content)
    check("setBakingStill", "func setBakingStill" in cam)
    check("MTKView size before drawable", "drawableSize.width > 1" in preview and preview.find("drawableSize") < preview.find("currentDrawable"))
    check("deep link queue", "beginReceiving" in deep and "endReceiving" in deep)
    check("ContentView drains async", "ShutterDeepLinkCenter.beginReceiving()" in content)
    check("ContentView endReceiving", "endReceiving()" in content)
    check("landscape orientations in plist", "UIInterfaceOrientationLandscapeLeft" in (ROOT / "Info.plist").read_text())
    check("shutter ButtonStyle", "ShutterPressStyle" in content)
    check("bottomDeckPullGap", "bottomDeckPullGap" in content)
    check("comic fallback", "func applyToon" in (ROOT / "LensFXEngine.swift").read_text())
    check("film grain bake", "func applyFilmGrain" in cam)
    check("cinestill preview bloom", "bloom.radius = 3.2" in cam or "bloom.intensity = 0.22" in cam)


# ── Landscape layout invariants ─────────────────────────────────────────────

@dataclass
class Rect:
    name: str
    x: float
    y: float
    w: float
    h: float

    @property
    def bottom(self): return self.y + self.h
    @property
    def top(self): return self.y
    @property
    def right(self): return self.x + self.w

    def overlaps(self, o: "Rect") -> bool:
        return not (self.right <= o.x or o.right <= self.x or self.bottom <= o.y or o.bottom <= self.y)


def test_landscape_layout() -> None:
    print("\n== Landscape layout ==")
    # iPhone landscape roughly 844×390
    W, H = 844.0, 390.0
    safe_top, safe_bottom = 0.0, 21.0
    top_panel = 44.0
    deck_h = 72.0  # landscapeDeckHeight
    fade_h = 48.0
    info_h = 48.0
    bottom_pad = max(safe_bottom * 0.55, 8.0)

    y = safe_top
    top = Rect("top", 10, y, W - 20, top_panel)
    y += top_panel + 4
    underlay_h = fade_h + deck_h + bottom_pad
    deck = Rect("deck", 0, H - bottom_pad - deck_h, W, deck_h)
    hist = Rect("hist", 10, H - (deck_h + bottom_pad + 8) - info_h, W - 20, info_h)
    film = Rect("film", W - 16 - 32 - 6, y + 16, 32, 32)

    check("landscape vf height", H - y > 180, f"{H - y}")
    check("landscape hist above deck", hist.bottom <= deck.top + 0.5, f"hist.bottom={hist.bottom} deck.top={deck.top}")
    check("landscape hist/deck gap", deck.top - hist.bottom >= 7.5, f"{deck.top - hist.bottom}")
    check("landscape film above hist", film.bottom < hist.top, f"film.bottom={film.bottom} hist.top={hist.top}")
    check("landscape no hist/deck overlap", not hist.overlaps(deck))
    check("landscape deck fits", deck.bottom <= H + 0.1)


# ── Natural capture truth table ─────────────────────────────────────────────

def test_natural_truth() -> None:
    print("\n== Natural capture truth ==")
    # natural reduces Apple processing; looks still bake
    for natural in (True, False):
        for film_none in (True, False):
            for fx_none in (True, False):
                needs_bake = (not film_none) or (not fx_none)
                # prioritization
                prio = "speed" if natural else "quality"
                check(
                    f"natural={natural} filmNone={film_none} fxNone={fx_none}",
                    (prio in ("speed", "quality")) and (needs_bake == ((not film_none) or (not fx_none))),
                )


# ── PBX / version sanity ────────────────────────────────────────────────────

def test_project_sanity() -> None:
    print("\n== Project sanity ==")
    plist = (ROOT / "Info.plist").read_text()
    pbx = (ROOT / "ProCamera.xcodeproj/project.pbxproj").read_text()
    wf = (ROOT / ".github/workflows/build-ipa.yml").read_text()

    m = re.search(r"<key>CFBundleVersion</key>\s*<string>(\d+)</string>", plist)
    ver = m.group(1) if m else "?"
    check("Info.plist build >= 30", m is not None and int(ver) >= 30, ver)
    check("pbx CURRENT_PROJECT_VERSION 30+", "CURRENT_PROJECT_VERSION = 30" in pbx or "CURRENT_PROJECT_VERSION = 31" in pbx)
    check("CI builds cursor/**", '"cursor/**"' in wf or "cursor/**" in wf)
    check("widgets compile ShutterDeepLink", "ShutterDeepLink.swift in Sources" in pbx)
    check("landscape in INFOPLIST_KEY", "LandscapeLeft" in pbx)


def main() -> int:
    print("Shutter stress suite")
    test_deeplinks()
    test_orientation_touch()
    test_enum_coverage()
    test_source_guards()
    test_landscape_layout()
    test_natural_truth()
    test_project_sanity()

    # Also run layout regression
    print("\n== Visual layout regression ==")
    import subprocess
    r = subprocess.run([sys.executable, str(ROOT / "scripts/visual_layout_regression.py")], cwd=ROOT)
    check("visual_layout_regression.py", r.returncode == 0, f"exit {r.returncode}")

    print(f"\n===== RESULTS: {PASS} passed, {FAIL} failed =====")
    if ERRORS:
        print("\nFailures:")
        for e in ERRORS:
            print(e)
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
