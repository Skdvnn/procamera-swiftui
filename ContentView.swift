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

// MARK: - Design System
struct DS {
    // Colors - not pure black, layered grays
    static let pageBg = Color(white: 0.07)           // #121212 - main background
    static let controlBg = Color(white: 0.05)        // #0D0D0D - control background
    static let controlBgLight = Color(white: 0.09)   // #171717 - lighter control bg
    static let strokeOuter = Color(white: 0.18)      // outer stroke
    static let strokeInner = Color(white: 0.08)      // inner stroke
    static let textPrimary = Color.white.opacity(0.9)
    static let textSecondary = Color.white.opacity(0.5)
    static let accent = Color(red: 1.0, green: 0.85, blue: 0.35) // golden yellow

    // Spacing
    static let pageMargin: CGFloat = 20

    // Radius
    static let radiusSmall: CGFloat = 8
    static let radiusMedium: CGFloat = 12
    static let radiusLarge: CGFloat = 16
    static let radiusPill: CGFloat = 22

    // Font
    static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
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

    private let modes = ["P", "A", "T"]
    private let isoValues = [100, 200, 400, 800, 1600, 3200]
    private let focalLengths = [24, 28, 35, 50, 70, 85, 105]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Vulcanite black background with grain
                vulcaniteBlack.ignoresSafeArea()
                VulcaniteGrain().ignoresSafeArea()

                VStack(spacing: 0) {
                    // TOP: Analog Display Panel - compact
                    AnalogDisplayPanel(
                        focusPosition: $focusPosition,
                        exposureValue: $exposureValue,
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
                    .frame(height: 120)
                    .padding(.horizontal, DS.pageMargin)

                    Spacer().frame(height: 6)

                    // VIEWFINDER - full width with 20px margins
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

                        ViewfinderOverlay(showGrid: showGrid)
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
                            .padding(.horizontal, 8)
                            .padding(.bottom, 6)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(3.0/4.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: DS.radiusMedium))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.radiusMedium)
                            .stroke(DS.strokeInner, lineWidth: 2)
                    )
                    .shadow(color: Color.black.opacity(0.4), radius: 4, y: 2)
                    .padding(.horizontal, DS.pageMargin)

                    Spacer().frame(height: 6)

                    // LENS RING SLIDER (Zoom) - centered
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
                    .frame(maxWidth: 260)

                    Spacer().frame(height: 8)

                    // BOTTOM CONTROLS - compact, centered
                    VStack(spacing: 10) {
                        // ROW 1: Flash | WB | Aperture - centered
                        HStack(spacing: 0) {
                            Spacer()
                            FlashButton(flashMode: camera.flashMode) {
                                Haptics.click()
                                camera.cycleFlash()
                            }
                            Spacer()
                            WBPill(
                                whiteBalanceIndex: $whiteBalanceIndex,
                                onChanged: { mode in
                                    camera.setWhiteBalance(mode: mode)
                                }
                            )
                            Spacer()
                            ApertureDial(
                                aperture: $apertureValue,
                                onChanged: { newAperture in
                                    let baseAperture: Float = 2.8
                                    let stops = log2(newAperture / baseAperture)
                                    let evAdjust = -stops * 0.5
                                    exposureValue = max(-2, min(2, evAdjust))
                                    camera.setExposure(exposureValue)
                                }
                            )
                            .frame(width: 90, height: 100)
                            Spacer()
                        }
                        .padding(.horizontal, DS.pageMargin)

                        // ROW 2: Thumbnail | Shutter | ISO - centered
                        HStack(spacing: 0) {
                            Spacer()
                            ThumbnailView(image: lastCapturedImage)
                            Spacer()
                            ShutterButton(isCapturing: isCapturing) {
                                Haptics.heavy()
                                handleCapture()
                            }
                            Spacer()
                            ISOPill(
                                iso: $isoValue,
                                isoValues: isoValues,
                                onChanged: { iso in
                                    camera.setISO(Float(iso))
                                }
                            )
                            Spacer()
                        }
                        .padding(.horizontal, DS.pageMargin)
                    }
                    .padding(.bottom, DS.pageMargin)
                }

                if showFlash {
                    Color.white.ignoresSafeArea()
                }
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(false)
        .onAppear { camera.checkPermissions() }
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

// MARK: - Lens Ring Control
struct LensRingControl: View {
    @Binding var focalLength: Int
    @Binding var isoValue: Int
    let onFocalLengthChanged: (Int) -> Void
    let onISOChanged: (Int) -> Void

    private let focalLengths = [24, 28, 35, 50, 70, 85, 105]
    private let isoValues = [100, 200, 400, 800, 1600, 3200]

    @State private var tickOffset: CGFloat = 0
    @State private var accumulatedDrag: CGFloat = 0

    private var currentIndex: Int {
        focalLengths.firstIndex(of: focalLength) ?? 0
    }

    private var nextFocalLength: Int? {
        let idx = currentIndex
        return idx < focalLengths.count - 1 ? focalLengths[idx + 1] : nil
    }

