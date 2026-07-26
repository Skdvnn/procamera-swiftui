import SwiftUI
import UIKit
import AVFoundation
import WidgetKit
import Combine

struct Haptics {
    static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func medium() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func heavy() { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
    static func click() { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
}

/// Trailing-edge scrub peel identity (Build 71 fullscreen arch vibe).
enum ScrubEdgeKind: Equatable {
    case focus, ev, iso, shutter

    var title: String {
        switch self {
        case .focus: return "FOCUS"
        case .ev: return "EV"
        case .iso: return "ISO"
        case .shutter: return "S"
        }
    }

    var subtitle: String {
        switch self {
        case .focus: return "DIST"
        case .ev: return "STOP"
        case .iso: return "GAIN"
        case .shutter: return "TIME"
        }
    }
}

// MARK: - Finder motion
/// Timing curves for camera chrome. Prefer these over bouncy springs so motion
/// stays mechanical and never walks animated Metal shutter params.
enum ShutterMotion {
    /// Bottom / top deck expand-collapse
    static let deck = Animation.timingCurve(0.22, 0.82, 0.2, 1.0, duration: 0.38)
    /// Glass info bar / compact overlays
    static let chrome = Animation.timingCurve(0.22, 0.78, 0.2, 1.0, duration: 0.28)
    /// Focus reticle
    static let reticleIn = Animation.easeOut(duration: 0.14)
    static let reticleOut = Animation.easeOut(duration: 0.2)
    /// Capture flash wash
    static let flash = Animation.easeOut(duration: 0.1)
    /// Timer digit tick
    static let tick = Animation.easeOut(duration: 0.15)
    /// Local film / FX / recipe picker entrance (picker subtree only)
    static let picker = Animation.timingCurve(0.2, 0.8, 0.22, 1.0, duration: 0.2)
    /// Scrubber / ticker settle — no bounce
    static let scrub = Animation.easeOut(duration: 0.18)
    /// Mechanical shutter 3D press-in (offset + bevel, never scale) — snappy.
    static let press = Animation.easeOut(duration: 0.08)
}

/// Pressed state for the shutter face only (collar stays solid).
private struct ShutterPressedKey: EnvironmentKey {
    static let defaultValue = false
}
private extension EnvironmentValues {
    var shutterPressed: Bool {
        get { self[ShutterPressedKey.self] }
        set { self[ShutterPressedKey.self] = newValue }
    }
}

// MARK: - Vulcanite Leather Texture (Leica-style vulcanite rubber grain)
struct VulcaniteGrain: View {
    var body: some View {
        Canvas { ctx, size in
            // Layer 1: Base fine grain (denser for leather-like feel)
            for _ in 0..<Int(size.width * size.height * 0.008) {
                let x = CGFloat.random(in: 0..<size.width)
                let y = CGFloat.random(in: 0..<size.height)
                let gray = CGFloat.random(in: 0.04...0.12)
                let particleSize = CGFloat.random(in: 0.6...1.2)
                let rect = CGRect(x: x, y: y, width: particleSize, height: particleSize)
                ctx.fill(Path(rect), with: .color(Color(white: gray, opacity: 0.2)))
            }

            // Layer 2: Larger scattered specks (vulcanite texture variation)
            for _ in 0..<Int(size.width * size.height * 0.001) {
                let x = CGFloat.random(in: 0..<size.width)
                let y = CGFloat.random(in: 0..<size.height)
                let gray = CGFloat.random(in: 0.08...0.18)
                let particleSize = CGFloat.random(in: 1.5...2.5)
                let rect = CGRect(x: x, y: y, width: particleSize, height: particleSize)
                ctx.fill(Path(rect), with: .color(Color(white: gray, opacity: 0.12)))
            }

            // Layer 3: Subtle horizontal striations (leather grain direction)
            for i in stride(from: 0, to: size.height, by: CGFloat.random(in: 3...6)) {
                if CGFloat.random(in: 0...1) < 0.3 {
                    let lineY = i + CGFloat.random(in: -1...1)
                    let lineWidth = CGFloat.random(in: 20...80)
                    let startX = CGFloat.random(in: 0..<size.width)
                    let rect = CGRect(x: startX, y: lineY, width: lineWidth, height: 0.5)
                    ctx.fill(Path(rect), with: .color(Color(white: 0.1, opacity: 0.06)))
                }
            }
        }
        .allowsHitTesting(false)
        .blendMode(.overlay)
    }
}

// MARK: - Design System (matches Figma exactly, adaptive light/dark)
struct DS {
    // Colors - Adaptive for light/dark mode (DSLR body feel, inverted tones)
    static var pageBg: Color {
        Color(uiColor: UIColor(dynamicProvider: { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: "131313") : UIColor(hex: "ececec")
        }))
    }
    static var controlBg: Color {
        Color(uiColor: UIColor(dynamicProvider: { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: "242424") : UIColor(hex: "dbdbdb")
        }))
    }
    static var controlBgLight: Color {
        Color(uiColor: UIColor(dynamicProvider: { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: "3a3a3a") : UIColor(hex: "c5c5c5")
        }))
    }
    static var strokeOuter: Color {
        Color(uiColor: UIColor(dynamicProvider: { traits in
            traits.userInterfaceStyle == .dark ? UIColor(white: 0.22, alpha: 1) : UIColor(white: 0.78, alpha: 1)
        }))
    }
    static var strokeInner: Color {
        Color(uiColor: UIColor(dynamicProvider: { traits in
            traits.userInterfaceStyle == .dark ? UIColor(white: 0.12, alpha: 1) : UIColor(white: 0.88, alpha: 1)
        }))
    }
    static var textPrimary: Color {
        Color(uiColor: UIColor(dynamicProvider: { traits in
            traits.userInterfaceStyle == .dark ? .white : UIColor(hex: "131313")
        }))
    }
    static var textSecondary: Color {
        Color(uiColor: UIColor(dynamicProvider: { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: "5e5e5e") : UIColor(hex: "a1a1a1")
        }))
    }
    static let accent = Color(red: 1.0, green: 0.85, blue: 0.35) // golden yellow for indicators

    // Spacing
    static let pageMargin: CGFloat = 10

    // Radius (from Figma measurements)
    static let radiusSmall: CGFloat = 5    // Figma r=5
    static let radiusMedium: CGFloat = 12
    static let radiusLarge: CGFloat = 28   // Figma r=28 for pills
    static let radiusPill: CGFloat = 100   // Figma r=100 for full pills

    // Font
    static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

// UIColor hex extension for adaptive colors
extension UIColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(
            red: CGFloat(r) / 255,
            green: CGFloat(g) / 255,
            blue: CGFloat(b) / 255,
            alpha: 1
        )
    }
}

// Color extension for hex values
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255
        )
    }
}

// Legacy alias
let vulcaniteBlack = DS.pageBg

// MARK: - Capture Format
enum CaptureFormat: String, CaseIterable, Hashable {
    case heic, jpeg, raw

    var label: String {
        switch self {
        case .heic: return "HEIC"
        case .jpeg: return "JPG"
        case .raw: return "RAW"
        }
    }

    var next: CaptureFormat {
        let all = CaptureFormat.allCases
        let idx = all.firstIndex(of: self) ?? 0
        return all[(idx + 1) % all.count]
    }
}

/// Thin observer that re-renders only the chrome subtree when AE hunts.
/// Keeps ContentView body from rebuilding ~2.5×/sec during AUTO exposure.
private struct LiveExposureChrome<Content: View>: View {
    @ObservedObject private var bus = LiveExposureBus.shared
    let isManualExposure: Bool
    let isoOverride: Int
    let shutterOverride: String
    @ViewBuilder let content: (_ iso: Int, _ shutter: String) -> Content

    private var resolvedISO: Int {
        if isManualExposure { return isoOverride }
        let live = Int(bus.iso.rounded())
        return live > 0 ? live : isoOverride
    }

    private var resolvedShutter: String {
        if isManualExposure { return shutterOverride }
        let live = bus.shutterLabel
        return live.isEmpty || live == "AUTO" ? "AUTO" : live
    }

    var body: some View {
        content(resolvedISO, resolvedShutter)
    }
}

struct ContentView: View {
    @StateObject private var camera = CameraManager()
    @Environment(\.colorScheme) var colorScheme  // Track color scheme changes

    @AppStorage("cam.showGrid") private var showGrid = true
    @AppStorage("cam.focusPeaking") private var focusPeaking = false
    @AppStorage("cam.zebra") private var zebraEnabled = false
    /// Off by default — motion updates were fighting the camera UI for main-thread time.
    @AppStorage("cam.showLevel") private var showLevel = false
    @AppStorage("cam.shootMode") private var shootModeRaw: String = ShootMode.street.rawValue
    @AppStorage("cam.defaultFilm") private var defaultFilmRaw: Int = FilmFilterMode.none.rawValue
    @AppStorage("cam.captureFormat") private var captureFormatRaw: String = CaptureFormat.heic.rawValue
    /// Default ON — minimize Apple computational photography (speed + Bayer RAW).
    /// Does not strip selected film/FX — those still bake WYSIWYG.
    @AppStorage("cam.naturalCapture") private var naturalCapture = true
    @State private var showSettings = false
    @AppStorage("cam.timerSeconds") private var timerSeconds = 0
    @State private var timerCountdown = 0
    @State private var timerGeneration = UUID()
    @State private var frozenCaptureIsLE = false
    @State private var frozenLEDuration: Double? = nil
    /// Film/FX frozen at timer arm — countdown must not change the look mid-flight.
    @State private var frozenFilmFilter: FilmFilterMode? = nil
    @State private var frozenLensFX: LensFXMode? = nil
    @State private var lastShutterEventAt: CFAbsoluteTime = 0
    @State private var photoCount = 0
    @State private var lastCapturedImage: UIImage?
    @State private var showFlash = false
    /// Brief dark shutter curtain (burst / clap) — not the white flash wash.
    @State private var showShutterCurtain = false
    /// Brief chrome toast for failed capture / Photos denial / LE cancel.
    @State private var statusToast: String?
    @State private var statusToastWork: DispatchWorkItem?
    /// Suppresses "Capture failed" toast when the user aborted LE.
    @State private var expectingLECancel = false
    /// Soft Auto Night assist — opt-in chip when AUTO is hunting in the dark.
    @State private var nightAssistVisible = false
    @State private var nightAssistDarkStreak = 0
    @State private var nightAssistDismissedUntil: Date?
    @AppStorage("cam.nightAssist") private var nightAssistEnabled = true
    /// Hold-to-burst is opt-in — default off (Build 65).
    @AppStorage("cam.holdBurst") private var holdBurstEnabled = false
    /// Hold-to-burst: finger still down after long-press threshold.
    @State private var isBurstHolding = false
    /// Suppresses the Button tap that fires when a long-press burst ends.
    @State private var burstConsumedTap = false
    @State private var burstCaptured = 0
    @State private var burstNilRetries = 0
    private let burstMaxFrames = 6
    private let burstMaxNilRetries = 60
    @State private var showFocusPoint = false
    @State private var frozenMorphTouch: MorphTouchState? = nil
    @State private var focusPoint: CGPoint = .zero
    /// Latest viewfinder size — used to center the EV sun when dragging without a prior tap.
    @State private var viewfinderSize: CGSize = .zero
    /// EV captured when the focus reticle appeared — vertical drag offsets from this.
    @State private var focusStartEV: Float = 0
    /// ISO captured at drag start — MANUAL sun-drag moves gain, not bias.
    @State private var dragStartISO: Int = 100
    @State private var isDraggingExposure = false
    @State private var focusHideWorkItem: DispatchWorkItem?
    @State private var lastExposureHapticStep: Int = 0
    @State private var macroEnabled = false
    @State private var isCapturing = false
    @State private var whiteBalanceIndex: Int = 0
    @State private var isManualFocusEnabled = false
    @State private var isLocked = false
    @State private var focusPosition: Float = 0.5
    @State private var exposureValue: Float = 0.0
    @State private var isoValue: Int = 400
    @State private var focalLength: Int = 24
    @State private var zoomValue: CGFloat = 1.0
    /// Hardware lens aperture readout only (phones don't stop down).
    @State private var apertureValue: Float = 0
    @State private var shutterSpeedIndex: Int = 9  // Default to 1/125
    @State private var aspectRatio: AspectRatioMode = .full
    @State private var filmFilter: FilmFilterMode = .none
    @State private var lensFX: LensFXMode = .none
    @State private var finderIsLandscape = false
    @State private var captureFormat: CaptureFormat = .heic
    @State private var topCollapsed = false
    /// Deep-link / shortcut capture before the session is up.
    @State private var pendingCaptureWhenReady = false
    @State private var timerWorkItem: DispatchWorkItem?
    /// Start fullscreen (shutter docked at bottom) — swipe up to expand controls.
    @State private var bottomCollapsed = true
    /// Live vertical drag on the bottom deck (positive = pulling down / collapsing).
    @State private var bottomDeckDrag: CGFloat = 0
    /// Fullscreen scrub arch — FOCUS/EV (and expanded ISO/S) peel the trailing edge.
    @State private var scrubEdgeKind: ScrubEdgeKind? = nil
    @State private var scrubEdgeProgress: CGFloat = 0
    @State private var scrubEdgeValue: String = ""
    @StateObject private var gallery = GalleryStore()
    @StateObject private var volumeShutter = VolumeShutterObserver()
    @State private var showPhotoBook = false
    /// Field Book deep link — applied when CullLibraryView appears (not a racy Notification).
    @State private var pendingOpenFieldBook = false
    @State private var showingCleanCompare = false

    private var defaultFilmBinding: Binding<FilmFilterMode> {
        Binding(
            get: { FilmFilterMode(rawValue: defaultFilmRaw) ?? .none },
            set: { defaultFilmRaw = $0.rawValue }
        )
    }

    private let shutterSpeeds = ["4\"", "2\"", "1\"", "1/2", "1/4", "1/8", "1/15", "1/30", "1/60", "1/125", "1/250", "1/500", "1/1000", "1/2000", "1/4000"]
    private let isoValues = [100, 200, 400, 800, 1600, 3200]
    private let focalLengths = [13, 24, 48, 120]

    /// Trailing-edge peel content while collapsing or scrubbing.
    private struct EdgeReadout: Equatable {
        var title: String
        var value: String
        var subtitle: String
        var progress: CGFloat
        var serif: Bool
    }

    private var activeEdgeReadout: EdgeReadout? {
        // Collapse drag still owns the ƒ peel when expanded.
        if !bottomCollapsed && bottomDeckDrag > 4 && apertureValue > 0.5 {
            return EdgeReadout(
                title: "ƒ",
                value: String(format: "%.1f", apertureValue),
                subtitle: "EQ",
                progress: min(max(bottomDeckDrag / 120.0, 0), 1),
                serif: true
            )
        }
        // Fullscreen (or any) active scrub — arch becomes the scrub vibe.
        if let kind = scrubEdgeKind, scrubEdgeProgress > 0.05 {
            return EdgeReadout(
                title: kind.title,
                value: scrubEdgeValue,
                subtitle: kind.subtitle,
                progress: scrubEdgeProgress,
                serif: false
            )
        }
        return nil
    }

    private func setScrubEdge(_ kind: ScrubEdgeKind?, active: Bool, value: String) {
        if active {
            let first = scrubEdgeKind != kind || scrubEdgeProgress < 0.4
            scrubEdgeKind = kind
            scrubEdgeValue = value
            if first {
                withAnimation(ShutterMotion.deck) { scrubEdgeProgress = 0.92 }
            }
        } else if scrubEdgeKind == kind {
            withAnimation(ShutterMotion.scrub) { scrubEdgeProgress = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                if scrubEdgeProgress < 0.08 { scrubEdgeKind = nil }
            }
        }
    }

    /// Shared collapsed chrome metrics — histogram floats above fade/deck.
    private enum CollapsedChrome {
        static let deckHeight: CGFloat = 88
        /// Tall enough for the compact shutter (64) + vertical pad in landscape.
        static let landscapeDeckHeight: CGFloat = 80
        static let fadeHeight: CGFloat = 48
        /// Approximate RefractiveGlassInfoBar height (pad + hist + readouts).
        static let infoBarHeight: CGFloat = 56
        /// Gap between histogram bottom and shutter deck top when collapsed.
        static let histDeckGap: CGFloat = 8
        /// Expanded: keep histogram inside the viewfinder, clear of the deck below.
        static let expandedHistogramBottomPad: CGFloat = 14
        /// Gap between viewfinder bottom and expanded shutter deck.
        static let viewfinderToDeckGap: CGFloat = 5

        static func bottomPad(safeBottom: CGFloat) -> CGFloat {
            max(safeBottom * 0.55, 8)
        }

        /// Lift the glass bar above the safe-area strip + shutter deck.
        static func histogramBottomPad(safeBottom: CGFloat, deckHeight: CGFloat = deckHeight) -> CGFloat {
            deckHeight + bottomPad(safeBottom: safeBottom) + histDeckGap
        }
    }

