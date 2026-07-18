import SwiftUI
import UIKit

// Simple haptics for this file
private struct VFHaptics {
    static func click() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// MARK: - Film Grain Overlay
struct FilmGrainOverlay: View {
    @State private var noiseOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                // Create noise pattern
                for _ in 0..<Int(size.width * size.height * 0.01) {
                    let x = CGFloat.random(in: 0...size.width)
                    let y = CGFloat.random(in: 0...size.height)
                    let opacity = CGFloat.random(in: 0.02...0.08)

                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 1.5)),
                        with: .color(.white.opacity(opacity))
                    )
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Viewfinder Overlay (matches Figma design)
struct ViewfinderOverlay: View {
    let showGrid: Bool
    @Binding var aspectRatio: AspectRatioMode
    @Binding var filmFilter: FilmFilterMode
    @Binding var lensFX: LensFXMode
    @State private var showFilmMenu = false
    @State private var showFXMenu = false

    private let filmAccent = Color(red: 1.0, green: 0.85, blue: 0.35)
    private let fxAccent = Color(red: 0.55, green: 0.88, blue: 0.95)
    private let chromeInset: CGFloat = 12
    private let chromeHit: CGFloat = 44

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Decorative layer — never steal focus/morph gestures
                ZStack {
                    FilmGrainOverlay()
                        .opacity(0.3)

                    if lensFX == .vhs {
                        ScanlineShaderOverlay()
                    }

                    CenterFocusBrackets()

                    if showGrid {
                        GridLines()
                    }

                    if aspectRatio != .full {
                        AspectRatioMask(mode: aspectRatio, size: geo.size)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)

            }
            // Overlay chrome keeps hit targets to control bounds only.
            // (`.position()` expands layout/hit area to the full GeometryReader.)
            .overlay(alignment: .topLeading) {
                vfChromeButton(active: false, accent: .white) {
                    Text(aspectRatio.label)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.9))
                } action: {
                    VFHaptics.click()
                    aspectRatio = aspectRatio.next
                }
                .padding(chromeInset)
            }
            .overlay(alignment: .topTrailing) {
                VStack(spacing: 8) {
                    vfChromeButton(active: filmFilter != .none, accent: filmAccent) {
                        Image(systemName: "film")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(filmFilter == .none ? .white.opacity(0.8) : filmAccent)
                    } action: {
                        VFHaptics.click()
                        showFXMenu = false
                        showFilmMenu.toggle()
                    }

                    vfChromeButton(active: lensFX != .none, accent: fxAccent) {
                        Image(systemName: "water.waves")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(lensFX == .none ? .white.opacity(0.8) : fxAccent)
                    } action: {
                        VFHaptics.click()
                        showFilmMenu = false
                        showFXMenu.toggle()
                    }
                }
                .padding(chromeInset)
            }
            .overlay {
                if showFilmMenu || showFXMenu {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            showFilmMenu = false
                            showFXMenu = false
                        }
                }
            }
            .overlay(alignment: .topTrailing) {
                Group {
                    if showFilmMenu {
                        LeicaFilmPicker(
                            selectedFilter: $filmFilter,
                            isPresented: $showFilmMenu
                        )
                    } else if showFXMenu {
                        LensFXPicker(
                            selectedFX: $lensFX,
                            isPresented: $showFXMenu
                        )
                    }
                }
                .padding(.trailing, chromeInset)
                .padding(.top, chromeInset + chromeHit + (showFXMenu ? chromeHit + 8 : 0) + 8)
            }
        }
    }

    @ViewBuilder
    private func vfChromeButton<Label: View>(
        active: Bool,
        accent: Color,
        @ViewBuilder label: () -> Label,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(active ? 0.55 : 0.4))
                    .frame(width: 32, height: 32)
                    .overlay(
                        Circle()
                            .stroke(active ? accent.opacity(0.45) : Color.white.opacity(0.12), lineWidth: 1)
                    )
                label()
            }
            .frame(width: chromeHit, height: chromeHit)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Aspect Ratio Mode