    private var prevFocalLength: Int? {
        let idx = currentIndex
        return idx > 0 ? focalLengths[idx - 1] : nil
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width

            ZStack {
                // Background pill
                RoundedRectangle(cornerRadius: DS.radiusMedium)
                    .fill(DS.controlBg)

                // Outer stroke
                RoundedRectangle(cornerRadius: DS.radiusMedium)
                    .stroke(DS.strokeOuter, lineWidth: 1)

                // Inner stroke
                RoundedRectangle(cornerRadius: DS.radiusMedium - 2)
                    .stroke(DS.strokeInner, lineWidth: 1)
                    .padding(2)

                // Bottom tick marks (ruler scale) - contained within bounds
                HStack(spacing: 4) {
                    ForEach(0..<20, id: \.self) { i in
                        Rectangle()
                            .fill(Color.white.opacity(i % 4 == 0 ? 0.4 : 0.2))
                            .frame(width: 1, height: i % 4 == 0 ? 7 : 4)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 8)
                .offset(x: tickOffset * 0.2)

                // Content overlay
                HStack(spacing: 0) {
                    // LEFT: Dots
                    HStack(spacing: 4) {
                        ForEach(0..<min(currentIndex, 3), id: \.self) { _ in
                            Circle()
                                .fill(Color.white.opacity(0.35))
                                .frame(width: 4, height: 4)
                        }
                    }
                    .frame(width: 50, alignment: .trailing)

                    Spacer()

                    // CENTER: Focal length + indicator
                    VStack(spacing: 2) {
                        Text("\(focalLength)MM")
                            .font(DS.mono(14, weight: .bold))
                            .foregroundColor(DS.accent)

                        Rectangle()
                            .fill(DS.accent)
                            .frame(width: 2, height: 8)
                    }

                    Spacer()

                    // RIGHT: Next focal + dots
                    HStack(spacing: 6) {
                        if let next = nextFocalLength {
                            Text("\(next)")
                                .font(DS.mono(12, weight: .medium))
                                .foregroundColor(DS.textSecondary)
                        }

                        HStack(spacing: 4) {
                            ForEach(0..<min(focalLengths.count - 1 - currentIndex, 3), id: \.self) { _ in
                                Circle()
                                    .fill(Color.white.opacity(0.35))
                                    .frame(width: 4, height: 4)
                            }
                        }
                    }
                    .frame(width: 60, alignment: .leading)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            }
            .shadow(color: Color.black.opacity(0.3), radius: 4, y: 2)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        // Animate tick offset for visual feedback
                        tickOffset = value.translation.width

                        // Track accumulated drag for step changes
                        let stepWidth: CGFloat = 50
                        let steps = Int((value.translation.width - accumulatedDrag) / stepWidth)

                        if steps != 0 {
                            accumulatedDrag += CGFloat(steps) * stepWidth

                            if steps < 0 {
                                // Dragging left = increase focal length
                                for _ in 0..<abs(steps) {
                                    if currentIndex < focalLengths.count - 1 {
                                        Haptics.light()
                                        focalLength = focalLengths[currentIndex + 1]
                                        onFocalLengthChanged(focalLength)
                                    }
                                }
                            } else {
                                // Dragging right = decrease focal length
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
                        accumulatedDrag = 0
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            tickOffset = 0
                        }
                    }
            )
            .onTapGesture {
                // Tap to cycle ISO
                Haptics.click()
                if let idx = isoValues.firstIndex(of: isoValue) {
                    isoValue = isoValues[(idx + 1) % isoValues.count]
                    onISOChanged(isoValue)
                }
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

// MARK: - Shutter Button (Rich metal shader with press feel)
struct ShutterButton: View {
    let isCapturing: Bool
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            ZStack {
                // Outer bezel - brushed metal look
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(white: 0.25),
                                Color(white: 0.12),
                                Color(white: 0.08),
                                Color(white: 0.15)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 76, height: 76)

                // Outer ring highlight
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.3), Color.white.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1.5
                    )
                    .frame(width: 76, height: 76)

                // Inner button face - rich metal gradient
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color(white: isPressed ? 0.12 : 0.18),
                                Color(white: isPressed ? 0.06 : 0.10),
                                Color(white: isPressed ? 0.04 : 0.06)
                            ],
                            center: UnitPoint(x: 0.35, y: 0.35),
                            startRadius: 0,
                            endRadius: 35
                        )
                    )
                    .frame(width: 62, height: 62)

                // Inner highlight ring
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(isPressed ? 0.05 : 0.15),
                                Color.clear,
                                Color.black.opacity(0.2)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
                    .frame(width: 58, height: 58)

                // Center detail ring
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                    .frame(width: 40, height: 40)

                // Capturing flash
                if isCapturing {
                    Circle()
                        .fill(Color.white.opacity(0.3))
                        .frame(width: 62, height: 62)
                }
            }
            .shadow(color: Color.black.opacity(0.5), radius: isPressed ? 3 : 8, y: isPressed ? 1 : 4)
            .scaleEffect(isPressed ? 0.96 : 1.0)
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

// MARK: - Flash Button (Shows current flash mode clearly)
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

