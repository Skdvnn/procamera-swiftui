import SwiftUI
import UIKit
import AVFoundation

struct Haptics {
    static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func medium() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func heavy() { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
    static func click() { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
}

// MARK: - Vulcanite Film Grain (Background texture)
struct VulcaniteGrain: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.15)) { _ in
            Canvas { ctx, size in
                for _ in 0..<Int(size.width * size.height * 0.002) {
                    let x = CGFloat.random(in: 0..<size.width)
                    let y = CGFloat.random(in: 0..<size.height)
                    let gray = CGFloat.random(in: 0.08...0.18)
                    let rect = CGRect(x: x, y: y, width: 1, height: 1)
                    ctx.fill(Path(rect), with: .color(Color(white: gray, opacity: 0.12)))
                }
            }
        }
        .allowsHitTesting(false)
        .blendMode(.overlay)
    }
}

// MARK: - Design System (matches Figma exactly)
struct DS {
    // Colors - from Figma design
    static let pageBg = Color(hex: "171717")         // Figma Frame 1 background
    static let controlBg = Color(hex: "2c2c2c")      // Figma control backgrounds
    static let controlBgLight = Color(hex: "3a3a3a") // lighter control bg for hover
    static let strokeOuter = Color(white: 0.22)      // outer stroke
    static let strokeInner = Color(white: 0.12)      // inner stroke
    static let textPrimary = Color.white
    static let textSecondary = Color(hex: "5e5e5e")  // Figma icon gray
    static let accent = Color(red: 1.0, green: 0.85, blue: 0.35) // golden yellow for indicators

    // Spacing
    static let pageMargin: CGFloat = 16

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

struct ContentView: View {
    @StateObject private var camera = CameraManager()

    @State private var showGrid = true
    @State private var timerSeconds = 0
    @State private var timerCountdown = 0
    @State private var photoCount = 9999
    @State private var lastCapturedImage: UIImage?
    @State private var showFlash = false
    @State private var showFocusPoint = false
    @State private var focusPoint: CGPoint = .zero
    @State private var macroEnabled = false
    @State private var isCapturing = false
    @State private var isRecording = false
    @State private var selectedMode: Int = 1
    @State private var whiteBalanceIndex: Int = 0
    @State private var isManualFocusEnabled = false
    @State private var isLocked = false
    @State private var focusPosition: Float = 0.5
    @State private var exposureValue: Float = 0.0
    @State private var isoValue: Int = 800
    @State private var focalLength: Int = 24
    @State private var zoomValue: CGFloat = 1.0
    @State private var apertureValue: Float = 2.8
    @State private var shutterSpeedIndex: Int = 9  // Default to 1/125
    @State private var aspectRatio: AspectRatioMode = .full
    @State private var filmFilter: FilmFilterMode = .none

    private let modes = ["P", "A", "T"]
    private let shutterSpeeds = ["4\"", "2\"", "1\"", "1/2", "1/4", "1/8", "1/15", "1/30", "1/60", "1/125", "1/250", "1/500", "1/1000", "1/2000", "1/4000"]
    private let isoValues = [100, 200, 400, 800, 1600, 3200]
    private let focalLengths = [24, 28, 35, 50, 70, 85, 105]