    var body: some View {
        GeometryReader { geo in
            finderCanvas(geo: geo)
        }
        .statusBarHidden(false)
        // Require a second deliberate swipe for the home gesture so drags on
        // the bottom control rows don't accidentally minimize the app
        .defersSystemGestures(on: .bottom)
        .id(colorScheme)  // Force redraw on color scheme change
        .onAppear(perform: handleAppear)
        .onDisappear {
            ChromePickerGate.dismiss(commit: false)
            volumeShutter.stop()
            ShutterDeepLinkCenter.endReceiving()
            cancelTimerCountdown()
            if camera.isLongExposureCapturing {
                camera.cancelLongExposure()
                isCapturing = false
            }
            isBurstHolding = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .shutterDeepLink)) { note in
            if let link = note.userInfo?["link"] as? ShutterDeepLink {
                applyDeepLink(link)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .shutterHardwareShutter)) { _ in
            guard !showPhotoBook, !showSettings, !isBurstHolding,
                  !ChromePickerGate.isPresented else { return }
            handleCapture()
        }
        .modifier(ContentViewLifecycle(
            camera: camera,
            pendingCaptureWhenReady: $pendingCaptureWhenReady,
            focusPeaking: $focusPeaking,
            zebraEnabled: $zebraEnabled,
            naturalCapture: naturalCapture,
            captureFormat: $captureFormat,
            captureFormatRaw: $captureFormatRaw,
            apertureValue: $apertureValue,
            isLocked: $isLocked,
            filmFilter: filmFilter,
            lensFX: lensFX,
            onCapture: { handleCapture() },
            onClampISO: { clampISOToDevice(maxISO: $0) },
            onToast: { showStatusToast($0) },
            onSyncFilm: { syncFilmFilter($0) },
            onSyncContext: { syncCaptureContextToSystem() }
        ))
        .fullScreenCover(isPresented: $showPhotoBook, onDismiss: {
            // Resync after Darkroom deletes / cull finish.
            photoCount = gallery.shots.count
            if let last = gallery.shots.last,
               let img = gallery.thumbnail(for: last) {
                lastCapturedImage = img
            } else {
                lastCapturedImage = nil
            }
        }) {
            CullLibraryView(
                store: gallery,
                openFieldBooksOnAppear: pendingOpenFieldBook,
                onConsumedFieldBookOpen: { pendingOpenFieldBook = false }
            )
        }
        .sheet(isPresented: $showSettings) {
            ShutterSettingsSheet(
                showGrid: $showGrid,
                focusPeaking: $focusPeaking,
                zebraEnabled: $zebraEnabled,
                showLevel: $showLevel,
                captureFormat: $captureFormat,
                defaultFilm: defaultFilmBinding,
                naturalCapture: $naturalCapture,
                nightAssist: $nightAssistEnabled,
                holdBurst: $holdBurstEnabled,
                filmFilter: $filmFilter,
                lensFX: $lensFX,
                onLookApplied: { film, fx in
                    applyExclusiveLook(film: film, fx: fx)
                },
                onDismiss: {
                    captureFormatRaw = captureFormat.rawValue
                    switch captureFormat {
                    case .heic: camera.captureFormat = .heic
                    case .jpeg: camera.captureFormat = .jpeg
                    case .raw: camera.captureFormat = .raw
                    }
                    camera.focusPeakingEnabled = focusPeaking
                    showSettings = false
                }
            )
        }
        .onChange(of: bottomCollapsed) { _, _ in
            // Collapse/expand must not leave a UIKit picker orphaned over the finder.
            ChromePickerGate.dismiss()
        }
        .onChange(of: showPhotoBook) { _, open in
            if open { ChromePickerGate.dismiss() }
        }
        .onChange(of: showSettings) { _, open in
            if open { ChromePickerGate.dismiss() }
        }
    }

    /// Separate UIWindow + UIKit table — never touch Metal on the button turn.
    /// Tap always opens the menu; long-press clears (Build 73).
    private func toggleChromePicker(_ menu: ChromePickerMenu) {
        ChromePickerGate.toggle(
            menu,
            filmFilter: filmFilter,
            lensFX: lensFX,
            focusPeaking: focusPeaking,
            shootMode: ShootMode(rawValue: shootModeRaw),
            compactChrome: finderIsLandscape,
            onWillPresent: {
                camera.setChromePickerPreviewSuspended(true)
            },
            onCommit: { commit in
                applyChromePickerCommit(commit)
            },
            onTeardown: { willCommit in
                if !willCommit {
                    camera.setChromePickerPreviewSuspended(false)
                } else {
                    // Safety net: if commit never lands, don't stay parked forever
                    // (pink/blank frozen finder after FX — Build 74).
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.40) { [weak camera] in
                        guard !ChromePickerGate.isPresented else { return }
                        camera?.setChromePickerPreviewSuspended(false)
                    }
                }
            }
        )
    }

    private func clearChromeLook(film: Bool, fx: Bool) {
        Haptics.medium()
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            if film { filmFilter = .none }
            if fx {
                lensFX = .none
                LensFXEngine.shared.clearStickyTouch()
                // Long-press FX also clears peaking-only tint.
                if focusPeaking {
                    focusPeaking = false
                    camera.focusPeakingEnabled = false
                }
            }
        }
        if film { camera.selectedFilmFilter = .none }
        if fx { camera.selectedLensFX = .none }
        syncCaptureContextToSystem()
    }

    /// Film and Lens FX are exclusive — never both on.
    private func applyExclusiveLook(film: FilmFilterMode, fx: LensFXMode) {
        let exclusiveFilm: FilmFilterMode
        let exclusiveFX: LensFXMode
        if fx != .none {
            exclusiveFilm = .none
            exclusiveFX = fx
        } else {
            exclusiveFilm = film
            exclusiveFX = .none
        }
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            filmFilter = exclusiveFilm
            lensFX = exclusiveFX
        }
        camera.selectedFilmFilter = exclusiveFilm
        camera.selectedLensFX = exclusiveFX
        if !exclusiveFX.isTouchReactive {
            LensFXEngine.shared.clearStickyTouch()
        }
        syncCaptureContextToSystem()
    }

    private func applyChromePickerCommit(_ commit: ChromePickerCommit) {
        // Exclusive film ↔ FX before unsuspending live Metal.
        let exclusiveFilm: FilmFilterMode
        let exclusiveFX: LensFXMode
        if commit.lensFX != .none {
            exclusiveFilm = .none
            exclusiveFX = commit.lensFX
        } else {
            exclusiveFilm = commit.filmFilter
            exclusiveFX = .none
        }
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) {
            filmFilter = exclusiveFilm
            lensFX = exclusiveFX
            focusPeaking = commit.focusPeaking
        }
        camera.selectedFilmFilter = exclusiveFilm
        camera.selectedLensFX = exclusiveFX
        camera.focusPeakingEnabled = commit.focusPeaking
        if !exclusiveFX.isTouchReactive {
            LensFXEngine.shared.clearStickyTouch()
        }
        if commit.filmAppliedDirectly {
            shootModeRaw = "auto"
        }
        if let mode = commit.shootMode {
            applyShootMode(mode)
        }
        if commit.saveLook {
            LookRecipeStore.shared.saveCurrent(film: exclusiveFilm, lensFX: exclusiveFX)
            Haptics.medium()
        }
        syncCaptureContextToSystem()
        // Unsuspend AFTER look is on pipeline — resets preview clock so the
        // first film frame lands immediately (avoids pink/blank stall).
        camera.setChromePickerPreviewSuspended(false)
    }

    /// Split out of `body` so the Swift type-checker can finish (CI archive).
    @ViewBuilder
    private func finderCanvas(geo: GeometryProxy) -> some View {
            let safeTop = geo.safeAreaInsets.top
            let safeBottom = geo.safeAreaInsets.bottom
            let isLandscape = geo.size.width > geo.size.height
            // Landscape: keep the top dial compact. Bottom deck can expand —
            // trapping it collapsed made swipe-up feel broken.
            let effectiveTopCollapsed = topCollapsed || isLandscape
            let effectiveBottomCollapsed = bottomCollapsed

            // Layout measurements — top collapse keeps FOCUS/EV strip as the hero
            let topPanelHeight: CGFloat = effectiveTopCollapsed ? (isLandscape ? 44 : 52) : 110
            let gaugeToViewfinderSpacing: CGFloat = effectiveTopCollapsed ? 3 : 4
            let viewfinderToControlsSpacing: CGFloat = max(2, CollapsedChrome.viewfinderToDeckGap - 2)

            ZStack(alignment: .top) {
                // Non-Metal grip texture — stitchable vulcaniteTexture in this tree
                // MetadataCache-crashes when film/FX pickers insert (device EXC_BAD_ACCESS).
                ZStack {
                    Color(white: 0.075)
                    ControlsGrain()
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)

                VStack(spacing: 0) {
                    // TOP: Analog Display Panel — FOCUS/EV when compact
                    LiveExposureChrome(
                        isManualExposure: camera.isManualExposure,
                        isoOverride: isoValue,
                        shutterOverride: shutterSpeeds[safeShutterSpeedIndex]
                    ) { liveISO, liveShutter in
                        AnalogDisplayPanel(
                            focusPosition: $focusPosition,
                            exposureValue: $exposureValue,
                            shutterSpeedIndex: $shutterSpeedIndex,
                            timerSeconds: timerSeconds,
                            iso: liveISO,
                            isoIsAuto: !camera.isManualExposure,
                            shutterLabel: liveShutter,
                            shutterIsAuto: !camera.isManualExposure,
                            flashMode: flashModeLabel(camera.flashMode),
                            macroEnabled: macroEnabled,
                            isAutoFocus: !isManualFocusEnabled,
                            compact: effectiveTopCollapsed,
                            showLevel: showLevel,
                            onFocusChanged: { val in
                                guard !isLocked else { return }
                                camera.setManualFocus(val)
                                isManualFocusEnabled = true
                            },
                            onExposureChanged: { val in
                                guard !isLocked, !camera.isManualExposure else { return }
                                camera.setExposure(val)
                            },
                            onShutterSpeedChanged: { idx in
                                guard !isLocked else { return }
                                // Pass UI ISO so we don't lock shutter with CameraManager's stale 100.
                                shutterSpeedIndex = idx
                                camera.setShutterSpeed(index: idx, iso: Float(isoValue))
                            },
                            // Arch peel is reserved for the viewfinder sun-drag (Build 81) —
                            // the scrubbers have their own inline readouts.
                            onTimerTap: {
                                Haptics.click()
                                if timerSeconds == 0 { timerSeconds = 3 }
                                else if timerSeconds == 3 { timerSeconds = 10 }
                                else { timerSeconds = 0 }
                            },
                            onMacroTap: {
                                Haptics.click()
                                macroEnabled.toggle()
                                if macroEnabled, isLocked {
                                    isLocked = false
                                    camera.setAEAFLocked(false)
                                }
                                camera.setMacroEnabled(macroEnabled)
                                if macroEnabled {
                                    isManualFocusEnabled = false
                                }
                            }
                        )
                    }
                    .frame(height: topPanelHeight)
                    .padding(.horizontal, DS.pageMargin)
                    // Higher threshold when dials are out so vertical dial drags
                    // don't collapse the top deck.
                    .simultaneousGesture(
                        deckSwipe(
                            collapseOnSwipeUp: true,
                            // Compact scrubbers: require a clear vertical intent so
                            // horizontal FOCUS/EV scrubs don't expand the dials.
                            minDistance: effectiveTopCollapsed ? 48 : 56,
                            verticalBias: effectiveTopCollapsed ? 2.8 : 1.15
                        ) { topCollapsed = $0 }
                    )

                    Spacer().frame(height: gaugeToViewfinderSpacing)

                    // VIEWFINDER — when bottom is collapsed, feed runs under the shutter
                    // with a bottom gradient + compact controls overlaid.
                    ZStack(alignment: .bottom) {
                        viewfinderFrame(showHistogram: !effectiveBottomCollapsed)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .layoutPriority(1)
                            .padding(.horizontal, effectiveBottomCollapsed ? 6 : DS.pageMargin)

                        if effectiveBottomCollapsed {
                            // Histogram BELOW shutter in z-order. Never put contentShape
                            // on the bottom-padded frame — that invisible pad sat on top
                            // of the shutter and ate every tap.
                            LiveExposureChrome(
                                isManualExposure: camera.isManualExposure,
                                isoOverride: isoValue,
                                shutterOverride: shutterSpeeds[safeShutterSpeedIndex]
                            ) { liveISO, liveShutter in
                                RefractiveGlassInfoBar(
                                    iso: liveISO,
                                    shutterSpeed: liveShutter,
                                    aperture: apertureValue,
                                    photoCount: photoCount,
                                    exposureValue: exposureValue,
                                    captureFormat: captureFormat,
                                    aspectLabel: aspectRatio.shortLabel,
                                    isLocked: isLocked,
                                    isManualExposure: camera.isManualExposure,
                                    naturalCapture: naturalCapture,
                                    showLevel: showLevel,
                                    compact: isLandscape,
                                    onToggleLock: { toggleAEAFLock() },
                                    onReturnToAuto: { returnToAuto() }
                                )
                            }
                            .padding(.horizontal, isLandscape ? 10 : 14)
                            .simultaneousGesture(bottomDeckSwipe)
                            .padding(.bottom, CollapsedChrome.histogramBottomPad(
                                safeBottom: safeBottom,
                                deckHeight: isLandscape
                                    ? CollapsedChrome.landscapeDeckHeight
                                    : CollapsedChrome.deckHeight
                            ))
                            .transition(
                                .asymmetric(
                                    insertion: .opacity.combined(with: .offset(y: 8)),
                                    removal: .opacity.combined(with: .offset(y: 6))
                                )
                            )
                            .zIndex(2)

                            collapsedBottomOverlay(safeBottom: safeBottom, compact: isLandscape)
                                // Fill the finder and pin chrome to the bottom edge —
                                // without this the shutter can float mid-frame.
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                                .transition(
                                    .asymmetric(
                                        insertion: .opacity.combined(with: .offset(y: 12)),
                                        removal: .opacity.combined(with: .offset(y: 10))
                                    )
                                )
                                // Above histogram + viewfinder chrome so shutter wins taps.
                                .zIndex(10)
                        }

                        // Chrome above histogram, BELOW shutter dock — corner
                        // buttons stay tappable; empty space can't cover shutter.
                        ViewfinderOverlay(
                            showGrid: showGrid,
                            aspectRatio: $aspectRatio,
                            filmFilter: $filmFilter,
                            lensFX: $lensFX,
                            focusPeaking: $focusPeaking,
                            compactChrome: isLandscape,
                            onFlipCamera: {
                                Haptics.click()
                                camera.switchCamera()
                                // Flip parks on wide @ 1x — reset ring/pinch state.
                                focalLength = 24
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    zoomValue = camera.zoomFactor
                                }
                            },
                            onTogglePicker: { toggleChromePicker($0) },
                            onClearLook: { menu in
                                switch menu {
                                case .film: clearChromeLook(film: true, fx: false)
                                case .fx: clearChromeLook(film: false, fx: true)
                                case .looks: break
                                }
                            }
                        )
                        .padding(.horizontal, effectiveBottomCollapsed ? 6 : DS.pageMargin)
                        .zIndex(5)

                        // Level lives under the top EV meter (replaces ISO/S there).

                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)

                    if !effectiveBottomCollapsed {
                        Spacer().frame(height: viewfinderToControlsSpacing)

                        // Expanded deck — opaque grain slab (scrubbers live here)
                        VStack(spacing: 0) {
                            bottomExpandedDeck
                                .offset(y: bottomDeckDrag * 0.55)
                                .opacity(1.0 - min(bottomDeckDrag / 110.0, 0.55))

                            Color.clear
                                .frame(height: max(safeBottom * 0.55, 8))
                                .frame(maxWidth: .infinity)
                                .contentShape(Rectangle())
                                .gesture(bottomDeckSwipe)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                        .background { ControlsGrain() }
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .offset(y: 10)),
                                removal: .opacity.combined(with: .offset(y: 12))
                            )
                        )
                    }
                }
                .padding(.top, safeTop)
                // Animate only chrome commits via withAnimation(ShutterMotion.deck) —
                // never attach .animation to this VStack (it owns the Metal preview).

                // Soft clap wash — brief, low white (not a phone-camera flash bang).
                Color.white
                    .ignoresSafeArea()
                    .opacity(showFlash ? 0.28 : 0)
                    .allowsHitTesting(false)
                    .animation(ShutterMotion.flash, value: showFlash)

                // Subtle shutter curtain (burst clap) — dark, brief, no blue glow.
                Color.black
                    .ignoresSafeArea()
                    .opacity(showShutterCurtain ? 0.78 : 0)
                    .allowsHitTesting(false)
                    .animation(.easeOut(duration: 0.05), value: showShutterCurtain)

                FinderStatusOverlays(
                    safeTop: safeTop,
                    toast: statusToast,
                    nightAssistVisible: nightAssistVisible,
                    cameraError: camera.error?.localizedDescription,
                    onApplyNight: { applyNightAssistFromChip() },
                    onDismissNight: {
                        Haptics.click()
                        nightAssistVisible = false
                        nightAssistDismissedUntil = Date().addingTimeInterval(300)
                    }
                )
                .animation(ShutterMotion.chrome, value: statusToast)
                .animation(ShutterMotion.chrome, value: nightAssistVisible)
            }
            .ignoresSafeArea()
            // NEVER attach .animation to this ZStack — it owns Metal preview + shutter.
            // Toast/night chrome animate inside FinderStatusOverlays only.
            .onReceive(LiveExposureBus.shared.$iso) { _ in evaluateNightAssist() }
            .onReceive(LiveExposureBus.shared.$shutterLabel) { _ in evaluateNightAssist() }
            .onChange(of: camera.isManualExposure) { _, manual in
                if manual { nightAssistVisible = false; nightAssistDarkStreak = 0 }
                else { evaluateNightAssist() }
            }
            .onChange(of: isLandscape) { _, landscape in
                finderIsLandscape = landscape
                // Landscape uses compact chrome; remember portrait expanded state separately.
                if landscape {
                    bottomDeckDrag = 0
                }
                let orient = CameraManager.currentInterfaceOrientation()
                LensFXEngine.shared.setPreviewBufferRotation(
                    PreviewBufferRotation.from(interfaceOrientation: orient)
                )
            }
            .onAppear { finderIsLandscape = isLandscape }
            .onAppear {
                let orient = CameraManager.currentInterfaceOrientation()
                LensFXEngine.shared.setPreviewBufferRotation(
                    PreviewBufferRotation.from(interfaceOrientation: orient)
                )
            }
    }

    private func handleAppear() {
        camera.checkPermissions()
        syncFilmFilter(filmFilter)
        camera.selectedLensFX = lensFX
        camera.focusPeakingEnabled = focusPeaking
        camera.zebraEnabled = zebraEnabled
        photoCount = gallery.shots.count
        if let last = gallery.shots.last, let img = gallery.thumbnail(for: last) {
            lastCapturedImage = img
        }
        // Seed widget overlapping recents from gallery if App Group is empty.
        seedWidgetRecentsIfNeeded()
        apertureValue = camera.lensAperture
        camera.naturalCaptureEnabled = naturalCapture
        if let fmt = CaptureFormat(rawValue: captureFormatRaw) {
            captureFormat = fmt
            switch fmt {
            case .heic: camera.captureFormat = .heic
            case .jpeg: camera.captureFormat = .jpeg
            case .raw: camera.captureFormat = .raw
            }
        }
        let film = FilmFilterMode(rawValue: defaultFilmRaw) ?? .none
        if filmFilter == .none, film != .none {
            filmFilter = film
        }
        volumeShutter.onShutter = {
            guard !showPhotoBook, !showSettings,
                  !ChromePickerGate.isPresented else { return }
            handleCapture()
        }
        DispatchQueue.main.async {
            let host = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow }
            volumeShutter.start(in: host)
        }
        syncCaptureContextToSystem()
        DispatchQueue.main.async {
            ShutterDeepLinkCenter.beginReceiving()
        }
    }

    /// ISO for chrome / metadata — live sensor value while AUTO.
    private var displayISO: Int {
        if camera.isManualExposure { return isoValue }
        let live = Int(LiveExposureBus.shared.iso.rounded())
        return live > 0 ? live : isoValue
    }

    /// Clamped shutter index — never crash on a restored/corrupt value.
    private var safeShutterSpeedIndex: Int {
        min(max(shutterSpeedIndex, 0), shutterSpeeds.count - 1)
    }

    /// LE durations for shutter indices 0…3 (4″ / 2″ / 1″ / 1/2).
    private static let longExposureDurations: [Double] = [4.0, 2.0, 1.0, 0.5]

    private var isLongExposureShutterIndex: Bool {
        camera.isManualExposure && (0...3).contains(safeShutterSpeedIndex)
    }

    private var longExposureDurationIfAny: Double? {
        guard isLongExposureShutterIndex else { return nil }
        return Self.longExposureDurations[safeShutterSpeedIndex]
    }

    /// Shutter label for chrome / metadata — live duration while AUTO.
    private var displayShutterLabel: String {
        if camera.isManualExposure { return shutterSpeeds[safeShutterSpeedIndex] }
        let live = LiveExposureBus.shared.shutterLabel
        return live.isEmpty || live == "AUTO" ? "AUTO" : live
    }

    // Bind a captured frame into the Field Book with the live shot settings
    private func recordShot(_ img: UIImage, completion: (() -> Void)? = nil) {
        let metadata = ShotMetadata(
            id: UUID(),
            date: Date(),
            iso: displayISO,
            shutter: displayShutterLabel,
            aperture: apertureValue > 0 ? apertureValue : 0,
            ev: exposureValue,
            filmFilter: filmFilter.name,
            lensFX: lensFX.name,
            focalLength: focalLength
        )
        gallery.add(image: img, metadata: metadata, completion: completion)
        // Dual-write to Photos; stash localIdentifier so cull can delete both sides.
        camera.saveToPhotoLibrary(img) { assetID in
            if let assetID {
                gallery.setPhotosAssetIdentifier(assetID, for: metadata.id)
            } else {
                showStatusToast("Saved in app · Photos access needed")
            }
        }
    }

    private func flashModeLabel(_ mode: AVCaptureDevice.FlashMode) -> String {
        switch mode {
        case .off: return "OFF"
        case .on: return "ON"
        case .auto: return "AUTO"
        @unknown default: return "OFF"
        }
    }

    private func showStatusToast(_ message: String) {
        statusToastWork?.cancel()
        statusToast = message
        let work = DispatchWorkItem {
            statusToast = nil
        }
        statusToastWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2, execute: work)
    }

    /// Soft Auto Night — suggest manual Night when AUTO is clearly dark.
    /// Opt-in chip only (never auto-applies 1″ LE mid-shoot).
    private func evaluateNightAssist() {
        guard nightAssistEnabled else {
            nightAssistVisible = false
            nightAssistDarkStreak = 0
            return
        }
        // Never prompt / keep chip up while a capture owns the pipeline.
        if isCapturing || isBurstHolding || camera.isLongExposureCapturing {
            if nightAssistVisible {
                withAnimation(ShutterMotion.chrome) { nightAssistVisible = false }
            }
            nightAssistDarkStreak = 0
            return
        }
        guard !camera.isManualExposure else {
            nightAssistVisible = false
            nightAssistDarkStreak = 0
            return
        }
        if ShootMode(rawValue: shootModeRaw) == .night {
            nightAssistVisible = false
            return
        }
        if let until = nightAssistDismissedUntil, Date() < until {
            nightAssistVisible = false
            return
        }
        let dark = isLowLightAUTO(
            iso: LiveExposureBus.shared.iso,
            shutterLabel: LiveExposureBus.shared.shutterLabel
        )
        if dark {
            nightAssistDarkStreak += 1
        } else {
            nightAssistDarkStreak = 0
            if nightAssistVisible {
                withAnimation(ShutterMotion.chrome) { nightAssistVisible = false }
            }
            return
        }
        // ~3 samples at 0.4s probe ≈ 1.2s of stable dark before prompting.
        if nightAssistDarkStreak >= 3, !nightAssistVisible {
            withAnimation(ShutterMotion.chrome) { nightAssistVisible = true }
        }
    }

    private func applyNightAssistFromChip() {
        guard !isCapturing, !isBurstHolding, !camera.isLongExposureCapturing else { return }
        nightAssistVisible = false
        nightAssistDismissedUntil = Date().addingTimeInterval(180)
        applyShootMode(.night)
        showStatusToast("Night · 1/15 · ISO 1600")
    }

    private func isLowLightAUTO(iso: Float, shutterLabel: String) -> Bool {
        if iso >= 1000 { return true }
        guard let seconds = Self.parseShutterSeconds(shutterLabel) else { return false }
        // AE slower than ~1/30 in AUTO → scene is dark enough for Night assist.
        return seconds >= (1.0 / 30.0) - 0.0005
    }

    private static func parseShutterSeconds(_ label: String) -> Double? {
        let t = label.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, t != "AUTO" else { return nil }
        if t.hasSuffix("\"") {
            return Double(t.dropLast())
        }
        if t.hasPrefix("1/") {
            let denom = Double(t.dropFirst(2)) ?? 0
            guard denom > 0 else { return nil }
            return 1.0 / denom
        }
        return Double(t)
    }

    private func beginBurstHold() {
        guard holdBurstEnabled else { return }
        // Timer / LE cancel must still reach Button.action — do NOT consume the tap.
        if camera.isLongExposureCapturing || timerWorkItem != nil || timerCountdown > 0 {
            return
        }
        guard !isCapturing else { return }
        // Manual LE indices — hold is cancel, not burst.
        if isLongExposureShutterIndex { return }
        // Only swallow the Button release when a real burst actually starts.
        burstConsumedTap = true
        isBurstHolding = true
        burstCaptured = 0
        burstNilRetries = 0
        fireBurstFrame()
    }

    private func endBurstHold() {
        isBurstHolding = false
        if burstCaptured > 1 {
            showStatusToast("Burst · \(burstCaptured)")
        }
        // Do NOT clear burstConsumedTap here — finger-up order is
        // onBurstEnd → (maybe disable) → Button.action. Clearing early lets
        // Button.action fire a bonus single shot. Swallow in the action, or
        // clear on the next main turn if the action was skipped (disabled).
        DispatchQueue.main.async {
            if self.burstConsumedTap {
                self.burstConsumedTap = false
            }
        }
    }

    private func fireBurstFrame() {
        guard isBurstHolding, burstCaptured < burstMaxFrames else {
            isBurstHolding = false
            if burstCaptured > 1 {
                showStatusToast("Burst · \(burstCaptured)")
            }
            return
        }
        // Pipeline still owned — reschedule while finger is down (don't stall burst).
        if isCapturing {
            burstNilRetries += 1
            guard burstNilRetries < burstMaxNilRetries else {
                isBurstHolding = false
                showStatusToast(burstCaptured > 0 ? "Burst · \(burstCaptured)" : "Burst stopped")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                fireBurstFrame()
            }
            return
        }
        burstNilRetries = 0
        isCapturing = true
        syncCaptureControlsToCamera()
        let shutterFilm = cameraFilmFilter(from: filmFilter)
        let shutterFX = lensFX
        let morphTouch = shutterFX.isTouchReactive
            ? LensFXEngine.shared.snapshotForCapture()
            : nil
        if burstCaptured == 0 {
            // Subtle clap + dark curtain — not the gnarly white/blue wash.
            Haptics.medium()
            showShutterCurtain = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { showShutterCurtain = false }
        } else {
            Haptics.light()
        }
        camera.capturePhoto(
            filmFilter: shutterFilm,
            lensFX: shutterFX,
            morphTouch: morphTouch
        ) { img in
            isCapturing = false
            if let img {
                finishCapturedImage(img)
                burstCaptured += 1
                if isBurstHolding && burstCaptured < burstMaxFrames {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                        fireBurstFrame()
                    }
                } else {
                    isBurstHolding = false
                    if burstCaptured > 1 {
                        showStatusToast("Burst · \(burstCaptured)")
                    }
                }
            } else if isBurstHolding && burstCaptured < burstMaxFrames {
                burstNilRetries += 1
                guard burstNilRetries < burstMaxNilRetries else {
                    isBurstHolding = false
                    showStatusToast(burstCaptured > 0 ? "Burst · \(burstCaptured)" : "Burst stopped")
                    return
                }
                // Serialize reject / bake busy — retry while still holding.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                    fireBurstFrame()
                }
            } else {
                isBurstHolding = false
                if burstCaptured == 0 {
                    showStatusToast("Capture failed")
                } else if burstCaptured > 1 {
                    showStatusToast("Burst · \(burstCaptured)")
                }
            }
        }
    }

    private func clampISOToDevice(maxISO: Float = 0) {
        let cap = maxISO > 0 ? maxISO : camera.maxISO
        guard cap > 0 else { return }
        let maxI = Int(cap)
        if isoValue > maxI {
            isoValue = isoValues.last(where: { $0 <= maxI }) ?? maxI
        }
    }

    private func syncFilmFilter(_ filter: FilmFilterMode) {
        camera.selectedFilmFilter = filter
    }

    private func cameraFilmFilter(from filter: FilmFilterMode) -> FilmFilterMode {
        filter
    }

    /// Push viewfinder controls into CameraManager immediately before shutter
    /// so bake cannot miss a lagging onChange.
    private func syncCaptureControlsToCamera() {
        syncFilmFilter(filmFilter)
        camera.selectedLensFX = lensFX
    }

    private func applyShootMode(_ mode: ShootMode) {
        shootModeRaw = mode.rawValue
        switch mode {
        case .street:
            showGrid = true
            focusPeaking = false
            zebraEnabled = false
            shutterSpeedIndex = 10 // 1/250
            isoValue = 400
            camera.setShutterSpeed(index: 10)
            camera.setISO(400)
            isLocked = false
            camera.setAEAFLocked(false)
        case .night:
            // Clean low-light preset — no peaking/zebra/film pink cast, no 1″ LE stack.
            showGrid = false
            focusPeaking = false
            zebraEnabled = false
            filmFilter = .none
            lensFX = .none
            camera.selectedFilmFilter = .none
            camera.selectedLensFX = .none
            camera.focusPeakingEnabled = false
            LensFXEngine.shared.clearStickyTouch()
            shutterSpeedIndex = 6 // 1/15 — handheld-ish, not LE
            isoValue = 1600
            camera.setShutterSpeed(index: 6)
            camera.setISO(1600)
            isLocked = false
            camera.setAEAFLocked(false)
        case .studio:
            showGrid = true
            focusPeaking = true
            zebraEnabled = true
            shutterSpeedIndex = 9 // 1/125
            isoValue = 200
            camera.setShutterSpeed(index: 9)
            camera.setISO(200)
            camera.setAEAFLocked(true)
            isLocked = true
        case .film:
            showGrid = true
            focusPeaking = false
            zebraEnabled = false
            let film = FilmFilterMode(rawValue: defaultFilmRaw) ?? .portra400
            filmFilter = film == .none ? .portra400 : film
            lensFX = .none
            shutterSpeedIndex = 8 // 1/60
            isoValue = 400
            // Keep 1/60 + ISO 400 — do not call return-to-auto (it wiped the preset).
            camera.setShutterSpeed(index: 8)
            camera.setISO(400)
            isLocked = false
            camera.setAEAFLocked(false)
        }
        syncCaptureContextToSystem()
        Haptics.medium()
    }

    private func toggleAEAFLock() {
        Haptics.click()
        let next = !isLocked
        isLocked = next
        camera.setAEAFLocked(next)
    }

    private func returnToAuto() {
        Haptics.medium()
        isLocked = false
        isManualFocusEnabled = false
        exposureValue = 0
        // Reset UI stops so a leftover Night "1\"" doesn't still trigger LE while
        // the glass bar says AUTO.
        shutterSpeedIndex = 9 // 1/125 (display only until next manual set)
        isoValue = 400
        // Clear SCENE highlight — no preset owns AUTO exposure.
        shootModeRaw = "auto"
        nightAssistVisible = false
        nightAssistDarkStreak = 0
        camera.returnToAuto()
    }

    private func applyDeepLink(_ link: ShutterDeepLink) {
        switch link {
        case .openCamera:
            showPhotoBook = false
        case .capture:
            showPhotoBook = false
            if camera.isSessionRunning {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    handleCapture()
                }
            } else {
                pendingCaptureWhenReady = true
            }
        case .darkroom:
            showPhotoBook = true
        case .fieldBook:
            pendingOpenFieldBook = true
            showPhotoBook = true
        case .look(let filmName, let fxName):
            showPhotoBook = false
            // Always apply both — film-only widgets used to leave a stale FX on.
            if let filmName,
               let film = FilmFilterMode.allCases.first(where: {
                   $0.name.compare(filmName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
               }) {
                filmFilter = film
            } else if filmName == nil {
                // keep current film
            }
            if let fxName {
                if fxName.compare("None", options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                    || fxName == "—" || fxName.isEmpty {
                    lensFX = .none
                } else if let fx = LensFXMode.allCases.first(where: {
                    $0.name.compare(fxName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                }) {
                    lensFX = fx
                }
                // Unknown fxName: leave current FX (don't wipe a live look).
            }
        case .timer(let seconds):
            timerSeconds = [0, 3, 10].contains(seconds) ? seconds : 0
        case .peaking(let on):
            focusPeaking = on
        case .flip:
            camera.switchCamera()
        }
        syncCaptureContextToSystem()
    }

    private func syncCaptureContextToSystem() {
        let ctx = ShutterCaptureContext(
            useFrontCamera: camera.currentCamera == .front,
            filmName: filmFilter.name,
            lensFXName: lensFX.name,
            timerSeconds: timerSeconds,
            peaking: focusPeaking
        )
        ctx.saveToAppGroup()
        // Encode film|fx so widget deep links restore full looks, not film-only.
        var encoded: [String] = []
        func push(film: FilmFilterMode, fx: LensFXMode) {
            guard film != .none || fx != .none else { return }
            let token = ShutterAppGroup.encodeLook(film: film.name, fx: fx.name)
            if !encoded.contains(token) { encoded.append(token) }
        }
        push(film: filmFilter, fx: lensFX)
        for recipe in LookRecipeStore.shared.recipes {
            push(film: recipe.film, fx: recipe.lensFX)
        }
        // Fallback film-only chips if the user has no active look yet.
        if encoded.isEmpty {
            for name in ["Portra 400", "Tri-X 400", "Velvia 50"] {
                encoded.append(ShutterAppGroup.encodeLook(film: name, fx: nil))
            }
        }
        ShutterAppGroup.defaults.set(Array(encoded.prefix(4)), forKey: "widget.lookNames")
        // Refresh Lock / Home widgets immediately (Release / TestFlight App Group).
        WidgetCenter.shared.reloadAllTimelines()
        if #available(iOS 18.0, *) {
            Task {
                try? await ShutterCameraCaptureIntent.updateAppContext(ctx)
            }
        }
    }

    /// Apply aspect crop then dual-write gallery + Photos.
    private func finishCapturedImage(_ img: UIImage) {
        let framed = img.croppedToAspectMode(aspectRatio)
        lastCapturedImage = framed
        photoCount += 1
        // Gallery publishes only after JPEG + thumb exist. Refreshing before
        // this completion made widget recents one capture behind.
        recordShot(framed) {
            photoCount = gallery.shots.count
            refreshWidgetRecents()
        }
    }

    /// Push the 2 newest unculled frames (+ meta) into the App Group widget stack.
    private func refreshWidgetRecents() {
        ContentView.pushUnculledWidgetRecents(from: gallery)
    }

    /// Shared with CullGallery so rejects drop off the Home Screen stack.
    static func pushUnculledWidgetRecents(from gallery: GalleryStore, marks: FrameMarkStore? = nil) {
        let markStore = marks ?? FrameMarkStore()
        let unculled = gallery.shots
            .sorted { $0.date > $1.date }
            .filter { markStore.state(for: $0.id) != .reject }
            .prefix(ShutterAppGroup.recentThumbnailSlots)
        var frames: [ShutterAppGroup.WidgetRecentFrame] = []
        for shot in unculled {
            guard let img = gallery.thumbnail(for: shot) ?? gallery.image(for: shot) else { continue }
            let meta = ShutterAppGroup.WidgetRecentMeta(
                shotID: shot.id.uuidString,
                capturedAt: shot.date.timeIntervalSince1970,
                iso: shot.iso,
                shutter: shot.shutter,
                aperture: shot.aperture,
                filmFilter: shot.filmFilter,
                lensFX: shot.lensFX,
                focalLength: shot.focalLength,
                mark: markStore.state(for: shot.id).rawValue
            )
            frames.append(.init(image: img, meta: meta))
        }
        ShutterAppGroup.rebuildRecentFrames(frames)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// One-time backfill so widgets aren't blank before the next shutter press.
    private func seedWidgetRecentsIfNeeded() {
        guard ShutterAppGroup.loadRecentThumbnails().isEmpty else { return }
        refreshWidgetRecents()
    }

    private func handleFocusTap(_ viewNorm: CGPoint, devicePoint: CGPoint, in size: CGSize) {
        guard !isLocked else { return }
        Haptics.light()
        camera.setFocus(at: devicePoint)
        isManualFocusEnabled = false
        focusPoint = CGPoint(x: viewNorm.x * size.width, y: viewNorm.y * size.height)
        focusStartEV = exposureValue
        lastExposureHapticStep = halfStopDetent(exposureValue)
        isDraggingExposure = false
        // Local reticle animation via .animation on the preview chrome — not withAnimation
        // (avoids walking the Metal shutter tree).
        showFocusPoint = true
        scheduleFocusHide(after: 2.8)
        // Tap also drops a decaying ripple when a morphic FX is active
        if lensFX.isTouchReactive {
            LensFXEngine.shared.setTouch(
                x: viewNorm.x, y: viewNorm.y,
                force: 0.85, velX: 0, velY: 0,
                active: false
            )
        }
    }

    /// iOS Camera-style sun drag: finger up brightens, down darkens.
    /// Works anywhere on the finder, expanded or collapsed, without a prior tap.
    /// In MANUAL the device ignores exposure bias, so the same drag moves gain
    /// instead — the gesture must never be a silent no-op.
    private func handleExposureDrag(_ translationY: CGFloat, ended: Bool) {
        guard !isLocked else { return }
        let manual = camera.isManualExposure

        if ended {
            focusStartEV = exposureValue
            isDraggingExposure = false
            setScrubEdge(manual ? .iso : .ev, active: false, value: scrubEdgeValue)
            scheduleFocusHide(after: 2.2)
            return
        }

        if !isDraggingExposure {
            focusStartEV = exposureValue
            dragStartISO = isoValue
            lastExposureHapticStep = halfStopDetent(exposureValue)
            // No prior tap — park the sun reticle mid-finder.
            if !showFocusPoint, viewfinderSize.width > 1, viewfinderSize.height > 1 {
                focusPoint = CGPoint(x: viewfinderSize.width / 2, y: viewfinderSize.height / 2)
            }
        }
        isDraggingExposure = true
        showFocusPoint = true

        // ~140pt per stop, up is brighter.
        let stops = -Float(translationY) / 140.0

        if manual {
            let target = Float(dragStartISO) * powf(2, stops)
            let capped = Int(max(camera.minISO, min(camera.maxISO, target)).rounded())
            if capped != isoValue {
                isoValue = capped
                camera.setISO(Float(capped))
            }
            exposureDetentHaptic(stops)
            setScrubEdge(.iso, active: true, value: "\(capped)")
        } else {
            let newEV = max(camera.minExposure, min(camera.maxExposure, focusStartEV + stops))
            exposureValue = newEV
            camera.setExposure(newEV)
            exposureDetentHaptic(newEV)
            setScrubEdge(.ev, active: true, value: String(format: "%+.1f", newEV))
        }
        scheduleFocusHide(after: 2.8)
    }

    /// Half-stop detents — the arch reads in half stops, so the finger should too.
    private func halfStopDetent(_ stops: Float) -> Int {
        Int((stops / 0.5).rounded())
    }

    private func exposureDetentHaptic(_ stops: Float) {
        let detent = halfStopDetent(stops)
        guard detent != lastExposureHapticStep else { return }
        lastExposureHapticStep = detent
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func scheduleFocusHide(after delay: TimeInterval) {
        focusHideWorkItem?.cancel()
        let work = DispatchWorkItem {
            if !isDraggingExposure {
                showFocusPoint = false
            }
        }
        focusHideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Viewfinder drag → morph uniforms (Liquid / Chrome / Fisheye / Kaleido).
    private func handleMorphTouch(_ point: CGPoint, velocity: CGPoint, active: Bool) {
        guard !isLocked, lensFX.isTouchReactive else { return }
        // Focus/EV scrub owns the gesture while the reticle is up
        guard !showFocusPoint, !isDraggingExposure else { return }
        let force: CGFloat = active ? 1.0 : max(0.35, min(1.0, hypot(velocity.x, velocity.y) * 0.12))
        LensFXEngine.shared.setTouch(
            x: point.x,
            y: point.y,
            force: force,
            velX: velocity.x,
            velY: velocity.y,
            active: active
        )
    }

    // Vertical swipe that collapses/expands a control deck.
    // For the top deck a swipe up collapses; for the bottom deck a swipe down does.
    private func deckSwipe(
        collapseOnSwipeUp: Bool,
        minDistance: CGFloat = 20,
        verticalBias: CGFloat = 1.15,
        set: @escaping (Bool) -> Void
    ) -> some Gesture {
        DragGesture(minimumDistance: minDistance)
            .onEnded { value in
                let dy = value.translation.height
                let dx = value.translation.width
                let threshold = max(30, minDistance * 0.6)
                // Require vertical dominance so scrubbers don't flip deck state.
                guard abs(dy) > abs(dx) * verticalBias else { return }
                withAnimation(ShutterMotion.deck) {
                    if dy < -threshold {
                        set(collapseOnSwipeUp)
                    } else if dy > threshold {
                        set(!collapseOnSwipeUp)
                    }
                }
            }
    }

    // MARK: - Viewfinder chrome

    @ViewBuilder
    private func viewfinderFrame(showHistogram: Bool = true) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: bottomCollapsed ? 10 : 8)
                .fill(Color.black)

            ZStack {
                GeometryReader { vfGeo in
                    FilteredCameraPreview(
                        session: camera.session,
                        livePreview: camera.livePreview,
                        onTap: { viewNorm, devicePOI in
                            handleFocusTap(viewNorm, devicePoint: devicePOI, in: vfGeo.size)
                        },
                        onPinch: { scale in
                            guard !isLocked else { return }
                            Haptics.light()
                            let requested = zoomValue * scale
                            // Sync UI to what the device actually accepted (min is often 1.0).
                            zoomValue = camera.setZoom(requested)
                            // Focus and zoom are independent — never write zoom into FOCUS.
                        },
                        onMorphTouch: handleMorphTouch,
                        // iOS Camera sun-drag anytime unlocked — no prior tap needed, and
                        // MANUAL is allowed too (the handler moves gain instead of bias).
                        exposureDragEnabled: !isLocked,
                        onExposureDrag: handleExposureDrag,
                        onCompareHold: { holding in
                            showingCleanCompare = holding
                            camera.previewLooksBypassed = holding
                            if holding { Haptics.light() }
                        }
                    )
                    .frame(width: vfGeo.size.width, height: vfGeo.size.height)
                    // Hard-stop inherited animations — Metal shutter args must stay constant.
                    .transaction { $0.animation = nil }
                    .onAppear { viewfinderSize = vfGeo.size }
                    .onChange(of: vfGeo.size) { _, size in viewfinderSize = size }

                    if showFocusPoint || isDraggingExposure {
                        FocusExposureReticle(exposureBias: exposureValue)
                            .position(focusPoint)
                            .allowsHitTesting(false)
                            .transition(
                                .opacity.combined(with: .scale(scale: 1.06))
                            )
                    }
                }
                .animation(
                    showFocusPoint ? ShutterMotion.reticleIn : ShutterMotion.reticleOut,
                    value: showFocusPoint
                )

                ViewfinderVignette()

                Group {
                    if timerCountdown > 0 {
                        Text("\(timerCountdown)")
                            .font(.system(size: 80, weight: .thin, design: .monospaced))
                            .foregroundColor(.white.opacity(0.9))
                            .contentTransition(.numericText())
                            .id(timerCountdown)
                            .transition(.opacity.combined(with: .scale(scale: 1.12)))
                            .allowsHitTesting(false)
                    }
                }
                .animation(ShutterMotion.tick, value: timerCountdown)

                Group {
                    if camera.isLongExposureCapturing {
                        LongExposureProgressOverlay(
                            progress: camera.longExposureProgress,
                            pathLabel: camera.longExposurePathLabel,
                            onCancel: { handleCapture() }
                        )
                        .transition(.opacity)
                    }
                }
                .animation(ShutterMotion.chrome, value: camera.isLongExposureCapturing)

                Group {
                    if showingCleanCompare {
                        Text("CLEAN")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.black.opacity(0.55)))
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .padding(.top, 56)
                            .transition(.opacity)
                            .allowsHitTesting(false)
                    }
                }
                .animation(ShutterMotion.press, value: showingCleanCompare)

                // Trailing-edge peel: collapse ƒ theater, or active scrub vibe (Build 71).
                if let edge = activeEdgeReadout {
                    CurvedParamEdgeReadout(
                        title: edge.title,
                        value: edge.value,
                        subtitle: edge.subtitle,
                        progress: edge.progress,
                        serifValue: edge.serif
                    )
                    .padding(.vertical, 36)
                    .padding(.trailing, 2)
                    .allowsHitTesting(false)
                    .zIndex(6)
                    .transition(.opacity)
                    .animation(ShutterMotion.scrub, value: edge.value)
                    .animation(ShutterMotion.deck, value: edge.progress)
                }

                // Histogram inside frame only when expanded — sits above the deck
                // (deck is a separate VStack sibling below the viewfinder, not overlaid).
                if showHistogram {
                    VStack {
                        Spacer().allowsHitTesting(false)
                        LiveExposureChrome(
                            isManualExposure: camera.isManualExposure,
                            isoOverride: isoValue,
                            shutterOverride: shutterSpeeds[safeShutterSpeedIndex]
                        ) { liveISO, liveShutter in
                            RefractiveGlassInfoBar(
                                iso: liveISO,
                                shutterSpeed: liveShutter,
                                aperture: apertureValue,
                                photoCount: photoCount,
                                exposureValue: exposureValue,
                                captureFormat: captureFormat,
                                aspectLabel: aspectRatio.shortLabel,
                                isLocked: isLocked,
                                isManualExposure: camera.isManualExposure,
                                naturalCapture: naturalCapture,
                                showLevel: showLevel,
                                onToggleLock: { toggleAEAFLock() },
                                onReturnToAuto: { returnToAuto() }
                            )
                        }
                        .padding(.horizontal, 8)
                        // Keep clear of the viewfinder bottom edge / swipe strip so it
                        // never reads as overlapping the expanded shutter row below.
                        .simultaneousGesture(bottomDeckSwipe)
                        .padding(.bottom, CollapsedChrome.expandedHistogramBottomPad)
                        .transition(
                            .asymmetric(
                                insertion: .opacity.combined(with: .offset(y: 8)),
                                removal: .opacity.combined(with: .offset(y: 6))
                            )
                        )
                    }
                    .zIndex(5)
                }


                // Chrome moved to parent ZStack (above collapsed fade) so FX stays tappable.

                // Inner inset shadows — never steal focus / film / FX hits
                VStack(spacing: 0) {
                    LinearGradient(colors: [Color.black.opacity(0.6), Color.clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 12)
                    Spacer()
                }
                .allowsHitTesting(false)
                HStack(spacing: 0) {
                    LinearGradient(colors: [Color.black.opacity(0.5), Color.clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 10)
                    Spacer()
                }
                .allowsHitTesting(false)
                VStack(spacing: 0) {
                    Spacer()
                    LinearGradient(colors: [Color.clear, Color.white.opacity(0.03)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 6)
                }
                .allowsHitTesting(false)
                HStack(spacing: 0) {
                    Spacer()
                    LinearGradient(colors: [Color.clear, Color.white.opacity(0.02)], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 4)
                }
                .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: bottomCollapsed ? 8 : 6))
            .padding(bottomCollapsed ? 1 : 2)

            RoundedRectangle(cornerRadius: bottomCollapsed ? 8 : 6)
                .stroke(Color(hex: "333333"), lineWidth: 0.5)
                .padding(bottomCollapsed ? 1 : 2)
        }
    }

    /// Compact shutter row — gradient runs UNDER the controls (not only above them).
    private func collapsedBottomOverlay(safeBottom: CGFloat, compact: Bool = false) -> some View {
        let bottomPad = CollapsedChrome.bottomPad(safeBottom: safeBottom)
        let deckH = compact ? CollapsedChrome.landscapeDeckHeight : CollapsedChrome.deckHeight
        let underlayHeight = CollapsedChrome.fadeHeight + deckH + bottomPad

        return VStack(spacing: 0) {
            Spacer(minLength: 0)
                .allowsHitTesting(false)

            ZStack(alignment: .bottom) {
                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.black.opacity(0.35),
                        Color.black.opacity(0.75),
                        Color.black.opacity(0.92)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: underlayHeight)
                .allowsHitTesting(false)

                VStack(spacing: 0) {
                    // Visual fade only — never a hit sink over the glass bar L/A.
                    Color.clear
                        .frame(height: CollapsedChrome.fadeHeight)
                        .frame(maxWidth: .infinity)
                        .allowsHitTesting(false)

                    bottomCompactDeck(compact: compact)
                        .frame(height: deckH)
                        .offset(y: bottomDeckDrag * 0.12)
                        .opacity(1.0 - min(abs(bottomDeckDrag) / 90.0, 0.45))
                        .contentShape(Rectangle())
                        .simultaneousGesture(bottomDeckSwipe)

                    Color.clear
                        .frame(height: bottomPad)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .simultaneousGesture(bottomDeckSwipe)
                }
            }
            .frame(height: underlayHeight)
            .allowsHitTesting(true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    /// Bottom deck: swipe down collapses, swipe up expands.
    private var bottomDeckSwipe: some Gesture {
        DragGesture(minimumDistance: 16, coordinateSpace: .local)
            .onChanged { value in
                let dy = value.translation.height
                let dx = value.translation.width
                // Stronger vertical bias so ISO/shutter scrubs don't collapse the deck.
                guard abs(dy) > abs(dx) * 1.6 else { return }
                // Use visible collapsed state (landscape forces compact chrome).
                let collapsed = bottomCollapsed
                if collapsed {
                    bottomDeckDrag = min(0, max(dy, -160))
                } else {
                    bottomDeckDrag = max(0, min(dy, 160))
                }
            }
            .onEnded { value in
                let dy = value.translation.height
                let dx = value.translation.width
                let predicted = value.predictedEndTranslation.height
                let effective: CGFloat = {
                    guard abs(dy) > 8, abs(predicted) > abs(dy) else { return dy }
                    return predicted
                }()

                let committedDrag = bottomDeckDrag
                withAnimation(ShutterMotion.deck) {
                    bottomDeckDrag = 0
                    guard abs(effective) > abs(dx) * 1.6 else { return }
                    if bottomCollapsed {
                        // Swipe up (negative) expands out of fullscreen finder.
                        if effective < -20 || committedDrag < -18 {
                            bottomCollapsed = false
                        }
                    } else if effective > 28 || committedDrag > 24 {
                        bottomCollapsed = true
                    }
                }
            }
    }

    private func bottomCompactDeck(compact: Bool = false) -> some View {
        // Fullscreen / collapsed — no HEIC/JPEG/RAW chip (expanded deck only).
        HStack(alignment: .center, spacing: 0) {
            ThumbnailPill(image: lastCapturedImage) {
                Haptics.click()
                showPhotoBook = true
            }

            Spacer(minLength: 8)

            ShutterButton(
                isBusy: isCapturing && !isBurstHolding && !burstConsumedTap,
                timerCountdown: timerCountdown,
                longExposureProgress: camera.isLongExposureCapturing
                    ? camera.longExposureProgress
                    : nil,
                allowCancelWhileBusy: camera.isLongExposureCapturing,
                compact: compact,
                burstCount: isBurstHolding ? max(burstCaptured, 1) : 0,
                onBurstStart: holdBurstEnabled ? { beginBurstHold() } : nil,
                onBurstEnd: holdBurstEnabled ? { endBurstHold() } : nil
            ) {
                if burstConsumedTap {
                    burstConsumedTap = false
                    return
                }
                handleCapture()
            }
            .zIndex(2)

            Spacer(minLength: 8)

            WBPill(
                whiteBalanceIndex: $whiteBalanceIndex,
                onChanged: { mode in
                    camera.setWhiteBalance(mode: mode)
                }
            )
        }
        .padding(.horizontal, DS.pageMargin)
        .padding(.vertical, compact ? 4 : 6)
    }

    private var bottomExpandedDeck: some View {
        VStack(spacing: 0) {
            // ROW 1: Zoom control (full width)
            LensRingControl(
                focalLength: $focalLength,
                isoValue: $isoValue,
                onFocalLengthChanged: { fl in
                    if !isCapturing && !camera.isLongExposureCapturing {
                        camera.switchToLens(focalLength: fl)
                    }
                    // Device zoom is often 1.0 on UW/tele — don't invent 0.5/5.0 for pinch.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        zoomValue = camera.zoomFactor
                        if camera.isManualExposure {
                            camera.setISO(Float(isoValue))
                            camera.setShutterSpeed(index: shutterSpeedIndex, iso: Float(isoValue))
                        }
                    }
                },
                onISOChanged: { iso in
                    guard !isLocked else { return }
                    camera.setISO(Float(iso))
                }
            )
            .frame(height: 40)
            .padding(.horizontal, DS.pageMargin)

            Spacer().frame(height: 1)

            // ROW 2: ISO & Shutter side by side
            HStack(spacing: 4) {
                // No arch peel here — that treatment belongs to the viewfinder
                // sun-drag now (Build 81); these scrubbers read their own values.
                ISOScrubberHorizontal(
                    iso: $isoValue,
                    onChanged: { iso in
                        guard !isLocked else { return }
                        let capped = min(iso, max(1, Int(camera.maxISO)))
                        if capped != isoValue { isoValue = capped }
                        camera.setISO(Float(capped))
                    }
                )

                ShutterScrubber(
                    shutterSpeed: $shutterSpeedIndex,
                    onChanged: { idx in
                        guard !isLocked else { return }
                        // Pass UI ISO; shutter and EV stay independent.
                        camera.setShutterSpeed(index: idx, iso: Float(isoValue))
                    }
                )
            }
            .frame(height: 40)
            .padding(.horizontal, DS.pageMargin)

            // Breathing room from scrubbers (Build 72) — flash drops toward the
            // pinned preview/shutter row without inserting gap between them.
            Spacer().frame(height: 10)

            // ROW 3: Flash | Format (true center above shutter) | Settings/Macro/Timer
            ZStack {
                HStack(alignment: .center, spacing: 0) {
                    FlashButtonPill(flashMode: camera.flashMode) {
                        Haptics.click()
                        camera.cycleFlash()
                    }
                    .frame(width: 84, alignment: .leading)

                    Spacer(minLength: 0)

                    // Trio spans exactly one pill width so it lines up with WB below.
                    HStack(spacing: 0) {
                        ModeControl(icon: "gearshape", isActive: showSettings) {
                            Haptics.click()
                            showSettings = true
                        }
                        ModeControl(icon: "camera.macro", isActive: macroEnabled) {
                            Haptics.click()
                            macroEnabled.toggle()
                            if macroEnabled, isLocked {
                                isLocked = false
                                camera.setAEAFLocked(false)
                            }
                            camera.setMacroEnabled(macroEnabled)
                            if macroEnabled {
                                isManualFocusEnabled = false
                            }
                        }
                        ModeControl(icon: "timer", isActive: timerSeconds > 0) {
                            Haptics.click()
                            if timerSeconds == 0 { timerSeconds = 3 }
                            else if timerSeconds == 3 { timerSeconds = 10 }
                            else { timerSeconds = 0 }
                            syncCaptureContextToSystem()
                        }
                    }
                    .frame(width: 84, height: 40, alignment: .trailing)
                }

                FormatTogglePill(format: $captureFormat) { newFormat in
                    captureFormatRaw = newFormat.rawValue
                    switch newFormat {
                    case .heic: camera.captureFormat = .heic
                    case .jpeg: camera.captureFormat = .jpeg
                    case .raw: camera.captureFormat = .raw
                    }
                }
            }
            .padding(.horizontal, DS.pageMargin)
            // Snug onto the bottom row — no extra flash→preview gap.
            .padding(.bottom, -6)
            .contentShape(Rectangle())
            .simultaneousGesture(bottomDeckSwipe)

            // ROW 4: Thumbnail | Shutter | WB — stays put; flash sits just above.
            HStack(alignment: .center, spacing: 0) {
                ThumbnailPill(image: lastCapturedImage) {
                    Haptics.click()
                    showPhotoBook = true
                }

                Spacer(minLength: 8)

                ShutterButton(
                    isBusy: isCapturing && !isBurstHolding && !burstConsumedTap,
                    timerCountdown: timerCountdown,
                    longExposureProgress: camera.isLongExposureCapturing
                        ? camera.longExposureProgress
                        : nil,
                    allowCancelWhileBusy: camera.isLongExposureCapturing,
                    burstCount: isBurstHolding ? max(burstCaptured, 1) : 0,
                    onBurstStart: holdBurstEnabled ? { beginBurstHold() } : nil,
                    onBurstEnd: holdBurstEnabled ? { endBurstHold() } : nil
                ) {
                    if burstConsumedTap {
                        burstConsumedTap = false
                        return
                    }
                    handleCapture()
                }
                .zIndex(2)

                Spacer(minLength: 8)

                WBPill(
                    whiteBalanceIndex: $whiteBalanceIndex,
                    onChanged: { mode in
                        camera.setWhiteBalance(mode: mode)
                    }
                )
            }
            .padding(.horizontal, DS.pageMargin)
            .contentShape(Rectangle())
            .simultaneousGesture(bottomDeckSwipe)
        }
    }

    private func handleCapture() {
        // Volume / hardware must not steal the burst pipeline mid-hold.
        if isBurstHolding { return }
        // Coalesce rapid shutter events (debounce 350 ms) unless cancelling.
        let now = CFAbsoluteTimeGetCurrent()
        let isCancel = camera.isLongExposureCapturing || timerWorkItem != nil || timerCountdown > 0
        if !isCancel, now - lastShutterEventAt < 0.35 { return }
        lastShutterEventAt = now
        // Abort in-flight long exposure (shutter stays enabled during LE).
        if camera.isLongExposureCapturing {
            Haptics.click()
            expectingLECancel = true
            camera.cancelLongExposure()
            isCapturing = false
            showStatusToast("Long exposure cancelled")
            return
        }
        // Second tap during countdown cancels (shutter stays enabled while armed).
        if timerWorkItem != nil || timerCountdown > 0 {
            Haptics.click()
            cancelTimerCountdown()
            showStatusToast("Timer cancelled")
            return
        }
        guard !isCapturing else { return }
        if timerSeconds > 0 {
            // Do NOT set isCapturing — that used to .disabled the shutter and
            // blocked the on-screen cancel path the comment above promises.
            timerCountdown = timerSeconds
            // Freeze touch-reactive morph at arm time so the composition doesn't
            // drift while the countdown runs and the finger lifts off the screen.
            let armFX = lensFX
            frozenMorphTouch = armFX.isTouchReactive
                ? LensFXEngine.shared.snapshotForCapture()
                : nil
            // Freeze the look the preview is showing — changing film/FX mid-countdown
            // used to bake a different (or .none) look than the finder.
            frozenFilmFilter = filmFilter
            frozenLensFX = lensFX
            // Freeze LE intent so shutter-speed changes during countdown don't alter the shot.
            frozenCaptureIsLE = isLongExposureShutterIndex
            frozenLEDuration = longExposureDurationIfAny
            let gen = UUID()
            timerGeneration = gen
            runCountdown(expected: gen)
        } else {
            captureNow()
        }
    }

    private func cancelTimerCountdown() {
        timerGeneration = UUID()
        timerWorkItem?.cancel()
        timerWorkItem = nil
        timerCountdown = 0
        frozenMorphTouch = nil
        frozenFilmFilter = nil
        frozenLensFX = nil
        frozenCaptureIsLE = false
        frozenLEDuration = nil
    }

    private func runCountdown(expected: UUID) {
        guard expected == timerGeneration else { return }
        guard timerCountdown > 0 else {
            timerWorkItem = nil
            captureNow()
            return
        }
        Haptics.light()
        let work = DispatchWorkItem {
            guard expected == self.timerGeneration else { return }
            self.timerCountdown -= 1
            self.runCountdown(expected: expected)
        }
        timerWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func captureNow() {
        isCapturing = true
        Haptics.heavy()
        // Prefer looks frozen at timer arm; otherwise live viewfinder state.
        let shutterFilm = cameraFilmFilter(from: frozenFilmFilter ?? filmFilter)
        let shutterFX = frozenLensFX ?? lensFX
        frozenFilmFilter = nil
        frozenLensFX = nil
        // Force-sync CameraManager so pipeline + bake cannot see stale .none.
        camera.selectedFilmFilter = shutterFilm
        camera.selectedLensFX = shutterFX
        // Only use morph touch if FX is still touch-reactive (may have changed during countdown).
        let morphTouch: MorphTouchState? = {
            guard shutterFX.isTouchReactive else { return nil }
            return frozenMorphTouch ?? LensFXEngine.shared.snapshotForCapture()
        }()
        frozenMorphTouch = nil

        // Use frozen LE intent if timer was armed; otherwise evaluate live.
        let isLongExposure: Bool
        let duration: Double?
        if let d = frozenLEDuration {
            isLongExposure = true
            duration = d
        } else {
            // LE only when manuals are live — AUTO must not inherit a stale Night index.
            isLongExposure = isLongExposureShutterIndex
            duration = longExposureDurationIfAny
        }
        frozenLEDuration = nil
        frozenCaptureIsLE = false

        if isLongExposure, let duration = duration {

            isCapturing = true
            camera.captureLongExposure(
                durationSeconds: duration,
                filmFilter: shutterFilm,
                lensFX: shutterFX,
                morphTouch: morphTouch
            ) { img in
                isCapturing = false
                if let img = img {
                    expectingLECancel = false
                    finishCapturedImage(img)
                } else if expectingLECancel {
                    expectingLECancel = false
                } else {
                    showStatusToast("Capture failed")
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        } else {
            // Normal capture with flash wash (opacity eases via ShutterMotion.flash)
            isCapturing = true
            showFlash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) { showFlash = false }
            camera.capturePhoto(
                filmFilter: shutterFilm,
                lensFX: shutterFX,
                morphTouch: morphTouch
            ) { img in
                isCapturing = false
                if let img = img {
                    finishCapturedImage(img)
                } else {
                    showStatusToast("Capture failed")
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                }
            }
        }
    }

}

// MARK: - Viewfinder Vignette (Subtle corner darkening only)
struct ViewfinderVignette: View {
    var body: some View {
        // Subtle corner vignette for cinematic feel
        RadialGradient(
            colors: [Color.clear, Color.clear, Color.black.opacity(0.15)],
            center: .center,
            startRadius: 100,
            endRadius: 250
        )
        .allowsHitTesting(false)
    }
}

// MARK: - Long Exposure Progress (viewfinder ring during computational LE)
struct LongExposureProgressOverlay: View {
    let progress: Float
    var pathLabel: String = ""
    var onCancel: (() -> Void)? = nil

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .allowsHitTesting(false)

            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 3)
                        .frame(width: 72, height: 72)
                    Circle()
                        .trim(from: 0, to: CGFloat(max(0, min(1, progress))))
                        .stroke(Color.white.opacity(0.9), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .frame(width: 72, height: 72)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.1), value: progress)

                    Text("\(Int((progress * 100).rounded()))%")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                }

                VStack(spacing: 4) {
                    Text("LONG EXPOSURE")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1.5)
                        .foregroundColor(.white.opacity(0.7))
                    if !pathLabel.isEmpty {
                        Text(pathLabel == "HW" ? "HARDWARE" : "STACKED")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.45))
                    }
                }

                if onCancel != nil {
                    Button {
                        onCancel?()
                    } label: {
                        Text("CANCEL")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.white.opacity(0.18)))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }
        }
    }
}

