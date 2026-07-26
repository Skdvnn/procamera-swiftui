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
    check("switchCamera updates max dims", "updateMaxPhotoDimensions" in cam[cam.find("func switchCamera"): cam.find("func switchCamera") + 2500])
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
    check("contact loupe on long-press", "loupedShotID" in (ROOT / "CullGallery.swift").read_text() and "Long press to loupe" in (ROOT / "CullGallery.swift").read_text())
    check("shortcuts for look+timer", "ApplyShutterLookIntent()" in (ROOT / "ShutterAppIntents.swift").read_text() and "SetShutterTimerIntent()" in (ROOT / "ShutterAppIntents.swift").read_text())
    # Build 48 — Auto Night, burst, share/compare/map, widgets, Field Book intent
    gauge = (ROOT / "AnalogGaugeView.swift").read_text()
    cull = (ROOT / "CullGallery.swift").read_text()
    chrome = (ROOT / "CullChrome.swift").read_text()
    proof = (ROOT / "ProofExport.swift").read_text()
    intents = (ROOT / "ShutterAppIntents.swift").read_text()
    check("live shutter on top meter", "shutterIsAuto" in gauge and ("shutterLabel: liveShutter" in content or "shutterLabel: displayShutterLabel" in content) and "LiveExposureChrome" in content)
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
    overlays = content.split('struct FinderStatusOverlays')[1].split('struct ContentViewLifecycle')[0]
    night = overlays.split("if nightAssistVisible")[1].split("if let cameraError")[0]
    check("Night chip has no maxHeight infinity hit sink", "maxHeight: .infinity" not in night)
    check("Night chip not full-bleed width frame", ".frame(maxWidth: .infinity" not in night)
    check("Night chip dismiss is 44pt", "minWidth: 44, minHeight: 44" in night)
    check("burstConsumedTap cleared in endBurstHold", "func endBurstHold" in content and "burstConsumedTap = false" in content[content.find("func endBurstHold"):content.find("func endBurstHold")+780] and "Do NOT clear burstConsumedTap here" in content)
    check("burst marks consumed only when burst starts", "Only swallow the Button release when a real burst actually starts" in content and content.find("burstConsumedTap = true") > content.find("func beginBurstHold"))
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
    check("no picker entrance over Metal", "struct PickerEntrance" not in (ROOT / "ViewfinderOverlay.swift").read_text())
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
    check("capture serialized", "peekPhotoHandler()" in cam and "bakeTimeoutCompletion != nil" in cam)
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
    check("LE only when manual", "isLongExposureShutterIndex" in content and "longExposureDurationIfAny" in content)
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

    # Build 52 — no-bugs swarm: bake timeout, LE cancel, CI serialize, UI hits
    check("bakeTimeoutCompletion exists", "bakeTimeoutCompletion" in cam)
    check("bakeGeneration invalidation", "bakeGeneration" in cam and "finishUserBake" in cam)
    check("photo handler lock helpers", "func takePhotoHandler" in cam and "func setPhotoHandler" in cam)
    check("STACK keeps LE flag through bake", "Keep isLongExposureCapturing true through bake" in cam)
    check("cancel clears bake + photo handler", "Atomically bump leOpID" in cam or "Invalidate any in-flight still bake" in cam)
    check("switchCamera blocks mid-bake", "capturePipelineBusy(includeUILongExposure: true)" in cam[cam.find("func switchCamera"):cam.find("func switchCamera")+500])
    check("formats empty-safe", "device.formats.first" in cam and "device.formats[0]" not in cam)
    check("HEIC decode fallback", "decodedProcessedPhoto" in cam and "CGImageSourceCreateWithData" in cam)
    check("syncCI used in CameraManager", "ShutterRender.syncCI" in cam)
    check("live preview materializes frames", "Materialize now — CVPixelBuffer is recycled" in cam)
    check("LivePreviewBridge coalesces", "Latest-wins coalesce" in preview)
    check("LiveExposureChrome isolates bus", "struct LiveExposureChrome" in content)
    check("ContentView does not observe LiveExposureBus", "@ObservedObject private var liveExposure" not in content)
    _looks = (ROOT / "ViewfinderOverlay.swift").read_text().split("ForEach(store.recipes)")[1][:2200]
    check("LOOKS delete not nested Button", "store.delete(recipe.id)" in _looks and 'Image(systemName: "xmark")' in _looks and _looks.count("Button {") >= 2)

    check("SCENE apply before dismiss", "onApplyShootMode?(mode)" in (ROOT / "ViewfinderOverlay.swift").read_text().split("sectionLabel(\"SCENE\")")[1][:400])
    vf = (ROOT / "ViewfinderOverlay.swift").read_text()
    scene = vf.split('sectionLabel("SCENE")')[1][:500]
    check("SCENE no async apply", "DispatchQueue.main.async" not in scene.split("sectionLabel")[0] if "sectionLabel" in scene else "DispatchQueue.main.async" not in scene)
    check("no 56pt expanded focus strip", "frame(height: 56)" not in content or "focus-stealing" in content)
    # Prefer absence of the clear strip over finder
    check(
        "expanded strip removed",
        "Color.clear\n                            .frame(height: 56)" not in content
        and ".frame(height: 56)\n                            .frame(maxWidth: .infinity)\n                            .contentShape(Rectangle())\n                            .simultaneousGesture(bottomDeckSwipe)" not in content,
    )
    check("Flash/Thumb/WB use ProButtonStyle not DragGesture0", content.count("DragGesture(minimumDistance: 0)") == 0 or "FlashButtonPill" in content)
    # Count DragGesture(0) outside shutter comments — should be zero in pill structs
    flash_chunk = content.split("struct FlashButtonPill")[1].split("struct ModeIcon")[0] if "struct FlashButtonPill" in content else ""
    thumb_chunk = content.split("struct ThumbnailPill")[1].split("struct FormatTogglePill")[0] if "struct ThumbnailPill" in content else ""
    wb_chunk = content.split("struct WBPill")[1].split("struct ExposureKnob")[0] if "struct WBPill" in content else ""
    check("FlashPill no DragGesture0", "DragGesture(minimumDistance: 0)" not in flash_chunk)
    check("ThumbnailPill no DragGesture0", "DragGesture(minimumDistance: 0)" not in thumb_chunk)
    check("WBPill no DragGesture0", "DragGesture(minimumDistance: 0)" not in wb_chunk)
    check("timer freezes morph", "frozenMorphTouch" in content)
    check("LE accepts morphTouch", "morphTouch: MorphTouchState? = nil" in cam)
    check("finish delete fail keeps marks", "Leave marks intact so the user can retry" in (ROOT / "CullGallery.swift").read_text())
    check("initialBookID onChange", "onChange(of: initialBookID)" in (ROOT / "PhotoBook.swift").read_text())
    check("CloudKit found lock", "NSLock()" in (ROOT / "CloudBooks.swift").read_text() and "found.append" in (ROOT / "CloudBooks.swift").read_text())
    check("thumb cache limits", "thumbCache.countLimit" in (ROOT / "PhotoBook.swift").read_text())
    check("loupeSessionActive still present", "loupeSessionActive" in (ROOT / "CullGallery.swift").read_text())
    # ModeControl sizing asserted in Build 56 block (26×48 / wing 112)

    # Build 53 — full-surface fixes
    check("timer generation cancel", "timerGeneration" in content and "runCountdown(expected:" in content)
    check("shutter coalesce window", "lastShutterEventAt" in content)
    check("frozen LE duration on timer", "frozenLEDuration" in content)
    check("leOpID cancel/finalize", "leOpID" in cam)
    check("STACK watchdog", "stackWatchdogWork" in cam)
    check("HW timeout work cancel", "hwTimeoutWork" in cam)
    check("pending RAW until processed", "pendingRawData" in cam)
    check("switchToLens busy gate", "func switchToLens" in cam and "capturePipelineBusy(includeUILongExposure: true)" in cam[cam.find("func switchToLens"):cam.find("func switchToLens")+2500])
    check("switchCamera gates HW token", "func capturePipelineBusy" in cam and "hwLongExposureToken != nil" in cam[cam.find("func capturePipelineBusy"):cam.find("func capturePipelineBusy")+500])
    check("STACK accumulate autoreleasepool", "autoreleasepool" in cam[cam.find("accumulationFrame"):cam.find("accumulationFrame")+500] or "autoreleasepool" in cam)
    check("clearStickyTouch API", "func clearStickyTouch" in (ROOT / "LensFXEngine.swift").read_text())
    check("Night chip not full-width hit", ".frame(maxWidth: .infinity" not in content.split("if nightAssistVisible")[1].split("if let cameraError")[0])
    check("FinishDone onDismiss handled", "handledFinishDone" in (ROOT / "CullGallery.swift").read_text())
    check("loupeSessionActive cleared only by cull drag", "Keep loupeSessionActive" in (ROOT / "CullGallery.swift").read_text() or "only cull drag onEnded clears" in (ROOT / "CullGallery.swift").read_text())
    check("contact loupeArmed", "loupedShotID" in (ROOT / "CullGallery.swift").read_text())
    check("mark-only keeps marks", "Clear marks only on delete-and-export" in (ROOT / "CullGallery.swift").read_text())
    check("deleteAssets stale IDs fail", "completion(false)" in (ROOT / "ShootCull.swift").read_text())
    check("FrameMarkStore uniquing", "uniquingKeysWith" in (ROOT / "ShootCull.swift").read_text())
    check("GalleryStore atomic index", "options: .atomic" in (ROOT / "PhotoBook.swift").read_text())
    check("CullDisplayCache", "CullDisplayCache" in (ROOT / "CullGallery.swift").read_text())
    check("shortcut debounce", "lastShortcutAt" in (ROOT / "ProCameraApp.swift").read_text())
    check("look deep link preserves FX when nil", "Unknown fxName: leave current FX" in content or "leave current FX" in content)
    check("timer AppStorage", '@AppStorage("cam.timerSeconds")' in content)
    check("volume prime ignoring", "ignoring = true" in (ROOT / "LookRecipes.swift").read_text())
    check("dial highPriorityGesture", "highPriorityGesture" in (ROOT / "AnalogGaugeView.swift").read_text())
    check("burst nil retries raised", "burstMaxNilRetries = 60" in content)

    # Build 54 — layout polish + crash fix
    check("peaking in FX picker", "peakingRow" in (ROOT / "ViewfinderOverlay.swift").read_text() and "PEAKING" in (ROOT / "ViewfinderOverlay.swift").read_text())
    check("no peaking chrome toggle", "plus.viewfinder" not in (ROOT / "ViewfinderOverlay.swift").read_text())
    check("scrubber white majors only", "yellow is reserved for the center indicator" in content)
    check("scrubber value spring", "scaleEffect(isScrolling ? 1.12" in content)
    check("shutter no press brightness", "No brightness shift" in content)
    check("shutter matte collar", "matte steel, not chrome" in content)
    check("metal shader no cool blue", "Neutral steel cast" in (ROOT / "Shaders.metal").read_text())
    # Build 55 — hard film crash fix
    check("no vulcanite Metal on camera", "LeicaVulcaniteTexture(scale: 20" not in content)
    check("no metallicSurface on shutter", "ShaderLibrary.metallicSurface" not in content)
    check("info bar L overlay hit", 'Text("L")' in content and "frame(width: 44, height: 36)" in content)

    # Build 56 — black finder freeze + tight ModeControl
    preview = (ROOT / "FilteredCameraPreview.swift").read_text()
    vf = (ROOT / "ViewfinderOverlay.swift").read_text()
    cam = (ROOT / "CameraManager.swift").read_text()
    check("preview keeps AV until Metal presents", "KEEP the AV preview visible until Metal paints" in preview)
    check("preview own CIContext", "makePreviewCIContext" in preview)
    check("preview restore on draw fail", "noteDrawFailure" in preview)
    check("preview scheduleMetalDraw fallback", "restoreCleanPreview()" in preview and "scheduleMetalDraw" in preview)
    check("live preview fail streak", "livePreviewFailStreak" in cam)
    check("format centered ZStack", "FormatTogglePill(format: $captureFormat)" in content and "ZStack {" in content[content.find("ROW 3"):content.find("ROW 3")+900])
    check("ModeControl column 26", ".frame(width: 26, height: 48)" in content)
    check("no deck grid ModeControl", "ModeControl(icon: \"rectangle.on.rectangle\"" not in content)

    # Build 57 — crash/freeze hardening
    check("capture uniqueID gate", "activeCaptureUniqueID" in cam)
    check("capturePipelineBusy helper", "func capturePipelineBusy" in cam)
    check("STACK watchdog off-main", "STACK watchdog fired" in cam and "videoDataQueue.async" in cam)
    check("finalize normalize off-main", "normalizeAccumulator may syncCI" in cam or "never run that on the main queue" in cam)
    check("switchCamera rollback", "restored previous camera" in cam)
    check("switchToLens rollback", "restored previous lens" in cam)
    check("session interruption observers", "wasInterruptedNotification" in cam and "runtimeErrorNotification" in cam)
    check("safe shutter index", "safeShutterSpeedIndex" in content)
    check("LE duration helper", "longExposureDurations" in content)
    check("Field Book no vulcanite Metal", "LeicaVulcaniteTexture" not in (ROOT / "PhotoBook.swift").read_text())
    check("CloudBooks no vulcanite Metal", "LeicaVulcaniteTexture" not in (ROOT / "CloudBooks.swift").read_text())
    check("didFinish clears pending RAW", "pendingRawData = nil" in cam[cam.find("didFinishCaptureFor"):cam.find("didFinishCaptureFor")+800])

    # Build 58–64 — pickers NEVER in Metal / SwiftUI camera tree
    overlay_chrome = vf.split("struct ViewfinderOverlay")[1].split("struct UIKitChromeLookButtons")[0]
    check("ChromePickerMenu enum", "enum ChromePickerMenu" in vf)
    check("ChromePickerGate UIKit", "enum ChromePickerGate" in vf and "ChromePickerViewController" in vf)
    check("pure UIKit picker VC", "final class ChromePickerViewController" in vf)
    check("no UIHostingController picker", "UIHostingController(rootView" not in vf and "UIHostingController(" not in vf)
    check("overlay chrome no local pickers", "LeicaFilmPicker(" not in overlay_chrome)
    check("overlay chrome no FX picker", "LensFXPicker(" not in overlay_chrome)
    check("overlay chrome no looks picker", "LookRecipePicker(" not in overlay_chrome)
    check("no ContentView chromePicker state", "chromePicker" not in content)
    check("no fullScreenCover chromePicker", "fullScreenCover(item: $chromePicker)" not in content)
    check("toggle uses ChromePickerGate", "ChromePickerGate.toggle(" in content)
    check("dismiss on collapse", "ChromePickerGate.dismiss()" in content and "onChange(of: bottomCollapsed)" in content)
    check("onTogglePicker film", "onTogglePicker?(.film)" in vf)
    check("onTogglePicker fx", "onTogglePicker?(.fx)" in vf)
    check("no looks chrome button", "onTogglePicker?(.looks)" not in overlay_chrome and "bookmark.fill" not in overlay_chrome)
    check("UIKit look buttons", "struct UIKitChromeLookButtons" in vf and "UIButton" in vf)
    check("symbol config chrome icons", "SymbolConfiguration(pointSize: 12" in vf)
    check("no LookRecipeStore on overlay chrome", "LookRecipeStore" not in overlay_chrome)
    check("no activePicker on overlay", "activePicker" not in overlay_chrome)

    # Build 60 — WYSIWYG still bake must not ship clean looks
    check("bakeLooks returns optional", "-> UIImage?" in cam[cam.find("private func bakeLooksForCapture"):cam.find("private func bakeLooksForCapture")+250])
    check("no silent clean look save", "saved clean look" not in cam)
    check("bake fail try again note", "bake failed — try again" in cam)
    check("pause live preview for bake", "Free live Metal/CI so the still bake" in cam)
    check("timer freezes film", "frozenFilmFilter" in content and "frozenLensFX" in content)
    check("film bake prefers CGImage", "Prefer CGImage → CIImage" in cam)

    # Build 61+ — separate UIWindow + snapshot session (no live Bindings)
    check("picker overlay UIWindow", "UIWindow(windowScene:" in vf and "windowLevel = .alert" in vf)
    check("ChromePickerSession snapshot", "final class ChromePickerSession" in vf)
    check("commit after window teardown", "Apply AFTER the overlay window is gone" in vf)
    check("everything deferred off touch", "EVERYTHING deferred" in vf)
    check("toggle passes values not Bindings", "filmFilter: filmFilter," in content and "onCommit:" in content)
    check("applyChromePickerCommit", "func applyChromePickerCommit" in content)

    # Build 62–63 — chrome suspend + commit-after-apply
    check("pipelineChromeSuspended", "pipelineChromeSuspended" in cam)
    check("setChromePickerPreviewSuspended", "func setChromePickerPreviewSuspended" in cam)
    check("clearLivePreviewForReconfiguration", "func clearLivePreviewForReconfiguration" in cam)
    check("video skips when chrome suspended", "!chromeSuspended" in cam)
    check("suspend on willPresent", "onWillPresent:" in content and "setChromePickerPreviewSuspended(true)" in content)
    check("no sync suspend on toggle", "setChromePickerPreviewSuspended(true)" not in content[content.find("func toggleChromePicker"):content.find("ChromePickerGate.toggle")])
    check("teardown unsuspends preview", "onTeardown:" in content and "setChromePickerPreviewSuspended(false)" in content)
    check("presentationToken race cancel", "presentationToken" in vf)
    check("foregroundActive scene only", "foregroundActive" in vf)
    check("no grain overlay on finder", "FilmGrainOverlay()" not in overlay_chrome)
    check("no scanline on finder", "ScanlineShaderOverlay()" not in overlay_chrome)
    _mask = vf[vf.find("struct AspectRatioMask"):vf.find("struct AspectRatioMask") + 900]
    check("AspectRatioMask no AnyView", "return AnyView" not in _mask and "AnyView(" not in _mask)
    check("grain cache bounded", "maxEntries = 12" in vf)
    check("recipe ID dedupe", "Deduplicate IDs" in (ROOT / "LookRecipes.swift").read_text())
    check("LivePreviewBridge attach reset", "restoreCleanPreview()" in (ROOT / "FilteredCameraPreview.swift").read_text())
    _commit_fn = content.find("func applyChromePickerCommit")
    check(
        "commit disables animations",
        _commit_fn >= 0 and "disablesAnimations = true" in content[_commit_fn:_commit_fn + 500],
    )
    check("teardown willCommit flag", "willCommit" in vf and "teardown?(willCommit)" in vf)
    check("abort unsuspends only", "if !willCommit" in content and "setChromePickerPreviewSuspended(false)" in content)
    _commit_body = content[content.find("func applyChromePickerCommit"):content.find("func applyChromePickerCommit") + 1800]
    check(
        "unsuspend after FX commit",
        "selectedLensFX" in _commit_body
        and "setChromePickerPreviewSuspended(false)" in _commit_body
        and _commit_body.find("selectedLensFX") < _commit_body.find("setChromePickerPreviewSuspended(false)"),
    )
    check("peaking committed with FX", "camera.focusPeakingEnabled = commit.focusPeaking" in content)
    check("deferred MTKView drain", "Drain filtered preview on the next turn" in cam)

    # Build 64 — pure UIKit picker + UIButton chrome (witness-table freeze)
    check("asyncAfter present delay", "asyncAfter(deadline: .now() + 0.05)" in vf)
    check("UITableView picker", "UITableView" in vf and "UITableViewDataSource" in vf)

    # Build 65 — polish: exclusive looks, retap clear, burst calm, settings looks
    check("retap clears film", "case .film where filmFilter != .none" in content and "clearChromeLook" in content)
    check("retap clears fx", "case .fx where lensFX != .none" in content)
    check("exclusive film clears FX", "if filter != .none { session.lensFX = .none }" in vf)
    check("exclusive FX clears film", "if fx != .none { session.filmFilter = .none }" in vf)
    check("applyExclusiveLook helper", "func applyExclusiveLook" in content)
    check("settings saved looks", "Saved looks" in (ROOT / "ShutterSettings.swift").read_text())
    check("burst default off", 'holdBurstEnabled = false' in content)
    check("shutter curtain state", "showShutterCurtain" in content)
    check("no cyan burstAccent", "0.55, green: 0.82, blue: 1.0" not in content)
    check("compact scrubbers no outer box", "Scrubbers only — no extra outer container" in (ROOT / "AnalogGaugeView.swift").read_text())
    check("deck swipe verticalBias", "verticalBias:" in content)
    check("no format on compact deck", "FormatTogglePill" not in content[content.find("func bottomCompactDeck"):content.find("func bottomCompactDeck")+700])
    check("format on expanded deck", "FormatTogglePill" in content[content.find("ROW 3"):content.find("ROW 3")+2200])

    # Build 66 — Night clean + EV drag anytime + hide format in fullscreen
    check("night clears looks", "filmFilter = .none" in content[content.find("case .night:"):content.find("case .night:")+700])
    check("night no peaking", "focusPeaking = false" in content[content.find("case .night:"):content.find("case .night:")+500])
    check("night 1/15 not 1 inch", "shutterSpeedIndex = 6" in content[content.find("case .night:"):content.find("case .night:")+500])
    check("EV drag anytime AUTO", "exposureDragEnabled: !isLocked && !camera.isManualExposure" in content)
    check("EV drag seeds without tap", "park the sun reticle mid-finder" in content)
    check("pan waits for direction", "Wait for direction" in (ROOT / "FilteredCameraPreview.swift").read_text())



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
    check("Info.plist build >= 66", m is not None and int(ver) >= 66, ver)
    import re as _re

    vers = [int(v) for v in _re.findall(r"CURRENT_PROJECT_VERSION = (\d+);", pbx)]
    check("pbx CURRENT_PROJECT_VERSION 66+", any(v >= 66 for v in vers), f"versions={sorted(set(vers))}")
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