    var body: some View {
        GeometryReader { geo in
            let screenWidth = geo.size.width
            let safeTop = geo.safeAreaInsets.top
            let safeBottom = geo.safeAreaInsets.bottom

            // Layout measurements - maximize viewport
            let topPanelHeight: CGFloat = 110
            let bottomControlsHeight: CGFloat = 145  // Tight controls
            let spacing: CGFloat = 4
            let bottomPadding: CGFloat = 10

            // Calculate viewfinder to fill remaining space
            let availableHeight = geo.size.height - topPanelHeight - bottomControlsHeight - spacing * 2 - bottomPadding - safeTop
            let viewfinderHeight = availableHeight

            ZStack {
                // Vulcanite black background with grain
                vulcaniteBlack.ignoresSafeArea()
                VulcaniteGrain().ignoresSafeArea()

                VStack(spacing: 0) {
                    // TOP: Analog Display Panel (with shutter speed connected)
                    AnalogDisplayPanel(
                        focusPosition: $focusPosition,
                        exposureValue: $exposureValue,
                        shutterSpeedIndex: $shutterSpeedIndex,
                        timerSeconds: timerSeconds,
                        iso: isoValue,
                        flashMode: camera.flashMode == .off ? "OFF" : "ON",
                        macroEnabled: macroEnabled,
                        isAutoFocus: !isManualFocusEnabled,
                        onFocusChanged: { val in
                            camera.setManualFocus(val)
                            isManualFocusEnabled = true
                        },
                        onExposureChanged: { val in
                            camera.setExposure(val)
                        },
                        onShutterSpeedChanged: { idx in
                            // Adjust exposure based on shutter speed change
                            // Higher index = faster shutter = less light = darker
                            let baseIndex = 4  // 1/250 as neutral
                            let evAdjust = Float(idx - baseIndex) * 0.5
                            exposureValue = max(-2, min(2, evAdjust))
                            camera.setExposure(exposureValue)
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
                        }
                    )
                    .frame(height: topPanelHeight)
                    .padding(.horizontal, DS.pageMargin)

                    Spacer().frame(height: spacing)

                    // VIEWFINDER - with 20px margins for camera body look
                    ZStack {
                        CameraPreviewView(
                            session: camera.session,
                            onTap: handleFocusTap,
                            onPinch: { scale in
                                guard !isLocked else { return }
                                Haptics.light()
                                let newZoom = zoomValue * scale
                                zoomValue = min(max(newZoom, 1.0), 5.0)
                                camera.setZoom(zoomValue)
                                if !isManualFocusEnabled {
                                    focusPosition = Float(zoomValue - 1) / 4.0
                                }
                            }
                        )

                        ViewfinderOverlay(showGrid: showGrid, aspectRatio: $aspectRatio, filmFilter: $filmFilter)
                        ViewfinderVignette()

                        if showFocusPoint {
                            FocusIndicator().position(focusPoint)
                        }

                        if timerCountdown > 0 {
                            Text("\(timerCountdown)")
                                .font(.system(size: 80, weight: .thin, design: .monospaced))
                                .foregroundColor(.white.opacity(0.9))
                        }

                        VStack {
                            Spacer()
                            RefractiveGlassInfoBar(
                                iso: isoValue,
                                shutterSpeed: computeShutterSpeed(),
                                aperture: apertureValue,
                                photoCount: photoCount,
                                exposureValue: exposureValue
                            )
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
                        }
                    }
                    .frame(height: viewfinderHeight)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: DS.radiusMedium))
                    .padding(.horizontal, DS.pageMargin)

                    Spacer().frame(height: spacing)

                    // BOTTOM CONTROLS - better spacing per Figma
                    ZStack {
                        // Grain texture for controls area
                        ControlsGrain()

                        VStack(spacing: 8) {
                            // ROW 1: Zoom control (full width)
                            LensRingControl(
                                focalLength: $focalLength,
                                isoValue: $isoValue,
                                onFocalLengthChanged: { fl in
                                    let zoom = CGFloat(fl) / 24.0
                                    zoomValue = zoom
                                    camera.setZoom(zoom)
                                    if !isManualFocusEnabled {
                                        focusPosition = Float(zoom - 1) / 4.0
                                    }
                                },
                                onISOChanged: { iso in
                                    camera.setISO(Float(iso))
                                }
                            )
                            .frame(height: 42)
                            .padding(.horizontal, DS.pageMargin)

                            // ROW 2: ISO & Shutter side by side (same height as buttons)
                            HStack(spacing: 8) {
                                ISOScrubberHorizontal(
                                    iso: $isoValue,
                                    onChanged: { iso in
                                        camera.setISO(Float(iso))
                                    }
                                )

                                ShutterScrubber(
                                    shutterSpeed: $shutterSpeedIndex,
                                    onChanged: { idx in
                                        let evShift = Float(idx - 9) * 0.5
                                        exposureValue = max(-2, min(2, evShift))
                                        camera.setExposure(exposureValue)
                                    }
                                )
                            }
                            .frame(height: 42)
                            .padding(.horizontal, DS.pageMargin)

                            // Extra spacing before capture row
                            Spacer().frame(height: 8)

                        // ROW 3: Main capture row with proper spacing
                        ZStack {
                            // Background layer: Left stack + Right WB with icons
                            HStack(alignment: .bottom, spacing: 0) {
                                // Left: Flash pill ABOVE Thumbnail pill
                                VStack(spacing: 10) {
                                    FlashButtonPill(flashMode: camera.flashMode) {
                                        Haptics.click()
                                        camera.cycleFlash()
                                    }

                                    ThumbnailPill(image: lastCapturedImage)
                                }

                                Spacer()

                                // Right: Mode controls per Figma (icons centered above buttons)
                                VStack(spacing: 10) {
                                    // Icons + Buttons combined for perfect alignment
                                    HStack(spacing: 16) {
                                        // Macro column
                                        VStack(spacing: 6) {
                                            ModeIcon(icon: "camera.macro", isActive: macroEnabled)
                                            ModeButton(isActive: macroEnabled) {
                                                Haptics.click()
                                                macroEnabled.toggle()
                                            }
                                        }

                                        // Timer column
                                        VStack(spacing: 6) {
                                            ModeIcon(icon: "timer", isActive: timerSeconds > 0)
                                            ModeButton(isActive: timerSeconds > 0) {
                                                Haptics.click()
                                                if timerSeconds == 0 { timerSeconds = 3 }
                                                else if timerSeconds == 3 { timerSeconds = 10 }
                                                else { timerSeconds = 0 }
                                            }
                                        }

                                        // Grid column
                                        VStack(spacing: 6) {
                                            ModeIcon(icon: "rectangle.on.rectangle", isActive: showGrid)
                                            ModeButton(isActive: showGrid) {
                                                Haptics.click()
                                                showGrid.toggle()
                                            }
                                        }
                                    }

                                    // WB pill below with spacing
                                    WBPill(
                                        whiteBalanceIndex: $whiteBalanceIndex,
                                        onChanged: { mode in
                                            camera.setWhiteBalance(mode: mode)
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, DS.pageMargin + 4)

                            // Foreground: Shutter button (absolutely centered)
                            ShutterButton(isCapturing: isCapturing) {
                                Haptics.heavy()
                                handleCapture()
                            }
                        }
                        }
                    }
                    .padding(.bottom, bottomPadding)
                }
                .padding(.top, safeTop)

                if showFlash {
                    Color.white.ignoresSafeArea()
                }
            }
            .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(false)
        .onAppear { camera.checkPermissions() }
        .onChange(of: filmFilter) { newFilter in
            // Sync UI film filter to CameraManager
            switch newFilter {
            case .none: camera.selectedFilmFilter = .none
            case .portra400: camera.selectedFilmFilter = .portra400
            case .kodakGold: camera.selectedFilmFilter = .ektar100  // Map to similar
            case .trix400: camera.selectedFilmFilter = .trix400
            case .velvia50: camera.selectedFilmFilter = .velvia50
            case .cinestill800: camera.selectedFilmFilter = .cinestill800
            }
        }
    }

    // MARK: - Helpers
    private func computeShutterSpeed() -> String {
        let speed = Int(1600 / pow(2, exposureValue))
        return "1/\(max(speed, 1))"
    }

    private func handleFocusTap(_ point: CGPoint) {
        guard !isLocked else { return }
        Haptics.light()
        camera.setFocus(at: point)
        isManualFocusEnabled = false
        focusPoint = CGPoint(x: point.x * UIScreen.main.bounds.width, y: point.y * 380 + 160)
        withAnimation(.easeOut(duration: 0.15)) { showFocusPoint = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { showFocusPoint = false }
        }
    }

    private func handleCapture() {
        guard !isCapturing else { return }
        if timerSeconds > 0 {
            isCapturing = true
            timerCountdown = timerSeconds
            runCountdown()
        } else {
            captureNow()
        }
    }

    private func runCountdown() {
        guard timerCountdown > 0 else { captureNow(); return }
        Haptics.light()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            timerCountdown -= 1
            runCountdown()
        }
    }

    private func captureNow() {
        Haptics.heavy()
        withAnimation(.easeInOut(duration: 0.1)) { showFlash = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { showFlash = false }
        camera.capturePhoto { img in
            isCapturing = false
            if let img = img {
                lastCapturedImage = img
                photoCount += 1
                camera.saveToPhotoLibrary(img) { _ in }
            }
        }
    }

    private func toggleRecording() {
        isRecording.toggle()
        if isRecording { camera.startRecording() }
        else { camera.stopRecording() }
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

// MARK: - Refractive Glass Info Bar (Apple-style Liquid Glass)
struct RefractiveGlassInfoBar: View {
    let iso: Int
    let shutterSpeed: String
    let aperture: Float
    let photoCount: Int
    let exposureValue: Float

    var body: some View {
        HStack(spacing: 10) {
            // Histogram in glass container
            GlassHistogram(exposureValue: exposureValue)
                .frame(width: 70, height: 40)

            // Format info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("HEIC")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                    Text("L")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.white)
                        )
                        .foregroundColor(.black)
                    Text("1:1")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                }
                HStack(spacing: 6) {
                    Text(formatNumber(photoCount))
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                    Text("F\(String(format: "%.1f", aperture))")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                }
            }
            .foregroundColor(.white)

            Spacer()

            // ISO & Shutter
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 3) {
                    Text("A")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 2).stroke(Color.white, lineWidth: 0.5))
                    Text("ISO \(iso)")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                }
                Text(shutterSpeed)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
            }
            .foregroundColor(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        )
        .environment(\.colorScheme, .dark)
    }

    private func formatNumber(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

// MARK: - Glass Histogram (Refractive Container)
struct GlassHistogram: View {
    let exposureValue: Float

    var body: some View {
        ZStack {
            // Glass container
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.black.opacity(0.4))

            // Inner highlight
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.2), Color.clear, Color.clear, Color.black.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
                .padding(0.5)

            // Histogram bars
            Canvas { ctx, size in
                let ev = CGFloat((exposureValue + 2) / 4)
                let padding: CGFloat = 4
                let barWidth = (size.width - padding * 2) / 40

                for i in 0..<40 {
                    let x = padding + CGFloat(i) * barWidth
                    let n = CGFloat(i) / 40
                    let shifted = n - (ev - 0.5) * 0.4
                    var h = exp(-pow((shifted - 0.3) * 4, 2)) * 0.85
                    h += exp(-pow((shifted - 0.7) * 5, 2)) * 0.6
                    h = min(max(h, 0.03), 1.0)
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
        TimelineView(.animation(minimumInterval: 0.2)) { _ in
            Canvas { context, size in
                // Denser grain for DSLR feel
                for _ in 0..<Int(size.width * size.height * 0.008) {
                    let x = CGFloat.random(in: 0...size.width)
                    let y = CGFloat.random(in: 0...size.height)
                    let opacity = CGFloat.random(in: 0.04...0.12)
                    let dotSize = CGFloat.random(in: 0.8...1.5)
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: dotSize, height: dotSize)),
                        with: .color(.white.opacity(opacity))
                    )
                }
                // Add some darker grain too for depth
                for _ in 0..<Int(size.width * size.height * 0.002) {
                    let x = CGFloat.random(in: 0...size.width)
                    let y = CGFloat.random(in: 0...size.height)
                    let opacity = CGFloat.random(in: 0.08...0.15)
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: 1, height: 1)),
                        with: .color(.black.opacity(opacity))
                    )
                }
            }
        }
        .allowsHitTesting(false)
        .blendMode(.overlay)
    }
}