enum AspectRatioMode: CaseIterable {
    case full, ratio4x3, ratio1x1, ratio16x9, ratio3x2

    var label: String {
        switch self {
        case .full: return "FULL"
        case .ratio4x3: return "4:3"
        case .ratio1x1: return "1:1"
        case .ratio16x9: return "16:9"
        case .ratio3x2: return "3:2"
        }
    }

    var next: AspectRatioMode {
        let all = AspectRatioMode.allCases
        let idx = all.firstIndex(of: self) ?? 0
        return all[(idx + 1) % all.count]
    }
}

// MARK: - Film Filter Mode (classic color grades / film stocks)
enum FilmFilterMode: CaseIterable {
    case none, portra400, kodakGold, ektar100, trix400, velvia50, cinestill800, instant

    var name: String {
        switch self {
        case .none: return "None"
        case .portra400: return "Portra 400"
        case .kodakGold: return "Kodak Gold"
        case .ektar100: return "Ektar 100"
        case .trix400: return "Tri-X 400"
        case .velvia50: return "Velvia 50"
        case .cinestill800: return "CineStill 800T"
        case .instant: return "Instant"
        }
    }
}

// MARK: - Aspect Ratio Mask
struct AspectRatioMask: View {
    let mode: AspectRatioMode
    let size: CGSize

