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
    @State private var showFilmMenu = false

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let inset: CGFloat = 16

            ZStack {
                // Film grain texture (subtle)
                FilmGrainOverlay()
                    .opacity(0.3)

                // Center focus indicator - curved brackets style (main feature)
                CenterFocusBrackets()
                    .position(x: width/2, y: height/2)

                // Grid (rule of thirds)
                if showGrid {
                    GridLines()
                }

                // Aspect ratio crop mask
                if aspectRatio != .full {
                    AspectRatioMask(mode: aspectRatio, size: geo.size)
                }

                // Top left - Aspect ratio button (DSLR-style)
                Button(action: {
                    VFHaptics.click()
                    aspectRatio = aspectRatio.next
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.4))
                            .frame(width: 32, height: 32)
                        Text(aspectRatio.label)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
                .position(x: inset + 20, y: inset + 20)

                // Top right - Film filter button (Leica-style)
                Button(action: {
                    VFHaptics.click()
                    showFilmMenu.toggle()
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.4))
                            .frame(width: 32, height: 32)
                        Image(systemName: "film")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(filmFilter == .none ? .white.opacity(0.8) : .orange)
                    }
                }
                .position(x: width - inset - 20, y: inset + 20)

                // Leica-style film picker panel
                if showFilmMenu {
                    LeicaFilmPicker(
                        selectedFilter: $filmFilter,
                        isPresented: $showFilmMenu
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    .animation(.easeOut(duration: 0.15), value: showFilmMenu)
                }
            }
        }
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

// MARK: - Film Filter Mode
enum FilmFilterMode: CaseIterable {
    case none, portra400, kodakGold, trix400, velvia50, cinestill800

    var name: String {
        switch self {
        case .none: return "None"
        case .portra400: return "Portra 400"
        case .kodakGold: return "Kodak Gold"
        case .trix400: return "Tri-X 400"
        case .velvia50: return "Velvia 50"
        case .cinestill800: return "CineStill 800T"
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

// MARK: - Leica-Style Film Picker
struct LeicaFilmPicker: View {
    @Binding var selectedFilter: FilmFilterMode
    @Binding var isPresented: Bool

    private let accent = Color(red: 1.0, green: 0.85, blue: 0.35)

    var body: some View {
        ZStack {
            // Tap outside to dismiss
            Color.black.opacity(0.3)
                .ignoresSafeArea()
                .onTapGesture {
                    VFHaptics.click()
                    isPresented = false
                }

            // Film picker panel
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("FILM")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                        .tracking(2)
                    Spacer()
                    Button(action: {
                        VFHaptics.click()
                        isPresented = false
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()
                    .background(Color.white.opacity(0.1))

                // Film options
                ForEach(FilmFilterMode.allCases, id: \.self) { filter in
                    Button(action: {
                        VFHaptics.click()
                        selectedFilter = filter
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            isPresented = false
                        }
                    }) {
                        HStack(spacing: 12) {
                            // Color swatch
                            RoundedRectangle(cornerRadius: 3)
                                .fill(swatchColor(for: filter))
                                .frame(width: 24, height: 16)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 3)
                                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                                )

                            // Film name
                            Text(filter.name)
                                .font(.system(size: 14, weight: selectedFilter == filter ? .semibold : .regular, design: .default))
                                .foregroundColor(selectedFilter == filter ? accent : .white)

                            Spacer()

                            // Selected indicator
                            if selectedFilter == filter {
                                Circle()
                                    .fill(accent)
                                    .frame(width: 6, height: 6)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(selectedFilter == filter ? Color.white.opacity(0.05) : Color.clear)
                    }
                    .buttonStyle(.plain)

                    if filter != FilmFilterMode.allCases.last {
                        Divider()
                            .background(Color.white.opacity(0.05))
                            .padding(.leading, 52)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(red: 0.12, green: 0.12, blue: 0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
            )
            .frame(width: 200)
            .shadow(color: .black.opacity(0.5), radius: 20, x: 0, y: 10)
        }
    }

    private func swatchColor(for filter: FilmFilterMode) -> LinearGradient {
        switch filter {
        case .none:
            return LinearGradient(colors: [.gray.opacity(0.3), .gray.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .portra400:
            return LinearGradient(colors: [Color(red: 0.95, green: 0.85, blue: 0.75), Color(red: 0.85, green: 0.70, blue: 0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .kodakGold:
            return LinearGradient(colors: [Color(red: 1.0, green: 0.85, blue: 0.4), Color(red: 0.95, green: 0.65, blue: 0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .trix400:
            return LinearGradient(colors: [.white, .gray], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .velvia50:
            return LinearGradient(colors: [Color(red: 0.2, green: 0.7, blue: 0.4), Color(red: 0.1, green: 0.4, blue: 0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .cinestill800:
            return LinearGradient(colors: [Color(red: 0.3, green: 0.5, blue: 0.7), Color(red: 0.6, green: 0.3, blue: 0.5)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
}