// MARK: - ISO Scrubber Horizontal (WB-style with ticks)
struct ISOScrubberHorizontal: View {
    @Binding var iso: Int
    let onChanged: (Int) -> Void

    private let isoValues = [100, 200, 400, 800, 1600, 3200, 6400]
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var startIndex: Int = 0

    private var currentIndex: Int {
        isoValues.firstIndex(of: iso) ?? 3
    }

    private var prevISO: String {
        currentIndex > 0 ? "\(isoValues[currentIndex - 1])" : ""
    }

    private var nextISO: String {
        currentIndex < isoValues.count - 1 ? "\(isoValues[currentIndex + 1])" : ""
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Outer dark frame
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.black)

                // Inner frame
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(hex: "2c2c2c"))
                    .padding(2)

                // Inner stroke
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(hex: "444444"), lineWidth: 0.5)
                    .padding(2)

                // Tick marks at bottom with yellow center indicator
                Canvas { ctx, size in
                    let tickCount = 16
                    let usableWidth = size.width - 24
                    let spacing = usableWidth / CGFloat(tickCount - 1)
                    let offset = dragOffset * 0.08
                    let centerX = size.width / 2

                    for i in 0..<tickCount {
                        let x = 12 + CGFloat(i) * spacing + offset
                        guard x >= 6 && x <= size.width - 6 else { continue }
                        let isMajor = i % 4 == 0
                        let h: CGFloat = isMajor ? 5 : 3
                        let rect = CGRect(x: x - 0.5, y: size.height - h - 4, width: 1, height: h)
                        ctx.fill(Path(rect), with: .color(.white.opacity(isMajor ? 0.25 : 0.1)))
                    }

                    // Yellow center indicator line (grows when dragging)
                    let indicatorHeight: CGFloat = isDragging ? 14 : 10
                    let indicatorWidth: CGFloat = isDragging ? 2.5 : 2
                    let indicatorRect = CGRect(
                        x: centerX - indicatorWidth / 2,
                        y: size.height - indicatorHeight - 2,
                        width: indicatorWidth,
                        height: indicatorHeight
                    )
                    ctx.fill(Path(indicatorRect), with: .color(Color(red: 1.0, green: 0.85, blue: 0.35)))
                }

                // Content with prev/next values (yellow when active)
                HStack(spacing: 0) {
                    Text(prevISO)
                        .font(DS.mono(9, weight: .medium))
                        .foregroundColor(DS.textSecondary)
                        .frame(width: 32, alignment: .center)

                    Spacer()

                    HStack(spacing: 2) {
                        Text("ISO")
                            .font(DS.mono(8, weight: .medium))
                            .foregroundColor(isDragging ? DS.accent : DS.textSecondary)
                        Text("\(iso)")
                            .font(DS.mono(11, weight: .bold))
                            .foregroundColor(isDragging ? DS.accent : .white)
                            .frame(minWidth: 32, alignment: .center)
                    }

                    Spacer()

                    Text(nextISO)
                        .font(DS.mono(9, weight: .medium))
                        .foregroundColor(DS.textSecondary)
                        .frame(width: 32, alignment: .center)
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 6)
            }
            .animation(.easeOut(duration: 0.15), value: isDragging)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            startIndex = currentIndex
                        }
                        dragOffset = value.translation.width
                        let stepWidth: CGFloat = 35
                        let steps = Int(-value.translation.width / stepWidth)
                        let newIndex = max(0, min(isoValues.count - 1, startIndex + steps))
                        if newIndex != currentIndex {
                            Haptics.light()
                            iso = isoValues[newIndex]
                            onChanged(iso)
                        }
                    }
                    .onEnded { _ in
                        isDragging = false
                        dragOffset = 0
                    }
            )
        }
    }
}

