import SwiftUI
import UIKit

// Simple haptics for this file
private struct VFHaptics {
    static func click() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// MARK: - Cached grain textures (Canvas re-raster was a major lag source)

enum CachedGrainTexture {
    private static var cache: [Int: UIImage] = [:]
    private static let lock = NSLock()

    static func image(for size: CGSize, density: CGFloat, seed: UInt64, darkSpeckDensity: CGFloat = 0) -> UIImage {
        let w = max(64, (Int(size.width) / 64) * 64)
        let h = max(64, (Int(size.height) / 64) * 64)
        let key = (w &<< 16) ^ h ^ Int(density * 10_000) ^ Int(seed & 0xFFFF)
        lock.lock()
        if let hit = cache[key] {
            lock.unlock()
            return hit
        }
        lock.unlock()

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: w, height: h))
        let img = renderer.image { ctx in
            UIColor.clear.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            var rng = SeededGenerator(seed: seed)
            let count = Int(CGFloat(w * h) * density)
            for _ in 0..<count {
                let x = CGFloat.random(in: 0...CGFloat(w), using: &rng)
                let y = CGFloat.random(in: 0...CGFloat(h), using: &rng)
                let opacity = CGFloat.random(in: 0.02...0.08, using: &rng)
                let dot = CGFloat.random(in: 0.8...1.6, using: &rng)
                UIColor.white.withAlphaComponent(opacity).setFill()
                ctx.cgContext.fillEllipse(in: CGRect(x: x, y: y, width: dot, height: dot))
            }
            if darkSpeckDensity > 0 {
                let darkCount = Int(CGFloat(w * h) * darkSpeckDensity)
                for _ in 0..<darkCount {
                    let x = CGFloat.random(in: 0...CGFloat(w), using: &rng)
                    let y = CGFloat.random(in: 0...CGFloat(h), using: &rng)
                    let opacity = CGFloat.random(in: 0.08...0.15, using: &rng)
                    UIColor.black.withAlphaComponent(opacity).setFill()
                    ctx.cgContext.fillEllipse(in: CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
        lock.lock()
        cache[key] = img
        lock.unlock()
        return img
    }
}

// MARK: - Film Grain Overlay
struct FilmGrainOverlay: View {
    var body: some View {
        // One rasterized texture per size bucket — never re-draw thousands of ellipses.
        GeometryReader { geo in
            Image(uiImage: CachedGrainTexture.image(for: geo.size, density: 0.006, seed: 0xC0FFEE))
                .resizable()
                .interpolation(.none)
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
        }
        .allowsHitTesting(false)
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0xdeadbeef : seed }
    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
}

// MARK: - Viewfinder Overlay (matches Figma design)
struct ViewfinderOverlay: View {
    let showGrid: Bool
    @Binding var aspectRatio: AspectRatioMode
    @Binding var filmFilter: FilmFilterMode
    @Binding var lensFX: LensFXMode
    @Binding var focusPeaking: Bool
    /// Landscape: tuck pickers closer to the top chrome.
    var compactChrome: Bool = false
    var onFlipCamera: (() -> Void)? = nil
    var onSaveLook: (() -> Void)? = nil
    /// Scene presets live in the film dock (Street chip removed).
    var shootMode: ShootMode = .street
    var onApplyShootMode: ((ShootMode) -> Void)? = nil
    @ObservedObject var lookStore: LookRecipeStore = .shared
    @State private var showFilmMenu = false
    @State private var showFXMenu = false
    @State private var showRecipeMenu = false

    var body: some View {
        // ZStack (not a hit-blocking Color.clear root): empty space passes
        // taps to the shutter dock underneath (this view sits at zIndex 40).
        ZStack(alignment: .topTrailing) {
            GeometryReader { geo in
                ZStack {
                    if filmFilter != .none {
                        FilmGrainOverlay()
                            .opacity(0.32)
                    }
                    if lensFX == .vhs {
                        ScanlineShaderOverlay()
                    }
                    CenterFocusBrackets()
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    if showGrid {
                        GridLines()
                    }
                    if aspectRatio != .full {
                        AspectRatioMask(mode: aspectRatio, size: geo.size)
                    }
                }
            }
            .allowsHitTesting(false)

            VStack {
                HStack(alignment: .top) {
                    VStack(spacing: 8) {
                        chromeButton {
                            showFilmMenu = false
                            showFXMenu = false
                            showRecipeMenu = false
                            aspectRatio = aspectRatio.next
                        } label: {
                            Text(aspectRatio.label)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.9))
                        }

                        chromeButton {
                            onFlipCamera?()
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath.camera")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.85))
                        }

                        chromeButton {
                            var t = Transaction()
                            t.disablesAnimations = true
                            withTransaction(t) {
                                focusPeaking.toggle()
                            }
                        } label: {
                            Image(systemName: "plus.viewfinder")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(focusPeaking
                                                 ? Color(red: 0.35, green: 0.95, blue: 0.45)
                                                 : .white.opacity(0.8))
                        }
                    }
                    .padding(16)

                    Spacer().allowsHitTesting(false)

                    VStack(spacing: 8) {
                        chromeButton {
                            var t = Transaction()
                            t.disablesAnimations = true
                            withTransaction(t) {
                                showFXMenu = false
                                showRecipeMenu = false
                                showFilmMenu.toggle()
                            }
                        } label: {
                            Image(systemName: "film")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(showFilmMenu || filmFilter != .none
                                                 ? Color(red: 1.0, green: 0.85, blue: 0.35)
                                                 : .white.opacity(0.8))
                        }

                        chromeButton {
                            var t = Transaction()
                            t.disablesAnimations = true
                            withTransaction(t) {
                                showFilmMenu = false
                                showRecipeMenu = false
                                showFXMenu.toggle()
                            }
                        } label: {
                            Image(systemName: "water.waves")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(showFXMenu || lensFX != .none
                                                 ? Color(red: 0.55, green: 0.88, blue: 0.95)
                                                 : .white.opacity(0.8))
                        }

                        chromeButton {
                            var t = Transaction()
                            t.disablesAnimations = true
                            withTransaction(t) {
                                showFilmMenu = false
                                showFXMenu = false
                                showRecipeMenu.toggle()
                            }
                        } label: {
                            Image(systemName: "bookmark.fill")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(showRecipeMenu || !lookStore.recipes.isEmpty
                                                 ? Color(red: 1.0, green: 0.75, blue: 0.45)
                                                 : .white.opacity(0.8))
                        }
                    }
                    .padding(16)
                }
                Spacer().allowsHitTesting(false)
            }

            if showFilmMenu || showFXMenu || showRecipeMenu {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        var t = Transaction()
                        t.disablesAnimations = true
                        withTransaction(t) {
                            showFilmMenu = false
                            showFXMenu = false
                            showRecipeMenu = false
                        }
                    }
            }

            if showFilmMenu {
                LeicaFilmPicker(
                    selectedFilter: $filmFilter,
                    isPresented: $showFilmMenu,
                    shootMode: shootMode,
                    onApplyShootMode: onApplyShootMode,
                    onSaveLook: { onSaveLook?() }
                )
                .modifier(PickerEntrance())
                .padding(.trailing, compactChrome ? 10 : 16)
                .padding(.top, compactChrome ? 48 : 100)
            }

            if showFXMenu {
                LensFXPicker(
                    selectedFX: $lensFX,
                    isPresented: $showFXMenu
                )
                .modifier(PickerEntrance())
                .padding(.trailing, compactChrome ? 10 : 16)
                .padding(.top, compactChrome ? 72 : 140)
            }

            if showRecipeMenu {
                LookRecipePicker(
                    store: lookStore,
                    filmFilter: $filmFilter,
                    lensFX: $lensFX,
                    isPresented: $showRecipeMenu,
                    onSaveCurrent: { onSaveLook?() }
                )
                .modifier(PickerEntrance())
                .padding(.trailing, compactChrome ? 10 : 16)
                .padding(.top, compactChrome ? 96 : 180)
            }
        }
    }

