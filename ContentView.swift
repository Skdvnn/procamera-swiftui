import SwiftUI
import UIKit
import AVFoundation

struct Haptics {
    static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func medium() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func heavy() { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
    static func click() { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
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
    @State private var timerSeconds = 0
    @State private var timerCountdown = 0
    @State private var photoCount = 0
    @State private var lastCapturedImage: UIImage?
    @State private var showFlash = false
    @State private var showFocusPoint = false
    @State private var focusPoint: CGPoint = .zero
    /// EV captured when the focus reticle appeared — vertical drag offsets from this.
    @State private var focusStartEV: Float = 0
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
    @State private var captureFormat: CaptureFormat = .heic
    @State private var topCollapsed = false
    /// Deep-link / shortcut capture before the session is up.
    @State private var pendingCaptureWhenReady = false
    @State private var timerWorkItem: DispatchWorkItem?
    /// Start fullscreen (shutter docked at bottom) — swipe up to expand controls.
    @State private var bottomCollapsed = true
    /// Live vertical drag on the bottom deck (positive = pulling down / collapsing).
    @State private var bottomDeckDrag: CGFloat = 0
    @StateObject private var gallery = GalleryStore()
    @StateObject private var volumeShutter = VolumeShutterObserver()
    @State private var showPhotoBook = false
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

    /// Shared collapsed chrome metrics — histogram floats above fade/deck.
    private enum CollapsedChrome {
        static let deckHeight: CGFloat = 88
        static let landscapeDeckHeight: CGFloat = 72
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

    private var deckCollapseSpring: Animation {
        .spring(response: 0.52, dampingFraction: 0.92)
    }

    var body: some View {
        GeometryReader { geo in
            let safeTop = geo.safeAreaInsets.top
            let safeBottom = geo.safeAreaInsets.bottom
            let isLandscape = geo.size.width > geo.size.height
            // Landscape: keep the top dial compact. Bottom deck can expand —
            // trapping it collapsed made swipe-up feel broken.
            let effectiveTopCollapsed = topCollapsed || isLandscape
            let effectiveBottomCollapsed = bottomCollapsed

            // Layout measurements — top collapse keeps FOCUS/EV strip as the hero
            let topPanelHeight: CGFloat = effectiveTopCollapsed ? (isLandscape ? 44 : 52) : 110
            let gaugeToViewfinderSpacing: CGFloat = effectiveTopCollapsed ? 4 : 5
            let viewfinderToControlsSpacing: CGFloat = CollapsedChrome.viewfinderToDeckGap

            ZStack(alignment: .top) {
                // Diamond/crosshatch texture background like Leica camera grip
                LeicaVulcaniteTexture(scale: 20, intensity: 0.8).ignoresSafeArea()

                VStack(spacing: 0) {
                    // TOP: Analog Display Panel — FOCUS/EV when compact
                    AnalogDisplayPanel(
                        focusPosition: $focusPosition,
                        exposureValue: $exposureValue,
                        shutterSpeedIndex: $shutterSpeedIndex,
                        timerSeconds: timerSeconds,
                        iso: isoValue,
                        flashMode: camera.flashMode == .off ? "OFF" : "ON",
                        macroEnabled: macroEnabled,
                        isAutoFocus: !isManualFocusEnabled,
                        compact: effectiveTopCollapsed,
                        onFocusChanged: { val in
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
                    .frame(height: topPanelHeight)
                    .padding(.horizontal, DS.pageMargin)
                    // Higher threshold when dials are out so vertical dial drags
                    // don't collapse the top deck.
                    .simultaneousGesture(
                        deckSwipe(
                            collapseOnSwipeUp: true,
                            minDistance: effectiveTopCollapsed ? 20 : 56
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
                            RefractiveGlassInfoBar(
                                iso: isoValue,
                                shutterSpeed: shutterSpeeds[shutterSpeedIndex],
                                aperture: apertureValue,
                                photoCount: photoCount,
                                exposureValue: exposureValue,
                                captureFormat: captureFormat,
                                aspectLabel: aspectRatio.shortLabel,
                                isLocked: isLocked,
                                isManualExposure: camera.isManualExposure,
                                naturalCapture: naturalCapture,
                                compact: isLandscape,
                                onToggleLock: { toggleAEAFLock() },
                                onReturnToAuto: { returnToAuto() }
                            )
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
                                    insertion: .opacity.combined(with: .offset(y: 10)),
                                    removal: .opacity
                                )
                            )
                            .zIndex(2)

                            collapsedBottomOverlay(safeBottom: safeBottom, compact: isLandscape)
                                // Fill the finder and pin chrome to the bottom edge —
                                // without this the shutter can float mid-frame.
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                                .transition(
                                    .asymmetric(
                                        insertion: .opacity.combined(with: .offset(y: 14)),
                                        removal: .opacity.combined(with: .offset(y: 16))
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
                            onSaveLook: {
                                LookRecipeStore.shared.saveCurrent(film: filmFilter, lensFX: lensFX)
                                Haptics.medium()
                            },
                            shootMode: ShootMode(rawValue: shootModeRaw) ?? .street,
                            onApplyShootMode: { applyShootMode($0) }
                        )
                        .padding(.horizontal, effectiveBottomCollapsed ? 6 : DS.pageMargin)
                        .zIndex(5)

                        if showLevel {
                            HorizonLevelIndicator()
                                .padding(.top, 18)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                                .allowsHitTesting(false)
                                .zIndex(35)
                        }

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
                                insertion: .opacity.combined(with: .offset(y: 12)),
                                removal: .opacity.combined(with: .offset(y: 14))
                            )
                        )
                    }
                }
                .padding(.top, safeTop)
                .animation(deckCollapseSpring, value: bottomCollapsed)
                .animation(deckCollapseSpring, value: isLandscape)

                if showFlash {
                    Color.white.ignoresSafeArea()
                }
            }
            .ignoresSafeArea()
            .onChange(of: isLandscape) { _, landscape in
                // Landscape uses compact chrome; remember portrait expanded state separately.
                if landscape {
                    withAnimation(deckCollapseSpring) {
                        bottomDeckDrag = 0
                    }
                }
                let orient = CameraManager.currentInterfaceOrientation()
                LensFXEngine.shared.setPreviewBufferRotation(
                    PreviewBufferRotation.from(interfaceOrientation: orient)
                )
            }
            .onAppear {
                let orient = CameraManager.currentInterfaceOrientation()
                LensFXEngine.shared.setPreviewBufferRotation(
                    PreviewBufferRotation.from(interfaceOrientation: orient)
                )
            }
        }
        .statusBarHidden(false)
        // Require a second deliberate swipe for the home gesture so drags on
        // the bottom control rows don't accidentally minimize the app
        .defersSystemGestures(on: .bottom)
        .id(colorScheme)  // Force redraw on color scheme change
        .onAppear {
            camera.checkPermissions()
            // Sync initial filter state
            syncFilmFilter(filmFilter)
            camera.selectedLensFX = lensFX
            camera.focusPeakingEnabled = focusPeaking
            camera.zebraEnabled = zebraEnabled
            photoCount = gallery.shots.count
            if let last = gallery.shots.last, let img = gallery.thumbnail(for: last) ?? gallery.image(for: last) {
                lastCapturedImage = img
            }
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
                guard !showPhotoBook, !showSettings else { return }
                handleCapture()
            }
            // Attach offscreen volume view to key window when available.
            DispatchQueue.main.async {
                let host = UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .flatMap(\.windows)
                    .first { $0.isKeyWindow }
                volumeShutter.start(in: host)
            }
            syncCaptureContextToSystem()
            // Next main turn: `.onReceive` below is installed; then drain the queue.
            DispatchQueue.main.async {
                ShutterDeepLinkCenter.beginReceiving()
            }
        }
        .onDisappear {
            volumeShutter.stop()
            ShutterDeepLinkCenter.endReceiving()
            cancelTimerCountdown()
        }
        .onReceive(NotificationCenter.default.publisher(for: .shutterDeepLink)) { note in
            if let link = note.userInfo?["link"] as? ShutterDeepLink {
                applyDeepLink(link)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .shutterHardwareShutter)) { _ in
            guard !showPhotoBook, !showSettings else { return }
            handleCapture()
        }
        .onChange(of: camera.isSessionRunning) { _, running in
            guard running, pendingCaptureWhenReady else { return }
            pendingCaptureWhenReady = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                handleCapture()
            }
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
        .onChange(of: camera.isAEAFLocked) { _, locked in
            isLocked = locked
        }
        .onChange(of: filmFilter) { _, newFilter in
            // Apply without inheriting any animation transaction into camera chrome.
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                syncFilmFilter(newFilter)
            }
            syncCaptureContextToSystem()
        }
        .onChange(of: lensFX) { _, newFX in
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                camera.selectedLensFX = newFX
                if !newFX.isTouchReactive {
                    LensFXEngine.shared.setTouch(x: 0.5, y: 0.5, force: 0, velX: 0, velY: 0, active: false)
                }
            }
            syncCaptureContextToSystem()
        }
        .fullScreenCover(isPresented: $showPhotoBook, onDismiss: {
            // Resync after Darkroom deletes / cull finish.
            photoCount = gallery.shots.count
            if let last = gallery.shots.last,
               let img = gallery.thumbnail(for: last) ?? gallery.image(for: last) {
                lastCapturedImage = img
            } else {
                lastCapturedImage = nil
            }
        }) {
            CullLibraryView(store: gallery)
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
                onDismiss: {
                    captureFormatRaw = captureFormat.rawValue
                    switch captureFormat {
                    case .heic: camera.captureFormat = .heic
                    case .jpeg: camera.captureFormat = .jpeg
                    case .raw: camera.captureFormat = .raw
                    }
                    showSettings = false
                }
            )
        }
    }

    // Bind a captured frame into the Field Book with the live shot settings
    private func recordShot(_ img: UIImage) {
        let manual = camera.isManualExposure
        let metadata = ShotMetadata(
            id: UUID(),
            date: Date(),
            iso: manual ? isoValue : 0,
            shutter: manual ? shutterSpeeds[shutterSpeedIndex] : "AUTO",
            aperture: apertureValue > 0 ? apertureValue : 0,
            ev: exposureValue,
            filmFilter: filmFilter.name,
            lensFX: lensFX.name,
            focalLength: focalLength
        )
        gallery.add(image: img, metadata: metadata)
        // Dual-write to Photos; stash localIdentifier so cull can delete both sides.
        camera.saveToPhotoLibrary(img) { assetID in
            gallery.setPhotosAssetIdentifier(assetID, for: metadata.id)
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
            showGrid = false
            focusPeaking = true
            zebraEnabled = true
            shutterSpeedIndex = 2 // 1"
            isoValue = 1600
            camera.setShutterSpeed(index: 2)
            camera.setISO(1600)
            // Always clear Studio lock when entering Night.
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
            if let fxName,
               let fx = LensFXMode.allCases.first(where: {
                   $0.name.compare(fxName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
               }) {
                lensFX = fx
            } else {
                lensFX = .none
            }
        case .timer(let seconds):
            timerSeconds = [0, 3, 10].contains(seconds) ? seconds : 3
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
        recordShot(framed)
    }

    private func handleFocusTap(_ viewNorm: CGPoint, devicePoint: CGPoint, in size: CGSize) {
        guard !isLocked else { return }
        Haptics.light()
        camera.setFocus(at: devicePoint)
        isManualFocusEnabled = false
        focusPoint = CGPoint(x: viewNorm.x * size.width, y: viewNorm.y * size.height)
        focusStartEV = exposureValue
        lastExposureHapticStep = Int((exposureValue * 10).rounded())
        isDraggingExposure = false
        withAnimation(.easeOut(duration: 0.15)) { showFocusPoint = true }
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
    private func handleExposureDrag(_ translationY: CGFloat, ended: Bool) {
        guard !isLocked, !camera.isManualExposure else { return }
        if !ended {
            isDraggingExposure = true
            showFocusPoint = true
            // ~140pt per EV stop; clamp to device bias range
            let delta = -Float(translationY) / 140.0
            let newEV = max(camera.minExposure, min(camera.maxExposure, focusStartEV + delta))
            let step = Int((newEV * 10).rounded())
            if step != lastExposureHapticStep {
                lastExposureHapticStep = step
                UISelectionFeedbackGenerator().selectionChanged()
            }
            exposureValue = newEV
            camera.setExposure(newEV)
            scheduleFocusHide(after: 2.8)
        } else {
            focusStartEV = exposureValue
            isDraggingExposure = false
            scheduleFocusHide(after: 2.2)
        }
    }

    private func scheduleFocusHide(after delay: TimeInterval) {
        focusHideWorkItem?.cancel()
        let work = DispatchWorkItem {
            withAnimation(.easeOut(duration: 0.25)) {
                if !isDraggingExposure {
                    showFocusPoint = false
                }
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
        set: @escaping (Bool) -> Void
    ) -> some Gesture {
        DragGesture(minimumDistance: minDistance)
            .onEnded { value in
                let dy = value.translation.height
                let threshold = max(30, minDistance * 0.6)
                guard abs(dy) > abs(value.translation.width) * 1.15 else { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
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
                        exposureDragEnabled: showFocusPoint || isDraggingExposure,
                        onExposureDrag: handleExposureDrag,
                        onCompareHold: { holding in
                            showingCleanCompare = holding
                            camera.previewLooksBypassed = holding
                            if holding { Haptics.light() }
                        }
                    )
                    .frame(width: vfGeo.size.width, height: vfGeo.size.height)

                    if showFocusPoint || isDraggingExposure {
                        FocusExposureReticle(exposureBias: exposureValue)
                            .position(focusPoint)
                            .allowsHitTesting(false)
                    }
                }

                ViewfinderVignette()

                if timerCountdown > 0 {
                    Text("\(timerCountdown)")
                        .font(.system(size: 80, weight: .thin, design: .monospaced))
                        .foregroundColor(.white.opacity(0.9))
                        .allowsHitTesting(false)
                }

                if camera.isLongExposureCapturing {
                    LongExposureProgressOverlay(
                        progress: camera.longExposureProgress,
                        pathLabel: camera.longExposurePathLabel
                    )
                }

                if showingCleanCompare {
                    Text("CLEAN")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Color.black.opacity(0.55)))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.top, 56)
                        .allowsHitTesting(false)
                }

                // Curved ƒ readout peels from the trailing edge while scrubbing down.
                if !bottomCollapsed && bottomDeckDrag > 4 && apertureValue > 0.5 {
                    CurvedFStopEdgeReadout(
                        aperture: apertureValue,
                        progress: min(max(bottomDeckDrag / 120.0, 0), 1)
                    )
                    .padding(.vertical, 36)
                    .padding(.trailing, 2)
                    .allowsHitTesting(false)
                    .zIndex(6)
                    .transition(.opacity)
                }

                // Histogram inside frame only when expanded — sits above the deck
                // (deck is a separate VStack sibling below the viewfinder, not overlaid).
                if showHistogram {
                    VStack {
                        Spacer().allowsHitTesting(false)
                        RefractiveGlassInfoBar(
                            iso: isoValue,
                            shutterSpeed: shutterSpeeds[shutterSpeedIndex],
                            aperture: apertureValue,
                            photoCount: photoCount,
                            exposureValue: exposureValue,
                            captureFormat: captureFormat,
                            aspectLabel: aspectRatio.shortLabel,
                            isLocked: isLocked,
                            isManualExposure: camera.isManualExposure,
                            naturalCapture: naturalCapture,
                            onToggleLock: { toggleAEAFLock() },
                            onReturnToAuto: { returnToAuto() }
                        )
                        .padding(.horizontal, 8)
                        // Keep clear of the viewfinder bottom edge / swipe strip so it
                        // never reads as overlapping the expanded shutter row below.
                        .simultaneousGesture(bottomDeckSwipe)
                        .padding(.bottom, CollapsedChrome.expandedHistogramBottomPad)
                    }
                    .zIndex(5)
                }

                if !bottomCollapsed {
                    VStack {
                        Spacer().allowsHitTesting(false)
                        Color.clear
                            .frame(height: 56)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                            .simultaneousGesture(bottomDeckSwipe)
                    }
                    .zIndex(4)
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
                    Color.clear
                        .frame(height: CollapsedChrome.fadeHeight)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())

                    bottomCompactDeck
                        .frame(height: deckH)
                        .offset(y: bottomDeckDrag * 0.12)
                        .opacity(1.0 - min(abs(bottomDeckDrag) / 90.0, 0.45))

                    Color.clear
                        .frame(height: bottomPad)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
            }
            .frame(height: underlayHeight)
            .contentShape(Rectangle())
            // Whole dock is a pull zone; shutter Button still wins taps.
            .simultaneousGesture(bottomDeckSwipe)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    /// Bottom deck: swipe down collapses, swipe up expands.
    private var bottomDeckSwipe: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                let dy = value.translation.height
                let dx = value.translation.width
                guard abs(dy) > abs(dx) * 0.55 else { return }
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
                withAnimation(deckCollapseSpring) {
                    bottomDeckDrag = 0
                    guard abs(effective) > abs(dx) * 0.5 else { return }
                    if bottomCollapsed {
                        // Swipe up (negative) expands out of fullscreen finder.
                        if effective < -14 || committedDrag < -12 {
                            bottomCollapsed = false
                        }
                    } else if effective > 18 || committedDrag > 16 {
                        bottomCollapsed = true
                    }
                }
            }
    }

    private var bottomCompactDeck: some View {
        HStack(alignment: .center, spacing: 0) {
            ThumbnailPill(image: lastCapturedImage) {
                Haptics.click()
                showPhotoBook = true
            }

            Spacer(minLength: 8)

            ShutterButton(isCapturing: isCapturing) {
                Haptics.heavy()
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
        .padding(.vertical, 6)
    }

    private var bottomExpandedDeck: some View {
        VStack(spacing: 0) {
            // ROW 1: Zoom control (full width)
            LensRingControl(
                focalLength: $focalLength,
                isoValue: $isoValue,
                onFocalLengthChanged: { fl in
                    camera.switchToLens(focalLength: fl)
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
            .frame(height: 44)
            .padding(.horizontal, DS.pageMargin)

            Spacer().frame(height: 2)

            // ROW 2: ISO & Shutter side by side
            HStack(spacing: 4) {
                ISOScrubberHorizontal(
                    iso: $isoValue,
                    onChanged: { iso in
                        guard !isLocked else { return }
                        camera.setISO(Float(iso))
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
            .frame(height: 44)
            .padding(.horizontal, DS.pageMargin)

            Spacer().frame(height: 6)

            // ROW 3: Flash | Format | Mode icons+buttons
            HStack(alignment: .center, spacing: 0) {
                FlashButtonPill(flashMode: camera.flashMode) {
                    Haptics.click()
                    camera.cycleFlash()
                }
                .frame(width: 88)

                Spacer()

                FormatTogglePill(format: $captureFormat) { newFormat in
                    captureFormatRaw = newFormat.rawValue
                    switch newFormat {
                    case .heic: camera.captureFormat = .heic
                    case .jpeg: camera.captureFormat = .jpeg
                    case .raw: camera.captureFormat = .raw
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    VStack(spacing: 8) {
                        ModeIcon(icon: "gearshape", isActive: showSettings)
                        ModeButton(isActive: showSettings) {
                            Haptics.click()
                            showSettings = true
                        }
                    }
                    VStack(spacing: 8) {
                        ModeIcon(icon: "camera.macro", isActive: macroEnabled)
                        ModeButton(isActive: macroEnabled) {
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
                    }
                    VStack(spacing: 8) {
                        ModeIcon(icon: "timer", isActive: timerSeconds > 0)
                        ModeButton(isActive: timerSeconds > 0) {
                            Haptics.click()
                            if timerSeconds == 0 { timerSeconds = 3 }
                            else if timerSeconds == 3 { timerSeconds = 10 }
                            else { timerSeconds = 0 }
                        }
                    }
                    VStack(spacing: 8) {
                        ModeIcon(icon: "rectangle.on.rectangle", isActive: showGrid)
                        ModeButton(isActive: showGrid) {
                            Haptics.click()
                            showGrid.toggle()
                        }
                    }
                }
                .frame(width: 120, height: 48)
            }
            .padding(.horizontal, DS.pageMargin)
            .contentShape(Rectangle())
            .simultaneousGesture(bottomDeckSwipe)

            // ROW 4: Thumbnail | Shutter | WB
            HStack(alignment: .center, spacing: 0) {
                ThumbnailPill(image: lastCapturedImage) {
                    Haptics.click()
                    showPhotoBook = true
                }

                Spacer(minLength: 8)

                ShutterButton(isCapturing: isCapturing) {
                    Haptics.heavy()
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
        // Second tap during countdown cancels.
        if timerWorkItem != nil || timerCountdown > 0 {
            cancelTimerCountdown()
            return
        }
        guard !isCapturing else { return }
        if timerSeconds > 0 {
            isCapturing = true
            timerCountdown = timerSeconds
            runCountdown()
        } else {
            captureNow()
        }
    }

    private func cancelTimerCountdown() {
        timerWorkItem?.cancel()
        timerWorkItem = nil
        timerCountdown = 0
        if !camera.isLongExposureCapturing {
            isCapturing = false
        }
    }

    private func runCountdown() {
        guard timerCountdown > 0 else {
            timerWorkItem = nil
            captureNow()
            return
        }
        Haptics.light()
        let work = DispatchWorkItem {
            timerCountdown -= 1
            runCountdown()
        }
        timerWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    private func captureNow() {
        isCapturing = true
        Haptics.heavy()
        // Source of truth is ContentView state (viewfinder pickers). Force-sync
        // and pass explicitly so the still bake cannot see stale .none.
        syncCaptureControlsToCamera()
        let shutterFilm = cameraFilmFilter(from: filmFilter)
        let shutterFX = lensFX
        // Freeze drag-to-morph before the finger leaves the viewfinder for shutter
        let morphTouch = shutterFX.isTouchReactive
            ? LensFXEngine.shared.snapshotForCapture()
            : nil

        // LE only when manuals are live — AUTO must not inherit a stale Night index.
        let isLongExposure = camera.isManualExposure && shutterSpeedIndex <= 3

        if isLongExposure {
            // Use computational long exposure for slow shutter speeds
            let durations: [Double] = [4.0, 2.0, 1.0, 0.5]
            let duration = durations[shutterSpeedIndex]

            isCapturing = true
            camera.captureLongExposure(
                durationSeconds: duration,
                filmFilter: shutterFilm,
                lensFX: shutterFX
            ) { img in
                isCapturing = false
                if let img = img {
                    finishCapturedImage(img)
                }
            }
        } else {
            // Normal capture with flash effect
            isCapturing = true
            showFlash = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { showFlash = false }
            camera.capturePhoto(
                filmFilter: shutterFilm,
                lensFX: shutterFX,
                morphTouch: morphTouch
            ) { img in
                isCapturing = false
                if let img = img {
                    finishCapturedImage(img)
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

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)

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
            }
        }
        .allowsHitTesting(false)
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
    /// Landscape: denser readout, smaller histogram.
    var compact: Bool = false
    var onToggleLock: (() -> Void)? = nil
    var onReturnToAuto: (() -> Void)? = nil
    /// Isolated from CameraManager so ~2 Hz bin updates don't rebuild the finder.
    @ObservedObject private var histogramBus = HistogramBus.shared

    var body: some View {
        HStack(spacing: compact ? 8 : 10) {
            // Histogram in glass container
            GlassHistogram(exposureValue: exposureValue, bins: histogramBus.bins)
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

            // ISO & Shutter
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
                    }
                    .buttonStyle(.plain)
                    Text(isManualExposure ? "ISO \(iso)" : "ISO AUTO")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                }
                Text(isManualExposure ? shutterSpeed : "AUTO")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
            }
            .foregroundColor(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
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

// MARK: - Glass Histogram (Clean container)
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
                    let barHeight = (size.height - padding * 2) * h
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
            .scaleEffect(isDragging ? 1.15 : 1.0)
            .contentTransition(.numericText())
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isDragging)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: currentIndex)
    }
}

// MARK: - Native snap scrubber
/// Classic DSLR chrome (prev | label+value | next + ticks) with UIScrollView snap under the hood.
struct NativeSnapScrubber<Value: Hashable>: View {
    let label: String
    let values: [Value]
    @Binding var selection: Value
    var suffix: String? = nil
    var sideLabelWidth: CGFloat = 32
    var tickCount: Int = 16
    var title: (Value) -> String
    var onChanged: (Value) -> Void

    @State private var scrollID: Value?
    @State private var isScrolling = false
    /// Blocks scrollID↔selection sync until ScrollView finishes first layout (avoids launch animator stack overflow).
    @State private var scrubberReady = false
    /// True while we push an external selection into scrollPosition (must not echo back into onChanged).
    @State private var applyingExternal = false
    /// Cancels stacked isScrolling=false asyncAfters during rapid snaps.
    @State private var scrollGeneration = 0

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
                    .stroke(Color(hex: "444444"), lineWidth: 0.5)
                    .padding(2)

                // Tick marks — yellow majors when active
                Canvas { ctx, size in
                    let usableWidth = size.width - 24
                    let spacing = usableWidth / CGFloat(max(tickCount - 1, 1))
                    let centerX = size.width / 2
                    let yellow = Color(red: 1.0, green: 0.85, blue: 0.35)

                    for i in 0..<tickCount {
                        let x = 12 + CGFloat(i) * spacing
                        guard x >= 6 && x <= size.width - 6 else { continue }
                        let isMajor = i % 4 == 0
                        let h: CGFloat = isMajor ? 5 : 3
                        let rect = CGRect(x: x - 0.5, y: size.height - h - 4, width: 1, height: h)
                        let color: Color = isMajor
                            ? yellow.opacity(isScrolling ? 0.75 : 0.4)
                            : Color.white.opacity(0.12)
                        ctx.fill(Path(rect), with: .color(color))
                    }

                    let indicatorHeight: CGFloat = isScrolling ? 14 : 10
                    let indicatorWidth: CGFloat = isScrolling ? 2.5 : 2
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

                // Classic readout: prev | label + value (+suffix) | next
                HStack(spacing: 0) {
                    Text(prevTitle)
                        .font(DS.mono(suffix == nil ? 9 : 9, weight: .medium))
                        .foregroundColor(DS.textSecondary)
                        .frame(width: sideLabelWidth, alignment: .center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .opacity(isScrolling ? 0.7 : 0.4)

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
                            .contentTransition(.numericText())

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
                        .opacity(isScrolling ? 0.7 : 0.4)
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                if gen == scrollGeneration {
                    isScrolling = false
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

    private let isoValues = [100, 200, 400, 800, 1600, 3200, 6400]
    @State private var selection: Int = 800

    var body: some View {
        NativeSnapScrubber(
            label: "ISO",
            values: isoValues,
            selection: $selection,
            sideLabelWidth: 32,
            tickCount: 16,
            title: { "\($0)" },
            onChanged: { value in
                if iso != value { iso = value }
                onChanged(value)
            }
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
                        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isDragging)
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
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                focalLength = focalLengths[newIndex]
                            }
                            onFocalLengthChanged(focalLength)
                        }
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
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
/// Shader roughness args are CONSTANT — never animate stitchable Metal params
/// (animating them caused EXC_BAD_ACCESS / MetadataCache stack overflow on press & capture).
struct ShutterButton: View {
    let isCapturing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ShutterButtonChrome(isCapturing: isCapturing)
        }
        // ButtonStyle press feedback — never a DragGesture(minDistance: 0),
        // which stole taps when the expanded deck also owned a swipe gesture.
        .buttonStyle(ShutterPressStyle())
        .disabled(isCapturing)
    }
}

private struct ShutterPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.04 : 0)
            .opacity(configuration.isPressed ? 0.94 : 1)
            .shadow(
                color: Color.black.opacity(configuration.isPressed ? 0.35 : 0.55),
                radius: configuration.isPressed ? 2 : 5,
                y: configuration.isPressed ? 1 : 2.5
            )
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed {
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 0.8)
                } else {
                    UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.6)
                }
            }
    }
}

private struct ShutterButtonChrome: View {
    let isCapturing: Bool

    var body: some View {
        ZStack {
            // Knurled collar
            Circle()
                .fill(
                    AngularGradient(
                        colors: [
                            Color(red: 0.50, green: 0.52, blue: 0.56),
                            Color(red: 0.20, green: 0.21, blue: 0.24),
                            Color(red: 0.44, green: 0.46, blue: 0.50),
                            Color(red: 0.16, green: 0.17, blue: 0.20),
                            Color(red: 0.48, green: 0.50, blue: 0.54),
                            Color(red: 0.22, green: 0.23, blue: 0.26),
                            Color(red: 0.50, green: 0.52, blue: 0.56)
                        ],
                        center: .center
                    )
                )
                .frame(width: 76, height: 76)
                .overlay {
                    Circle()
                        .fill(Color(red: 0.33, green: 0.35, blue: 0.39))
                        .colorEffect(
                            ShaderLibrary.metallicSurface(
                                .float2(76, 76),
                                .float(1.0),
                                .float2(0.26, 0.14)
                            )
                        )
                        .clipShape(Circle())
                        .allowsHitTesting(false)
                }
                .overlay {
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.55),
                                    Color.white.opacity(0.08),
                                    Color.black.opacity(0.7)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.35
                        )
                }
                .overlay {
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.black.opacity(0.45),
                                    Color.clear,
                                    Color.white.opacity(0.12)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.0
                        )
                        .padding(2.5)
                }

            Circle()
                .stroke(Color.black.opacity(0.55), lineWidth: 1.75)
                .frame(width: 66, height: 66)
                .shadow(color: Color.black.opacity(0.35), radius: 1, y: 0.5)

            ZStack {
                Circle()
                    .fill(Color(red: 0.30, green: 0.32, blue: 0.36))
                    .frame(width: 60, height: 60)
                    .colorEffect(
                        ShaderLibrary.metallicSurface(
                            .float2(60, 60),
                            .float(0.95),
                            .float2(0.28, 0.20)
                        )
                    )
                    .clipShape(Circle())

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.26),
                                Color.clear,
                                Color.black.opacity(0.22)
                            ],
                            startPoint: UnitPoint(x: 0.22, y: 0.12),
                            endPoint: UnitPoint(x: 0.85, y: 0.92)
                        )
                    )
                    .frame(width: 60, height: 60)
                    .blendMode(.softLight)

                Ellipse()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.16),
                                Color.clear
                            ],
                            center: UnitPoint(x: 0.35, y: 0.28),
                            startRadius: 0,
                            endRadius: 18
                        )
                    )
                    .frame(width: 36, height: 22)
                    .offset(x: -4, y: -8)
                    .blendMode(.plusLighter)
                    .opacity(0.55)

                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .stroke(Color.white.opacity(0.05), lineWidth: 0.55)
                        .frame(width: CGFloat(50 - i * 9), height: CGFloat(50 - i * 9))
                }

                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.32),
                                Color.clear,
                                Color.black.opacity(0.45)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                    .frame(width: 58, height: 58)

                if isCapturing {
                    Circle()
                        .fill(Color.white.opacity(0.12))
                        .frame(width: 60, height: 60)
                }
            }
            .shadow(color: Color.black.opacity(0.5), radius: 2.5, y: 1.5)
        }
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
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

    // Uniform size for flash/thumbnail/WB
    private let pillWidth: CGFloat = 88
    private let pillHeight: CGFloat = 48
    @State private var isPressed = false

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

                // Inner frame - darker when pressed for inset effect
                Capsule()
                    .fill(Color(hex: isPressed ? "181818" : "242424"))
                    .frame(width: pillWidth - 4, height: pillHeight - 4)

                // Inner shadow when pressed (deep inset look)
                if isPressed {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.black.opacity(0.6),
                                    Color.black.opacity(0.25),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                        .frame(width: pillWidth - 4, height: pillHeight - 4)

                    // Blurred inner edge shadow
                    Capsule()
                        .stroke(Color.black.opacity(0.5), lineWidth: 3)
                        .blur(radius: 2)
                        .frame(width: pillWidth - 8, height: pillHeight - 8)
                        .clipShape(Capsule())
                }

                // Inner stroke (Figma: #444444)
                Capsule()
                    .stroke(Color(hex: isPressed ? "222222" : "444444"), lineWidth: 0.5)
                    .frame(width: pillWidth - 4, height: pillHeight - 4)

                Image(systemName: flashIconName)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(iconColor)
            }
            .frame(width: pillWidth, height: pillHeight)
        }
        .frame(width: pillWidth, height: pillHeight + 4)
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
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
    }
}