// MARK: - Lens Ring Control (WB-style with ticks)
struct LensRingControl: View {
    @Binding var focalLength: Int
    @Binding var isoValue: Int
    let onFocalLengthChanged: (Int) -> Void
    let onISOChanged: (Int) -> Void

    private let focalLengths = [24, 28, 35, 50, 70, 85, 105]
    private let isoValues = [100, 200, 400, 800, 1600, 3200]

    @State private var tickOffset: CGFloat = 0
    @State private var accumulatedDrag: CGFloat = 0
    @State private var isDragging = false

    private var currentIndex: Int {
        focalLengths.firstIndex(of: focalLength) ?? 0
    }

    private var prevFocalLength: String {
        currentIndex > 0 ? "\(focalLengths[currentIndex - 1])" : ""
    }

    private var nextFocalLength: String {
        currentIndex < focalLengths.count - 1 ? "\(focalLengths[currentIndex + 1])" : ""
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Outer dark frame
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.black)

                // Inner frame
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(hex: "2c2c2c"))
                    .padding(2)

                // Inner stroke
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(hex: "444444"), lineWidth: 0.5)
                    .padding(2)

                // Tick marks at bottom with yellow center indicator
                Canvas { ctx, size in
                    let tickCount = 20
                    let usableWidth = size.width - 24
                    let spacing = usableWidth / CGFloat(tickCount - 1)
                    let offset = tickOffset * 0.08
                    let centerX = size.width / 2

                    for i in 0..<tickCount {
                        let x = 12 + CGFloat(i) * spacing + offset
                        guard x >= 6 && x <= size.width - 6 else { continue }
                        let isMajor = i % 4 == 0
                        let h: CGFloat = isMajor ? 5 : 3
                        let rect = CGRect(x: x - 0.5, y: size.height - h - 4, width: 1, height: h)
                        ctx.fill(Path(rect), with: .color(.white.opacity(isMajor ? 0.25 : 0.1)))
                    }

                    // Yellow center indicator (grows when dragging)
                    let indicatorHeight: CGFloat = isDragging ? 14 : 10
                    let indicatorWidth: CGFloat = isDragging ? 2.5 : 2
                    let indicatorRect = CGRect(
                        x: centerX - indicatorWidth / 2,
                        y: size.height - indicatorHeight - 2,
                        width: indicatorWidth,
                        height: indicatorHeight
                    )
                    ctx.fill(Path(indicatorRect), with: .color(Color(red: 1.0, green: 0.85, blue: 0.35)))
                }

                // Content with prev/next values (yellow when active)
                HStack(spacing: 0) {
                    Text(prevFocalLength)
                        .font(DS.mono(9, weight: .medium))
                        .foregroundColor(DS.textSecondary)
                        .frame(width: 28, alignment: .center)

                    Spacer()

                    Text("\(focalLength)MM")
                        .font(DS.mono(11, weight: .bold))
                        .foregroundColor(isDragging ? DS.accent : .white)
                        .frame(width: 50, alignment: .center)

                    Spacer()

                    Text(nextFocalLength)
                        .font(DS.mono(9, weight: .medium))
                        .foregroundColor(DS.textSecondary)
                        .frame(width: 28, alignment: .center)
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
            }
            .animation(.easeOut(duration: 0.15), value: isDragging)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if !isDragging { isDragging = true }
                        tickOffset = value.translation.width

                        let stepWidth: CGFloat = 45
                        let steps = Int((value.translation.width - accumulatedDrag) / stepWidth)

                        if steps != 0 {
                            accumulatedDrag += CGFloat(steps) * stepWidth

                            if steps < 0 {
                                for _ in 0..<abs(steps) {
                                    if currentIndex < focalLengths.count - 1 {
                                        Haptics.light()
                                        focalLength = focalLengths[currentIndex + 1]
                                        onFocalLengthChanged(focalLength)
                                    }
                                }
                            } else {
                                for _ in 0..<steps {
                                    if currentIndex > 0 {
                                        Haptics.light()
                                        focalLength = focalLengths[currentIndex - 1]
                                        onFocalLengthChanged(focalLength)
                                    }
                                }
                            }
                        }
                    }
                    .onEnded { _ in
                        isDragging = false
                        accumulatedDrag = 0
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            tickOffset = 0
                        }
                    }
            )
            .onTapGesture {
                Haptics.click()
                let newIndex = (currentIndex + 1) % focalLengths.count
                focalLength = focalLengths[newIndex]
                onFocalLengthChanged(focalLength)
            }
        }
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

    private let focalLengths = [24, 28, 35, 50, 70, 85, 105]

    @State private var isDragging = false
    @State private var dragOffset: CGFloat = 0
    @State private var startIndex: Int = 0

    private var currentIndex: Int {
        focalLengths.firstIndex(of: focalLength) ?? 0
    }

    var body: some View {
        GeometryReader { geo in
            let _ = geo.size.width // Used for future layout

            ZStack {
                // Liquid glass background
                Capsule()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)

                // Inner border
                Capsule()
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)

                // Dot indicators on left
                HStack(spacing: 4) {
                    ForEach(0..<currentIndex, id: \.self) { _ in
                        Circle()
                            .fill(Color.white.opacity(0.3))
                            .frame(width: 4, height: 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 16)

                // Center focal length
                HStack(spacing: 8) {
                    Text("\(focalLength)MM")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(.yellow)

                    // Yellow indicator line
                    Rectangle()
                        .fill(Color.yellow)
                        .frame(width: 2, height: 16)
                }

                // Dot indicators on right
                HStack(spacing: 4) {
                    ForEach(0..<(focalLengths.count - 1 - currentIndex), id: \.self) { _ in
                        Circle()
                            .fill(Color.white.opacity(0.3))
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
                        let stepWidth: CGFloat = 40
                        let steps = Int(-value.translation.width / stepWidth)
                        let newIndex = max(0, min(focalLengths.count - 1, startIndex + steps))
                        if newIndex != currentIndex {
                            Haptics.light()
                            focalLength = focalLengths[newIndex]
                            onFocalLengthChanged(focalLength)
                        }
                    }
                    .onEnded { _ in
                        isDragging = false
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

// MARK: - Shutter Button (Figma style: large dark circle with subtle gradient)
struct ShutterButton: View {
    let isCapturing: Bool
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            ZStack {
                // Outer ring (Figma: dark circle with gradient)
                Circle()
                    .fill(Color(hex: "1a1a1a"))
                    .frame(width: 72, height: 72)

                // Subtle top highlight
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.15), Color.white.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                    .frame(width: 72, height: 72)

                // Inner button face with subtle 3D effect
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(hex: isPressed ? "181818" : "222222"),
                                Color(hex: isPressed ? "0f0f0f" : "151515"),
                                Color(hex: isPressed ? "0a0a0a" : "101010")
                            ],
                            center: UnitPoint(x: 0.4, y: 0.35),
                            startRadius: 0,
                            endRadius: 32
                        )
                    )
                    .frame(width: 64, height: 64)

                // Inner stroke
                Circle()
                    .stroke(Color(hex: "333333"), lineWidth: 0.5)
                    .frame(width: 64, height: 64)

                // Concentric detail circles (Figma shows subtle rings)
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(Color.white.opacity(0.03), lineWidth: 0.5)
                        .frame(width: CGFloat(52 - i * 12), height: CGFloat(52 - i * 12))
                }

                // Capturing flash
                if isCapturing {
                    Circle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 64, height: 64)
                }
            }
            .shadow(color: Color.black.opacity(0.6), radius: isPressed ? 2 : 6, y: isPressed ? 1 : 3)
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.1), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
        .disabled(isCapturing)
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Record Button (Video recording)
struct RecordButton: View {
    let isRecording: Bool
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            ZStack {
                // Outer bezel
                Circle()
                    .fill(DS.controlBg)
                    .frame(width: 52, height: 52)

                // Inner shadow
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.black.opacity(0.5), Color.clear, Color.white.opacity(0.03)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .frame(width: 48, height: 48)

                // Outer stroke
                Circle()
                    .stroke(DS.strokeOuter, lineWidth: 1)
                    .frame(width: 52, height: 52)

                // Inner stroke
                Circle()
                    .stroke(DS.strokeInner, lineWidth: 1)
                    .frame(width: 48, height: 48)

                // Red record indicator
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.95, green: 0.25, blue: 0.25),
                                Color(red: 0.75, green: 0.15, blue: 0.15)
                            ],
                            center: UnitPoint(x: 0.35, y: 0.35),
                            startRadius: 0,
                            endRadius: 12
                        )
                    )
                    .frame(width: 22, height: 22)
                    .scaleEffect(isRecording ? 0.7 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: isRecording)

                // Recording pulse
                if isRecording {
                    Circle()
                        .stroke(Color.red.opacity(0.5), lineWidth: 2)
                        .frame(width: 28, height: 28)
                        .scaleEffect(isRecording ? 1.3 : 1.0)
                        .opacity(isRecording ? 0 : 1)
                        .animation(.easeOut(duration: 1).repeatForever(autoreverses: false), value: isRecording)
                }
            }
            .shadow(color: Color.black.opacity(0.4), radius: 4, y: 2)
            .scaleEffect(isPressed ? 0.96 : 1.0)
            .animation(.easeOut(duration: 0.1), value: isPressed)
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
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
                    .fill(Color(hex: "2c2c2c"))
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
                    .frame(width: 80, height: 42)

                // Inner frame (Figma: #2c2c2c fill)
                Capsule()
                    .fill(Color(hex: "2c2c2c"))
                    .frame(width: 76, height: 38)

                // Inner stroke (Figma: #444444)
                Capsule()
                    .stroke(Color(hex: "444444"), lineWidth: 0.5)
                    .frame(width: 76, height: 38)

                // Lightning bolt icon
                Image(systemName: "bolt.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(iconColor)
            }
            .frame(width: 80, height: 42)
        }
        .buttonStyle(ProButtonStyle())
    }
}