    var body: some View {
        let targetRatio: CGFloat = {
            switch mode {
            case .full: return size.width / size.height
            case .ratio4x3: return 4.0 / 3.0
            case .ratio1x1: return 1.0
            case .ratio16x9: return 16.0 / 9.0
            case .ratio3x2: return 3.0 / 2.0
            }
        }()

        let currentRatio = size.width / size.height

        GeometryReader { geo in
            if targetRatio > currentRatio {
                // Letterbox (bars top/bottom)
                let newHeight = size.width / targetRatio
                let barHeight = (size.height - newHeight) / 2
                VStack(spacing: 0) {
                    Rectangle().fill(Color.black.opacity(0.7)).frame(height: barHeight)
                    Spacer()
                    Rectangle().fill(Color.black.opacity(0.7)).frame(height: barHeight)
                }
            } else {
                // Pillarbox (bars left/right)
                let newWidth = size.height * targetRatio
                let barWidth = (size.width - newWidth) / 2
                HStack(spacing: 0) {
                    Rectangle().fill(Color.black.opacity(0.7)).frame(width: barWidth)
                    Spacer()
                    Rectangle().fill(Color.black.opacity(0.7)).frame(width: barWidth)
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Viewfinder Bracket
struct ViewfinderBracket: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            let length: CGFloat = 24
            let thickness: CGFloat = 2

            // Vertical line
            path.move(to: CGPoint(x: 0, y: length))
            path.addLine(to: CGPoint(x: 0, y: 0))
            // Horizontal line
            path.addLine(to: CGPoint(x: length, y: 0))

            context.stroke(path, with: .color(.white.opacity(0.7)), lineWidth: thickness)
        }
        .frame(width: 28, height: 28)
    }
}

// MARK: - Center Focus Brackets
struct CenterFocusBrackets: View {
    var body: some View {
        HStack(spacing: 8) {
            // Left bracket - curved
            CurvedBracket(facing: .left)
                .frame(width: 20, height: 24)

            // Horizontal line
            Rectangle()
                .fill(Color.white.opacity(0.7))
                .frame(width: 16, height: 1.5)

            // Center oval
            Capsule()
                .stroke(Color.white.opacity(0.7), lineWidth: 1.5)
                .frame(width: 32, height: 18)

            // Horizontal line
            Rectangle()
                .fill(Color.white.opacity(0.7))
                .frame(width: 16, height: 1.5)

            // Right bracket - curved
            CurvedBracket(facing: .right)
                .frame(width: 20, height: 24)
        }
    }
}

enum BracketDirection {
    case left, right
}

struct CurvedBracket: View {
    let facing: BracketDirection

    var body: some View {
        Canvas { context, size in
            var path = Path()

            if facing == .left {
                path.move(to: CGPoint(x: size.width, y: 0))
                path.addQuadCurve(
                    to: CGPoint(x: size.width, y: size.height),
                    control: CGPoint(x: 0, y: size.height/2)
                )
            } else {
                path.move(to: CGPoint(x: 0, y: 0))
                path.addQuadCurve(
                    to: CGPoint(x: 0, y: size.height),
                    control: CGPoint(x: size.width, y: size.height/2)
                )
            }

            context.stroke(path, with: .color(.white.opacity(0.7)), lineWidth: 1.5)
        }
    }
}

// MARK: - Grid Lines
struct GridLines: View {
    var body: some View {
        GeometryReader { geo in
            Path { path in
                let w = geo.size.width
                let h = geo.size.height

                // Vertical lines
                path.move(to: CGPoint(x: w/3, y: 0))
                path.addLine(to: CGPoint(x: w/3, y: h))
                path.move(to: CGPoint(x: 2*w/3, y: 0))
                path.addLine(to: CGPoint(x: 2*w/3, y: h))

                // Horizontal lines
                path.move(to: CGPoint(x: 0, y: h/3))
                path.addLine(to: CGPoint(x: w, y: h/3))
                path.move(to: CGPoint(x: 0, y: 2*h/3))
                path.addLine(to: CGPoint(x: w, y: 2*h/3))
            }
            .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
        }
    }
}

// MARK: - Histogram View
struct HistogramView: View {
    var body: some View {
        Canvas { context, size in
            let barCount = 40
            let barWidth = size.width / CGFloat(barCount)

            for i in 0..<barCount {
                let x = CGFloat(i) * barWidth
                let normalizedI = CGFloat(i) / CGFloat(barCount)

                // Create realistic histogram shape
                var heightMultiplier: CGFloat = 0

                // Shadow peak (left)
                heightMultiplier += exp(-pow((normalizedI - 0.15) * 5, 2)) * 0.4

                // Midtone peak (center-left)
                heightMultiplier += exp(-pow((normalizedI - 0.35) * 4, 2)) * 0.7

                // Highlight peak (right)
                heightMultiplier += exp(-pow((normalizedI - 0.75) * 5, 2)) * 0.5

                // Add some noise
                heightMultiplier += CGFloat.random(in: 0.05...0.15)

                let barHeight = size.height * min(heightMultiplier, 1.0)

                let rect = CGRect(x: x, y: size.height - barHeight, width: barWidth - 0.5, height: barHeight)
                context.fill(Path(rect), with: .color(.white.opacity(0.8)))
            }
        }
        .frame(width: 70, height: 35)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
        )
    }
}

// MARK: - Info Bar (matches Figma design)
struct InfoBar: View {
    let iso: Int
    let shutterSpeed: String
    let aperture: Float
    let photoCount: Int
    let isAutoISO: Bool

    init(iso: Int, shutterSpeed: String, aperture: Float, photoCount: Int, isAutoISO: Bool = true) {
        self.iso = iso
        self.shutterSpeed = shutterSpeed
        self.aperture = aperture
        self.photoCount = photoCount
        self.isAutoISO = isAutoISO
    }

    var body: some View {
        HStack(spacing: 8) {
            // Histogram with blue tint (matches Figma)
            HistogramView()

            // Center info - matches Figma layout
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("HEIC")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)

                    // Large badge
                    Text("L")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(2)

                    Text("1:1")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                }

                HStack(spacing: 8) {
                    Text(formatNumber(photoCount))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))