// MARK: - WB Pill (Figma-style: stacked strokes, fixed width)
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
            HStack(spacing: 5) {
                Text("WB")
                    .font(DS.mono(12, weight: .medium))
                    .foregroundColor(DS.textPrimary)

                Text(wbModes[whiteBalanceIndex])
                    .font(DS.mono(12, weight: .medium))
                    .foregroundColor(DS.textSecondary)
                    .frame(width: 44, alignment: .leading) // Fixed width for stability
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: DS.radiusMedium)
                        .fill(DS.controlBg)

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

// MARK: - Aperture Dial (Larger, easier to use)
struct ApertureDial: View {
    @Binding var aperture: Float
    let onChanged: (Float) -> Void

    private let fStops: [Float] = [2.8, 4.0, 5.6, 8.0, 11, 16]

    @State private var dragStartIndex: Int = 0
    @State private var isDragging: Bool = false
    @State private var dragAccumulator: CGFloat = 0

    private var currentIndex: Int {
        fStops.firstIndex(where: { abs($0 - aperture) < 0.5 }) ?? 0
    }

    var body: some View {
        VStack(spacing: 2) {
            // Triangle pointer at top
            Image(systemName: "arrowtriangle.down.fill")
                .font(.system(size: 10))
                .foregroundColor(DS.textSecondary)

            // The dial - LARGER
            ZStack {
                // Dial background
                Circle()
                    .fill(DS.controlBg)

                // Outer stroke
                Circle()
                    .stroke(DS.strokeOuter, lineWidth: 1.5)

                // Inner stroke
                Circle()
                    .stroke(DS.strokeInner, lineWidth: 1)
                    .padding(3)

                // Rotating content
                let rotation = -Double(currentIndex) * (360.0 / Double(fStops.count))

                ZStack {
                    // F-stop numbers - larger font
                    ForEach(0..<fStops.count, id: \.self) { i in
                        let angle = Double(i) * (360.0 / Double(fStops.count))

                        Text(fStopLabel(fStops[i]))
                            .font(DS.mono(11, weight: .semibold))
                            .foregroundColor(DS.textPrimary)
                            .offset(y: -28)
                            .rotationEffect(.degrees(angle))
                    }

                    // Tick marks
                    ForEach(0..<(fStops.count * 2), id: \.self) { i in
                        Rectangle()
                            .fill(Color.white.opacity(i % 2 == 0 ? 0.5 : 0.25))
                            .frame(width: 1.5, height: i % 2 == 0 ? 7 : 4)
                            .offset(y: -38)
                            .rotationEffect(.degrees(Double(i) * (360.0 / Double(fStops.count * 2))))
                    }
                }
                .rotationEffect(.degrees(rotation))
                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: currentIndex)
            }
            .frame(width: 82, height: 82)
            .shadow(color: Color.black.opacity(0.4), radius: 5, y: 2)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            dragStartIndex = currentIndex
                            dragAccumulator = 0
                        }
                        // Smoother drag - accumulate small movements
                        dragAccumulator = value.translation.width
                        let stepSize: CGFloat = 20 // Easier to trigger
                        let steps = Int(dragAccumulator / stepSize)
                        let newIndex = max(0, min(fStops.count - 1, dragStartIndex + steps))

                        if newIndex != currentIndex {
                            Haptics.light()
                            aperture = fStops[newIndex]
                            onChanged(aperture)
                        }
                    }
                    .onEnded { _ in
                        isDragging = false
                        dragAccumulator = 0
                    }
            )
            .onTapGesture {
                Haptics.click()
                let newIndex = (currentIndex + 1) % fStops.count
                aperture = fStops[newIndex]
                onChanged(aperture)
            }
        }
    }

    private func fStopLabel(_ f: Float) -> String {
        if f >= 10 {
            return String(format: "%.0f", f)
        } else if f == floor(f) {
            return String(format: "%.0f", f)
        }
        return String(format: "%.1f", f)
    }
}

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

// MARK: - ISO Pill (Figma-style - stacked strokes, fixed width)
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
                    .frame(width: 36, alignment: .leading) // Fixed width for stability
            }
            .frame(width: 82) // Fixed total width
            .padding(.vertical, 12)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: DS.radiusMedium)
                        .fill(DS.controlBg)

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

// MARK: - Thumbnail View (Figma-style - stacked strokes)
struct ThumbnailView: View {
    let image: UIImage?

    var body: some View {
        ZStack {
            // Frame background
            RoundedRectangle(cornerRadius: DS.radiusMedium)
                .fill(DS.controlBg)

            // Outer stroke
            RoundedRectangle(cornerRadius: DS.radiusMedium)
                .stroke(DS.strokeOuter, lineWidth: 1)

            // Inner stroke
            RoundedRectangle(cornerRadius: DS.radiusMedium - 2)
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
                        .font(.system(size: 18))
                        .foregroundColor(DS.textSecondary)
                }
            }
            .frame(width: 58, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: DS.radiusSmall))
        }
        .frame(width: 68, height: 54)
        .shadow(color: Color.black.opacity(0.3), radius: 4, y: 2)
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
