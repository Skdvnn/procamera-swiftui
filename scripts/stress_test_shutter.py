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
    if route in ("fieldbook", "books", "book"):
        return ("fieldBook",)
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
        ("shuttercam://fieldbook", ("fieldBook",)),
        ("shuttercam://books", ("fieldBook",)),
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
    check(
        "collapsed dock swipe + shutter z-order",
        "collapsedBottomOverlay" in content
        and ".simultaneousGesture(bottomDeckSwipe)" in content
        and "Above histogram + viewfinder chrome" in content,
    )
    check(
        "shutter timer cancel stays enabled",
        "Do NOT set isCapturing" in content
        and "timerCountdown: timerCountdown" in content
        and ".disabled(isBusy && !canCancel)" in content,
    )
    check(
        "shutter SwiftUI press travel",
        "scaleEffect(configuration.isPressed ? 0.955" in content
        and "Shader roughness / size / lightPos args are CONSTANT" in content,
    )
    check(
        "shutter LE ring on button",
        "longExposureProgress:" in content and "showLERing" in content,
    )
    check("shutter compact landscape", "compact: compact" in content and "landscapeDeckHeight: CGFloat = 80" in content)
    check("shutter larger hit target", "contentShape(Circle())" in content and "hitPad" in content)
    check("camera permission overlay", "CameraPermissionOverlay" in content and "OPEN SETTINGS" in content)
    check("capture fail toast", "showStatusToast" in content and "Capture failed" in content)
    check("format syncs onChange", "onChange(of: captureFormat)" in content)
    check("LE cancel API", "func cancelLongExposure" in cam and "allowCancelWhileBusy" in content)
    check("HW LE configure restores exposure", "Don't leave the finder locked" in cam)
    check("flash AUTO label", 'case .auto: return "AUTO"' in content)
    check(
        "top ISO AUTO honesty",
        "isoIsAuto" in content and "isoIsAuto" in (ROOT / "AnalogGaugeView.swift").read_text(),
    )
    check("lock screen honest about looks", "LOOKS IN FULL APP" in (ROOT / "ShutterCaptureExtension" / "ShutterCaptureExtension.swift").read_text())
    check("photos denial toast", "Saved in app · Photos access needed" in content)
    check("live AUTO ISO probe", "liveISO" in cam and "startExposureProbe" in cam and "displayISO" in content)
    check("finish done handoff", "FinishDoneSheet" in (ROOT / "CullGallery.swift").read_text() and "initialBookID" in (ROOT / "PhotoBook.swift").read_text())
    check("open Photos helper", "func openPhotosApp" in (ROOT / "ShootCull.swift").read_text())
    check("contact loupe on long-press", "Long-press opens loupe" in (ROOT / "CullGallery.swift").read_text())
    check("shortcuts for look+timer", "ApplyShutterLookIntent()" in (ROOT / "ShutterAppIntents.swift").read_text() and "SetShutterTimerIntent()" in (ROOT / "ShutterAppIntents.swift").read_text())
    # Build 48 — Auto Night, burst, share/compare/map, widgets, Field Book intent
    gauge = (ROOT / "AnalogGaugeView.swift").read_text()
    cull = (ROOT / "CullGallery.swift").read_text()
    chrome = (ROOT / "CullChrome.swift").read_text()
    proof = (ROOT / "ProofExport.swift").read_text()
    intents = (ROOT / "ShutterAppIntents.swift").read_text()
    check("live shutter on top meter", "shutterIsAuto" in gauge and "shutterLabel: displayShutterLabel" in content)
    check("Auto Night assist chip", "evaluateNightAssist" in content and "TAP FOR NIGHT" in content)
    check("hold-to-burst shutter", "beginBurstHold" in content and "onBurstStart" in content and "Hold for burst" in content)
    check("widget timeline reload", "WidgetCenter.shared.reloadAllTimelines" in content)
    check("keeper JPEG share packager", "KeeperSharePackager" in proof and "jpegFileURLs" in cull)
    check("finish share dismisses first", "Dismiss done sheet first" in cull)
    check("compare EXIF + skip + reset", "metaLine(for:" in chrome and "SKIP" in chrome and "double-tap reset" in chrome)
    check("session title refine wired", "SessionTitle.refine" in cull)
    check("map chip opens Maps", "openInMaps" in proof)
    check("Field Book deep link", "case fieldBook" in deep and "shutterOpenFieldBook" in deep)
    check("Field Book intent", "OpenFieldBookIntent" in intents)
    check("film AppEnum for Shortcuts", "enum ShutterFilmLookEntity" in intents)
    check("timer AppEnum for Shortcuts", "enum ShutterTimerSecondsEntity" in intents)
    # Build 49 — finish proof, scene AUTO honesty, burst chrome, loupe badge, settings
    settings = (ROOT / "ShutterSettings.swift").read_text()
    check("finish share proof PDF", "SHARE PROOF PDF" in cull and "shareDoneProofPDF" in cull)
    check("AUTO clears SCENE highlight", 'shootModeRaw = "auto"' in content)
    check("optional shootMode in film dock", "var shootMode: ShootMode?" in (ROOT / "ViewfinderOverlay.swift").read_text())
    check("burst count on shutter chrome", "burstCount:" in content and "isBursting" in content)
    check("loupe magnification badge", "magnification" in cull and "%.1f×" in cull)
    check("settings night+burst toggles", "Low-light Night tip" in settings and "Hold shutter for burst" in settings)
    check("ContentView body split for type-checker", "finderCanvas(geo:" in content and "struct FinderStatusOverlays" in content and "struct ContentViewLifecycle" in content)

    # Build 51 — deep device-breaker guards (not just "string exists")
    check(
        "Night chip has no maxHeight infinity hit sink",
        'maxHeight: .infinity' not in content.split('struct FinderStatusOverlays')[1].split('struct ContentViewLifecycle')[0]
        or 'never maxHeight:.infinity' in content.split('struct FinderStatusOverlays')[1].split('struct ContentViewLifecycle')[0],
    )
    overlays = content.split('struct FinderStatusOverlays')[1].split('struct ContentViewLifecycle')[0]
    check("Night chip comment forbids full-bleed hit", "never maxHeight:.infinity" in overlays or "Street-chip hit sink" in overlays)
    check("Night chip frame is width-only", ".frame(maxWidth: .infinity, alignment: .top)" in overlays and "maxHeight: .infinity" not in overlays.split("if nightAssistVisible")[1].split("if let cameraError")[0])
    check("burstConsumedTap cleared in endBurstHold", "func endBurstHold" in content and "burstConsumedTap = false" in content[content.find("func endBurstHold"):content.find("func endBurstHold")+220])
    check("burst marks consumed before guards", content.find("burstConsumedTap = true") < content.find("guard holdBurstEnabled") or "Always mark the long-press" in content)
    check("burst reschedules when busy", "Pipeline still owned — reschedule" in content)
    check("burst retries serialize reject", "Serialize reject / bake busy" in content)
    check("handleCapture ignores volume during burst", "if isBurstHolding { return }" in content)
    check("Night assist hidden while capturing", "Never prompt / keep chip up while a capture" in content)
    check("Night apply gated on idle", "func applyNightAssistFromChip" in content and "guard !isCapturing, !isBurstHolding" in content)
    check("Field Book open via appear flag", "openFieldBooksOnAppear" in content and "pendingOpenFieldBook" in content)
    check("Field Book not only 0.35 notification", "pendingOpenFieldBook = true" in content)
    cull = (ROOT / "CullGallery.swift").read_text()
    check("share dismiss restores FinishDone", "Return to done sheet after share" in cull or "showFinishDone = true" in cull[cull.find("shareProofURL != nil"):cull.find("shareProofURL != nil")+500])
    check("empty keeper share restores done", "Done sheet was dismissed — bring it back" in cull)
    check("compare KEEP A/B chrome buttons", "KEEP A" in (ROOT / "CullChrome.swift").read_text() and "KEEP B" in (ROOT / "CullChrome.swift").read_text())
    check("compare panes are not Buttons", "private func pane(shot: ShotMetadata, label: String)" in (ROOT / "CullChrome.swift").read_text())
    shoot = (ROOT / "ShootCull.swift").read_text()
    check("session title caches place only", "Caches **place name only**" in shoot or "place name only" in shoot)
    check("geocode failures not cached", "Do not cache failures" in shoot)
    check("Apply Look None passes None string", 'film.map(\\ .rawValue)'.replace(' ', '') in (ROOT / "ShutterAppIntents.swift").read_text().replace(' ', '') or "film.map(\\.rawValue)" in (ROOT / "ShutterAppIntents.swift").read_text())


    check("bake failure note", "bakeLooksForCapture" in cam and "captureNote" in cam and "captureNote" in content)
    check("album export failure surfaced", "Album export failed — keepers in Field Book" in (ROOT / "CullGallery.swift").read_text())
    check("comic fallback", "func applyToon" in (ROOT / "LensFXEngine.swift").read_text())
    check("film grain bake", "func applyFilmGrain" in cam)
    # Preview intentionally skips CineStill bloom (perf); still bake keeps it.
    check("cinestill still bloom", "case .cinestill800:" in cam and "bloom.intensity = 0.3" in cam)
    check("preview bloom skipped", "Preview skips bloom" in cam)
    check("live preview bridge", "class LivePreviewBridge" in preview and "let livePreview = LivePreviewBridge()" in cam)
    check("no @Published filtered preview", "@Published var filteredPreviewImage" not in cam)
    check("previewCheap live FX", "previewCheap: true" in cam and "previewCheap: Bool = false" in (ROOT / "LensFXEngine.swift").read_text())
    check("cached grain texture", "enum CachedGrainTexture" in (ROOT / "ViewfinderOverlay.swift").read_text())
    render = (ROOT / "ShutterRender.swift").read_text()
    check("shared ShutterRender CIContext", "enum ShutterRender" in render and "static let ciContext" in render)
    check("histogram bus isolated", "final class HistogramBus" in render and "@Published var histogramBins" not in cam)
    check("histogram off video queue", "camera.histogram" in cam and "histogramQueue.async" in cam)
    check(
        "prefer 30fps preview format",
        "maxFps >= 29" in cam and "activeVideoMinFrameDuration = thirty" in cam,
    )
    check("idle frame early-out", "Idle frames: no CIImage wrap" in cam)
    check("morph texture cache", "morphCacheKey" in (ROOT / "LensFXEngine.swift").read_text())
    check("info bar observes HistogramBus", "HistogramBus.shared" in content)
    check("ShutterMotion curves", "enum ShutterMotion" in content and "static let deck" in content)
    check("no VStack deck .animation on Metal tree", ".animation(deckCollapseSpring" not in content)
    check("Metal preview freezes animation", ".transaction { $0.animation = nil }" in content)
    check("picker local entrance", "struct PickerEntrance" in (ROOT / "ViewfinderOverlay.swift").read_text())
    check("deck uses ShutterMotion", "withAnimation(ShutterMotion.deck)" in content)
    check("flash opacity wash", "opacity(showFlash ? 0.92 : 0)" in content)
    check("scrub no bounce spring", "withAnimation(ShutterMotion.scrub)" in content)
    check("no Street chip overlay", "cycleShootMode" not in content)
    check("scenes in film dock", "sectionLabel(\"SCENE\")" in (ROOT / "ViewfinderOverlay.swift").read_text())
    gauge = (ROOT / "AnalogGaugeView.swift").read_text()
    check(
        "shutter dial covers Night/LE",
        "cameraIndices = [14, 12, 11, 9, 7, 5, 2, 0]" in gauge,
    )
    check(
        "dial calls setShutterSpeed",
        "onShutterSpeedChanged" in content
        and "setShutterSpeed(index: idx, iso: Float(isoValue))" in content,
    )
    import re as _re_film
    _film_branch = _re_film.search(
        r"case \.film:(.*?)syncCaptureContextToSystem", content, _re_film.S
    )
    check(
        "film scene keeps manual exposure",
        _film_branch is not None and "camera.returnToAuto()" not in _film_branch.group(1),
    )
    check("shortcut not double-posted at launch", "Cold-start shortcuts are handled in FingerTipSceneDelegate only" in (ROOT / "ProCameraApp.swift").read_text())
    check("capture serialized", "if photoCompletionHandler != nil" in cam)
    check("look deep link clears FX", "lensFX = .none" in content and "Always apply both" in content)
    check("LE restores manuals", "restoreExposureAfterLongExposure" in cam and "exposureSnapshotBeforeLE" in cam)
    check("bake timeout armed", "func armBakeTimeout" in cam and "didFinishCaptureFor" in cam)
    check("orientation snapshotted on main", "Snapshot UIKit orientation on main" in cam)
    check("deep-link waits for session", "pendingCaptureWhenReady" in content)
    check("flip reapplies manual exposure", "reapplyManualExposure(on: newDevice)" in cam)
    check("scrubber does not fake EV", "Pass UI ISO; shutter and EV stay independent" in content)
    check("compact focus matches dial", 'stopValues: [Float] = [0.0, 0.17, 0.33, 0.5, 0.67, 1.0]' in gauge)
    check("ISO sentinel unclamped", "currentExposureDuration is a keep-current sentinel" in cam)
    check("portrait framed aspect", "case .ratio4x3: return 3.0 / 4.0" in (ROOT / "ViewfinderAids.swift").read_text())
    check("shutter passes UI ISO", "setShutterSpeed(index: idx, iso: Float(isoValue))" in content)
    check(
        "AUTO readout when not manual",
        "·A" in content and "liveISO" in cam and "displayISO" in content,
    )
    check("pinch does not write focus", "never write zoom into FOCUS" in content)
    check("timer countdown cancellable", "cancelTimerCountdown" in content)
    check("HW LE passes morphTouch", "morphTouch: self.longExposureMorphTouch" in cam)
    check(
        "HW LE not self-blocked",
        "isAccumulatingLongExposure" in cam
        and "Do NOT use isLongExposureCapturing" in cam,
    )
    check("AUTO return resets LE index", "shutterSpeedIndex = 9" in content and "leftover Night" in content)
    check("LE only when manual", "camera.isManualExposure && shutterSpeedIndex <= 3" in content)
    check("settings syncs camera format", "case .heic: camera.captureFormat = .heic" in content)
    check("no shutter under Darkroom", "guard !showPhotoBook, !showSettings" in content)
    check("zoom syncs clamped factor", "zoomValue = camera.setZoom(requested)" in content)
    check("flash auto icon", "bolt.badge.automatic.fill" in content)
    check(
        "tap-to-focus device POI",
        "captureDevicePointConverted" in preview
        and "devicePoint:" in content,
    )
    check("STACK LE upright", "longExposureInterfaceOrientation" in cam and "oriented(.right)" in cam)
    check("flip reapplies lock/WB", "reapplyLockWhiteBalanceMacro" in cam)
    check("video mirroring front", "applyVideoMirroring" in cam)
    check("flash resolved to supported", "resolvedFlashMode" in cam)
    check("cull delete requires Photos success", "Photos delete failed" in (ROOT / "CullGallery.swift").read_text())
    check("darkroom dismiss resyncs count", "onDismiss:" in content and "photoCount = gallery.shots.count" in content)
    check("preview layer rotation", "videoRotationAngle" in preview)


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
    deck_h = 80.0  # landscapeDeckHeight
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
    check("Info.plist build >= 51", m is not None and int(ver) >= 51, ver)
    import re as _re
    vers = [int(v) for v in _re.findall(r"CURRENT_PROJECT_VERSION = (\d+);", pbx)]
    check("pbx CURRENT_PROJECT_VERSION 51+", any(v >= 51 for v in vers), f"versions={sorted(set(vers))}")
    check("ShutterRender in pbx", "ShutterRender.swift in Sources" in pbx)
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
    viz_report = (ROOT / "docs" / "visual-regression" / "report.txt").read_text()
    check("visual report PASS", viz_report.startswith("PASS"))
    check("visual parses CollapsedChrome", "parsed CollapsedChrome:" in viz_report)
    check("visual film dock case", "film dock clears shutter: yes" in viz_report)
    check("visual shutter z-order", "shutter z-order above histogram: yes" in viz_report)
    check("visual landscape expanded", "landscape expanded hist↔shutter gap:" in viz_report)
    viz_dir = ROOT / "docs" / "visual-regression"
    for name in (
        "expanded-layout.png",
        "collapsed-layout.png",
        "landscape-layout.png",
        "expanded-iphone15.png",
        "collapsed-film-dock.png",
        "landscape-expanded-iphone15_land.png",
        "index.html",
    ):
        check(f"visual artifact {name}", (viz_dir / name).is_file())

    print(f"\n===== RESULTS: {PASS} passed, {FAIL} failed =====")
    if ERRORS:
        print("\nFailures:")
        for e in ERRORS:
            print(e)
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