                    Text("F\(String(format: "%.1f", aperture))")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                }
            }

            Spacer()

            // Right info - matches Figma
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 3) {
                    // Auto badge
                    Text("A")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(2)
                        .opacity(isAutoISO ? 1 : 0)

                    Text("ISO \(iso)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                }

                Text(shutterSpeed)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.6))
        )
    }

    private func formatNumber(_ num: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: num)) ?? "\(num)"
    }
}

// MARK: - Film Picker (DSLR-style inset menu)
struct LeicaFilmPicker: View {
    @Binding var selectedFilter: FilmFilterMode
    @Binding var isPresented: Bool

    private let accent = Color(red: 1.0, green: 0.85, blue: 0.35)
    @State private var animateIn = false

    var body: some View {
        // DSLR-style inset panel with context menu animation
        VStack(spacing: 0) {
            // Header with inset style
            HStack {
                Text("FILM")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Text("STOCK")
                    .font(.system(size: 8, weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.28))
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Rectangle()
                .fill(Color(hex: "2a2a2a"))
                .frame(height: 1)
                .padding(.horizontal, 8)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(FilmFilterMode.allCases, id: \.self) { filter in
                        Button(action: {
                            VFHaptics.click()
                            selectedFilter = filter
                            dismissWithAnimation()
                        }) {
                            HStack(spacing: 8) {
                                Text(selectedFilter == filter ? ">" : " ")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(accent)
                                    .frame(width: 12)

                                Text(filter.name.uppercased())
                                    .font(.system(size: 11, weight: selectedFilter == filter ? .semibold : .regular, design: .monospaced))
                                    .foregroundColor(selectedFilter == filter ? .white : .white.opacity(0.6))

                                Spacer()

                                if filter != .none {
                                    Text(isoLabel(for: filter))
                                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.3))
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(selectedFilter == filter ? Color.white.opacity(0.05) : Color.clear)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 250)

            Spacer().frame(height: 6)
        }
        // NOTE: must be a chained modifier. `.background(dsPickerChrome())`
        // resolves to `.background(self.dsPickerChrome())`, embedding the
        // picker inside itself -> infinite recursion -> stack overflow crash.
        .dsPickerChrome()
        .frame(width: 180)
        .scaleEffect(animateIn ? 1.0 : 0.8)
        .opacity(animateIn ? 1.0 : 0)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: animateIn)
        .onAppear {
            withAnimation {
                animateIn = true
            }
        }
    }

    private func dismissWithAnimation() {
        withAnimation(.easeOut(duration: 0.15)) {
            animateIn = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isPresented = false
        }
    }

    private func isoLabel(for filter: FilmFilterMode) -> String {
        switch filter {
        case .none: return ""
        case .portra400: return "400"
        case .kodakGold: return "200"
        case .ektar100: return "100"
        case .trix400: return "400"
        case .velvia50: return "50"
        case .cinestill800: return "800T"
        case .instant: return "SX70"
        }
    }
}

// MARK: - Shared DSLR inset chrome for film / FX pickers
private struct DSLRPickerChrome: ViewModifier {
    func body(content: Content) -> some View {
        content.background(
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex: "0d0d0d"))

                // Top + left inset shade (matches viewfinder DSLR recess)
                VStack(spacing: 0) {
                    LinearGradient(colors: [Color.black.opacity(0.55), Color.clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 12)
                    Spacer(minLength: 0)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack(spacing: 0) {
                    LinearGradient(colors: [Color.black.opacity(0.45), Color.clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 8)
                    Spacer(minLength: 0)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))

                // Soft bottom/right lift
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    LinearGradient(colors: [Color.clear, Color.white.opacity(0.03)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 8)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))

                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(hex: "2a2a2a"), lineWidth: 1)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.black.opacity(0.7), lineWidth: 2)
                            .padding(1)
                    )
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.45), radius: 8, x: 0, y: 4)
    }
}

private extension View {
    func dsPickerChrome() -> some View {
        modifier(DSLRPickerChrome())
    }
}