// MARK: - Finder status overlays (toast / Night assist / permission)
/// Pulled out of ContentView so the archive type-checker can finish.
/// Hit-testing rule: never enable a full-bleed wrapper (that ate the shutter
/// with the old Street chip). Only the Night capsule itself is tappable.
struct FinderStatusOverlays: View {
    let safeTop: CGFloat
    let toast: String?
    let nightAssistVisible: Bool
    let cameraError: String?
    let onApplyNight: () -> Void
    let onDismissNight: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            if let toast {
                Text(toast)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.black.opacity(0.72)))
                    .padding(.top, safeTop + 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .allowsHitTesting(false)
                    .zIndex(50)
            }

            if nightAssistVisible {
                // Chip is naturally sized — ZStack(alignment:.top) centers it horizontally.
                // No frame(maxWidth:.infinity) so the transparent space never eats shutter taps.
                HStack(spacing: 10) {
                    Button(action: onApplyNight) {
                        HStack(spacing: 8) {
                            Text("LOW LIGHT")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .tracking(1.2)
                            Text("·")
                                .foregroundColor(.white.opacity(0.35))
                            Text("TAP FOR NIGHT")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        }
                        .foregroundColor(Color(red: 1.0, green: 0.78, blue: 0.35))
                    }
                    Button(action: onDismissNight) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white.opacity(0.45))
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.black.opacity(0.78)))
                .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.6))
                .padding(.top, safeTop + (toast == nil ? 8 : 44))
                .transition(.opacity.combined(with: .move(edge: .top)))
                .zIndex(51)
            }

            if let cameraError {
                CameraPermissionOverlay(message: cameraError) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .zIndex(60)
            }
        }
    }
}