// MARK: - Mode Icon (small icon above button - only icon turns yellow when active)
struct ModeIcon: View {
    let icon: String
    let isActive: Bool

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .regular))
            .foregroundColor(isActive ? DS.accent : Color(hex: "5e5e5e"))
            .frame(width: 22, height: 18)  // Match button width for alignment
    }
}

// MARK: - Mode Button (gray when off, lighter when on - NOT yellow)
struct ModeButton: View {
    let isActive: Bool
    let action: () -> Void

    // Figma size: approximately 22px diameter
    private let size: CGFloat = 22

    var body: some View {
        Button(action: action) {
            ZStack {
                // Button background: darker gray when off, lighter when on
                Circle()
                    .fill(isActive ? Color(red: 0.25, green: 0.25, blue: 0.25) : Color(red: 0.17, green: 0.17, blue: 0.17))

                // Inner stroke: lighter when active
                Circle()
                    .stroke(isActive ? Color(red: 0.38, green: 0.38, blue: 0.38) : Color(red: 0.27, green: 0.27, blue: 0.27), lineWidth: 0.5)
                    .padding(0.5)
            }
            .frame(width: size, height: size)
            // Subtle shadows for depth
            .shadow(color: Color(red: 0.03, green: 0.03, blue: 0.03).opacity(0.25), radius: 1, x: 0, y: 0.8)
            .shadow(color: .black.opacity(0.2), radius: 0.5, x: 0, y: -0.3)
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

    var body: some View {
        ZStack {
            // Outer dark frame (Figma: r=27)
            RoundedRectangle(cornerRadius: 21)
                .fill(Color.black)
                .frame(width: 80, height: 42)

            // Inner frame
            RoundedRectangle(cornerRadius: 19)
                .fill(Color(hex: "2c2c2c"))
                .frame(width: 76, height: 38)

            // Inner stroke
            RoundedRectangle(cornerRadius: 19)
                .stroke(Color(hex: "444444"), lineWidth: 0.5)
                .frame(width: 76, height: 38)

            // Image or placeholder
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 68, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 15))
            } else {
                Image(systemName: "photo.stack")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(hex: "5e5e5e"))
            }
        }
        .frame(width: 80, height: 42)
    }
}