    /// Soft picker entrance scoped to the picker root — never `withAnimation` on
    /// the overlay ZStack (that walks Metal shutter chrome).
    private struct PickerEntrance: ViewModifier {
        @State private var revealed = false

        func body(content: Content) -> some View {
            content
                .opacity(revealed ? 1 : 0)
                .offset(y: revealed ? 0 : -8)
                .scaleEffect(revealed ? 1 : 0.98, anchor: .topTrailing)
                .onAppear { revealed = true }
                .animation(ShutterMotion.picker, value: revealed)
        }
    }

    private func chromeButton<Label: View>(
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Button(action: {
            VFHaptics.click()
            action()
        }) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.4))
                    .frame(width: 32, height: 32)
                label()
            }
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
/// Single source of truth for UI + CameraManager pipeline (Int raw values stable).
enum FilmFilterMode: Int, CaseIterable, Hashable {
    case none = 0
    case portra400 = 1
    case ektar100 = 2
    case kodakGold = 3
    case trix400 = 4
    case cinestill800 = 5
    case velvia50 = 6
    case instant = 7

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
        let targetRatio: CGFloat = mode.framedAspect(fitting: size) ?? (size.width / size.height)

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
    var shootMode: ShootMode = .street
    var onApplyShootMode: ((ShootMode) -> Void)? = nil
    var onSaveLook: (() -> Void)? = nil