// MARK: - Mode Button (small dot - gray when off, lighter when on)
struct ModeButton: View {
    let isActive: Bool
    let action: () -> Void

    // Smaller per Figma - approximately 16px diameter
    private let size: CGFloat = 16

    var body: some View {
        Button(action: action) {
            ZStack {
                // Button background: darker gray when off, lighter when on
                Circle()
                    .fill(isActive ? Color(red: 0.28, green: 0.28, blue: 0.28) : Color(red: 0.17, green: 0.17, blue: 0.17))

                // Inner stroke: lighter when active
                Circle()
                    .stroke(isActive ? Color(red: 0.4, green: 0.4, blue: 0.4) : Color(red: 0.25, green: 0.25, blue: 0.25), lineWidth: 0.5)
                    .padding(0.25)
            }
            .frame(width: size, height: size)
            .shadow(color: Color(red: 0.03, green: 0.03, blue: 0.03).opacity(0.2), radius: 0.5, x: 0, y: 0.5)
        }
        .buttonStyle(ProButtonStyle())
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

    // Uniform size for flash/thumbnail/WB
    private let pillWidth: CGFloat = 88
    private let pillHeight: CGFloat = 48
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            ZStack {
                // Outer dark frame (Figma: r=27)
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color.black)
                    .frame(width: pillWidth, height: pillHeight)

                // Inner frame - darker when pressed
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color(hex: isPressed ? "1a1a1a" : "242424"))
                    .frame(width: pillWidth - 4, height: pillHeight - 4)