/// Lifecycle onChange bindings — kept off ContentView.body for the type-checker.
private struct ContentViewLifecycle: ViewModifier {
    @ObservedObject var camera: CameraManager
    @Binding var pendingCaptureWhenReady: Bool
    @Binding var focusPeaking: Bool
    @Binding var zebraEnabled: Bool
    var naturalCapture: Bool
    @Binding var captureFormat: CaptureFormat
    @Binding var captureFormatRaw: String
    @Binding var apertureValue: Float
    @Binding var isLocked: Bool
    var filmFilter: FilmFilterMode
    var lensFX: LensFXMode
    var onCapture: () -> Void
    var onClampISO: (Float) -> Void
    var onToast: (String) -> Void
    var onSyncFilm: (FilmFilterMode) -> Void
    var onSyncContext: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: camera.isSessionRunning) { _, running in
                guard running, pendingCaptureWhenReady else { return }
                pendingCaptureWhenReady = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: onCapture)
            }
            .onChange(of: focusPeaking) { _, on in
                camera.focusPeakingEnabled = on
            }
            .onChange(of: zebraEnabled) { _, on in
                camera.zebraEnabled = on
            }
            .onChange(of: camera.lensAperture) { _, value in
                apertureValue = value
            }
            .onChange(of: naturalCapture) { _, on in
                camera.naturalCaptureEnabled = on
            }
            .onChange(of: captureFormat) { _, fmt in
                captureFormatRaw = fmt.rawValue
                switch fmt {
                case .heic: camera.captureFormat = .heic
                case .jpeg: camera.captureFormat = .jpeg
                case .raw: camera.captureFormat = .raw
                }
            }
            .onChange(of: camera.maxISO) { _, maxISO in
                onClampISO(maxISO)
            }
            .onChange(of: camera.captureNote) { _, note in
                guard let note else { return }
                onToast(note)
                camera.captureNote = nil
            }
            .onChange(of: camera.isAEAFLocked) { _, locked in
                isLocked = locked
            }
            .onChange(of: filmFilter) { _, newFilter in
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) {
                    onSyncFilm(newFilter)
                }
                onSyncContext()
            }
            .onChange(of: lensFX) { _, newFX in
                var t = Transaction()
                t.disablesAnimations = true
                withTransaction(t) {
                    camera.selectedLensFX = newFX
                    if !newFX.isTouchReactive {
                        LensFXEngine.shared.clearStickyTouch()
                    }
                }
                onSyncContext()
            }
    }
}