// MARK: - Record Button Compact (For stacking)
struct RecordButtonCompact: View {
    let isRecording: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(DS.controlBg)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.black.opacity(0.4), Color.clear, Color.white.opacity(0.02)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .padding(2)
                Circle()
                    .stroke(DS.strokeOuter, lineWidth: 1)
                Circle()
                    .stroke(DS.strokeInner, lineWidth: 1)
                    .padding(2)

                // Red record dot
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(red: 0.95, green: 0.25, blue: 0.25),
                                Color(red: 0.7, green: 0.15, blue: 0.15)
                            ],
                            center: UnitPoint(x: 0.35, y: 0.35),
                            startRadius: 0,
                            endRadius: 10
                        )
                    )
                    .frame(width: 18, height: 18)
                    .scaleEffect(isRecording ? 0.7 : 1.0)
                    .animation(.easeInOut(duration: 0.2), value: isRecording)
            }
        }
        .buttonStyle(ProButtonStyle())
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

    private let wbModes = ["Auto", "Sun", "Cloud", "Shade", "Lamp", "Fluo"]

    var body: some View {
        Button(action: {
            Haptics.click()
            whiteBalanceIndex = (whiteBalanceIndex + 1) % wbModes.count
            onChanged(whiteBalanceIndex)
        }) {
            ZStack {
                // Outer shadow frame (Figma: stroke #000000 sw=2)
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.black)
                    .frame(width: 80, height: 42)

                // Inner frame (Figma: fill #2c2c2c, r=5, stroke #444444 sw=0.5)
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(hex: "2c2c2c"))
                    .frame(width: 76, height: 38)

                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color(hex: "444444"), lineWidth: 0.5)
                    .frame(width: 76, height: 38)

                // Text (Figma: "WB Auto" Inter 12px w400 white)
                Text("WB \(wbModes[whiteBalanceIndex])")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.white)
            }
            .frame(width: 80, height: 42)
        }
        .buttonStyle(.plain)
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

    private let wbModes = ["AWB", "☀️", "☁️", "🏠", "💡", "📺"]

    var body: some View {
        Button(action: {
            Haptics.click()
            whiteBalanceIndex = (whiteBalanceIndex + 1) % wbModes.count
            onChanged(whiteBalanceIndex)
        }) {
            Text(wbModes[whiteBalanceIndex])
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
        GeometryReader { geo in
            let height = geo.size.height

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

// MARK: - F-Stop Scrubber (DSLR-style drag control)
struct FStopScrubber: View {
    @Binding var aperture: Float
    let onChanged: (Float) -> Void

    private let fStops: [Float] = [1.8, 2.8, 4.0, 5.6, 8.0, 11, 16, 22]
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var startIndex: Int = 0

    private var currentIndex: Int {
        fStops.firstIndex(where: { abs($0 - aperture) < 0.5 }) ?? 0
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size

            ZStack {
                // Background
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

                // Ticks at bottom only
                Canvas { ctx, size in
                    let tickCount = 24
                    let usableWidth = size.width - 20
                    let spacing = usableWidth / CGFloat(tickCount - 1)
                    let offset = dragOffset * 0.15
                    let startX: CGFloat = 10

                    for i in 0..<tickCount {
                        let x = startX + CGFloat(i) * spacing + offset
                        guard x >= 4 && x <= size.width - 4 else { continue }

                        let isMajor = i % 4 == 0
                        let tickHeight: CGFloat = isMajor ? 5 : 3
                        let opacity = isMajor ? 0.25 : 0.1

                        let rect = CGRect(
                            x: x - 0.5,
                            y: size.height - tickHeight - 4,
                            width: 1,
                            height: tickHeight
                        )
                        ctx.fill(Path(rect), with: .color(Color.white.opacity(opacity)))
                    }
                }

                // Content - text at top
                VStack(spacing: 0) {
                    HStack(spacing: 2) {
                        Text("f/")
                            .font(DS.mono(9, weight: .medium))
                            .foregroundColor(DS.textSecondary)
                        Text(fStopLabel(aperture))
                            .font(DS.mono(13, weight: .bold))
                            .foregroundColor(DS.textPrimary)
                    }
                    .padding(.top, 6)

                    Spacer()

                    // Center indicator
                    Rectangle()
                        .fill(DS.accent)
                        .frame(width: 2, height: 6)
                        .padding(.bottom, 3)
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
                        dragOffset = value.translation.width

                        let stepWidth: CGFloat = 35
                        let steps = Int(-value.translation.width / stepWidth)
                        let newIndex = max(0, min(fStops.count - 1, startIndex + steps))

                        if newIndex != currentIndex {
                            Haptics.light()
                            aperture = fStops[newIndex]
                            onChanged(aperture)
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

    private func fStopLabel(_ f: Float) -> String {
        if f >= 10 { return String(format: "%.0f", f) }
        if f == floor(f) { return String(format: "%.0f", f) }
        return String(format: "%.1f", f)
    }
}

// MARK: - Shutter Speed Scrubber (DSLR-style drag control)
struct ShutterScrubber: View {
    @Binding var shutterSpeed: Int
    let onChanged: (Int) -> Void

    private let speeds = ["4\"", "2\"", "1\"", "1/2", "1/4", "1/8", "1/15", "1/30", "1/60", "1/125", "1/250", "1/500", "1/1000", "1/2000", "1/4000"]
    @State private var dragOffset: CGFloat = 0
    @State private var isDragging = false
    @State private var startIndex: Int = 0

    private var prevSpeed: String {
        shutterSpeed > 0 ? speeds[shutterSpeed - 1] : ""
    }

    private var nextSpeed: String {
        shutterSpeed < speeds.count - 1 ? speeds[shutterSpeed + 1] : ""
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Outer dark frame
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.black)

                // Inner frame
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(hex: "2c2c2c"))
                    .padding(2)

                // Inner stroke
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(hex: "444444"), lineWidth: 0.5)
                    .padding(2)

                // Tick marks at bottom with yellow center indicator
                Canvas { ctx, size in
                    let tickCount = 16
                    let usableWidth = size.width - 24
                    let spacing = usableWidth / CGFloat(tickCount - 1)
                    let offset = dragOffset * 0.08
                    let centerX = size.width / 2

                    for i in 0..<tickCount {
                        let x = 12 + CGFloat(i) * spacing + offset
                        guard x >= 6 && x <= size.width - 6 else { continue }
                        let isMajor = i % 4 == 0
                        let h: CGFloat = isMajor ? 5 : 3
                        let rect = CGRect(x: x - 0.5, y: size.height - h - 4, width: 1, height: h)
                        ctx.fill(Path(rect), with: .color(.white.opacity(isMajor ? 0.25 : 0.1)))
                    }

                    // Yellow center indicator line (grows when dragging)
                    let indicatorHeight: CGFloat = isDragging ? 14 : 10
                    let indicatorWidth: CGFloat = isDragging ? 2.5 : 2
                    let indicatorRect = CGRect(
                        x: centerX - indicatorWidth / 2,
                        y: size.height - indicatorHeight - 2,
                        width: indicatorWidth,
                        height: indicatorHeight
                    )
                    ctx.fill(Path(indicatorRect), with: .color(Color(red: 1.0, green: 0.85, blue: 0.35)))
                }

                // Content with prev/next values (fixed widths to prevent jumping)
                HStack(spacing: 0) {
                    Text(prevSpeed)
                        .font(DS.mono(8, weight: .medium))
                        .foregroundColor(DS.textSecondary)
                        .frame(width: 40, alignment: .center)
                        .lineLimit(1)

                    Spacer()

                    HStack(spacing: 2) {
                        Text("S")
                            .font(DS.mono(8, weight: .medium))
                            .foregroundColor(isDragging ? DS.accent : DS.textSecondary)
                        Text(speeds[shutterSpeed])
                            .font(DS.mono(10, weight: .bold))
                            .foregroundColor(isDragging ? DS.accent : .white)
                            .frame(width: 44, alignment: .center)
                            .lineLimit(1)
                    }

                    Spacer()

                    Text(nextSpeed)
                        .font(DS.mono(8, weight: .medium))
                        .foregroundColor(DS.textSecondary)
                        .frame(width: 40, alignment: .center)
                        .lineLimit(1)
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 6)
            }
            .animation(.easeOut(duration: 0.15), value: isDragging)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            startIndex = shutterSpeed
                        }
                        dragOffset = value.translation.width
                        let stepWidth: CGFloat = 30
                        let steps = Int(-value.translation.width / stepWidth)
                        let newIndex = max(0, min(speeds.count - 1, startIndex + steps))
                        if newIndex != shutterSpeed {
                            Haptics.light()
                            shutterSpeed = newIndex
                            onChanged(shutterSpeed)
                        }
                    }
                    .onEnded { _ in
                        isDragging = false
                        dragOffset = 0
                    }
            )
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

// MARK: - Focus Indicator
struct FocusIndicator: View {
    @State private var scale: CGFloat = 1.3
    @State private var opacity: Double = 1

    var body: some View {
        ZStack {
            // Brackets
            FocusBrackets()
                .stroke(Color.white, lineWidth: 1.5)
                .frame(width: 70, height: 70)
        }
        .scaleEffect(scale)
        .opacity(opacity)
        .onAppear {
            withAnimation(.easeOut(duration: 0.2)) { scale = 1 }
            withAnimation(.easeIn(duration: 1).delay(0.5)) { opacity = 0 }
        }
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