    private let accent = Color(red: 1.0, green: 0.85, blue: 0.35)

    var body: some View {
        // Entrance motion lives on PickerEntrance (local opacity/offset only).
        // Do not wrap apply/dismiss in withAnimation — that walks Metal chrome.
        VStack(spacing: 0) {
            HStack {
                Text("LOOKS")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                if selectedFilter != .none || onSaveLook != nil {
                    Button {
                        VFHaptics.click()
                        onSaveLook?()
                    } label: {
                        Text("SAVE LOOK")
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundColor(accent.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("STOCK")
                        .font(.system(size: 8, weight: .regular, design: .monospaced))
                        .foregroundColor(.white.opacity(0.28))
                }
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
                    if onApplyShootMode != nil {
                        sectionLabel("SCENE")
                        ForEach(ShootMode.allCases) { mode in
                            Button {
                                VFHaptics.click()
                                var t = Transaction()
                                t.disablesAnimations = true
                                withTransaction(t) { isPresented = false }
                                let chosen = mode
                                DispatchQueue.main.async {
                                    onApplyShootMode?(chosen)
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Text(shootMode == mode ? ">" : " ")
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        .foregroundColor(accent)
                                        .frame(width: 12)

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(mode.title.uppercased())
                                            .font(.system(
                                                size: 11,
                                                weight: shootMode == mode ? .semibold : .regular,
                                                design: .monospaced
                                            ))
                                            .foregroundColor(shootMode == mode ? .white : .white.opacity(0.6))
                                        Text(mode.blurb.uppercased())
                                            .font(.system(size: 8, weight: .regular, design: .monospaced))
                                            .foregroundColor(.white.opacity(0.28))
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(shootMode == mode ? Color.white.opacity(0.05) : Color.clear)
                            }
                            .buttonStyle(.plain)
                        }

                        Rectangle()
                            .fill(Color(hex: "2a2a2a"))
                            .frame(height: 1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)

                        sectionLabel("FILM")
                    }

                    ForEach(FilmFilterMode.allCases, id: \.self) { filter in
                        Button(action: {
                            VFHaptics.click()
                            // Same as Lens FX: dismiss first, apply on next turn so
                            // the live Metal/CI preview doesn't enable mid-teardown.
                            var t = Transaction()
                            t.disablesAnimations = true
                            withTransaction(t) {
                                isPresented = false
                            }
                            let chosen = filter
                            DispatchQueue.main.async {
                                selectedFilter = chosen
                            }
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
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: onApplyShootMode != nil ? 320 : 250)

            Spacer().frame(height: 6)
        }
        .background(dsPickerChrome())
        .frame(width: 196)
    }

    private func sectionLabel(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.35))
                .tracking(1.0)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 2)
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

                VStack(spacing: 0) {
                    LinearGradient(colors: [Color.black.opacity(0.5), Color.clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 10)
                    Spacer()
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack(spacing: 0) {
                    LinearGradient(colors: [Color.black.opacity(0.4), Color.clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 8)
                    Spacer()
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))

                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(hex: "1a1a1a"), lineWidth: 2)
            }
        )
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

    /// Stable lists — avoid rebuilding ForEach identity every body pass.
    private static let warpCases: [LensFXMode] = LensFXMode.pickerCases.filter {
        $0 == .none || $0.pickerSection == .warp
    }
    private static let lookCases: [LensFXMode] = LensFXMode.pickerCases.filter {
        $0 != .none && $0.pickerSection == .look
    }

    var body: some View {
        // Apply/dismiss stay transaction-frozen; entrance is PickerEntrance only.
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
                    sectionHeader("WARP")
                    ForEach(Self.warpCases, id: \.self) { fx in
                        fxRow(fx)
                    }

                    sectionHeader("LOOK")
                    ForEach(Self.lookCases, id: \.self) { fx in
                        fxRow(fx)
                    }
                }
            }
            .frame(maxHeight: 260)

            Spacer().frame(height: 6)
        }
        .background(dsPickerChrome())
        .frame(width: 180)
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.32))
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    private func fxRow(_ fx: LensFXMode) -> some View {
        Button(action: {
            VFHaptics.click()
            // Dismiss first, then apply FX on the next turn so the Metal
            // preview pipeline doesn't enable mid-teardown.
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                isPresented = false
            }
            let chosen = fx
            DispatchQueue.main.async {
                selectedFX = chosen
            }
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

                if fx != .none {
                    Text(fx.badge)
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(selectedFX == fx ? Color.white.opacity(0.05) : Color.clear)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Look recipe picker (saved film + FX combos)
struct LookRecipePicker: View {
    @ObservedObject var store: LookRecipeStore
    @Binding var filmFilter: FilmFilterMode
    @Binding var lensFX: LensFXMode
    @Binding var isPresented: Bool
    var onSaveCurrent: (() -> Void)? = nil

    private let accent = Color(red: 1.0, green: 0.75, blue: 0.45)

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("LOOKS")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Button {
                    VFHaptics.click()
                    onSaveCurrent?()
                } label: {
                    Text("SAVE")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundColor(accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Rectangle()
                .fill(Color(hex: "2a2a2a"))
                .frame(height: 1)
                .padding(.horizontal, 8)

            if store.recipes.isEmpty {
                Text("Save film + FX combos\nfor one-tap recall.")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .padding(16)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(store.recipes) { recipe in
                            Button {
                                VFHaptics.click()
                                var t = Transaction()
                                t.disablesAnimations = true
                                withTransaction(t) { isPresented = false }
                                let film = recipe.film
                                let fx = recipe.lensFX
                                DispatchQueue.main.async {
                                    filmFilter = film
                                    lensFX = fx
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(recipe.name.uppercased())
                                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                        Text(recipe.subtitle.uppercased())
                                            .font(.system(size: 8, weight: .regular, design: .monospaced))
                                            .foregroundColor(.white.opacity(0.35))
                                            .lineLimit(1)
                                    }
                                    Spacer()
                                    Button {
                                        VFHaptics.click()
                                        store.delete(recipe.id)
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.white.opacity(0.35))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 220)
            }

            Spacer().frame(height: 6)
        }
        .background(dsPickerChrome())
        .frame(width: 200)
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
