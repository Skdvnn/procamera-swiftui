import SwiftUI
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreMotion

// MARK: - Aspect crop (matches viewfinder mask)

extension AspectRatioMode {
    /// Short label for the info bar (FULL / 4:3 / 1:1 / …).
    var shortLabel: String { label }

    /// Framed width÷height for the portrait viewfinder. `nil` = no crop.
    var framedAspect: CGFloat? {
        switch self {
        case .full: return nil
        case .ratio4x3: return 4.0 / 3.0
        case .ratio1x1: return 1.0
        case .ratio16x9: return 16.0 / 9.0
        case .ratio3x2: return 3.0 / 2.0
        }
    }
}

extension UIImage {
    /// Center-crop to a width/height aspect (same framing as the viewfinder mask).
    func croppedToAspect(_ aspect: CGFloat) -> UIImage {
        let w = size.width
        let h = size.height
        guard w > 1, h > 1, aspect > 0, aspect.isFinite else { return self }
        let current = w / h
        let crop: CGRect
        if abs(current - aspect) < 0.01 {
            return self
        } else if current > aspect {
            let newW = h * aspect
            crop = CGRect(x: (w - newW) / 2, y: 0, width: newW, height: h)
        } else {
            let newH = w / aspect
            crop = CGRect(x: 0, y: (h - newH) / 2, width: w, height: newH)
        }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: crop.size, format: format)
        return renderer.image { _ in
            draw(at: CGPoint(x: -crop.origin.x, y: -crop.origin.y))
        }
    }
}

// MARK: - Focus peaking / zebra (CI helpers for live preview)

enum ViewfinderMonitor {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// Green edge overlay for manual focus.
    static func applyFocusPeaking(to image: CIImage) -> CIImage {
        let edges = CIFilter.edges()
        edges.inputImage = image
        edges.intensity = 1.8
        guard let edgeImage = edges.outputImage else { return image }

        // Tint edges green
        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = edgeImage
        matrix.rVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        matrix.gVector = CIVector(x: 0.2, y: 0.9, z: 0.2, w: 0)
        matrix.bVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 0.85)
        matrix.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        guard let green = matrix.outputImage else { return image }

        let comp = CIFilter.sourceOverCompositing()
        comp.inputImage = green
        comp.backgroundImage = image
        return comp.outputImage?.cropped(to: image.extent) ?? image
    }

    /// Magenta warning on near-clipped highlights.
    static func applyZebra(to image: CIImage) -> CIImage {
        // Soft highlight mask via color controls + blend
        let controls = CIFilter.colorControls()
        controls.inputImage = image
        controls.contrast = 2.4
        controls.brightness = -0.35
        controls.saturation = 0
        guard let harsh = controls.outputImage else { return image }

        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = harsh
        matrix.rVector = CIVector(x: 1.1, y: 0, z: 0, w: 0)
        matrix.gVector = CIVector(x: 0, y: 0.15, z: 0, w: 0)
        matrix.bVector = CIVector(x: 0, y: 0, z: 1.0, w: 0)
        matrix.aVector = CIVector(x: 0.35, y: 0.35, z: 0.35, w: 0)
        matrix.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        guard let tint = matrix.outputImage else { return image }

        let soft = CIFilter.sourceOverCompositing()
        soft.inputImage = tint
        soft.backgroundImage = image
        return soft.outputImage?.cropped(to: image.extent) ?? image
    }
}

// MARK: - Horizon / level bubble

struct HorizonLevelIndicator: View {
    @StateObject private var motion = HorizonMotion()

    var body: some View {
        let roll = motion.rollDegrees
        let level = abs(roll) < 1.2
        HStack(spacing: 6) {
            Capsule()
                .fill(level ? Color.green.opacity(0.9) : Color.white.opacity(0.55))
                .frame(width: 36, height: 2)
                .rotationEffect(.degrees(Double(roll)))
            Text(String(format: "%+.0f°", roll))
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(level ? Color.green.opacity(0.95) : .white.opacity(0.7))
                .frame(width: 32, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.35))
        )
        .allowsHitTesting(false)
        .onAppear { motion.start() }
        .onDisappear { motion.stop() }
    }
}

@MainActor
final class HorizonMotion: ObservableObject {
    @Published var rollDegrees: Float = 0
    private let manager = CMMotionManager()

    func start() {
        guard manager.isDeviceMotionAvailable else { return }
        // 10Hz + deadband — 30Hz publish was thrashing SwiftUI with the camera.
        manager.deviceMotionUpdateInterval = 1.0 / 10.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let attitude = motion?.attitude else { return }
            let roll = max(-45, min(45, Float(attitude.roll * 180.0 / .pi)))
            guard abs(roll - self.rollDegrees) >= 0.4 else { return }
            self.rollDegrees = roll
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}

// MARK: - Curved f-stop edge readout (collapse scrub)

/// Animated aperture curve that peels in from the trailing edge while scrubbing
/// the bottom deck down into fullscreen. Hardware ƒ only — not a fake stop control.
struct CurvedFStopEdgeReadout: View {
    let aperture: Float
    /// 0…1 scrub progress (deck drag / collapse distance).
    let progress: CGFloat

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let w = geo.size.width
            let inset = 10 + (1 - progress) * 28
            let curve = FStopEdgeCurve(progress: progress)

            ZStack(alignment: .trailing) {
                curve
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.05 + 0.35 * progress),
                                Color(red: 1.0, green: 0.85, blue: 0.35).opacity(0.15 + 0.55 * progress),
                                Color.white.opacity(0.08 + 0.25 * progress)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        style: StrokeStyle(lineWidth: 1.6 + progress * 0.8, lineCap: .round)
                    )
                    .frame(width: 36)
                    .padding(.trailing, inset)
                    .opacity(Double(min(1, progress * 1.4)))

                VStack(spacing: 4) {
                    Text("ƒ")
                        .font(.system(size: 11, weight: .semibold, design: .serif))
                        .foregroundStyle(Color.white.opacity(0.55 + 0.35 * progress))
                    Text(String(format: "%.1f", aperture))
                        .font(.system(size: 22, weight: .medium, design: .serif))
                        .foregroundStyle(Color.white.opacity(0.75 + 0.25 * progress))
                        .monospacedDigit()
                    Text("EQ")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(Color.white.opacity(0.35 + 0.25 * progress))
                }
                .padding(.trailing, inset + 18)
                .offset(y: (0.5 - progress) * 18)
                .opacity(Double(min(1, max(0, progress * 1.6 - 0.15))))
            }
            .frame(width: w, height: h, alignment: .trailing)
        }
    }
}

private struct FStopEdgeCurve: Shape {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let top = rect.minY + 24
        let bottom = rect.maxY - 24
        let midY = rect.midY
        let xRight = rect.maxX - 2
        let bulge = 10 + progress * 22
        path.move(to: CGPoint(x: xRight, y: top))
        path.addCurve(
            to: CGPoint(x: xRight, y: bottom),
            control1: CGPoint(x: xRight - bulge, y: midY - 40),
            control2: CGPoint(x: xRight - bulge, y: midY + 40)
        )
        return path
    }
}