// MARK: - Camera permission / error overlay
struct CameraPermissionOverlay: View {
    let message: String
    let onOpenSettings: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()
            VStack(spacing: 18) {
                Text("CAMERA")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45))
                    .tracking(2)
                Text(message)
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                Text("Enable camera access in Settings to shoot.")
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button(action: onOpenSettings) {
                    Text("OPEN SETTINGS")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.black)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(Color.white))
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
        }
    }
}

// MARK: - Refractive Glass Info Bar (Apple-style Liquid Glass)
struct RefractiveGlassInfoBar: View {
    let iso: Int
    let shutterSpeed: String
    let aperture: Float
    let photoCount: Int
    let exposureValue: Float
    let captureFormat: CaptureFormat
    var aspectLabel: String = "FULL"
    var isLocked: Bool = false
    var isManualExposure: Bool = false
    var naturalCapture: Bool = true
    /// Kept for call-site compatibility; level moved to top AnalogDisplayPanel (Build 73).
    var showLevel: Bool = false
    /// Landscape: denser readout, smaller histogram.
    var compact: Bool = false
    var onToggleLock: (() -> Void)? = nil
    var onReturnToAuto: (() -> Void)? = nil
    /// Isolated from CameraManager so ~2 Hz bin updates don't rebuild the finder.
    @ObservedObject private var histogramBus = HistogramBus.shared

    var body: some View {
        HStack(spacing: compact ? 8 : 10) {
            // Histogram stays its own well
            GlassHistogram(
                exposureValue: exposureValue,
                bins: histogramBus.bins
            )
            .frame(width: compact ? 54 : 70, height: compact ? 32 : 40)

            // Format info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(captureFormat.label)
                        .font(.system(size: compact ? 9 : 10, weight: .medium, design: .monospaced))
                        .foregroundColor(captureFormat == .raw ? DS.accent : .white)
                    if naturalCapture {
                        Text("NAT")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(red: 0.55, green: 0.92, blue: 0.62))
                    }
                    Button {
                        onToggleLock?()
                    } label: {
                        Text("L")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(isLocked ? Color(red: 1.0, green: 0.85, blue: 0.35) : Color.white)
                            )
                            .foregroundColor(.black)
                            .overlay {
                                Color.clear
                                    .frame(width: 44, height: 36)
                                    .contentShape(Rectangle())
                            }
                    }
                    .buttonStyle(.plain)
                    Text(aspectLabel)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                }
                HStack(spacing: 6) {
                    Text(formatNumber(photoCount))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                    // Hardware f-number only — phones can't stop down.
                    if aperture > 0.5 {
                        Text("ƒ\(String(format: "%.1f", aperture))")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.55))
                    }
                }
            }
            .foregroundColor(.white)

            Spacer()

            // ISO & Shutter (level lives in the top panel under EV — Build 73)
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 3) {
                    Button {
                        onReturnToAuto?()
                    } label: {
                        Text("A")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(isManualExposure ? Color(red: 1.0, green: 0.85, blue: 0.35) : Color.white, lineWidth: 0.5)
                            )
                            .foregroundColor(isManualExposure ? Color(red: 1.0, green: 0.85, blue: 0.35) : .white)
                            .overlay {
                                Color.clear
                                    .frame(width: 44, height: 36)
                                    .contentShape(Rectangle())
                            }
                    }
                    .buttonStyle(.plain)
                    Text(isManualExposure ? "ISO \(iso)" : "ISO \(iso)·A")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                }
                Text(isManualExposure ? shutterSpeed : (shutterSpeed == "AUTO" ? "AUTO" : "\(shutterSpeed)·A"))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
            }
            .foregroundColor(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.3))
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
            }
        )
    }

    private func formatNumber(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

// MARK: - Glass Histogram (Clean container — level lives under top EV meter)
struct GlassHistogram: View {
    let exposureValue: Float
    var bins: [Float] = []

    var body: some View {
        ZStack {
            // Clean dark container (no liquid glass borders)
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.5))

            // Histogram bars - real luminance bins from the camera feed,
            // synthetic EV-shifted curve until the first frame arrives
            Canvas { ctx, size in
                let padding: CGFloat = 4
                let barCount = bins.isEmpty ? 40 : bins.count
                let barWidth = (size.width - padding * 2) / CGFloat(barCount)
                let usableH = size.height - padding * 2

                for i in 0..<barCount {
                    let x = padding + CGFloat(i) * barWidth
                    let h: CGFloat
                    if bins.isEmpty {
                        let ev = CGFloat((exposureValue + 2) / 4)
                        let n = CGFloat(i) / CGFloat(barCount)
                        let shifted = n - (ev - 0.5) * 0.4
                        var synth = exp(-pow((shifted - 0.3) * 4, 2)) * 0.85
                        synth += exp(-pow((shifted - 0.7) * 5, 2)) * 0.6
                        h = min(max(synth, 0.03), 1.0)
                    } else {
                        h = min(max(CGFloat(bins[i]), 0.03), 1.0)
                    }
                    let barHeight = usableH * h
                    let rect = CGRect(
                        x: x,
                        y: size.height - padding - barHeight,
                        width: barWidth - 0.5,
                        height: barHeight
                    )
                    ctx.fill(Path(rect), with: .color(.white.opacity(0.8)))
                }
            }
            .padding(2)
        }
    }
}

// MARK: - Responsive Histogram
struct ResponsiveHistogram: View {
    let exposureValue: Float