// MARK: - Lens FX Picker (warp shaders vs look shaders)
struct LensFXPicker: View {
    @Binding var selectedFX: LensFXMode
    @Binding var isPresented: Bool

    private let accent = Color(red: 0.55, green: 0.88, blue: 0.95)
    @State private var animateIn = false

    private var warpCases: [LensFXMode] {
        LensFXMode.pickerCases.filter { $0 == .none || $0.pickerSection == .warp }
    }

    private var lookCases: [LensFXMode] {
        LensFXMode.pickerCases.filter { $0 != .none && $0.pickerSection == .look }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("LENS FX")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Text("SHADER")
                    .font(.system(size: 8, weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.28))
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Rectangle()
                .fill(Color(hex: "2a2a2a"))
                .frame(height: 1)
                .padding(.horizontal, 8)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    sectionHeader("WARP", subtitle: "DRAG TO MORPH")
                    ForEach(warpCases, id: \.self) { fx in
                        fxRow(fx)
                    }

                    sectionHeader("LOOK", subtitle: "STYLE")
                    ForEach(lookCases, id: \.self) { fx in
                        fxRow(fx)
                    }
                }
            }
            .frame(maxHeight: 280)

            Spacer().frame(height: 6)
        }
        // NOTE: must be a chained modifier, NOT `.background(dsPickerChrome())`.
        // That form resolves to `.background(self.dsPickerChrome())` - the picker
        // becomes its own background -> infinite view recursion -> stack overflow.
        .dsPickerChrome()
        .frame(width: 180)
        .scaleEffect(animateIn ? 1.0 : 0.8)
        .opacity(animateIn ? 1.0 : 0)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: animateIn)
        .onAppear {
            withAnimation {
                animateIn = true
            }
        }
    }

    private func sectionHeader(_ title: String, subtitle: String) -> some View {
        VStack(spacing: 4) {
            if title == "LOOK" {
                Rectangle()
                    .fill(Color(hex: "2a2a2a"))
                    .frame(height: 1)
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.38))
                    .tracking(1.0)
                Spacer()
                Text(subtitle)
                    .font(.system(size: 7, weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.22))
                    .tracking(0.4)
            }
            .padding(.horizontal, 14)
            .padding(.top, title == "WARP" ? 8 : 6)
            .padding(.bottom, 2)
        }
    }

    private func fxRow(_ fx: LensFXMode) -> some View {
        Button(action: {
            VFHaptics.click()
            selectedFX = fx
            dismissWithAnimation()
        }) {
            HStack(spacing: 8) {
                Text(selectedFX == fx ? ">" : " ")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(accent)
                    .frame(width: 12)

                Text(fx.name.uppercased())
                    .font(.system(size: 11, weight: selectedFX == fx ? .semibold : .regular, design: .monospaced))
                    .foregroundColor(selectedFX == fx ? .white : .white.opacity(0.6))

                Spacer()

                if fx.isTouchReactive {
                    Text("TOUCH")
                        .font(.system(size: 7, weight: .semibold, design: .monospaced))
                        .foregroundColor(accent.opacity(selectedFX == fx ? 0.85 : 0.45))
                        .tracking(0.3)
                } else if fx != .none {
                    Text(fx.badge)
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(selectedFX == fx ? Color.white.opacity(0.05) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func dismissWithAnimation() {
        withAnimation(.easeOut(duration: 0.15)) {
            animateIn = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isPresented = false
        }
    }
}

// MARK: - Scanline Overlay (VHS mode)
// Drawn in SwiftUI rather than ShaderLibrary — avoids a hard crash on devices
// where the Metal stitchable library fails to resolve at first FX toggle.
struct ScanlineShaderOverlay: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 3
            var y: CGFloat = 0
            while y < size.height {
                let rect = CGRect(x: 0, y: y, width: size.width, height: 1)
                context.fill(Path(rect), with: .color(.black.opacity(0.28)))
                y += spacing
            }
        }
        .allowsHitTesting(false)
    }
}