                // Inner shadow when pressed
                if isPressed {
                    RoundedRectangle(cornerRadius: 22)
                        .fill(
                            LinearGradient(
                                colors: [Color.black.opacity(0.3), Color.clear],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: pillWidth - 4, height: pillHeight - 4)
                }

                // Inner stroke
                RoundedRectangle(cornerRadius: 22)
                    .stroke(Color(hex: isPressed ? "333333" : "444444"), lineWidth: 0.5)
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
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
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
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct SkeuomorphicButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - WB Pill (Figma exact: 80x42, r=5, #2c2c2c fill, #444444 stroke)
struct WBPill: View {
    @Binding var whiteBalanceIndex: Int
    let onChanged: (Int) -> Void

    private let wbModes = ["AWB", "SUN", "CLD", "SHD", "TNG", "FLO"]  // Fixed-width abbreviations
    // Uniform size for flash/thumbnail/WB
    private let pillWidth: CGFloat = 88
    private let pillHeight: CGFloat = 48
    @State private var isPressed = false

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

                // Inner frame - darker when pressed
                Capsule()
                    .fill(Color(hex: isPressed ? "181818" : "242424"))
                    .frame(width: pillWidth - 4, height: pillHeight - 4)

                // Inner shadow when pressed (deep inset look)
                if isPressed {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.black.opacity(0.6),
                                    Color.black.opacity(0.25),
                                    Color.clear
                                ],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                        .frame(width: pillWidth - 4, height: pillHeight - 4)

                    // Blurred inner edge shadow
                    Capsule()
                        .stroke(Color.black.opacity(0.5), lineWidth: 3)
                        .blur(radius: 2)
                        .frame(width: pillWidth - 8, height: pillHeight - 8)
                        .clipShape(Capsule())
                }

                Capsule()
                    .stroke(Color(hex: isPressed ? "222222" : "444444"), lineWidth: 0.5)
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
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
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
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
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

    private let speeds = ["4\"", "2\"", "1\"", "1/2", "1/4", "1/8", "1/15", "1/30", "1/60", "1/125", "1/250", "1/500", "1/1000", "1/2000", "1/4000"]
    private var indices: [Int] { Array(speeds.indices) }
    @State private var selection: Int = 9

    var body: some View {
        NativeSnapScrubber(
            label: "S",
            values: indices,
            selection: $selection,
            sideLabelWidth: 36,
            tickCount: 16,
            title: { speeds[$0] },
            onChanged: { idx in
                if shutterSpeed != idx { shutterSpeed = idx }
                onChanged(idx)
            }
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
        .onAppear {
            withAnimation(.easeOut(duration: 0.18)) { scale = 1 }
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