    var body: some View {
        Canvas { ctx, size in
            let ev = CGFloat((exposureValue + 2) / 4)
            for i in 0..<40 {
                let x = CGFloat(i) * (size.width / 40)
                let n = CGFloat(i) / 40
                let shifted = n - (ev - 0.5) * 0.4
                var h = exp(-pow((shifted - 0.3) * 4, 2)) * 0.85
                h += exp(-pow((shifted - 0.7) * 5, 2)) * 0.6
                h = min(max(h, 0.03), 1.0)
                let barHeight = size.height * h
                let rect = CGRect(x: x, y: size.height - barHeight, width: size.width/40 - 0.5, height: barHeight)
                ctx.fill(Path(rect), with: .color(.white.opacity(0.7)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
        )
    }
}

// MARK: - Controls Grain (DSLR vulcanite texture - more visible)
struct ControlsGrain: View {
    var body: some View {
        // Cached texture — Canvas ellipse storms on every camera publish were laggy.
        GeometryReader { geo in
            Image(uiImage: CachedGrainTexture.image(
                for: geo.size,
                density: 0.008,
                seed: 0xBEEF,
                darkSpeckDensity: 0.002
            ))
            .resizable()
            .interpolation(.none)
            .scaledToFill()
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .allowsHitTesting(false)
        .blendMode(.overlay)
    }
}

// MARK: - Ticker Value (Animated value display)
struct TickerValue: View {
    let values: [String]
    let currentIndex: Int
    let tickerOffset: CGFloat
    let isDragging: Bool
    var itemWidth: CGFloat = 50

    private var currentValue: String {
        guard currentIndex >= 0 && currentIndex < values.count else { return "" }
        return values[currentIndex]
    }

    var body: some View {
        Text(currentValue)
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .foregroundColor(isDragging ? DS.accent : .white)
            .scaleEffect(isDragging ? 1.12 : 1.0)
            .contentTransition(.numericText())
            .animation(ShutterMotion.scrub, value: isDragging)
            .animation(ShutterMotion.scrub, value: currentIndex)
    }
}

// MARK: - Native snap scrubber
/// Classic DSLR chrome (prev | label+value | next + moving ticks) with UIScrollView snap.
struct NativeSnapScrubber<Value: Hashable>: View {
    let label: String
    let values: [Value]
    @Binding var selection: Value
    var suffix: String? = nil
    var sideLabelWidth: CGFloat = 32
    var tickCount: Int = 16
    /// Denser majors for ISO; slightly airier for shutter.
    var tickMajorEvery: Int = 4
    var title: (Value) -> String
    var onChanged: (Value) -> Void
    /// Fires while the scrubber is actively snapping (fullscreen arch vibe).
    var onActiveChanged: ((Bool) -> Void)? = nil

    @State private var scrollID: Value?
    @State private var isScrolling = false
    /// Blocks scrollID↔selection sync until ScrollView finishes first layout (avoids launch animator stack overflow).
    @State private var scrubberReady = false
    /// True while we push an external selection into scrollPosition (must not echo back into onChanged).
    @State private var applyingExternal = false
    /// Cancels stacked isScrolling=false asyncAfters during rapid snaps.
    @State private var scrollGeneration = 0
    /// Film-gate tick phase — advances with each snap for mechanical travel.
    @State private var tickPhase: CGFloat = 0

    private var currentIndex: Int {
        values.firstIndex(of: selection) ?? 0
    }

    private var prevTitle: String {
        currentIndex > 0 ? title(values[currentIndex - 1]) : ""
    }

    private var nextTitle: String {
        currentIndex < values.count - 1 ? title(values[currentIndex + 1]) : ""
    }

    var body: some View {
        GeometryReader { geo in
            let itemWidth = max(36, geo.size.width / 5)
            let sideInset = max((geo.size.width - itemWidth) / 2, 0)

            ZStack {
                // Classic control chrome
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.black)
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(hex: "242424"))
                    .padding(2)
                RoundedRectangle(cornerRadius: 4)
                    .stroke(
                        isScrolling
                            ? DS.accent.opacity(0.55)
                            : Color(hex: "444444"),
                        lineWidth: isScrolling ? 0.9 : 0.5
                    )
                    .padding(2)
                    .animation(ShutterMotion.scrub, value: isScrolling)

                // Soft LCD wash while scrubbing
                if isScrolling {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(DS.accent.opacity(0.07))
                        .padding(2)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                // Moving tick strip — film-gate feel (Build 71).
                // Tick marks — white only; yellow is reserved for the center indicator.
                Canvas { ctx, size in
                    let usableWidth = size.width - 24
                    let spacing = usableWidth / CGFloat(max(tickCount - 1, 1))
                    let centerX = size.width / 2
                    let yellow = Color(red: 1.0, green: 0.85, blue: 0.35)
                    let phase = tickPhase.truncatingRemainder(dividingBy: spacing)

                    // Extra ticks off-screen so scrolling doesn't leave gaps.
                    let extra = 3
                    for i in -extra..<(tickCount + extra) {
                        let x = 12 + CGFloat(i) * spacing - phase
                        guard x >= 4 && x <= size.width - 4 else { continue }
                        let isMajor = abs(i) % tickMajorEvery == 0
                        let h: CGFloat = isMajor ? (isScrolling ? 6.5 : 5) : (isScrolling ? 3.5 : 3)
                        let rect = CGRect(x: x - 0.5, y: size.height - h - 4, width: 1, height: h)
                        let opacity: Double = isScrolling
                            ? (isMajor ? 0.42 : 0.18)
                            : (isMajor ? 0.25 : 0.10)
                        ctx.fill(Path(rect), with: .color(.white.opacity(opacity)))
                    }

                    let indicatorHeight: CGFloat = isScrolling ? 15 : 10
                    let indicatorWidth: CGFloat = isScrolling ? 2.6 : 2
                    let indicatorRect = CGRect(
                        x: centerX - indicatorWidth / 2,
                        y: size.height - indicatorHeight - 2,
                        width: indicatorWidth,
                        height: indicatorHeight
                    )
                    ctx.fill(
                        Path(indicatorRect),
                        with: .color(isScrolling ? yellow : Color.white.opacity(0.7))
                    )
                }
                .allowsHitTesting(false)
                .animation(ShutterMotion.scrub, value: tickPhase)

                // Classic readout: prev | label + value (+suffix) | next
                HStack(spacing: 0) {
                    Text(prevTitle)
                        .font(DS.mono(suffix == nil ? 9 : 9, weight: .medium))
                        .foregroundColor(DS.textSecondary)
                        .frame(width: sideLabelWidth, alignment: .center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .opacity(isScrolling ? 0.85 : 0.4)
                        .offset(x: isScrolling ? -2 : 0)

                    Spacer(minLength: 0)

                    HStack(spacing: suffix == nil ? 2 : 0) {
                        if suffix == nil {
                            Text(label)
                                .font(DS.mono(9, weight: .medium))
                                .foregroundColor(isScrolling ? DS.accent : DS.textSecondary)
                        }

                        Text(title(selection))
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(isScrolling ? DS.accent : .white)
                            .scaleEffect(isScrolling ? 1.12 : 1.0)
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: selection)
                            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isScrolling)

                        if let suffix {
                            Text(suffix)
                                .font(DS.mono(9, weight: .medium))
                                .foregroundColor(isScrolling ? DS.accent : .white)
                        }
                    }

                    Spacer(minLength: 0)

                    Text(nextTitle)
                        .font(DS.mono(suffix == nil ? 9 : 9, weight: .medium))
                        .foregroundColor(DS.textSecondary)
                        .frame(width: sideLabelWidth, alignment: .center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .opacity(isScrolling ? 0.85 : 0.4)
                        .offset(x: isScrolling ? 2 : 0)
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
                .allowsHitTesting(false)

                // Invisible native scroll — keeps UIScrollView physics, hides the strip UI
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(values, id: \.self) { value in
                            Color.clear
                                .frame(width: itemWidth, height: max(geo.size.height, 36))
                                .id(value)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $scrollID)
                .scrollIndicators(.hidden)
                .safeAreaPadding(.horizontal, sideInset)
                .contentShape(Rectangle())
            }
        }
        .onAppear {
            applyingExternal = true
            scrollID = selection
            tickPhase = CGFloat(currentIndex) * 6
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                applyingExternal = false
                scrubberReady = true
            }
        }
        .onChange(of: selection) { _, newValue in
            // External updates only — push into scrollPosition without echoing onChanged
            guard scrubberReady, scrollID != newValue else { return }
            applyingExternal = true
            scrollID = newValue
            if let idx = values.firstIndex(of: newValue) {
                tickPhase = CGFloat(idx) * 6
            }
            DispatchQueue.main.async {
                applyingExternal = false
            }
        }
        .onChange(of: scrollID) { _, newValue in
            guard scrubberReady, !applyingExternal, let newValue, newValue != selection else { return }
            // Apply without nested withAnimation (freezes / MetadataCache blowups)
            scrollGeneration += 1
            let gen = scrollGeneration
            isScrolling = true
            selection = newValue
            onChanged(newValue)
            // After onChanged so parent state (focus/EV/ISO) is current for the arch.
            onActiveChanged?(true)
            if let idx = values.firstIndex(of: newValue) {
                withAnimation(ShutterMotion.scrub) {
                    tickPhase = CGFloat(idx) * 6
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.38) {
                if gen == scrollGeneration {
                    isScrolling = false
                    onActiveChanged?(false)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(title(selection) + (suffix.map { " \($0)" } ?? ""))
        .accessibilityAdjustableAction { direction in
            guard scrubberReady, let idx = values.firstIndex(of: selection) else { return }
            switch direction {
            case .increment:
                if idx + 1 < values.count {
                    let next = values[idx + 1]
                    selection = next
                    onChanged(next)
                }
            case .decrement:
                if idx > 0 {
                    let prev = values[idx - 1]
                    selection = prev
                    onChanged(prev)
                }
            @unknown default:
                break
            }
        }
    }
}

// MARK: - ISO Scrubber Horizontal
struct ISOScrubberHorizontal: View {
    @Binding var iso: Int
    let onChanged: (Int) -> Void
    var onActiveChanged: ((Bool) -> Void)? = nil

    private let isoValues = [100, 200, 400, 800, 1600, 3200, 6400]
    @State private var selection: Int = 800

    var body: some View {
        NativeSnapScrubber(
            label: "ISO",
            values: isoValues,
            selection: $selection,
            sideLabelWidth: 32,
            tickCount: 18,
            tickMajorEvery: 3,
            title: { "\($0)" },
            onChanged: { value in
                if iso != value { iso = value }
                onChanged(value)
            },
            onActiveChanged: onActiveChanged
        )
        .onAppear { selection = nearest(iso, in: isoValues) }
        .onChange(of: iso) { _, newValue in
            let n = nearest(newValue, in: isoValues)
            if selection != n { selection = n }
        }
    }

    private func nearest(_ value: Int, in values: [Int]) -> Int {
        if values.contains(value) { return value }
        return values.min(by: { abs($0 - value) < abs($1 - value) }) ?? value
    }
}

// MARK: - Lens Ring Control
struct LensRingControl: View {
    @Binding var focalLength: Int
    @Binding var isoValue: Int
    let onFocalLengthChanged: (Int) -> Void
    let onISOChanged: (Int) -> Void

    private let focalLengths = [13, 24, 48, 120]
    @State private var selection: Int = 24

    var body: some View {
        NativeSnapScrubber(
            label: "LENS",
            values: focalLengths,
            selection: $selection,
            suffix: "MM",
            sideLabelWidth: 28,
            tickCount: 20,
            title: { "\($0)" },
            onChanged: { fl in
                if focalLength != fl { focalLength = fl }
                onFocalLengthChanged(fl)
                onISOChanged(isoValue)
            }
        )
        .onAppear { selection = nearest(focalLength, in: focalLengths) }
        .onChange(of: focalLength) { _, newValue in
            let n = nearest(newValue, in: focalLengths)
            if selection != n { selection = n }
        }
    }

    private func nearest(_ value: Int, in values: [Int]) -> Int {
        if values.contains(value) { return value }
        return values.min(by: { abs($0 - value) < abs($1 - value) }) ?? value
    }
}

// Scrolling tick marks that move with drag
struct ScrollingTicks: View {
    let offset: CGFloat
    let direction: CGFloat // -1 for left side, 1 for right side

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<12, id: \.self) { i in
                let isMajor = i % 3 == 0
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.white.opacity(isMajor ? 0.35 : 0.15))
                    .frame(width: isMajor ? 3 : 2, height: isMajor ? 14 : 8)
            }
        }
        .offset(x: offset * direction * 0.3)
    }
}

// MARK: - Liquid Glass Zoom Control (Reference Style)
struct LiquidGlassZoomControl: View {
    @Binding var focalLength: Int
    let onFocalLengthChanged: (Int) -> Void

    private let focalLengths = [13, 24, 48, 120]

    @State private var isDragging = false
    @State private var dragOffset: CGFloat = 0
    @State private var startIndex: Int = 0
    @State private var tickerOffset: CGFloat = 0

    private var currentIndex: Int {
        focalLengths.firstIndex(of: focalLength) ?? 0
    }

    var body: some View {
        GeometryReader { geo in
            let _ = geo.size.width // Used for future layout

            ZStack {
                // Solid dark background (matching other controls)
                Capsule()
                    .fill(Color.black)

                // Inner frame
                Capsule()
                    .fill(Color(hex: "1a1a1a"))
                    .padding(2)

                // Inner stroke
                Capsule()
                    .stroke(Color(hex: "333333"), lineWidth: 0.5)
                    .padding(2)

                // Dot indicators on left
                HStack(spacing: 4) {
                    ForEach(0..<currentIndex, id: \.self) { _ in
                        Circle()
                            .fill(Color.white.opacity(isDragging ? 0.5 : 0.3))
                            .frame(width: 4, height: 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 16)

                // Center: Ticker value with MM suffix
                HStack(spacing: 3) {
                    // Animated focal length value using TickerValue (same as ISO)
                    TickerValue(
                        values: focalLengths.map { "\($0)" },
                        currentIndex: currentIndex,
                        tickerOffset: tickerOffset,
                        isDragging: isDragging,
                        itemWidth: 40
                    )

                    Text("MM")
                        .font(DS.mono(9, weight: .medium))
                        .foregroundColor(isDragging ? DS.accent : .white)

                    // Indicator line (yellow when dragging, white at rest)
                    Rectangle()
                        .fill(isDragging ? DS.accent : Color.white.opacity(0.7))
                        .frame(width: isDragging ? 2.5 : 2, height: isDragging ? 16 : 12)
                        .animation(ShutterMotion.scrub, value: isDragging)
                }

                // Dot indicators on right
                HStack(spacing: 4) {
                    ForEach(0..<(focalLengths.count - 1 - currentIndex), id: \.self) { _ in
                        Circle()
                            .fill(Color.white.opacity(isDragging ? 0.5 : 0.3))
                            .frame(width: 4, height: 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 16)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            startIndex = currentIndex
                        }
                        // Horizontal ticker offset for film roll feel
                        tickerOffset = value.translation.width * 0.15

                        let stepWidth: CGFloat = 40
                        let steps = Int(-value.translation.width / stepWidth)
                        let newIndex = max(0, min(focalLengths.count - 1, startIndex + steps))
                        if newIndex != currentIndex {
                            Haptics.light()
                            withAnimation(ShutterMotion.scrub) {
                                focalLength = focalLengths[newIndex]
                            }
                            onFocalLengthChanged(focalLength)
                        }
                    }
                    .onEnded { _ in
                        withAnimation(ShutterMotion.scrub) {
                            isDragging = false
                            tickerOffset = 0
                        }
                    }
            )
        }
    }
}

// MARK: - ISO Slider (Horizontal, Easy to Use)
struct ISOSlider: View {
    @Binding var iso: Int
    let isoValues: [Int]
    let onChanged: (Int) -> Void

    @State private var startIndex: Int = -1

    private var currentIndex: Int {
        isoValues.firstIndex(of: iso) ?? 0
    }

    var body: some View {
        ZStack {
            // Background
            Capsule()
                .fill(Color(white: 0.10))

            // Border
            Capsule()
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)

            HStack(spacing: 4) {
                Text("ISO")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))

                Spacer()

                Text("\(iso)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 10)
        }
        .frame(height: 28)
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { drag in
                    if startIndex < 0 {
                        startIndex = currentIndex
                    }
                    let steps = Int(-drag.translation.width / 20)
                    let newIndex = max(0, min(isoValues.count - 1, startIndex + steps))
                    if newIndex != currentIndex {
                        Haptics.light()
                        iso = isoValues[newIndex]
                        onChanged(iso)
                    }
                }
                .onEnded { _ in
                    startIndex = -1
                }
        )
        .onTapGesture {
            Haptics.click()
            let newIndex = (currentIndex + 1) % isoValues.count
            iso = isoValues[newIndex]
            onChanged(iso)
        }
    }
}

// MARK: - EV Slider (Horizontal, Easy to Use)
struct EVSlider: View {
    @Binding var value: Float
    let onChanged: (Float) -> Void

    @State private var startValue: Float = 0
    @State private var isDragging = false

    var body: some View {
        ZStack {
            // Background
            Capsule()
                .fill(Color(white: 0.10))

            // Border
            Capsule()
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)

            HStack(spacing: 4) {
                Text("EV")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))

                Spacer()

                Text(value >= 0 ? "+\(String(format: "%.1f", value))" : String(format: "%.1f", value))
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(value == 0 ? .white : .yellow)
            }
            .padding(.horizontal, 10)
        }
        .frame(height: 28)
        .contentShape(Rectangle())
        .gesture(
            DragGesture()
                .onChanged { drag in
                    if !isDragging {
                        isDragging = true
                        startValue = value
                    }
                    let delta = Float(-drag.translation.width / 60)
                    let newValue = max(-2, min(2, startValue + delta))
                    let snapped = round(newValue * 2) / 2
                    if snapped != value {
                        Haptics.light()
                        value = snapped
                        onChanged(snapped)
                    }
                }
                .onEnded { _ in
                    isDragging = false
                }
        )
        .onTapGesture(count: 2) {
            Haptics.medium()
            value = 0
            onChanged(0)
        }
    }
}

// Triangle shape for indicator
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Shutter Button (machined steel — bevel + brush)
/// Shader roughness / size / lightPos args are CONSTANT — never animate
/// stitchable Metal params (EXC_BAD_ACCESS / MetadataCache on press & capture).
/// Press travel, busy rings, and timer digits are SwiftUI-only overlays.
struct ShutterButton: View {
    /// True while a still / LE bake owns the pipeline (disables the button).
    var isBusy: Bool = false
    /// Countdown seconds remaining; >0 keeps the button enabled for cancel.
    var timerCountdown: Int = 0
    /// 0…1 while STACK/HW long exposure is running (nil = not in LE).
    var longExposureProgress: Float? = nil
    /// Keep shutter enabled so the user can abort LE.
    var allowCancelWhileBusy: Bool = false
    /// Landscape / short deck — slightly smaller chrome.
    var compact: Bool = false
    /// Frames captured in the current hold-burst (0 = not bursting).
    var burstCount: Int = 0
    /// Hold past threshold → burst (optional).
    var onBurstStart: (() -> Void)? = nil
    var onBurstEnd: (() -> Void)? = nil
    let action: () -> Void

    @GestureState private var burstPressing = false

    private var isTimerArmed: Bool { timerCountdown > 0 }
    private var canCancel: Bool { isTimerArmed || allowCancelWhileBusy }

    var body: some View {
        Button(action: action) {
            ShutterButtonChrome(
                isBusy: isBusy,
                timerCountdown: timerCountdown,
                longExposureProgress: longExposureProgress,
                compact: compact,
                burstCount: burstCount
            )
        }
        // ButtonStyle press feedback — never a DragGesture(minDistance: 0),
        // which stole taps when the expanded deck also owned a swipe gesture.
        .buttonStyle(ShutterPressStyle(armed: canCancel))
        // Busy blocks re-entry; timer/LE cancel stays tappable.
        .disabled(isBusy && !canCancel)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.38)
                .updating($burstPressing) { current, state, _ in
                    state = current
                }
        )
        .onChange(of: burstPressing) { _, pressing in
            guard onBurstStart != nil else { return }
            if pressing {
                onBurstStart?()
            } else {
                onBurstEnd?()
            }
        }
        .accessibilityLabel(
            isTimerArmed ? "Cancel timer"
                : allowCancelWhileBusy ? "Cancel long exposure"
                : "Shutter"
        )
        .accessibilityHint(onBurstStart == nil ? "" : "Hold for burst")
    }
}

private struct ShutterPressStyle: ButtonStyle {
    var armed: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        // Collar stays solid — only the inner face reads `shutterPressed`.
        // No label-wide animation: color interpolation on the whole chrome was the white flash.
        configuration.label
            .environment(\.shutterPressed, configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed {
                    let style: UIImpactFeedbackGenerator.FeedbackStyle = armed ? .rigid : .heavy
                    UIImpactFeedbackGenerator(style: style).impactOccurred(intensity: armed ? 0.75 : 1.0)
                } else if !armed {
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.35)
                }
            }
    }
}

private struct ShutterButtonChrome: View {
    let isBusy: Bool
    let timerCountdown: Int
    let longExposureProgress: Float?
    let compact: Bool
    var burstCount: Int = 0
    @Environment(\.shutterPressed) private var isPressed

    private var outer: CGFloat { compact ? 64 : 76 }
    /// Face diameter — constant. Idle sits proud; press sinks via offset only.
    private var face: CGFloat { compact ? 50 : 60 }
    private var well: CGFloat { compact ? 56 : 66 }
    private var hitPad: CGFloat { compact ? 8 : 10 }

    private var isTimerArmed: Bool { timerCountdown > 0 }
    private var isBursting: Bool { burstCount > 0 }
    private var leProgress: CGFloat {
        CGFloat(max(0, min(1, longExposureProgress ?? 0)))
    }
    private var showLERing: Bool { longExposureProgress != nil }

    /// Accent for armed timer / LE — warm, reads on steel.
    private let armAccent = Color(red: 1.0, green: 0.72, blue: 0.28)
    private let leAccent = Color(red: 1.0, green: 0.42, blue: 0.28)
    /// Warm/neutral burst count — no cyan/blue glow (Build 65).
    private let burstAccent = Color(red: 0.92, green: 0.90, blue: 0.86)

