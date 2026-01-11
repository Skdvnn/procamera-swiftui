import SwiftUI

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

// MARK: - Viewfinder Overlay
struct ViewfinderOverlay: View {
    let showGrid: Bool

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let inset: CGFloat = 12

            ZStack {
                // Film grain texture
                FilmGrainOverlay()
                    .opacity(0.4)

                // Corner brackets
                ViewfinderBracket()
                    .position(x: inset + 20, y: inset + 20)

                ViewfinderBracket()
                    .rotationEffect(.degrees(90))
                    .position(x: width - inset - 20, y: inset + 20)

                ViewfinderBracket()
                    .rotationEffect(.degrees(-90))
                    .position(x: inset + 20, y: height - inset - 20)

                ViewfinderBracket()
                    .rotationEffect(.degrees(180))
                    .position(x: width - inset - 20, y: height - inset - 20)

                // Center focus indicator - curved brackets style
                CenterFocusBrackets()
                    .position(x: width/2, y: height/2)

                // Grid
                if showGrid {
                    GridLines()
                }

                // Top left - viewfinder icon
                Image(systemName: "viewfinder")
                    .font(.system(size: 14, weight: .light))
                    .foregroundColor(.white.opacity(0.6))
                    .position(x: inset + 18, y: inset + 18)

                // Top right - stabilization icon
                Image(systemName: "hand.raised")
                    .font(.system(size: 13, weight: .light))
                    .foregroundColor(.white.opacity(0.6))
                    .position(x: width - inset - 16, y: inset + 18)
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

// MARK: - Info Bar
struct InfoBar: View {
    let iso: Int
    let shutterSpeed: String
    let aperture: Float
    let photoCount: Int

    var body: some View {
        HStack(spacing: 10) {
            // Histogram
            HistogramView()

            // Center info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("RAW+J")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)

                    // Aspect ratio badge
                    Text("4:3")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(.black)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.white)
                        .cornerRadius(3)

                    Text("30M")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                }

                HStack(spacing: 10) {
                    HStack(spacing: 3) {
                        Image(systemName: "square.on.square")
                            .font(.system(size: 9))
                        Text(formatNumber(photoCount))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                    }
                    .foregroundColor(.white.opacity(0.6))

                    Text("F \(String(format: "%.1f", aperture))")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                }
            }

            Spacer()

            // Right info
            VStack(alignment: .trailing, spacing: 3) {
                HStack(spacing: 4) {
                    Text("ISO")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                    Text("\(iso)")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                }

                Text(shutterSpeed)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.black)
    }

    private func formatNumber(_ num: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: num)) ?? "\(num)"
    }
}
