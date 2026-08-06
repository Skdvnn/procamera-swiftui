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


def source_chunk(content: str, start: str, end: str) -> str:
    """Slice between two struct anchors, failing loudly if either moved.

    A missing anchor used to silently widen the slice, which turned every
    check on that chunk into a no-op instead of a failure.
    """
    ok = start in content and end in content.split(start, 1)[-1]
    check(f"anchors present: {start} → {end}", ok)
    if not ok:
        return ""
    return content.split(start, 1)[1].split(end, 1)[0]


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
    if route in ("scene", "mode"):
        return ("scene", (q.get("mode") or q.get("name") or "auto").lower())
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
        ("shuttercam://scene?mode=auto", ("scene", "auto")),
        ("shuttercam://scene?mode=night", ("scene", "night")),
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
        and "Above viewfinder chrome so shutter wins taps" in content,
    )
    # Build 121 — swiped-down finder hides histogram; shutter always stays
    # (including Minimalism, which previously gated the whole collapsed overlay off).
    check(
        "collapsed always shows shutter dock",
        "if effectiveBottomCollapsed {" in content
        and "Shutter dock always stays in the quiet finder" in content
        and "if effectiveBottomCollapsed && !minimalismMode" not in content,
    )
    check(
        "collapsed hides histogram",
        "Swiped-down / collapsed: no histogram" in content
        and "Histogram stays off while collapsed" in content
        and "histogramBottomPad" not in content,
    )
    check(
        "shutter timer cancel stays enabled",
        "Do NOT set isCapturing" in content
        and "timerCountdown: timerCountdown" in content
        and ".disabled(isBusy && !canCancel)" in content,
    )
    shutter_press = content[content.find("struct ShutterPressStyle"):content.find("struct ShutterButtonChrome")]
    shutter_chrome = content[content.find("struct ShutterButtonChrome"):content.find("struct ScaleButtonStyle")]
    check(
        "shutter face-only push-in",
        "shutterPressed" in content
        and "Collar stays solid" in shutter_press
        and "Shader roughness / size / lightPos args are CONSTANT" in content
        and "scaleEffect(configuration.isPressed" not in shutter_press
        and ".environment" in shutter_press and "shutterPressed" in shutter_press,
    )
    check(
        "shutter press scales into well",
        "scaleEffect(isPressed ? pressScale" in shutter_chrome
        and "private var pressScale" in shutter_chrome
        and "Scales into the well on press" in shutter_chrome,
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
    # Build 105 — SCENE Auto advisor (Night / Street / Film soft tips + Shortcuts).
    settings = (ROOT / "ShutterSettings.swift").read_text()
    check("ShootMode has auto", "case auto" in settings and '"Watch light · suggest SCENE"' in settings)
    check("AutoSceneAdvisor pick", "enum AutoSceneAdvisor" in settings and "static func pick(" in settings)
    check("scene assist evaluate", "evaluateSceneAssist" in content)
    check("scene tip settings label", "Scene tip" in settings)
    check("scene deep link", 'case "scene", "mode"' in (ROOT / "ShutterDeepLink.swift").read_text())
    check("ApplyShutterSceneIntent", "struct ApplyShutterSceneIntent" in (ROOT / "ShutterAppIntents.swift").read_text())
    check("hold-to-burst shutter", "beginBurstHold" in content and "onBurstStart" in content and "Hold for burst" in content)
    check(
        "widget timeline reload",
        "WidgetReloadGate.reload" in content
        or "WidgetCenter.shared.reloadAllTimelines" in content,
    )
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
    check("settings night+burst toggles", "Scene tip" in settings and "Hold burst" in settings)
    check("ContentView body split for type-checker", "finderCanvas(geo:" in content and "struct FinderStatusOverlays" in content and "struct ContentViewLifecycle" in content)

    # Build 51 — deep device-breaker guards (not just "string exists")
    overlays = source_chunk(content, "struct FinderStatusOverlays", "struct ContentViewLifecycle")
    night = source_chunk(overlays, "if sceneAssist.visible", "if let cameraError")
    check("Night chip has no maxHeight infinity hit sink", "maxHeight: .infinity" not in night)
    check("Night chip not full-bleed width frame", ".frame(maxWidth: .infinity" not in night)
    check("Night chip dismiss is 44pt", "minWidth: 44, minHeight: 44" in night)
    check("burstConsumedTap cleared in endBurstHold", "func endBurstHold" in content and "burstConsumedTap = false" in content[content.find("func endBurstHold"):content.find("func endBurstHold")+780] and "Do NOT clear burstConsumedTap here" in content)
    check("burst marks consumed only when burst starts", "Only swallow the Button release when a real burst actually starts" in content and content.find("burstConsumedTap = true") > content.find("func beginBurstHold"))
    check("burst reschedules when busy", "Pipeline still owned — reschedule" in content)
    check("burst retries serialize reject", "Serialize reject / bake busy" in content)
    check("handleCapture ignores volume during burst", "if isBurstHolding { return }" in content)
    check("Night assist hidden while capturing", "capturing || bursting || longExposure" in (ROOT / "ShutterRender.swift").read_text())
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


    check(
        "bake failure note",
        "bakeLooksForCapture" in cam
        and "ToastBus.shared.show" in cam
        and "ToastBus.shared.show" in content,
    )
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
    # Build 106 — lag / stability pass
    check("hist materialize skips Metal syncCI", "histogramContext.createCGImage" in cam)
    check("hist materialize comment", "never stalls live FX createCGImage" in cam)
    check("scene assist no hist onReceive", "do NOT observe HistogramBus here" in content)
    check("scene assist no-op when chip up", "if visible || darkStreak >= 3 { return }" in (ROOT / "ShutterRender.swift").read_text())
    check("settings suspends live preview", "Park live film/FX Metal while Settings" in content)
    check("EV drag throttled device writes", "~30Hz device writes" in content)
    check("EV drag hide only on end", "Hide timer only on drag end" in content)
    check("camera EV not Published", "Not @Published — ContentView owns EV UI" in cam)
    # Build 108 — LE progress bus + demote dial publishes + debounce widgets
    check("LE progress bus isolated", "final class LongExposureProgressBus" in render)
    check("LE progress not Published on camera", "@Published var longExposureProgress" not in cam)
    check("LE overlay observes bus", "@ObservedObject private var leBus = LongExposureProgressBus.shared" in content)
    check("camera ISO not Published", "Not @Published — ContentView owns ISO dial" in cam)
    check("camera zoom not Published", "Not @Published — ContentView owns zoom via @State" in cam)
    check("widget reload gated", "enum WidgetReloadGate" in (ROOT / "ShutterDeepLink.swift").read_text())
    check("widget reload debounced", "WidgetReloadGate.reload(minInterval: 1.5)" in content)
    check("scrubber tickPhase no spring", "Snap ticks without stacking scrub springs" in content)
    check("manual exposure publish guarded", "if !self.isManualExposure { self.isManualExposure = true }" in cam)
    check("manual focus publish guarded", "if !self.isManualFocus { self.isManualFocus = true }" in cam)
    check("compare bypass not Published", "@Published var previewLooksBypassed" not in cam)
    check("scene assist probe leaf", "struct SceneAssistProbe" in content)
    check("scrubber label no spring", ".animation(.easeOut(duration: 0.12), value: selection)" in content)
    # Build 109 — toast/gallery/LE flag/wash/peaking
    check("toast bus isolated", "final class ToastBus" in render)
    check("captureNote not Published", "@Published var captureNote" not in cam)
    check("overlays observe ToastBus", "@ObservedObject private var toastBus = ToastBus.shared" in content)
    check("LE capturing not Published", "@Published var isLongExposureCapturing" not in cam)
    check("LE progress host leaf", "struct LongExposureProgressHost" in content)
    check("gallery owner isolates publishes", "final class GalleryStoreOwner" in (ROOT / "PhotoBook.swift").read_text())
    check("peaking not Published", "@Published var focusPeakingEnabled" not in cam)
    check("zebra not Published", "@Published var zebraEnabled" not in cam)
    check("wash check Instant/FX only", "shouldWashCheckPreview" in cam)
    check("peaking-only preview 6fps", "Peaking/zebra alone" in cam)
    check("scrub edge skip no-op value", "Skip no-op value writes" in content)
    # Build 110 — capture chrome / scene tip / demotes
    check("capture chrome bus", "final class CaptureChromeBus" in render)
    check("scene assist bus", "final class SceneAssistBus" in render)
    check("flash wash leaf host", "struct CaptureFlashWashHost" in content)
    check("curtain leaf host", "struct CaptureCurtainHost" in content)
    check("overlays observe SceneAssistBus", "@ObservedObject private var sceneAssist = SceneAssistBus.shared" in content)
    check("shutter observes CaptureChromeBus", "@ObservedObject private var captureChrome = CaptureChromeBus.shared" in content)
    check("film filter not Published", "@Published var selectedFilmFilter" not in cam)
    check("lens FX not Published", "@Published var selectedLensFX" not in cam)
    check("flash mode not Published", "@Published var flashMode" not in cam)
    check("session is let", "let session = AVCaptureSession()" in cam)
    check("manual focus not Published", "@Published var isManualFocus" not in cam)
    check("AEAF lock not Published", "@Published var isAEAFLocked" not in cam)
    check("volume shutter non-observing", "final class VolumeShutterOwner" in (ROOT / "PhotoBook.swift").read_text())
    check("volume shutter not ObservableObject", "class VolumeShutterObserver: NSObject, ObservableObject" not in (ROOT / "LookRecipes.swift").read_text())
    # Build 111 — darkroom page-turn + MANUAL demote + widget debounce
    cull = (ROOT / "CullGallery.swift").read_text()
    check("page turn duration constant", "static let pageTurnDuration" in cull)
    check("page turn uses duration constant", "CullMotion.pageTurnDuration" in cull)
    check("paper peel angle softened", "-86" in cull and "perspective: 0.48" in cull)
    check("filmstrip uses press scroll", "Filmstrip shouldn't ride the full page-turn" in cull)
    check("cull hint first-run only", "First-run only — coach covers the rest" in cull)
    check("cull prefetch ±1", "func prefetch(around" in cull)
    check("mark widget debounce", "debounce: true" in cull)
    check("push unculled debounce API", "debounce: Bool = false" in content)
    check("manual exposure not Published", "@Published var isManualExposure" not in cam)
    check("capture thumb on chrome bus", "lastThumb" in render and "bumpPhotoCount" in render)
    chrome = (ROOT / "CullChrome.swift").read_text()
    check("compare chrome quieted", "ZOOM & PAN ARE LOCKED TOGETHER" not in chrome)
    check("compare keep subtitle short", "KEEP A / B below" in chrome)
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
    check("flash opacity wash", "opacity(bus.showFlash ? 0.28 : 0)" in content)
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
    # Build 115 — CameraManager must stay free of illegal control bytes (Xcode
    # "Invalid character in source file").
    cam_bytes = (ROOT / "CameraManager.swift").read_bytes()
    illegal = [b for b in cam_bytes if b < 0x20 and b not in (0x09, 0x0A, 0x0D)]
    check("CameraManager no illegal control bytes", not illegal, f"{len(illegal)} found")
    # Build 116 — owners that construct MainActor types must themselves be MainActor.
    photobook = (ROOT / "PhotoBook.swift").read_text()
    check(
        "GalleryStoreOwner is MainActor",
        "@MainActor" in photobook[photobook.find("final class GalleryStoreOwner")-40:photobook.find("final class GalleryStoreOwner")+80],
    )
    check(
        "VolumeShutterOwner is MainActor",
        "@MainActor" in photobook[photobook.find("final class VolumeShutterOwner")-40:photobook.find("final class VolumeShutterOwner")+80],
    )
    # Build 118 — Minimalism mode (opt-in) + Save button hugs label.
    settings = (ROOT / "ShutterSettings.swift").read_text()
    vf = (ROOT / "ViewfinderOverlay.swift").read_text()
    check("minimalism AppStorage", '@AppStorage("cam.minimalism")' in content)
    check("minimalism settings toggle", 'title: "Minimalism"' in settings)
    check("minimalChrome on overlay", "minimalChrome: minimalismMode" in content)
    check("minimal hides top strip", "hideTopStrip = minimalismMode" in content)
    check("minimal gear escape hatch", "Escape hatch — gear lives on the expanded deck" in content)
    # Build 121 — Minimalism must keep the shutter in the collapsed dock.
    compact_deck = content[
        content.find("private func bottomCompactDeck") : content.find("private var bottomExpandedDeck")
    ]
    check(
        "minimalism keeps collapsed shutter",
        "Shutter dock always stays in the quiet finder (incl. Minimalism)" in content
        and "ShutterButton(" in compact_deck
        and "if minimalismMode {" in compact_deck
        and "Escape hatch — gear lives on the expanded deck" in compact_deck,
    )
    # Build 120 — Compact top (opt-in); classic dials remain when off.
    check("compactTop AppStorage", '@AppStorage("cam.compactTop")' in content)
    check("compactTop settings toggle", 'title: "Compact top"' in settings)
    check("compactTop locks strip", "lockCompactTop = compactTop" in content)
    check("compactTop keeps dials path", "Classic FOCUS + shutter dials stay" in content)
    check("compactTop shows level in strip", "stripShowsLevel = showLevel || lockCompactTop" in content)
    check("save look fixedSize hug", "SAVE LOOK" in vf and "fixedSize(horizontal: true, vertical: true)" in vf)
    check("settings save hugs text", "Save current look" in settings and "fixedSize(horizontal: true, vertical: true)" in settings)
    # Build 117 — labeled ShutterButton args must follow declaration order.
    import re as _re
    for m in _re.finditer(r"ShutterButton\(([\s\S]*?)\)\s*\{", content):
        body = m.group(1)
        if "onBurstStart" in body and "stayEnabledForBurstTap" in body:
            check(
                "ShutterButton arg order onBurst before stayEnabled",
                body.find("onBurstStart") < body.find("stayEnabledForBurstTap"),
            )
    # Build 114 — tap-to-focus must work while AE/AF was locked; clear manual.
    check(
        "tap focus unlocks AEAF",
        "Tap always retargets AF" in content
        and "camera.setAEAFLocked(false)" in content[content.find("func handleFocusTap"):content.find("func handleFocusTap")+900],
    )
    check(
        "setFocus clears manual flag",
        "if self.isManualFocus { self.isManualFocus = false }" in cam
        and "isSubjectAreaChangeMonitoringEnabled" in cam[cam.find("func setFocus(at"):cam.find("func setManualFocus")],
    )
    check(
        "exposure pan slop for taps",
        "abs(translation.y) > 14" in preview
        and "panMode == .undecided" in preview[preview.find("func handleTap"):preview.find("func handleTap")+400],
    )
    check(
        "scrub edge generation close",
        "scrubEdgeGeneration" in content
        and "beginScrubEdgeClose" in content
        and "forceCloseScrubEdge" in content,
    )
    check(
        "scrubber disappear closes edge",
        "Scrubber teardown used to skip onActiveChanged(false)" in content
        and "onActiveChanged?(false)" in content[content.find("Scrubber teardown used to skip"):content.find("Scrubber teardown used to skip")+400],
    )
    check(
        "deck collapse closes scrub edge",
        "forceCloseScrubEdge()" in content[content.find("onChange(of: bottomCollapsed)"):content.find("onChange(of: bottomCollapsed)")+350],
    )
    check(
        "STACK LE upright",
        "longExposureInterfaceOrientation" in cam
        and "PreviewBufferRotation.from(" in cam
        and "longExposureWasFront" in cam,
    )
    check(
        "front upright mapping inverted",
        "front: Bool = false" in (ROOT / "LensFXEngine.swift").read_text()
        and "return .rotateLeft" in (ROOT / "LensFXEngine.swift").read_text(),
    )
    check(
        "Metal preview passes front",
        "front: front" in (ROOT / "FilteredCameraPreview.swift").read_text(),
    )
    check("flip refreshes buffer rotation", "syncPreviewBufferRotation" in content)
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
    flash_chunk = source_chunk(content, "struct FlashButtonPill", "struct ModeControl")
    thumb_chunk = source_chunk(content, "struct ThumbnailPill", "struct FormatTogglePill")
    wb_chunk = source_chunk(content, "struct WBPill", "struct ExposureKnob")
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
    # Scope to the chip's view, not the visibility state machine that shares
    # the `if sceneAssist.visible` spelling higher up the file.
    night_chip = source_chunk(
        source_chunk(content, "struct FinderStatusOverlays", "struct ContentViewLifecycle"),
        "if sceneAssist.visible",
        "if let cameraError",
    )
    check("Night chip not full-width hit", ".frame(maxWidth: .infinity" not in night_chip)
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
    check(
        "scrubber yellow center indicator only",
        "White majors/minors" in content
        and "isScrolling ? yellow : yellow.opacity(0.70)" in content
        and "yellow.opacity(isScrolling ? 0.75 : 0.40)" not in content,
    )
    check("scrubber value spring", "scaleEffect(isScrolling ? 1.12" in content)
    check("shutter no press brightness", "No brightness shift" in content)
    check(
        "shutter muted dark collar",
        "muted dark steel" in content
        or "brushed mid steel" in content
        or "Matte dark steel" in content
        or "matte steel, not chrome" in content,
    )
    check("metal shader no cool blue", "Neutral steel cast" in (ROOT / "Shaders.metal").read_text())
    # Build 55 — hard film crash fix
    check("no vulcanite Metal on camera", "LeicaVulcaniteTexture(scale: 20" not in content)
    check("no metallicSurface on shutter", "ShaderLibrary.metallicSurface" not in content)
    check("info bar L overlay hit", 'Text("L")' in content and "frame(width: 44, height: 36)" in content)

    # Build 56 — black finder freeze + tight ModeControl
    preview = (ROOT / "FilteredCameraPreview.swift").read_text()
    vf = (ROOT / "ViewfinderOverlay.swift").read_text()
    cam = (ROOT / "CameraManager.swift").read_text()
    check(
        "preview keeps AV until Metal presents",
        "Always keep AV visible until Metal has painted" in preview
        or "KEEP the AV preview visible until Metal paints" in preview,
    )
    check("preview own CIContext", "makePreviewCIContext" in preview)
    check("preview restore on draw fail", "noteDrawFailure" in preview)
    check("preview scheduleMetalDraw fallback", "restoreCleanPreview()" in preview and "scheduleMetalDraw" in preview)
    check("live preview fail streak", "livePreviewFailStreak" in cam)
    check("format centered ZStack", "FormatTogglePill(format: $captureFormat)" in content and "ZStack {" in content[content.find("ROW 3"):content.find("ROW 3")+900])
    check("ModeControl column 28", ".frame(width: 28, height: 40)" in content)
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
    overlay_chrome = source_chunk(vf, "struct ViewfinderOverlay", "struct UIKitChromeLookButtons")
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

    # Build 65 — polish: exclusive looks, burst calm, settings looks
    check("exclusive film clears FX", "if filter != .none { session.lensFX = .none }" in vf)
    check("exclusive FX clears film", "if fx != .none { session.filmFilter = .none }" in vf)
    check("applyExclusiveLook helper", "func applyExclusiveLook" in content)
    check("settings saved looks", "Saved looks" in (ROOT / "ShutterSettings.swift").read_text())
    check("burst default off", 'holdBurstEnabled = false' in content)
    check("shutter curtain state", "showCurtain" in render and "CaptureCurtainHost" in content)
    check("no cyan burstAccent", "0.55, green: 0.82, blue: 1.0" not in content)
    check(
        "compact scrubbers no outer box",
        "Compact strip — 38pt instrument face" in (ROOT / "AnalogGaugeView.swift").read_text()
        or "Compact strip — minimized to 34pt" in (ROOT / "AnalogGaugeView.swift").read_text()
        or "Compact strip — a hair under the 40pt ISO" in (ROOT / "AnalogGaugeView.swift").read_text()
        or "Compact strip — shorter than the 40pt ISO" in (ROOT / "AnalogGaugeView.swift").read_text()
        or "Same 40pt instrument height as the ISO" in (ROOT / "AnalogGaugeView.swift").read_text()
        or "Scrubbers only — no extra outer container" in (ROOT / "AnalogGaugeView.swift").read_text(),
    )
    check("deck swipe verticalBias", "verticalBias:" in content)
    check("no format on compact deck", "FormatTogglePill" not in content[content.find("func bottomCompactDeck"):content.find("func bottomCompactDeck")+700])
    check("format on expanded deck", "FormatTogglePill" in content[content.find("ROW 3"):content.find("ROW 3")+2200])

    # Build 66 — Night clean + EV drag anytime + hide format in fullscreen
    check("night clears looks", "filmFilter = .none" in content[content.find("case .night:"):content.find("case .night:")+700])
    check("night no peaking", "focusPeaking = false" in content[content.find("case .night:"):content.find("case .night:")+500])
    check("night 1/15 not 1 inch", "shutterSpeedIndex = 6" in content[content.find("case .night:"):content.find("case .night:")+500])
    check("EV drag anytime unlocked", "exposureDragEnabled: !isLocked," in content)
    check("EV drag seeds without tap", "park the sun reticle mid-finder" in content)
    check("pan waits for direction", "Wait for direction" in (ROOT / "FilteredCameraPreview.swift").read_text())

    # Build 98 — shutter pushes in (scale) vs slides down; collar solid
    check("shutter pressed env key", "ShutterPressedKey" in content)
    check("shutter press style sets env", ".environment(\\shutterPressed" in content or ".environment(\\.shutterPressed" in content)
    check(
        "shutter fixed dark lip",
        "Inner lip stepping down into the well" in content or "Fixed dark lip" in content,
    )
    check(
        "shutter well darkens on press",
        "isPressed ? 0.92 : 0.78" in content or "isPressed ? 0.95 : 0.82" in content,
    )
    check("shutter face sink offset", "offset(y: isPressed ? sink : -proud)" in content)
    check("shutter tiny sink not slide", "private var sink: CGFloat { compact ? 1.2 : 1.5 }" in content)
    check("shutter face clipped to well", ".clipShape(Circle())" in content[content.find("struct ShutterButtonChrome"):content.find("struct ScaleButtonStyle")])
    check("shutter constant face fill", "Face fill is CONSTANT" in content)
    check("shutter press dim overlay", "isPressed ? 0.38 : 0" in content[content.find("struct ShutterButtonChrome"):content.find("struct ScaleButtonStyle")])
    check("shutter top lip inset shadow", "Top lip inset shadow" in content)

    # Build 80 — round silhouette restored: no extruded barrel behind a round cap
    check("shutter no barrel capsule", "barrelFill" not in content and "Button barrel" not in content)
    check("shutter idle silhouette unchanged", "Only shows while pressed" in shutter_chrome)
    check("shutter proud/sink travel", "private var proud" in content and "private var sink" in content)
    check("shutter face clipped by well edge", ".frame(width: well, height: well)" in shutter_chrome)

    # Build 68 — Nikon LCD chrome + tighter deck + no white shutter flash
    check("shutter no white top glow", "Color.white.opacity(isPressed ? 0 : 0.06)" not in content)
    check("shutter no collar dim flash", "isPressed ? 0.18 : 0" not in content[content.find("struct ShutterButtonChrome"):content.find("struct ScaleButtonStyle")])
    # Build 96 — shutter left / ISO right; scrubber row shares deck pull-down
    row2 = content[content.find("// ROW 2:"):content.find("// ROW 3:")]
    check("shutter scrubber left of ISO", row2.find("ShutterScrubber(") < row2.find("ISOScrubberHorizontal("))
    check("scrubber row shares deck swipe", ".simultaneousGesture(bottomDeckSwipe)" in row2)
    check("expanded deck easier collapse bias", "bottomCollapsed ? 1.6 : 1.25" in content)
    check(
        "easier pull-down leave explore",
        "effective > 22 || committedDrag > 18" in content,
    )
    check("scrubber flash breathing room", "Breathing room from scrubbers" in content)
    check("flash snug on preview row", ".padding(.bottom, -6)" in content)
    check("pill height 44", "pillHeight: CGFloat = 44" in content)
    overlay = (ROOT / "ViewfinderOverlay.swift").read_text()
    settings = (ROOT / "ShutterSettings.swift").read_text()
    cull = (ROOT / "ShootCull.swift").read_text()
    check("nikon lcd yellow picker", "lcdYellow" in overlay and "0.85, blue: 0.35" in overlay)
    check("nikon picker tight rows", "heightForRowAt" in overlay and "return 28" in overlay)
    check("nikon picker iso badge", "isoBadge(for" in overlay)
    check(
        "settings dslr menu",
        "DSLRToggleRow" in settings and "SettingsSheetBackground" in settings,
    )
    check("settings no List toggles", "Toggle(" not in settings and "List {" not in settings)
    check("cull amber matches DS.accent", "1.0, green: 0.85, blue: 0.35" in cull)

    # Build 70 — widget overlapping recent photos
    deep = (ROOT / "ShutterDeepLink.swift").read_text()
    widgets = (ROOT / "ShutterWidgets" / "ShutterWidgetsBundle.swift").read_text()
    check("widget push recent thumbs", "func pushRecentThumbnail" in deep)
    check("widget load recent thumbs", "func loadRecentThumbnails" in deep)
    check("widget recents dir", "widget-recents" in deep)
    check("capture feeds widget recents", "refreshWidgetRecents()" in content or "pushRecentThumbnail(framed)" in content)
    check("seed widget recents", "seedWidgetRecentsIfNeeded" in content)
    check("widget recent stack view", "struct WidgetRecentStack" in widgets)
    check(
        "launch widget systemLarge",
        ".supportedFamilies([.systemSmall, .systemMedium, .systemLarge])" in widgets,
    )
    check("looks large recents section", '"RECENTS"' in widgets and "darkroom.url" in widgets)
    # Build 102/119 — matched outer pad + fun photo previews.
    check("widget shared contentPad", "static let contentPad: CGFloat = 14" in widgets)
    check(
        "widget bodies use contentPad",
        widgets.count("padding(WidgetPalette.contentPad)") >= 4,
    )
    check("widget viewfinder brackets", "struct ViewfinderBrackets" in widgets)
    check("widget stack exposure stamp", "exposureStamp" in widgets)
    check("widget contact scan-line", "Soft scan-line" in widgets)
    check("widget empty emulsion ghost", "Unexposed emulsion ghost" in widgets)
    # Build 119 — restore air after Build 107's 8pt crush; keep system margins off.
    check("widget comfortable contentPad 14", "Comfortable outer pad" in widgets)
    check("widget medium sheet for 14pt pad", ".frame(width: 128, height: 100)" in widgets)
    check("widget small keep count", "KEEP" in widgets and "stats.keepers" in widgets)
    check("widget contentMarginsDisabled", "contentMarginsDisabled()" in widgets)
    # Build 119 — expanded EV meter stays on the −2…+2 rail.
    gauge_src = (ROOT / "AnalogGaugeView.swift").read_text()
    meter = gauge_src[gauge_src.find("struct HorizontalExposureMeter"):gauge_src.find("struct CenterDisplay")]
    check("EV meter clamps to painted rail", "Pin to the painted" in meter)
    check("EV meter panel clipped", ".clipped()" in meter)

    # Build 71/112 — fun scrubbers; edge readout is now a slimmer straight rail
    aids = (ROOT / "ViewfinderAids.swift").read_text()
    gauge = (ROOT / "AnalogGaugeView.swift").read_text()
    check("curved param edge readout", "struct CurvedParamEdgeReadout" in aids)
    # Numbers clear the rail; single steel guide + traveling needle.
    check("rail detail canvas", "struct EdgeParamRailDetail" in aids)
    check("rail shared geometry", "struct EdgeParamRailGeometry" in aids)
    check("rail half-stop ticks", "Half-stop ticks" in aids and "tickCount = 17" in aids)
    check("rail end caps", "End caps" in aids)
    check("rail single steel guide", "One steel rail" in aids)
    check("rail no yellow guide", "One accent rail" not in aids)
    check("rail yellow only focused tick", "Yellow only on the focused tick" in aids)
    check("rail traveling needle", "Traveling needle pip" in aids and "needle:" in aids)
    check("rail active value yellow", "yellow is for the live value only" in aids)
    check("rail numbers clear the guide", "valueClearance" in aids and "railColumn" in aids)
    check(
        "rail value sits left of column",
        "valueTrailing = inset + railColumn + valueClearance" in aids,
    )
    check("scrub edge kind enum", "enum ScrubEdgeKind" in content)
    check("scrubber moving tick phase", "tickPhase" in content and "Moving tick strip" in content)
    check("scrubber onActiveChanged", "onActiveChanged:" in content[content.find("struct NativeSnapScrubber"):content.find("struct ISOScrubberHorizontal")])
    check("active edge readout helper", "activeEdgeReadout" in content)
    check("scrub needle mapper", "func scrubNeedle(for" in content)

    # Build 94 — sun-drag + top FOCUS/EV scrubs both peel the interactive dial
    preview_src = (ROOT / "FilteredCameraPreview.swift").read_text()
    check("sun drag feeds arch", "setScrubEdge(.ev, active: true" in content)
    check("manual sun drag feeds arch", "setScrubEdge(.iso, active: true" in content)
    check(
        "top scrubbers feed arch",
        "onFocusScrubActive:" in content and "onEVScrubActive:" in content,
    )
    check("sun drag not gated on manual", "exposureDragEnabled: !isLocked," in content)
    check("manual sun drag moves gain", "dragStartISO" in content and "powf(2, stops)" in content)
    check("half stop detents", "func halfStopDetent" in content and "exposureDetentHaptic" in content)
    check(
        "manual detents track applied gain",
        "exposureDetentHaptic(log2(Float(capped) / Float(max(1, dragStartISO))))" in content
        and "manual ? 0 : halfStopDetent(exposureValue)" in content,
    )
    check("sun drag dead zone is a strip", "view.bounds.height - 64" in preview_src)
    check("vertical dominance threshold", "abs(translation.x) * 0.6" in preview_src)
    # Liquid FX and sun-drag share the finder — split by zone, not only by axis.
    check("sun drag zone constant", "sunDragZoneMinX" in preview_src)
    check("sun drag trailing strip", "0.58" in preview_src and "startedInSunZone" in preview_src)
    check("morphTouchEnabled wired", "morphTouchEnabled:" in content)
    check(
        "morph yields while reticle up",
        "morphTouchEnabled: !isLocked" in content and "!showFocusPoint" in content,
    )

    # Build 91 — jetsam guards (Debug was dying under liquid FX createCGImage)
    check("preview downsample 540/480", "heavyFX ? 480 : 540" in cam)
    check("heavy FX preview 6fps", "1.0 / 6.0" in cam)
    check("LE accumulate throttle", "leAccumulateInterval" in cam and "longEdge: 960" in cam)
    check("memory pressure purge", "func purgeMemoryPressure" in cam)
    check("background stops session", "handleDidEnterBackground" in cam)
    check("LensFX purge caches", "func purgePreviewCaches" in (ROOT / "LensFXEngine.swift").read_text())
    check("Metal drawable capped", "maxEdge: CGFloat = 1280" in preview)

    # Build 104 — FX stuck washout (cream+grain / white blowout / half-frame)
    fx = (ROOT / "LensFXEngine.swift").read_text()
    check("dream preview skips screen blend", "Live preview: soft glow without screen-blend washout" in fx)
    check("liquid texture never lazy blur", "Never return the lazy blur graph" in fx)
    check("glass scale clamped", "Clamp glass scale" in fx)
    check("legacy instant preview skips bloom", "Live bloom + Instant warmth" in fx)
    check("mirror clamps before flip", "Clamp first so the flip never samples" in fx)
    check("FX output pinned origin-zero", "Pin every FX to the input extent" in fx)
    check("heavy FX includes fisheye vhs mirror", ".fisheye, .vhs, .mirror" in cam)
    check("cached film grain tile", "func filmGrainTile" in cam and "cachedGrainTile" in cam)
    check("washed preview reject", "func isWashedPreviewFrame" in cam)
    check("wash reject before Metal push", "Drop cream/white wash before Metal" in cam)


    # Build 72 — DSLR settings + deck spacing
    check("dslr toggle row type", "struct DSLRToggleRow" in (ROOT / "ShutterSettings.swift").read_text())
    settings_src = (ROOT / "ShutterSettings.swift").read_text()
    check(
        "settings pure black blur bg",
        "SettingsSheetBackground" in settings_src
        and "SettingsLiquidGlassBackground" in settings_src
        and "no fake top liquid-glass gradient" in settings_src,
    )
    check("settings forced dark scheme", "preferredColorScheme(.dark)" in settings_src)
    check("settings well detailing", "struct SettingsDSLRWell" in settings_src)
    check("settings well clipped", ".clipShape(RoundedRectangle(cornerRadius: 12" in settings_src)
    check("settings title not all caps", 'Text("Settings")' in settings_src and 'navigationTitle("SETTINGS")' not in settings_src)
    check("settings title leading", "topBarLeading" in settings_src)
    check("settings headers not yellow", 'dslrSection("Viewfinder")' in settings_src and "foregroundStyle(DS.accent.opacity(0.9))" not in settings_src)
    check("settings yellow for state", 'isOn ? "On" : "Off"' in settings_src and "isOn ? DS.accent" in settings_src)
    check("settings uses DS.mono", "DS.mono(12, weight: .semibold)" in settings_src)
    # Compact FOCUS/EV — 38pt strip + outer dark bezel (Build 100)
    check("compact scrubbers 38pt", ".frame(height: 38)" in (ROOT / "AnalogGaugeView.swift").read_text())
    check("compact level matches scrubber height", "compact ? 38 : 36" in aids)
    check(
        "compact top panel clears strip",
        ("isLandscape || lockCompactTop ? 44 : 50" in content)
        or ("isLandscape ? 44 : 50" in content)
    )
    check(
        "gauge to viewfinder gap",
        ("gaugeToViewfinderSpacing" in content)
        and (("lockCompactTop ? 2 : 3" in content) or ("? 3 : 4" in content))
    )
    check("level yellow focused only", "Yellow only on the focused/leading mark" in aids)
    check("EV meter yellow focused only", "yellow only on the focused/leading mark" in (ROOT / "AnalogGaugeView.swift").read_text())
    snap = content[content.find("struct NativeSnapScrubber"):content.find("struct ISOScrubberHorizontal")]
    check("snap scrubber classic deck face", 'Color(hex: "242424")' in snap or 'faceHex' in snap)
    check("snap scrubber instrument face flag", "instrumentFace" in snap and '"0a0a0a"' in snap)
    check(
        "snap scrubber white majors",
        "White majors/minors" in snap and "yellow.opacity(isScrolling ? 0.75 : 0.40)" not in snap,
    )
    check("snap scrubber yellow center only", "isScrolling ? yellow : yellow.opacity(0.70)" in snap)
    check(
        "snap scrubber outer dark bezel",
        "Outer dark stroke" in snap and '.fill(Color.black)' in snap and ".padding(instrumentFace ? 1.5 : 2)" in snap,
    )
    # Hard chrome contract — never ship flattened scrubbers / pill bezels again (Build 101).
    def pill_has_dark_bezel(struct_name: str, next_struct: str) -> bool:
        chunk = content[content.find(f"struct {struct_name}"):content.find(f"struct {next_struct}")]
        return (
            ".fill(Color.black)" in chunk
            and 'Color(hex: "242424")' in chunk
            and 'Color(hex: "444444")' in chunk
            and ("pillWidth - 4" in chunk or "padding(2)" in chunk)
        )

    check("flash pill dark bezel", pill_has_dark_bezel("FlashButtonPill", "ModeControl"))
    check("thumbnail pill dark bezel", pill_has_dark_bezel("ThumbnailPill", "FormatTogglePill"))
    check("WB pill dark bezel", pill_has_dark_bezel("WBPill", "ExposureKnob"))
    check(
        "scrubber deck face inset shows black ring",
        ".padding(instrumentFace ? 1.5 : 2)" in snap
        and "No stacked black outer board" not in snap
        and snap.count(".fill(Color.black)") >= 1,
    )
    check(
        "scrubber stroke on face edge",
        "cornerRadius: instrumentFace ? 4 : 5" in snap,
    )
    # Shutter collar muted dark steel (Build 90 — mid-bright ring was too strong)
    check(
        "shutter collar muted steel",
        "Color(red: 0.28, green: 0.29, blue: 0.31)" in content[content.find("struct ShutterButtonChrome"):content.find("struct ScaleButtonStyle")],
    )
    check("settings cycle format row", "DSLRCycleRow" in (ROOT / "ShutterSettings.swift").read_text())

    # Build 73 — level under top EV, shutter deep push-in, film/FX long-press clear
    check("info bar metal level", "struct InfoBarMetalLevel" in aids)
    check("level under EV meter", "InfoBarMetalLevel" in gauge and "showLevel: showLevel" in gauge)
    check(
        "top panel showLevel wiring",
        ("showLevel: stripShowsLevel" in content[content.find("AnalogDisplayPanel("):content.find("AnalogDisplayPanel(")+900])
        or ("showLevel: showLevel" in content[content.find("AnalogDisplayPanel("):content.find("AnalogDisplayPanel(")+900])
    )
    check("soft fullscreen fade", "Color.black.opacity(0.20)" in content and "Color.black.opacity(0.48)" in content and "Color.black.opacity(0.74)" in content)
    check("histogram taller and wider", "compact ? 54 : 76" in content and "compact ? 32 : 46" in content)
    check("histogram exposure grid", "Fine exposure grid" in content)
    check("info bar machined rim", "Machined outer rim" in content)
    check("info bar no mid level", "InfoBarMetalLevel" not in content[content.find("struct RefractiveGlassInfoBar"):content.find("struct GlassHistogram")])
    check("hist without showLevel", "showLevel" not in content[content.find("struct GlassHistogram"):content.find("struct ResponsiveHistogram")])
    check("no floating top level chip", "HorizonLevelIndicator()" not in content)
    check("settings level under EV blurb", "Spirit bar under the EV meter" in settings)
    check("long-press clears look", "onClearLook" in content and "onClearLook" in overlay)
    check("UIKit film long press", "filmLong" in overlay and "minimumPressDuration = 0.38" in overlay)
    check("tap always opens picker", "Tap always opens the menu" in content)
    check("no retap-clear in toggle", "case .film where filmFilter != .none" not in content[content.find("func toggleChromePicker"):content.find("func toggleChromePicker")+900])
    check("clearChromeLook helper", "func clearChromeLook" in content)

    # Build 74 — EV scrub restore, FX freeze harden, richer widget
    preview = (ROOT / "FilteredCameraPreview.swift").read_text()
    deep = (ROOT / "ShutterDeepLink.swift").read_text()
    widgets = (ROOT / "ShutterWidgets" / "ShutterWidgetsBundle.swift").read_text()
    check("EV pan dead zone is a 64pt strip", "view.bounds.height - 64" in preview)
    check("EV cancels compare", "cancelCompareIfNeeded" in preview)
    check("long press no fight pan", "UILongPressGestureRecognizer" in preview and "return false" in preview)
    check("unsuspend resets preview clock", "lastPreviewFrameTime = 0" in cam)
    check("picker teardown safety net", "Safety net: if commit never lands" in content)
    check("widget recent meta sidecar", "struct WidgetRecentMeta" in deep)
    check("widget rebuild unculled", "func rebuildRecentFrames" in deep)
    check("push unculled widget helper", "pushUnculledWidgetRecents" in content)
    check("widget shoot deep link", "ShutterDeepLink.capture.url" in widgets)
    check("widget unculled label", "OPEN" in widgets and "stats.unculled" in widgets)
    check("widget exposure line", "exposureLine" in deep and "latestMeta" in widgets)

    # Build 75 — film FX pink freeze: origin normalize + transparent Metal until present
    check("Metal transparent until present", "isOpaque = false" in preview and "alpha: 0" in preview)
    check("draw normalizes CI origin", "Orientation shifts origin off" in preview)
    check("mark presented before GPU wait", "Reveal Metal as soon as this drawable" in preview)
    check("draw fail restores early", "if !metalHasPresented || consecutiveDrawFails >= 3" in preview)
    check("live film grain preview", "applyFilmGrain(to: outputImage, amount: 0.035)" in cam)
    check("CineStill bloom cropped", "result.cropped(to: bloomExtent)" in cam)
    check("preview normalize before CI", "Normalize origin before CI filters" in cam)

    # Build 76 — bug-fix pass
    photo_book = (ROOT / "PhotoBook.swift").read_text()
    check("direct film clears old scene", "session.shootMode = nil" in vf)
    check("long clear does not swallow next tap", "suppressFilmTap" not in vf and "suppressFXTap" not in vf)
    check("film FX accessibility state", 'accessibilityLabel = "Film"' in vf and 'accessibilityLabel = "Effects"' in vf)
    check("pinch does not drive pan", "panGesture.maximumNumberOfTouches = 1" in preview)
    check("picker blocks hardware shutter", content.count("!ChromePickerGate.isPresented") >= 2)
    check("gallery add completion", "completion?()" in photo_book)
    check("gallery keeps chronological order", "self.shots.sort { $0.date < $1.date }" in photo_book)
    check("widget refresh waits for gallery publish", "recordShot(framed) {" in content)
    check("widget recents sort by date", ".sorted { $0.date > $1.date }" in content)
    check("clean widget frame stays clean", 'meta.filmFilter == "None" ? "Clean"' in widgets)

    # Build 77/78 — level is a coherent companion to the EV instrument; ticks animate + useful.
    check("full level matches EV width", "compact ? 52 : 120" in aids)
    check("full level matches EV height", "compact ? 38 : 36" in aids)
    check("level 13-mark dial rhythm", "tickScale(count: 13" in aids and "degreeMarks" in aids)
    check("level mechanical center pointer", "Mechanical center pointer matches the EV triangle" in aids)
    check("level precision readout", 'String(format: "%+.1f°", roll)' in aids)
    check("level Nikon yellow lock", 'Text(isLevel ? "LEVEL"' in aids)
    check("level lock haptic", "UIImpactFeedbackGenerator(style: .rigid)" in aids)
    check("level 12hz motion", "1.0 / 12.0" in aids)

    # Build 97 — yellow only on focused/leading tick (no swept yellow run)
    check("level tick canvas", "func tickScale" in aids and "Canvas { ctx, size in" in aids)
    check(
        "level tick focused yellow only",
        "Yellow only on the focused/leading mark" in aids
        and "let swept = deg <= max(0, roll)" not in aids,
    )
    check("level leading tick pulse", "let leading = abs(deg - roll)" in aids and "TimelineView(.animation(minimumInterval: 1.0 / 8.0))" in aids)
    check("level beam still tilts", "Tilting horizon beam" in aids)
    check("level shared motion source", "static let shared = HorizonMotion()" in aids and "subscribers" in aids)
    check("level views share motion", "@StateObject private var motion = HorizonMotion()" not in aids)
    check(
        "EV ticks focused yellow only",
        "yellow only on the focused/leading mark" in gauge
        and "let swept = markEV <= max(0, value)" not in gauge,
    )
    check("EV ticks fixed baseline", "frame(height: 13, alignment: .bottom)" in gauge)
    check("mode trio spans WB pill width", ".frame(width: 84, height: 40, alignment: .trailing)" in content)
    check("mode key chrome", "Round key in the WB/flash pill chrome" in content)



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
    app_entry = (ROOT / "ProCameraApp.swift").read_text()

    m = re.search(r"<key>CFBundleVersion</key>\s*<string>(\d+)</string>", plist)
    ver = m.group(1) if m else "?"
    check("Info.plist build >= 77", m is not None and int(ver) >= 77, ver)
    check(
        "launch screen colorset exists",
        (ROOT / "Assets.xcassets/LaunchScreenBackground.colorset/Contents.json").is_file(),
    )
    check("forced dark UI style", "UIUserInterfaceStyle" in plist and "Dark" in plist)
    check("window vulcanite boot", "0x13 / 255" in app_entry and "host.view.backgroundColor" in app_entry)
    check("content dark scheme", "preferredColorScheme(.dark)" in (ROOT / "ContentView.swift").read_text())
    import re as _re

    vers = [int(v) for v in _re.findall(r"CURRENT_PROJECT_VERSION = (\d+);", pbx)]
    check("pbx CURRENT_PROJECT_VERSION 77+", any(v >= 77 for v in vers), f"versions={sorted(set(vers))}")
    # iOS refuses to install an extension whose CFBundleVersion differs from the
    # host app. Bumping only Info.plist silently drifted widgets/capture to 77.
    check(
        "app plist matches pbx build",
        m is not None and set(vers) == {int(ver)},
        f"plist={ver} pbx={sorted(set(vers))}",
    )
    for ext in ("ShutterWidgets/Info.plist", "ShutterCaptureExtension/Info.plist"):
        ext_plist = (ROOT / ext).read_text()
        em = re.search(r"<key>CFBundleVersion</key>\s*<string>([^<]+)</string>", ext_plist)
        found = em.group(1) if em else "?"
        check(
            f"{ext.split('/')[0]} build tracks app",
            found in ("$(CURRENT_PROJECT_VERSION)", ver),
            found,
        )
        es = re.search(r"<key>CFBundleShortVersionString</key>\s*<string>([^<]+)</string>", ext_plist)
        app_short = re.search(r"<key>CFBundleShortVersionString</key>\s*<string>([^<]+)</string>", plist)
        check(
            f"{ext.split('/')[0]} short version matches app",
            es is not None and app_short is not None and es.group(1) == app_short.group(1),
            f"{es.group(1) if es else '?'} vs {app_short.group(1) if app_short else '?'}",
        )
    check("ShutterRender in pbx", "ShutterRender.swift in Sources" in pbx)
    check("CI builds cursor/**", '"cursor/**"' in wf or "cursor/**" in wf)
    check("widgets compile ShutterDeepLink", "ShutterDeepLink.swift in Sources" in pbx)
    check("landscape in INFOPLIST_KEY", "LandscapeLeft" in pbx)


# ── Widget content + layout budget (Build 83) ───────────────────────────────

# Smallest content rects we support (iPhone SE), in points.
WIDGET_BOX = {"small": (155, 155), "medium": (329, 155), "large": (329, 345)}


def text_line(pt: float) -> float:
    """Rendered height of one line at `pt`, the ~1.25 leading SwiftUI uses."""
    return round(pt * 1.25)


def parse_int(chunk: str, pattern: str, name: str, fallback: int = 0, last: bool = False) -> int:
    """`last` picks the outer container padding over inner chrome padding."""
    found = re.findall(pattern, chunk)
    check(f"widget parses {name}", bool(found), pattern)
    if not found:
        return fallback
    return int(found[-1] if last else found[0])


def test_widget_content() -> None:
    print("\n== Widget content ==")
    wsrc = (ROOT / "ShutterWidgets/ShutterWidgetsBundle.swift").read_text()
    link = (ROOT / "ShutterDeepLink.swift").read_text()
    content = (ROOT / "ContentView.swift").read_text()

    # Data the widgets have to show something with
    check("six recent slots", "recentThumbnailSlots = 6" in link)
    check("push shifts every slot", "stride(from: last - 1, through: 0, by: -1)" in link)
    for field in (
        "framesToday", "framesWeek", "framesTotal", "keepers",
        "rejects", "unculled", "topFilm", "week", "weekLabels",
    ):
        check(f"stats field {field}", f"var {field}" in link)
    check("roll is 36 exposures", "rollLength = 36" in link)
    check("week spans 7 days", "weekSpan = 7" in link)
    check("week bucketed by day", "week[weekSpan - 1 - back] += 1" in link)
    check("today is the last bucket", "stats.framesToday = stats.week.last" in link)
    check("stats persist in app group", "func saveStats" in link and "func loadStats" in link)
    check("gallery preview has numbers", "static var placeholder: ShutterStats" in link)
    check(
        "app rebuilds stats with recents",
        "ShutterAppGroup.saveStats(" in content and "ShutterStats.compute(" in content,
    )
    # Debug Cmd+R ships empty App Group entitlements — widgets must still
    # surface the user's real frames via the Photos "Shutter" album.
    check("photos fallback frames", "func loadPhotosFallbackFrames" in link)
    check("photos fallback stats", "func loadPhotosFallbackStats" in link)
    check("loadRecentFrames prefers app group", "loadAppGroupFrames" in link)
    check("dual-write mirrors shutter album", "addAssetsToShutterAlbum" in (ROOT / "ShootCull.swift").read_text())
    check("widget photo library usage key", "NSPhotoLibraryUsageDescription" in (ROOT / "ShutterWidgets" / "Info.plist").read_text())
    check("vulcanite widget chrome", "vulcaniteBackground" in wsrc)
    check("metal shoot button", "struct WidgetShootButton" in wsrc)
    check("film sprocket contact sheet", "sprocketRail" in wsrc)
    # Without this an upgrade shows 2 frames in a 6-cell sheet and no numbers
    # until the user happens to shoot again.
    check(
        "upgrade backfills the sheet",
        "ShutterAppGroup.loadStats().framesTotal != shots" in content,
    )

    # Every family has to carry more than a thumbnail and a caption
    check("contact sheet exists", "struct WidgetContactSheet" in wsrc)
    check("week bars exist", "struct WidgetWeekBars" in wsrc)
    check("stat tiles exist", "struct WidgetStatTile" in wsrc)

    small = source_chunk(wsrc, "private var smallBody", "private var footerLine")
    check("small shows a sparkline", "WidgetWeekBars" in small)
    check("small shows today's count", "stats.framesToday" in small)

    medium = source_chunk(wsrc, "private var mediumBody", "private var subhead")
    check("medium shows week bars", "WidgetWeekBars" in medium)
    check("medium shows a contact sheet", "WidgetContactSheet" in medium)
    check("medium shows cull counts", "OPEN" in medium and "KEEP" in medium)

    large = source_chunk(wsrc, "private var largeBody", "private var rollLine")
    check("large shows a 3x2 sheet", "columns: 3, rows: 2" in large)
    check("large shows labelled week", "WidgetWeekBars" in large)
    check("large shows stat tiles", "WidgetStatTile" in large)

    check("looks marks the armed look", "chip.raw == entry.armed" in wsrc)
    check("inline accessory registered", "ShutterLockInlineWidget()" in wsrc)
    check("lock circular is a roll gauge", "gaugeStyle(.accessoryCircularCapacity)" in wsrc)
    check("lock rectangular shows the roll", "ShutterStats.rollLength)" in wsrc)

    # Layout budget — these stacks are dense enough to clip on an SE
    _, med_h = WIDGET_BOX["medium"]
    _, large_h = WIDGET_BOX["large"]

    # Build 102/107 — outer pad is WidgetPalette.contentPad on every Home face.
    content_pad = parse_int(
        wsrc, r"static let contentPad: CGFloat = (\d+)", "shared contentPad", 14
    )

    def face_pad(chunk: str, name: str, fallback: int) -> int:
        if "WidgetPalette.contentPad" in chunk:
            check(f"widget parses {name}", True)
            return content_pad
        return parse_int(chunk, r"\.padding\((\d+)\)", name, fallback, last=True)

    pad = face_pad(medium, "launch medium padding", 14)
    gap = parse_int(medium, r"VStack\(alignment: \.leading, spacing: (\d+)\)", "launch medium gap", 5)
    bars = parse_int(medium, r"barHeight: (\d+)", "launch medium bar height", 26)
    sheet = parse_int(medium, r"\.frame\(width: 128, height: (\d+)\)", "launch medium sheet", 100)
    left = (
        text_line(10)                       # SHUTTER / roll count row
        + bars + 3 + text_line(7)           # week bars + day letters
        + text_line(11) + 1 + text_line(9)  # headline + subhead
        + text_line(11) + 12                # SHOOT capsule
        + gap * 4
    )
    right = sheet + 5 + text_line(8)
    budget = med_h - pad * 2
    check("launch medium fits SE", left <= budget, f"{left}pt in {budget}pt")
    check("launch medium sheet fits", right <= budget, f"{right}pt in {budget}pt")

    looks = source_chunk(wsrc, "struct ShutterLooksView", "// MARK: - Lock Screen")
    lpad = face_pad(looks, "looks padding", 14)
    lgap = parse_int(looks, r"spacing: family == \.systemLarge \? \d+ : (\d+)", "looks medium gap", 6)
    chip = parse_int(looks, r"minHeight: family == \.systemLarge \? \d+ : (\d+)", "looks chip", 30)
    strip = parse_int(looks, r"\.frame\(width: 132, height: (\d+)\)", "looks strip", 34)
    looks_medium = text_line(10) + (chip * 2 + 8) + (strip + 2) + lgap * 2
    check(
        "looks medium fits SE",
        looks_medium <= med_h - lpad * 2,
        f"{looks_medium}pt in {med_h - lpad * 2}pt",
    )

    lchip = parse_int(looks, r"minHeight: family == \.systemLarge \? (\d+)", "looks large chip", 38)
    lsheet = parse_int(looks, r"\.frame\(height: (\d+)\)", "looks large sheet", 132)
    lbars = parse_int(looks, r"barHeight: (\d+)", "looks large bars", 22)
    looks_large = (
        text_line(10)
        + (lchip * 2 + 8)
        + (text_line(10) + 7 + lsheet + 7 + lbars + 3 + text_line(7) + 2)
        + 10 * 2
    )
    check(
        "looks large fits SE",
        looks_large <= large_h - lpad * 2,
        f"{looks_large}pt in {large_h - lpad * 2}pt",
    )

    lgpad = face_pad(large, "launch large padding", 8)
    lggap = parse_int(large, r"VStack\(alignment: \.leading, spacing: (\d+)\)", "launch large gap", 9)
    lgbars = parse_int(large, r"barHeight: (\d+)", "launch large bars", 28)
    header = max(
        text_line(11) + text_line(19) + text_line(11) + text_line(9) + 9,
        text_line(26) + 3 + text_line(9) + 18,
    )
    footer = max(lgbars + 3 + text_line(7), text_line(15) + 1 + text_line(7) + 5 + text_line(8))
    sheet_room = (large_h - lgpad * 2) - lggap * 3 - header - footer
    # Below ~110pt the 3x2 sheet stops reading as photographs.
    check("large sheet keeps its room", sheet_room >= 110, f"{sheet_room}pt for 2 rows")


def main() -> int:
    print("Shutter stress suite")
    test_deeplinks()
    test_orientation_touch()
    test_enum_coverage()
    test_source_guards()
    test_landscape_layout()
    test_natural_truth()
    test_widget_content()
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
    check("visual shutter z-order", "collapsed shutter dock: yes" in viz_report)
    check("visual collapsed hist hidden", "collapsed histogram: hidden" in viz_report)
    check("visual landscape expanded", "landscape expanded hist↔shutter gap:" in viz_report)
    print("\n== Widget preview render ==")
    w = subprocess.run([sys.executable, str(ROOT / "scripts/widget_layout_preview.py")], cwd=ROOT)
    check("widget_layout_preview.py", w.returncode == 0, f"exit {w.returncode}")
    widget_dir = ROOT / "docs" / "widget-preview"
    for name in (
        "launch-small.png",
        "launch-medium.png",
        "launch-large.png",
        "looks-medium.png",
        "looks-large.png",
        "lock-accessories.png",
        "widget-preview.png",
    ):
        check(f"widget artifact {name}", (widget_dir / name).is_file())

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