    /// Idle lift — same proud sit the button has always had. An extruded barrel
    /// read as a pill behind a round button, so travel is offset + shading only.
    private var proud: CGFloat { compact ? 1.2 : 1.5 }
    /// How far the face drops into the well on press.
    private var sink: CGFloat { compact ? 5.0 : 6.0 }

    /// Face fill is CONSTANT — never animate gradient stops (that flashed white).
    private var faceFill: RadialGradient {
        RadialGradient(
            colors: [
                Color(red: 0.20, green: 0.21, blue: 0.22),
                Color(red: 0.13, green: 0.14, blue: 0.15),
                Color(red: 0.08, green: 0.09, blue: 0.10)
            ],
            center: UnitPoint(x: 0.38, y: 0.32),
            startRadius: 0,
            endRadius: face * 0.72
        )
    }

    var body: some View {
        ZStack {
            // Outer collar — SOLID. Matte dark steel only. Never moves / never brightens.
            // No isPressed dependency — housing stays put.
            Circle()
                .fill(
                    AngularGradient(
                        colors: [
                            Color(red: 0.20, green: 0.21, blue: 0.22),
                            Color(red: 0.11, green: 0.12, blue: 0.13),
                            Color(red: 0.18, green: 0.19, blue: 0.20),
                            Color(red: 0.09, green: 0.10, blue: 0.11),
                            Color(red: 0.19, green: 0.20, blue: 0.21),
                            Color(red: 0.20, green: 0.21, blue: 0.22)
                        ],
                        center: .center
                    )
                )
                .frame(width: outer, height: outer)
                .overlay {
                    Circle()
                        .stroke(Color.black.opacity(0.80), lineWidth: 1.6)
                }
                // Fixed dark lip — matte steel rim into the well (no bright white).
                .overlay {
                    Circle()
                        .stroke(Color.black.opacity(0.55), lineWidth: 2.2)
                        .padding(compact ? 3.5 : 4.0)
                }
                .shadow(
                    color: (isTimerArmed ? armAccent : showLERing ? leAccent : .clear)
                        .opacity(isTimerArmed || showLERing ? 0.40 : 0),
                    radius: 5,
                    y: 0
                )
                .shadow(color: Color.black.opacity(0.70), radius: 7, y: 3)

            // Deep well — constant dark pit (opacity only, never brightens).
            Circle()
                .fill(Color.black.opacity(isPressed ? 0.95 : 0.82))
                .frame(width: well, height: well)
                .overlay {
                    Circle()
                        .stroke(Color.black.opacity(0.95), lineWidth: 2.2)
                }

            // Inner face — the ONLY moving part. Proud idle → sunk pressed.
            // NO scaleEffect shrink — travel is offset + shading only (Build 78).
            ZStack {
                Circle()
                    .fill(faceFill)
                    .frame(width: face, height: face)

                // Matte rings only — black strokes, never white sheen.
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(Color.black.opacity(0.22), lineWidth: 0.65)
                        .frame(
                            width: face - 12 - CGFloat(i) * (face * 0.16),
                            height: face - 12 - CGFloat(i) * (face * 0.16)
                        )
                }

                // Dark bevel rim — thickens on press for inset depth.
                Circle()
                    .stroke(Color.black.opacity(isPressed ? 0.70 : 0.45), lineWidth: isPressed ? 2.0 : 1.2)
                    .frame(width: face - 1, height: face - 1)

                // Top lip inset shadow — the housing casting onto a sunk face.
                // Only shows while pressed, so the idle silhouette is unchanged.
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.black.opacity(isPressed ? 0.62 : 0),
                                Color.black.opacity(0)
                            ],
                            startPoint: .top,
                            endPoint: .center
                        ),
                        lineWidth: isPressed ? 6 : 0.1
                    )
                    .frame(width: face - 2, height: face - 2)
                    .blur(radius: isPressed ? 1.2 : 0)

                // Press dim — black overlay only (opacity animates; colors stay put).
                Circle()
                    .fill(Color.black.opacity(isPressed ? 0.38 : 0))
                    .frame(width: face, height: face)

                if isBusy && !isTimerArmed {
                    Circle()
                        .fill(Color.black.opacity(0.40))
                        .frame(width: face, height: face)
                }

                if isTimerArmed {
                    Text("\(timerCountdown)")
                        .font(.system(size: compact ? 22 : 26, weight: .semibold, design: .monospaced))
                        .foregroundColor(armAccent)
                        .shadow(color: .black.opacity(0.55), radius: 1, y: 1)
                        .contentTransition(.numericText())
                        .animation(ShutterMotion.tick, value: timerCountdown)
                } else if isBursting {
                    Text("\(burstCount)")
                        .font(.system(size: compact ? 20 : 24, weight: .semibold, design: .monospaced))
                        .foregroundColor(burstAccent)
                        .shadow(color: .black.opacity(0.55), radius: 1, y: 1)
                        .contentTransition(.numericText())
                        .animation(ShutterMotion.tick, value: burstCount)
                }
            }
            // Press-in: face keeps size and drops; the well edge clips the sinking
            // bottom, which is the housing occluding it. Collar never moves.
            // No shrink. No white halo. No brightness shift on fills.
            .offset(y: isPressed ? sink : -proud)
            .shadow(
                color: Color.black.opacity(isPressed ? 0.02 : 0.75),
                radius: isPressed ? 0.5 : 6,
                y: isPressed ? 0 : 4
            )
            .animation(
                isPressed
                    ? .easeOut(duration: 0.055)
                    : .interpolatingSpring(stiffness: 420, damping: 32),
                value: isPressed
            )
            .frame(width: well, height: well)
            .clipShape(Circle())

            // Status rings — collar-relative, not pressed with face.
            if isTimerArmed {
                Circle()
                    .stroke(armAccent.opacity(0.85), lineWidth: 2.25)
                    .frame(width: face + 6, height: face + 6)
                Circle()
                    .stroke(armAccent.opacity(0.25), lineWidth: 4)
                    .frame(width: face + 10, height: face + 10)
            } else if isBursting {
                Circle()
                    .stroke(burstAccent.opacity(0.45), lineWidth: 1.5)
                    .frame(width: face + 6, height: face + 6)
            } else if showLERing {
                Circle()
                    .stroke(leAccent.opacity(0.22), lineWidth: 2.5)
                    .frame(width: face + 8, height: face + 8)
                Circle()
                    .trim(from: 0, to: leProgress)
                    .stroke(
                        leAccent,
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .frame(width: face + 8, height: face + 8)
                    .rotationEffect(.degrees(-90))
                    .animation(ShutterMotion.scrub, value: leProgress)
            } else if isBusy {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    let t = context.date.timeIntervalSinceReferenceDate
                    let spin = t.truncatingRemainder(dividingBy: 1.2) / 1.2
                    let pulse = 0.35 + 0.40 * (0.5 + 0.5 * sin(t * 7))
                    Circle()
                        .trim(from: spin, to: min(1, spin + 0.28))
                        .stroke(
                            armAccent.opacity(pulse * 0.75),
                            style: StrokeStyle(lineWidth: 2.2, lineCap: .round)
                        )
                        .frame(width: face + 8, height: face + 8)
                        .rotationEffect(.degrees(-90))
                }
            }
        }
        .frame(width: outer + hitPad, height: outer + hitPad)
        .contentShape(Circle())
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(ShutterMotion.press, value: configuration.isPressed)
    }
}

// MARK: - Flash Button (Figma exact: 80x42 pill, #2c2c2c fill, #444444 stroke)
struct FlashButtonCompact: View {
    let flashMode: AVCaptureDevice.FlashMode
    let action: () -> Void

    private var iconColor: Color {
        switch flashMode {
        case .off: return Color(hex: "5e5e5e")  // Figma gray
        case .on: return DS.accent
        case .auto: return Color.white
        @unknown default: return Color(hex: "5e5e5e")
        }
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                // Outer shadow frame (Figma: stroke #000000 sw=2)
                Capsule()
                    .fill(Color.black)
                    .frame(width: 80, height: 42)

                // Inner frame (Figma: fill #2c2c2c, r=5, stroke #444444 sw=0.5)
                Capsule()
                    .fill(Color(hex: "242424"))
                    .frame(width: 76, height: 38)

                Capsule()
                    .stroke(Color(hex: "444444"), lineWidth: 0.5)
                    .frame(width: 76, height: 38)

                // Lightning bolt icon (Figma: fill #5e5e5e)
                Image(systemName: "bolt.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(iconColor)
            }
            .frame(width: 80, height: 42)
        }
        .buttonStyle(ProButtonStyle())
    }
}

// MARK: - Flash Button Pill (Figma: 80x42, cornerRadius 100 = true pill)
struct FlashButtonPill: View {
    let flashMode: AVCaptureDevice.FlashMode
    let action: () -> Void

    // Uniform size for flash/thumbnail/WB — tightened (Build 68).
    private let pillWidth: CGFloat = 84
    private let pillHeight: CGFloat = 44

    private var iconColor: Color {
        switch flashMode {
        case .off: return Color(hex: "5e5e5e")
        case .on: return DS.accent
        case .auto: return Color.white
        @unknown default: return Color(hex: "5e5e5e")
        }
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                // Outer dark frame (Figma: pill shape r=100)
                Capsule()
                    .fill(Color.black)
                    .frame(width: pillWidth, height: pillHeight)

                // Inner frame
                Capsule()
                    .fill(Color(hex: "242424"))
                    .frame(width: pillWidth - 4, height: pillHeight - 4)

                // Inner stroke (Figma: #444444)
                Capsule()
                    .stroke(Color(hex: "444444"), lineWidth: 0.5)
                    .frame(width: pillWidth - 4, height: pillHeight - 4)

                Image(systemName: flashIconName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(iconColor)
            }
            .frame(width: pillWidth, height: pillHeight)
        }
        .frame(width: pillWidth, height: pillHeight + 4)
        .contentShape(Rectangle())
        .buttonStyle(ProButtonStyle())
    }

    private var flashIconName: String {
        switch flashMode {
        case .off: return "bolt.slash.fill"
        case .on: return "bolt.fill"
        case .auto: return "bolt.badge.automatic.fill"
        @unknown default: return "bolt.fill"
        }
    }
}

// MARK: - Mode Icon (small icon above button - only icon turns yellow when active)
struct ModeIcon: View {
    let icon: String
    let isActive: Bool

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 13, weight: .regular))
            .foregroundColor(isActive ? DS.accent : Color(hex: "5e5e5e"))
            .frame(width: 16, height: 16)
            .allowsHitTesting(false)
    }
}

// MARK: - Mode control (round key — whole column is the hit target)
struct ModeControl: View {
    let icon: String
    let isActive: Bool
    let action: () -> Void

    /// Round key in the WB/flash pill chrome. Three of these span one pill width
    /// (28pt columns × 3 = 84) with real air between them (Build 79).
    private let key: CGFloat = 20

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.black)
                    .frame(width: key + 3, height: key + 3)

                Circle()
                    .fill(Color(hex: isActive ? "2b2718" : "242424"))
                    .frame(width: key, height: key)

                Circle()
                    .stroke(Color(hex: isActive ? "6b5c2c" : "444444"), lineWidth: 0.5)
                    .frame(width: key, height: key)

                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isActive ? DS.accent : Color(hex: "5e5e5e"))
            }
            // Spaced column — trio matches the WB pill footprint (Build 79).
            .frame(width: 28, height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Mode Button (small dot - gray when off, lighter when on)
struct ModeButton: View {
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ModeButtonChrome(isActive: isActive)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ModeButtonChrome: View {
    let isActive: Bool
    private let size: CGFloat = 16

    var body: some View {
        ZStack {
            Circle()
                .fill(isActive ? Color(red: 0.28, green: 0.28, blue: 0.28) : Color(red: 0.17, green: 0.17, blue: 0.17))
            Circle()
                .stroke(
                    isActive ? Color(red: 0.4, green: 0.4, blue: 0.4) : Color(red: 0.25, green: 0.25, blue: 0.25),
                    lineWidth: 0.5
                )
                .padding(0.25)
        }
        .frame(width: size, height: size)
        .shadow(color: Color(red: 0.03, green: 0.03, blue: 0.03).opacity(0.2), radius: 0.5, x: 0, y: 0.5)
    }
}

// MARK: - Mode Icon Button (Combined for backwards compat)
struct ModeIconButton: View {
    let icon: String
    let isActive: Bool
    let action: () -> Void

    private let size: CGFloat = 22

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.17, green: 0.17, blue: 0.17))

                Circle()
                    .stroke(Color(red: 0.27, green: 0.27, blue: 0.27), lineWidth: 0.5)
                    .padding(0.5)

                if isActive {
                    Circle()
                        .fill(DS.accent.opacity(0.2))
                        .padding(3)
                }
            }
            .frame(width: size, height: size)
            .shadow(color: Color(red: 0.03, green: 0.03, blue: 0.03).opacity(0.25), radius: 1, x: 0, y: 0.8)
            .shadow(color: .black.opacity(0.2), radius: 0.5, x: 0, y: -0.3)
        }
        .buttonStyle(ProButtonStyle())
    }
}

// MARK: - Thumbnail Pill (Figma: 80x42, cornerRadius 27 for rounded rect look)
struct ThumbnailPill: View {
    let image: UIImage?
    let action: () -> Void

    // Uniform size for flash/thumbnail/WB — tightened (Build 68).
    private let pillWidth: CGFloat = 84
    private let pillHeight: CGFloat = 44

    var body: some View {
        Button(action: action) {
            ZStack {
                // Outer dark frame (Figma: r=27)
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.black)
                    .frame(width: pillWidth, height: pillHeight)

                // Inner frame
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color(hex: "242424"))
                    .frame(width: pillWidth - 4, height: pillHeight - 4)

                // Inner stroke
                RoundedRectangle(cornerRadius: 22)
                    .stroke(Color(hex: "444444"), lineWidth: 0.5)
                    .frame(width: pillWidth - 4, height: pillHeight - 4)

                // Image or placeholder
                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: pillWidth - 12, height: pillHeight - 12)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                } else {
                    Image(systemName: "photo.stack")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(Color(hex: "5e5e5e"))
                }
            }
            .frame(width: pillWidth, height: pillHeight)
        }
        .frame(width: pillWidth, height: pillHeight + 4)
        .contentShape(Rectangle())
        .buttonStyle(ProButtonStyle())
    }
}

// MARK: - Format Toggle Pill (HEIC/JPG/RAW toggle)
struct FormatTogglePill: View {
    @Binding var format: CaptureFormat
    let onChanged: (CaptureFormat) -> Void

    private let toggleWidth: CGFloat = 72
    private let toggleHeight: CGFloat = 30

    var body: some View {
        Button(action: {
            Haptics.click()
            format = format.next
            onChanged(format)
        }) {
            ZStack {
                // Outer dark frame (pill shape)
                Capsule()
                    .fill(Color.black)
                    .frame(width: toggleWidth, height: toggleHeight)

                // Inner frame
                Capsule()
                    .fill(Color(hex: "242424"))
                    .frame(width: toggleWidth - 4, height: toggleHeight - 4)

                // Inner stroke
                Capsule()
                    .stroke(Color(hex: "444444"), lineWidth: 0.5)
                    .frame(width: toggleWidth - 4, height: toggleHeight - 4)

                // Format label
                Text(format.label)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(format == .raw ? DS.accent : .white)
            }
            .frame(width: toggleWidth, height: toggleHeight)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Flash Button (Shows current flash mode clearly, with inner shadow)
struct FlashButton: View {
    let flashMode: AVCaptureDevice.FlashMode
    let action: () -> Void

    private var iconName: String {
        switch flashMode {
        case .off: return "bolt.slash.fill"
        case .on: return "bolt.fill"
        case .auto: return "bolt.badge.automatic.fill"
        @unknown default: return "bolt.slash.fill"
        }
    }

    private var iconColor: Color {
        switch flashMode {
        case .off: return DS.textSecondary
        case .on: return DS.accent
        case .auto: return DS.textPrimary
        @unknown default: return DS.textSecondary
        }
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                // Base fill
                Circle()
                    .fill(DS.controlBg)

                // Inner shadow (top darker)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.black.opacity(0.5), Color.clear, Color.white.opacity(0.03)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .padding(2)

                // Outer stroke
                Circle()
                    .stroke(DS.strokeOuter, lineWidth: 1)

                // Inner stroke for depth
                Circle()
                    .stroke(DS.strokeInner, lineWidth: 1)
                    .padding(2)

                // Icon
                Image(systemName: iconName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(iconColor)
            }
            .frame(width: 52, height: 52)
            .shadow(color: Color.black.opacity(0.4), radius: 4, y: 2)
        }
        .buttonStyle(ProButtonStyle())
    }
}

// MARK: - Control Button (Figma-style - stacked strokes, not pure black)
struct ControlButton: View {
    let icon: String
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                // Base fill - not pure black
                Circle()
                    .fill(DS.controlBg)

                // Outer stroke
                Circle()
                    .stroke(DS.strokeOuter, lineWidth: 1)

                // Inner stroke for depth
                Circle()
                    .stroke(DS.strokeInner, lineWidth: 1)
                    .padding(2)

                // Icon
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(active ? .white : DS.textPrimary)
            }
            .frame(width: 52, height: 52)
            .shadow(color: Color.black.opacity(0.4), radius: 4, y: 2)
        }
        .buttonStyle(ProButtonStyle())
    }
}

// Legacy alias
struct ProButton: View {
    let icon: String
    let active: Bool
    let action: () -> Void
    var body: some View {
        ControlButton(icon: icon, active: active, action: action)
    }
}

struct ProButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(ShutterMotion.press, value: configuration.isPressed)
    }
}

struct SkeuomorphicButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(ShutterMotion.press, value: configuration.isPressed)
    }
}

// MARK: - WB Pill (Figma exact: 80x42, r=5, #2c2c2c fill, #444444 stroke)
struct WBPill: View {
    @Binding var whiteBalanceIndex: Int
    let onChanged: (Int) -> Void

    private let wbModes = ["AWB", "SUN", "CLD", "SHD", "TNG", "FLO"]  // Fixed-width abbreviations
    // Uniform size for flash/thumbnail/WB — tightened (Build 68).
    private let pillWidth: CGFloat = 84
    private let pillHeight: CGFloat = 44

    var body: some View {
        Button(action: {
            Haptics.click()
            whiteBalanceIndex = (whiteBalanceIndex + 1) % wbModes.count
            onChanged(whiteBalanceIndex)
        }) {
            ZStack {
                // Outer frame (pill shape)
                Capsule()
                    .fill(Color.black)
                    .frame(width: pillWidth, height: pillHeight)

                // Inner frame
                Capsule()
                    .fill(Color(hex: "242424"))
                    .frame(width: pillWidth - 4, height: pillHeight - 4)

                Capsule()
                    .stroke(Color(hex: "444444"), lineWidth: 0.5)
                    .frame(width: pillWidth - 4, height: pillHeight - 4)

                // Text
                HStack(spacing: 4) {
                    Text("WB")
                        .font(DS.mono(11, weight: .semibold))
                        .foregroundColor(.white)
                    Text(wbModes[whiteBalanceIndex])
                        .font(DS.mono(11, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(width: 28, alignment: .center)  // Fixed width prevents jumping
                }
            }
            .frame(width: pillWidth, height: pillHeight)
        }
        .frame(width: pillWidth, height: pillHeight + 4)
        .contentShape(Rectangle())
        .buttonStyle(ProButtonStyle())
    }
}

// MARK: - Exposure Knob (Easy to use dial)
struct ExposureKnob: View {
    @Binding var value: Float
    let onChanged: (Float) -> Void

    @State private var startValue: Float = 0
    @State private var lastSnapped: Float = 0

    var body: some View {
        VStack(spacing: 4) {
            Text("EV")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))

            ZStack {
                // Knob body with knurled edge texture
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(white: 0.20), Color(white: 0.10)],
                            center: .init(x: 0.35, y: 0.25),
                            startRadius: 0,
                            endRadius: 28
                        )
                    )

                // Knurled edge (grip lines)
                ForEach(0..<24, id: \.self) { i in
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 1, height: 4)
                        .offset(y: -22)
                        .rotationEffect(.degrees(Double(i) * 15))
                }

                // Inner circle
                Circle()
                    .fill(Color(white: 0.12))
                    .frame(width: 34, height: 34)

                // Indicator dot
                Circle()
                    .fill(Color.yellow)
                    .frame(width: 5, height: 5)
                    .offset(y: -18)
                    .rotationEffect(.degrees(Double(value) * 45)) // -2 to +2 = -90 to +90

                // Value display
                Text(value >= 0 ? "+\(String(format: "%.1f", value))" : String(format: "%.1f", value))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
            }
            .frame(width: 54, height: 54)
            .gesture(
                DragGesture()
                    .onChanged { drag in
                        if startValue == 0 && lastSnapped == 0 {
                            startValue = value
                            lastSnapped = value
                        }
                        let delta = Float(-drag.translation.height / 80)
                        let newValue = max(-2, min(2, startValue + delta))
                        let snapped = round(newValue * 2) / 2
                        if snapped != lastSnapped {
                            lastSnapped = snapped
                            value = snapped
                            onChanged(snapped)
                            Haptics.light()
                        }
                    }
                    .onEnded { _ in
                        startValue = 0
                        lastSnapped = 0
                    }
            )
            .onTapGesture(count: 2) {
                Haptics.medium()
                value = 0
                onChanged(0)
            }
        }
    }
}

// MARK: - ISO Knob (Easy to use dial)
struct ISOKnob: View {
    @Binding var iso: Int
    let isoValues: [Int]
    let onChanged: (Int) -> Void

    @State private var startIndex: Int = -1
    @State private var lastIndex: Int = -1

    var body: some View {
        VStack(spacing: 4) {
            Text("ISO")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.4))

            ZStack {
                // Knob body with knurled edge texture
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(white: 0.20), Color(white: 0.10)],
                            center: .init(x: 0.35, y: 0.25),
                            startRadius: 0,
                            endRadius: 28
                        )
                    )

                // Knurled edge (grip lines)
                ForEach(0..<24, id: \.self) { i in
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 1, height: 4)
                        .offset(y: -22)
                        .rotationEffect(.degrees(Double(i) * 15))
                }

                // Inner circle
                Circle()
                    .fill(Color(white: 0.12))
                    .frame(width: 34, height: 34)

                // Value display
                Text("\(iso)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.9))
            }
            .frame(width: 54, height: 54)
            .gesture(
                DragGesture()
                    .onChanged { drag in
                        if startIndex < 0 {
                            startIndex = isoValues.firstIndex(of: iso) ?? 0
                            lastIndex = startIndex
                        }
                        let steps = Int(-drag.translation.height / 40)
                        let newIdx = max(0, min(isoValues.count - 1, startIndex + steps))
                        if newIdx != lastIndex {
                            lastIndex = newIdx
                            iso = isoValues[newIdx]
                            onChanged(iso)
                            Haptics.light()
                        }
                    }
                    .onEnded { _ in
                        startIndex = -1
                        lastIndex = -1
                    }
            )
            .onTapGesture {
                Haptics.click()
                if let idx = isoValues.firstIndex(of: iso) {
                    iso = isoValues[(idx + 1) % isoValues.count]
                    onChanged(iso)
                }
            }
        }
    }
}

// Legacy support
struct SkeuomorphicButton: View {
    let icon: String
    let active: Bool
    let action: () -> Void
    var body: some View {
        ProButton(icon: icon, active: active, action: action)
    }
}

// ApertureDial is defined in AnalogGaugeView.swift

// MARK: - WB Tuner Pill (White Balance Control)
struct WBTunerPill: View {
    @Binding var whiteBalanceIndex: Int
    let onChanged: (Int) -> Void

    private let wbModes = ["AUTO", "SUN", "CLOUD", "SHADE", "LAMP", "FLUO"]

    var body: some View {
        Button(action: {
            Haptics.click()
            whiteBalanceIndex = (whiteBalanceIndex + 1) % wbModes.count
            onChanged(whiteBalanceIndex)
        }) {
            HStack(spacing: 0) {
                // WB label
                Text("WB")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                    .padding(.leading, 12)

                Spacer()

                // Current mode
                Text(wbModes[whiteBalanceIndex])
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(.white)

                Spacer()

                // Knurled texture indicator
                HStack(spacing: 2) {
                    ForEach(0..<4, id: \.self) { _ in
                        Rectangle()
                            .fill(Color.white.opacity(0.2))
                            .frame(width: 1.5, height: 12)
                    }
                }
                .padding(.trailing, 10)
            }
            .frame(width: 130, height: 36)
            .background(
                ZStack {
                    // Base
                    Capsule()
                        .fill(Color(white: 0.08))

                    // Inner shadow (top)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.black.opacity(0.4), Color.clear, Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    // Bevel highlight
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: [Color.white.opacity(0.1), Color.clear, Color.clear, Color.black.opacity(0.2)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                }
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - ISO Badge (Tappable - matches button style)
struct ISOBadge: View {
    @Binding var iso: Int
    let isoValues: [Int]
    let onChanged: (Int) -> Void

    var body: some View {
        Button(action: {
            Haptics.click()
            if let idx = isoValues.firstIndex(of: iso) {
                let newIso = isoValues[(idx + 1) % isoValues.count]
                iso = newIso
                onChanged(newIso)
            }
        }) {
            ZStack {
                // Outer bezel
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(white: 0.06))

                // Inner shadow (top)
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [Color.black.opacity(0.4), Color.clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                    .padding(2)

                // Button face
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.14), Color(white: 0.08)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .padding(3)

                // Highlight rim
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.12), Color.clear, Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                    .padding(3)

                // Content
                VStack(spacing: 1) {
                    Text("ISO")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                    Text("\(iso)")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            .frame(width: 50, height: 44)
            .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
        }
        .buttonStyle(SkeuomorphicButtonStyle())
    }
}

// MARK: - ISO Pill (Figma-style - stacked strokes, inner shadow)
struct ISOPill: View {
    @Binding var iso: Int
    let isoValues: [Int]
    let onChanged: (Int) -> Void

    var body: some View {
        Button(action: {
            Haptics.click()
            if let idx = isoValues.firstIndex(of: iso) {
                let newIso = isoValues[(idx + 1) % isoValues.count]
                iso = newIso
                onChanged(newIso)
            }
        }) {
            HStack(spacing: 2) {
                Text("ISO:")
                    .font(DS.mono(11, weight: .medium))
                    .foregroundColor(DS.textSecondary)
                Text("\(iso)")
                    .font(DS.mono(11, weight: .semibold))
                    .foregroundColor(DS.textPrimary)
                    .frame(width: 36, alignment: .leading)
            }
            .frame(width: 82)
            .padding(.vertical, 12)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: DS.radiusMedium)
                        .fill(DS.controlBg)

                    // Inner shadow
                    RoundedRectangle(cornerRadius: DS.radiusMedium)
                        .fill(
                            LinearGradient(
                                colors: [Color.black.opacity(0.5), Color.clear, Color.white.opacity(0.03)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .padding(2)

                    RoundedRectangle(cornerRadius: DS.radiusMedium)
                        .stroke(DS.strokeOuter, lineWidth: 1)

                    RoundedRectangle(cornerRadius: DS.radiusMedium - 2)
                        .stroke(DS.strokeInner, lineWidth: 1)
                        .padding(2)
                }
            )
            .shadow(color: Color.black.opacity(0.3), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - WB Pill Compact (For stacking)
struct WBPillCompact: View {
    @Binding var whiteBalanceIndex: Int
    let onChanged: (Int) -> Void

    private let wbModes = ["AWB", "SUN", "CLD", "SHD", "TNG", "FLO"]  // Fixed-width text

    var body: some View {
        Button(action: {
            Haptics.click()
            whiteBalanceIndex = (whiteBalanceIndex + 1) % wbModes.count
            onChanged(whiteBalanceIndex)
        }) {
            Text(wbModes[whiteBalanceIndex])
                .font(DS.mono(11, weight: .semibold))
                .foregroundColor(DS.textPrimary)
                .frame(width: 36, alignment: .center)  // Fixed width
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(DS.controlBg)

                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    colors: [Color.black.opacity(0.4), Color.clear, Color.white.opacity(0.02)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .padding(1)

                        RoundedRectangle(cornerRadius: 8)
                            .stroke(DS.strokeOuter, lineWidth: 1)
                    }
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ISO Pill Compact (For stacking)
struct ISOPillCompact: View {
    @Binding var iso: Int
    let isoValues: [Int]
    let onChanged: (Int) -> Void

    var body: some View {
        Button(action: {
            Haptics.click()
            if let idx = isoValues.firstIndex(of: iso) {
                let newIso = isoValues[(idx + 1) % isoValues.count]
                iso = newIso
                onChanged(newIso)
            }
        }) {
            Text("\(iso)")
                .font(DS.mono(11, weight: .semibold))
                .foregroundColor(DS.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(DS.controlBg)

                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    colors: [Color.black.opacity(0.4), Color.clear, Color.white.opacity(0.02)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .padding(1)

                        RoundedRectangle(cornerRadius: 8)
                            .stroke(DS.strokeOuter, lineWidth: 1)
                    }
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - ISO Vertical Scrubber
struct ISOScrubberVertical: View {
    @Binding var iso: Int
    let isoValues: [Int]
    let onChanged: (Int) -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var startIndex: Int = 0

    private var currentIndex: Int {
        isoValues.firstIndex(of: iso) ?? 0
    }

    var body: some View {
        GeometryReader { _ in
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 10)
                    .fill(DS.controlBg)

                // Inner shadow
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [Color.black.opacity(0.4), Color.clear, Color.white.opacity(0.02)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .padding(2)

                // Outer stroke
                RoundedRectangle(cornerRadius: 10)
                    .stroke(DS.strokeOuter, lineWidth: 1)

                // Inner stroke
                RoundedRectangle(cornerRadius: 8)
                    .stroke(DS.strokeInner, lineWidth: 1)
                    .padding(2)

                // Ticks on left side
                Canvas { ctx, size in
                    let tickCount = 20
                    let usableHeight = size.height - 20
                    let spacing = usableHeight / CGFloat(tickCount - 1)
                    let offset = dragOffset * 0.12
                    let startY: CGFloat = 10

                    for i in 0..<tickCount {
                        let y = startY + CGFloat(i) * spacing + offset
                        guard y >= 6 && y <= size.height - 6 else { continue }

                        let isMajor = i % 4 == 0
                        let tickWidth: CGFloat = isMajor ? 5 : 3
                        let opacity = isMajor ? 0.25 : 0.1

                        let rect = CGRect(
                            x: 5,
                            y: y - 0.5,
                            width: tickWidth,
                            height: 1
                        )
                        ctx.fill(Path(rect), with: .color(Color.white.opacity(opacity)))
                    }
                }

                // ISO value and label
                VStack(spacing: 2) {
                    Text("ISO")
                        .font(DS.mono(8, weight: .medium))
                        .foregroundColor(DS.textSecondary)

                    Text("\(iso)")
                        .font(DS.mono(12, weight: .bold))
                        .foregroundColor(DS.textPrimary)
                }

                // Center indicator on right
                HStack {
                    Spacer()
                    Rectangle()
                        .fill(DS.accent)
                        .frame(width: 6, height: 2)
                        .padding(.trailing, 4)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            startIndex = currentIndex
                        }
                        dragOffset = value.translation.height

                        let stepHeight: CGFloat = 25
                        let steps = Int(value.translation.height / stepHeight)
                        let newIndex = max(0, min(isoValues.count - 1, startIndex + steps))

                        if newIndex != currentIndex {
                            Haptics.light()
                            iso = isoValues[newIndex]
                            onChanged(iso)
                        }
                    }
                    .onEnded { _ in
                        isDragging = false
                        withAnimation(ShutterMotion.scrub) {
                            dragOffset = 0
                        }
                    }
            )
        }
    }
}

// MARK: - Shutter Speed Scrubber
struct ShutterScrubber: View {
    @Binding var shutterSpeed: Int
    let onChanged: (Int) -> Void
    var onActiveChanged: ((Bool) -> Void)? = nil

    private let speeds = ["4\"", "2\"", "1\"", "1/2", "1/4", "1/8", "1/15", "1/30", "1/60", "1/125", "1/250", "1/500", "1/1000", "1/2000", "1/4000"]
    private var indices: [Int] { Array(speeds.indices) }
    @State private var selection: Int = 9

    var body: some View {
        NativeSnapScrubber(
            label: "S",
            values: indices,
            selection: $selection,
            sideLabelWidth: 36,
            tickCount: 20,
            tickMajorEvery: 4,
            title: { speeds[$0] },
            onChanged: { idx in
                if shutterSpeed != idx { shutterSpeed = idx }
                onChanged(idx)
            },
            onActiveChanged: onActiveChanged
        )
        .onAppear { selection = min(max(shutterSpeed, 0), speeds.count - 1) }
        .onChange(of: shutterSpeed) { _, newValue in
            let clamped = min(max(newValue, 0), speeds.count - 1)
            if selection != clamped { selection = clamped }
        }
    }
}

// MARK: - Thumbnail View (Figma-style - stacked strokes)
struct ThumbnailView: View {
    let image: UIImage?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Frame background
                RoundedRectangle(cornerRadius: 10)
                    .fill(DS.controlBg)

                // Inner shadow
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [Color.black.opacity(0.4), Color.clear, Color.white.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .padding(2)

                // Outer stroke
                RoundedRectangle(cornerRadius: 10)
                    .stroke(DS.strokeOuter, lineWidth: 1)

                // Inner stroke
                RoundedRectangle(cornerRadius: 8)
                    .stroke(DS.strokeInner, lineWidth: 1)
                    .padding(2)

                // Image or placeholder
                Group {
                    if let img = image {
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 20))
                            .foregroundColor(DS.textSecondary)
                    }
                }
                .frame(width: geo.size.width - 10, height: geo.size.height - 10)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .shadow(color: Color.black.opacity(0.3), radius: 4, y: 2)
    }
}

// MARK: - Film Strip Thumbnail (Pill with stacked image effect)
struct FilmStripThumbnail: View {
    let image: UIImage?

    var body: some View {
        ZStack {
            // Pill background
            Capsule()
                .fill(DS.controlBg)

            // Inner shadow
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color.black.opacity(0.4), Color.clear, Color.white.opacity(0.02)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .padding(2)

            // Outer stroke
            Capsule()
                .stroke(DS.strokeOuter, lineWidth: 1)

            // Inner stroke
            Capsule()
                .stroke(DS.strokeInner, lineWidth: 1)
                .padding(2)

            HStack(spacing: 0) {
                // Left side: Stacked frames indicator
                ZStack {
                    // Background frames (stacked effect)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 28, height: 36)
                        .offset(x: -4, y: 0)
                        .rotationEffect(.degrees(-6))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 28, height: 36)
                        .offset(x: -2, y: 0)
                        .rotationEffect(.degrees(-3))

                    // Front frame
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.18))
                        .frame(width: 28, height: 36)
                }
                .frame(width: 44)
                .clipped()

                // Divider line
                Rectangle()
                    .fill(DS.strokeOuter)
                    .frame(width: 1, height: 40)

                // Right side: Actual image preview
                Group {
                    if let img = image {
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle()
                            .fill(Color.white.opacity(0.05))
                            .overlay(
                                Image(systemName: "photo")
                                    .font(.system(size: 16))
                                    .foregroundColor(DS.textSecondary)
                            )
                    }
                }
                .frame(width: 60, height: 44)
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 0,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 20,
                        topTrailingRadius: 20
                    )
                )
                .padding(.trailing, 4)
            }
        }
        .frame(width: 120, height: 54)
        .shadow(color: Color.black.opacity(0.4), radius: 5, y: 2)
    }
}

// MARK: - Focus + exposure reticle (iOS Camera–style)
struct FocusExposureReticle: View {
    let exposureBias: Float

    @State private var scale: CGFloat = 1.25

    /// Sun rides a short vertical track beside the box (up = brighter).
    private var sunOffsetY: CGFloat {
        // Map -2…+2 → +22…-22 (negative Y is up)
        CGFloat(-exposureBias / 2.0) * 22
    }

    var body: some View {
        ZStack {
            FocusBrackets()
                .stroke(Color(red: 1.0, green: 0.84, blue: 0.2), lineWidth: 1.6)
                .frame(width: 72, height: 72)

            // Brightness scrubber — sun + tick rail (drag anywhere on frame to drive EV)
            HStack(spacing: 6) {
                Spacer().frame(width: 72)
                ZStack {
                    Capsule()
                        .fill(Color.white.opacity(0.22))
                        .frame(width: 1.5, height: 44)

                    Image(systemName: "sun.max.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(red: 1.0, green: 0.84, blue: 0.2))
                        .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                        .offset(y: sunOffsetY)
                        .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.85), value: exposureBias)
                }
                .frame(width: 18, height: 52)
            }
        }
        .scaleEffect(scale)
        .animation(ShutterMotion.reticleIn, value: scale)
        .onAppear {
            // Next turn so the scale change animates after the view is mounted.
            DispatchQueue.main.async { scale = 1 }
        }
    }
}

/// Legacy name kept for any call sites / previews.
struct FocusIndicator: View {
    var body: some View {
        FocusExposureReticle(exposureBias: 0)
    }
}

struct FocusBrackets: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let len: CGFloat = 15

        // Top-left
        path.move(to: CGPoint(x: 0, y: len))
        path.addLine(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: len, y: 0))

        // Top-right
        path.move(to: CGPoint(x: rect.width - len, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: len))

        // Bottom-right
        path.move(to: CGPoint(x: rect.width, y: rect.height - len))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: rect.width - len, y: rect.height))

        // Bottom-left
        path.move(to: CGPoint(x: len, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height - len))

        return path
    }
}

#Preview { ContentView() }
