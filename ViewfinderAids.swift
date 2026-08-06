import SwiftUI
import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import CoreMotion

// MARK: - Aspect crop (matches viewfinder mask)

extension AspectRatioMode {
    /// Short label for the info bar (FULL / 4:3 / 1:1 / …).
    var shortLabel: String { label }

    /// Portrait-native width÷height (phone upright). `nil` = no crop.
    /// 4:3 means a 3:4 portrait still — matching iOS Camera labeling.
    var framedAspect: CGFloat? {
        switch self {
        case .full: return nil
        case .ratio4x3: return 3.0 / 4.0
        case .ratio1x1: return 1.0
        case .ratio16x9: return 9.0 / 16.0
        case .ratio3x2: return 2.0 / 3.0
        }
    }

    /// Aspect for a viewfinder or still of the given size (inverts for landscape).
    func framedAspect(fitting size: CGSize) -> CGFloat? {
        guard let base = framedAspect else { return nil }
        if size.width > size.height, abs(base - 1) > 0.01 {
            return 1.0 / base
        }
        return base
    }
}

extension UIImage {
    /// Center-crop using an aspect mode (orientation-aware).
    func croppedToAspectMode(_ mode: AspectRatioMode) -> UIImage {
        guard let aspect = mode.framedAspect(fitting: size) else { return self }
        return croppedToAspect(aspect)
    }

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
        // `.standard` avoids HDR tone-map crunch when redrawing P3/gain-map stills.
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        format.preferredRange = .standard
        let renderer = UIGraphicsImageRenderer(size: crop.size, format: format)
        return renderer.image { _ in
            draw(at: CGPoint(x: -crop.origin.x, y: -crop.origin.y))
        }
    }

    /// Bake `imageOrientation` into upright SDR pixels (Build 123).
    func normalizedUpSDR() -> UIImage {
        guard imageOrientation != .up else { return self }
        return redrawnSDR(size: size) { draw(at: .zero) }
    }

    /// Rotate 90° clockwise into upright SDR pixels.
    func rotated90ClockwiseSDR() -> UIImage {
        let newSize = CGSize(width: size.height, height: size.width)
        return redrawnSDR(size: newSize) {
            guard let ctx = UIGraphicsGetCurrentContext() else { return }
            ctx.translateBy(x: newSize.width, y: 0)
            ctx.rotate(by: .pi / 2)
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Rotate 90° counter-clockwise into upright SDR pixels.
    func rotated90CounterClockwiseSDR() -> UIImage {
        let newSize = CGSize(width: size.height, height: size.width)
        return redrawnSDR(size: newSize) {
            guard let ctx = UIGraphicsGetCurrentContext() else { return }
            ctx.translateBy(x: 0, y: newSize.height)
            ctx.rotate(by: -.pi / 2)
            draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// SDR redraw — kills HDR headroom that otherwise becomes haloed/crunchy JPEG.
    private func redrawnSDR(size: CGSize, draw: () -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in draw() }
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

/// Standalone chip (legacy). Prefer `HistogramHorizonOverlay` in the info bar.
struct HorizonLevelIndicator: View {
    @ObservedObject private var motion = HorizonMotion.shared

    var body: some View {
        let roll = motion.rollDegrees
        let level = abs(roll) < 1.2
        HStack(spacing: 6) {
            Capsule()
                .fill(level ? Color(red: 1.0, green: 0.85, blue: 0.35).opacity(0.95) : Color.white.opacity(0.55))
                .frame(width: 36, height: 2)
                .rotationEffect(.degrees(Double(roll)))
            Text(String(format: "%+.0f°", roll))
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(level ? Color(red: 1.0, green: 0.85, blue: 0.35) : .white.opacity(0.7))
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

/// Compact spirit level drawn inside the histogram glass — kept for reuse.
struct HistogramHorizonOverlay: View {
    @ObservedObject private var motion = HorizonMotion.shared

    private let accent = Color(red: 1.0, green: 0.85, blue: 0.35)

    var body: some View {
        let roll = motion.rollDegrees
        let level = abs(roll) < 1.2
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                HStack(spacing: w * 0.42) {
                    Capsule()
                        .fill(Color.white.opacity(0.28))
                        .frame(width: 5, height: 1.5)
                    Capsule()
                        .fill(Color.white.opacity(0.28))
                        .frame(width: 5, height: 1.5)
                }

                Capsule()
                    .fill(level ? accent.opacity(0.95) : Color.white.opacity(0.70))
                    .frame(width: max(22, w * 0.62), height: level ? 2.0 : 1.5)
                    .rotationEffect(.degrees(Double(roll)))
                    .shadow(color: level ? accent.opacity(0.45) : .clear, radius: 2)

                Text(level ? "LVL" : String(format: "%+.0f°", roll))
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundColor(level ? accent : .white.opacity(0.65))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 3)
                    .padding(.bottom, 2)
            }
            .frame(width: w, height: h)
        }
        .allowsHitTesting(false)
        .onAppear { motion.start() }
        .onDisappear { motion.stop() }
    }
}

/// Nikon-style horizon instrument under the top EV meter.
/// Full size deliberately matches the 120×36 EV scale above it.
///
/// The tick row is the readout: marks fill **yellow from center out to your tilt**,
/// the leading mark pulses, and everything locks solid yellow at level. One Canvas
/// draws the whole scale — 13 individually animated tick views thrashed SwiftUI.
struct InfoBarMetalLevel: View {
    @ObservedObject private var motion = HorizonMotion.shared
    var compact: Bool = false

    private let accent = Color(red: 1.0, green: 0.85, blue: 0.35)
    private let degreeMarks = ["−15", "−5", "0", "+5", "+15"]
    /// Degrees per tick — 13 marks over ±15° (same 1/3 rhythm as EV).
    private let degreesPerTick: Float = 2.5
    private let levelTolerance: Float = 1.2

    var body: some View {
        let roll = motion.rollDegrees
        let level = abs(roll) < levelTolerance
        let visualRoll = max(-15, min(15, roll))
        // Compact matches the top FOCUS / EV strip (Build 100 — 38pt).
        let w: CGFloat = compact ? 52 : 120
        let h: CGFloat = compact ? 38 : 36

        ZStack {
            // Same instrument face and border language as the EV meter.
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color(hex: "0a0a0a"))
            // Inner lip so the level sits in the same recess as the scrubbers.
            if compact {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.08),
                                Color.black.opacity(0.55),
                                Color.white.opacity(0.03)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.8
                    )
                    .padding(1.5)
            }
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(
                    level ? accent.opacity(0.55) : Color(hex: "2a2a2a"),
                    lineWidth: level ? 0.8 : 0.5
                )

            if compact {
                compactLevel(roll: visualRoll, isLevel: level)
            } else {
                fullLevel(roll: roll, visualRoll: visualRoll, isLevel: level)
            }
        }
        .frame(width: w, height: h)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .shadow(color: level ? accent.opacity(0.30) : .clear, radius: level ? 4 : 0)
        .animation(.easeOut(duration: 0.12), value: level)
        .allowsHitTesting(false)
        .onAppear { motion.start() }
        .onDisappear { motion.stop() }
        .onChange(of: level) { _, nowLevel in
            if nowLevel {
                UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.85)
            }
        }
    }

    /// Live tick scale. Yellow only on the focused/leading mark (and solid
    /// center when level) — no swept yellow run on unfocused ticks (Build 97).
    private func tickScale(
        count: Int,
        roll: Float,
        isLevel: Bool,
        step: Float,
        labels: Bool
    ) -> some View {
        // 8Hz pulse clock — was 15Hz stacked on motion publishes (Build 106).
        TimelineView(.animation(minimumInterval: 1.0 / 8.0)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
            let pulse = 0.5 + 0.5 * sin(phase * 4.2)

            Canvas { ctx, size in
                let mid = Float(count - 1) / 2
                let pitch = size.width / CGFloat(count)
                let baseY = size.height - (labels ? 9.5 : 0.5)

                for i in 0..<count {
                    let deg = (Float(i) - mid) * step
                    let major = labels ? (i % 3 == 0) : (i == count / 2)
                    let x = pitch * (CGFloat(i) + 0.5)

                    let leading = abs(deg - roll) <= step * 0.75
                    let atCenter = i == count / 2

                    let color: Color
                    var height: CGFloat = major ? 6.0 : 3.5

                    if isLevel && atCenter {
                        color = accent.opacity(0.92 + 0.08 * pulse)
                        height += 3.5
                    } else if !isLevel && leading {
                        color = accent.opacity(0.85 + 0.15 * pulse)
                        height += 3.5 + 1.0 * CGFloat(pulse)
                    } else {
                        color = Color.white.opacity(major ? 0.34 : 0.16)
                    }

                    let width: CGFloat = major ? 1.5 : 1
                    let rect = CGRect(x: x - width / 2, y: baseY - height, width: width, height: height)
                    ctx.fill(Path(rect), with: .color(color))
                }

                guard labels else { return }
                for markIndex in 0..<degreeMarks.count {
                    let i = markIndex * 3
                    let deg = (Float(i) - mid) * step
                    let x = pitch * (CGFloat(i) + 0.5)
                    let leading = abs(deg - roll) <= step * 0.75
                    let tint: Color = isLevel
                        ? (markIndex == 2 ? accent : Color.white.opacity(0.38))
                        : leading ? accent.opacity(0.85) : Color.white.opacity(markIndex == 2 ? 0.55 : 0.38)
                    let text = Text(degreeMarks[markIndex])
                        .font(.system(size: 6, weight: markIndex == 2 ? .bold : .medium, design: .monospaced))
                        .foregroundStyle(tint)
                    ctx.draw(text, at: CGPoint(x: x, y: size.height - 4.5), anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private func fullLevel(roll: Float, visualRoll: Float, isLevel: Bool) -> some View {
        VStack(spacing: 0) {
            tickScale(count: 13, roll: visualRoll, isLevel: isLevel, step: degreesPerTick, labels: true)
                .frame(height: 16)

            ZStack {
                // Fixed center datum: split rails leave a precision gate.
                HStack(spacing: 9) {
                    Capsule()
                        .fill(Color.white.opacity(0.22))
                        .frame(width: 38, height: 1)
                    Capsule()
                        .fill(Color.white.opacity(0.22))
                        .frame(width: 38, height: 1)
                }

                // Tilting horizon beam — the part that reads as a real level.
                HStack(spacing: 3) {
                    Capsule()
                        .fill(isLevel ? accent : Color.white.opacity(0.80))
                        .frame(width: 39, height: isLevel ? 2 : 1.5)
                    Circle()
                        .fill(isLevel ? accent : Color.white.opacity(0.90))
                        .frame(width: isLevel ? 5 : 4, height: isLevel ? 5 : 4)
                    Capsule()
                        .fill(isLevel ? accent : Color.white.opacity(0.80))
                        .frame(width: 39, height: isLevel ? 2 : 1.5)
                }
                .rotationEffect(.degrees(Double(visualRoll)))
                .shadow(color: isLevel ? accent.opacity(0.45) : .clear, radius: 2)
                .animation(.interactiveSpring(response: 0.16, dampingFraction: 0.85), value: visualRoll)

                // Mechanical center pointer matches the EV triangle.
                Triangle()
                    .fill(accent.opacity(isLevel ? 1 : 0.62))
                    .frame(width: 6, height: 4)
                    .offset(y: 7)

                Text(isLevel ? "LEVEL" : String(format: "%+.1f°", roll))
                    .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(isLevel ? accent : .white.opacity(0.58))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 5)
                    .padding(.bottom, 1)
                    .contentTransition(.numericText())
            }
            .frame(height: 18)
        }
        .padding(.top, 1)
    }

    @ViewBuilder
    private func compactLevel(roll: Float, isLevel: Bool) -> some View {
        // Fills the 38pt scrubber slot — ticks on top, horizon + readout below.
        VStack(spacing: 0) {
            tickScale(count: 7, roll: roll, isLevel: isLevel, step: 5, labels: false)
                .frame(height: 11)
                .padding(.top, 2)

            ZStack {
                HStack(spacing: 5) {
                    Rectangle().fill(Color.white.opacity(0.22)).frame(width: 14, height: 1)
                    Rectangle().fill(Color.white.opacity(0.22)).frame(width: 14, height: 1)
                }
                Capsule()
                    .fill(isLevel ? accent : Color.white.opacity(0.82))
                    .frame(width: 34, height: isLevel ? 2 : 1.4)
                    .rotationEffect(.degrees(Double(roll)))
                    .animation(.interactiveSpring(response: 0.16, dampingFraction: 0.85), value: roll)
                Text(isLevel ? "LVL" : String(format: "%+.0f°", roll))
                    .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(isLevel ? accent : .white.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 2)
            }
            .frame(maxHeight: .infinity)
        }
        .padding(.horizontal, 2)
    }
}

/// Single shared CMMotionManager. Two instances (full + compact level) fought over
/// device motion — collapsing the deck stopped updates for the level still on screen.
@MainActor
final class HorizonMotion: ObservableObject {
    static let shared = HorizonMotion()

    @Published var rollDegrees: Float = 0
    private let manager = CMMotionManager()
    private var subscribers = 0

    func start() {
        subscribers += 1
        guard subscribers == 1 else { return }
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        // 12Hz — enough for tick chase without 20Hz SwiftUI republish (Build 106).
        manager.deviceMotionUpdateInterval = 1.0 / 12.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let attitude = motion?.attitude else { return }
            let roll = max(-45, min(45, Float(attitude.roll * 180.0 / .pi)))
            // Wider deadband — calm the top strip while still reading tilt.
            guard abs(roll - self.rollDegrees) >= 0.35 else { return }
            self.rollDegrees = roll
        }
    }

    func stop() {
        subscribers = max(0, subscribers - 1)
        guard subscribers == 0 else { return }
        manager.stopDeviceMotionUpdates()
    }
}

// MARK: - Edge readout (straight rail between FX + histogram)

/// Trailing-edge readout used for collapse ƒ theater and fullscreen FOCUS/EV scrub.
/// Build 112 drops the oversized arch for a slimmer straight rail.
struct CurvedParamEdgeReadout: View {
    let title: String
    let value: String
    var subtitle: String = ""
    /// 0…1 peel intensity.
    let progress: CGFloat
    /// 0…1 dial needle along the rail (top → bottom). Snaps to half-stop ticks.
    var needle: CGFloat = 0.5
    /// Serif value (ƒ) vs mono LCD (ISO / S / EV / FOCUS).
    var serifValue: Bool = false

    private let accent = Color(red: 1.0, green: 0.85, blue: 0.35)
    /// Slimmer rail column — starts below FX buttons, ends above histogram.
    private let railColumn: CGFloat = 34
    /// Air between the value's trailing edge and the rail ticks.
    private let valueClearance: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            let h = geo.size.height
            let w = geo.size.width
            let inset = 10 + (1 - progress) * 14
            // Numbers sit entirely left of the rail column — never on the stroke.
            let valueTrailing = inset + railColumn + valueClearance
            // Keep the LCD stacked near the moving needle so the readout feels linked.
            let valueY = (needle - 0.5) * (h * 0.64)

            ZStack(alignment: .trailing) {
                EdgeParamRailDetail(progress: progress, needle: needle, accent: accent)
                    .frame(width: railColumn)
                    .padding(.trailing, inset)
                    .opacity(Double(min(1, progress * 1.4)))

                VStack(alignment: .trailing, spacing: 3) {
                    // Title stays muted — yellow is for the live value only (Build 103).
                    Text(title)
                        .font(.system(
                            size: serifValue ? 11 : 10,
                            weight: .semibold,
                            design: serifValue ? .serif : .monospaced
                        ))
                        .foregroundStyle(Color.white.opacity(0.55 + 0.35 * progress))
                    Text(value)
                        .font(.system(
                            size: serifValue ? 22 : 20,
                            weight: serifValue ? .medium : .semibold,
                            design: serifValue ? .serif : .monospaced
                        ))
                        .foregroundStyle(accent.opacity(0.80 + 0.20 * progress))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(ShutterMotion.scrub, value: value)
                        .shadow(color: .black.opacity(0.55), radius: 2, y: 1)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .tracking(1.2)
                            .foregroundStyle(Color.white.opacity(0.35 + 0.25 * progress))
                    }
                }
                .padding(.trailing, valueTrailing)
                .offset(y: valueY)
                .opacity(Double(min(1, max(0, progress * 1.6 - 0.15))))
            }
            .frame(width: w, height: h, alignment: .trailing)
        }
        .allowsHitTesting(false)
    }
}

/// Collapse gesture — hardware ƒ only (not a fake stop control).
struct CurvedFStopEdgeReadout: View {
    let aperture: Float
    let progress: CGFloat

    var body: some View {
        CurvedParamEdgeReadout(
            title: "ƒ",
            value: String(format: "%.1f", aperture),
            subtitle: "EQ",
            progress: progress,
            serifValue: true
        )
    }
}

/// Shared geometry for the rail — guide, ticks, and end caps all sample it.
private struct EdgeParamRailGeometry {
    let top: CGPoint
    let bottom: CGPoint
    let xRail: CGFloat

    init(rect: CGRect, progress: CGFloat) {
        let topY = rect.minY + 12 + (1 - progress) * 10
        let bottomY = rect.maxY - 12 - (1 - progress) * 10
        xRail = rect.maxX - 6
        top = CGPoint(x: xRail, y: topY)
        bottom = CGPoint(x: xRail, y: bottomY)
    }

    /// Point on the vertical rail at t ∈ 0…1.
    func point(at t: CGFloat) -> CGPoint {
        CGPoint(x: xRail, y: top.y + (bottom.y - top.y) * t)
    }

    /// Unit tangent at t, used to aim tick stems inward (toward the numbers).
    func tangent(at t: CGFloat) -> CGPoint {
        _ = t
        return CGPoint(x: 0, y: 1)
    }
}

/// Single-rail detail with half-stop ticks + traveling needle (Build 112).
/// Yellow is reserved for the focused tick + needle — the rail stays steel.
struct EdgeParamRailDetail: View {
    let progress: CGFloat
    /// 0…1 along the rail (top → bottom). Snapped to the nearest tick.
    var needle: CGFloat = 0.5
    let accent: Color

    /// Half-stop count across the dial face (majors on even indices).
    private let tickCount = 17

    var body: some View {
        Canvas { ctx, size in
            let rect = CGRect(origin: .zero, size: size)
            let geom = EdgeParamRailGeometry(rect: rect, progress: progress)
            let p = max(0, min(1, progress))
            let last = CGFloat(tickCount - 1)
            let needleT = (needle * last).rounded() / last
            let needleTClamped = max(0, min(1, needleT))

            var rail = Path()
            rail.move(to: geom.top)
            rail.addLine(to: geom.bottom)

            // Soft under-glow only — muted steel, not yellow.
            ctx.stroke(
                rail,
                with: .color(Color.white.opacity(0.04 + 0.08 * p)),
                style: StrokeStyle(lineWidth: 4.0 + p * 1.2, lineCap: .round)
            )
            // One steel rail — the dial track (not accent).
            ctx.stroke(
                rail,
                with: .color(Color.white.opacity(0.28 + 0.32 * p)),
                style: StrokeStyle(lineWidth: 1.45 + p * 0.4, lineCap: .round)
            )

            // Half-stop ticks — stems aim left (inward), like a cut meter rail.
            // Yellow only on the focused tick under the needle.
            for i in 0..<tickCount {
                let t = CGFloat(i) / last
                let pt = geom.point(at: t)
                let major = i % 2 == 0
                let atNeedle = abs(t - needleTClamped) < 0.001
                let stem: CGFloat = atNeedle ? 10 : (major ? 7.0 : 4.0)
                var tick = Path()
                tick.move(to: pt)
                tick.addLine(to: CGPoint(x: pt.x - stem, y: pt.y))
                let tickColor: Color = atNeedle
                    ? accent.opacity(0.85 + 0.15 * p)
                    : Color.white.opacity((major ? 0.42 : 0.20) + 0.18 * p)
                ctx.stroke(
                    tick,
                    with: .color(tickColor),
                    style: StrokeStyle(
                        lineWidth: atNeedle ? 1.55 : (major ? 1.1 : 0.7),
                        lineCap: .round
                    )
                )
            }

            // End caps — machined terminals on the rail (steel, not yellow).
            for end in [geom.top, geom.bottom] {
                let cap = Path(ellipseIn: CGRect(x: end.x - 2.0, y: end.y - 2.0, width: 4.0, height: 4.0))
                ctx.fill(cap, with: .color(Color.black.opacity(0.55)))
                ctx.stroke(cap, with: .color(Color.white.opacity(0.30 + 0.30 * p)), lineWidth: 0.9)
            }

            // Traveling needle pip — the only other yellow on the dial.
            let tip = geom.point(at: needleTClamped)
            let outer = Path(ellipseIn: CGRect(x: tip.x - 3.4, y: tip.y - 3.4, width: 6.8, height: 6.8))
            ctx.fill(outer, with: .color(Color.black.opacity(0.55)))
            ctx.stroke(outer, with: .color(accent.opacity(0.70 + 0.25 * p)), lineWidth: 1.25)
            let inner = Path(ellipseIn: CGRect(x: tip.x - 1.5, y: tip.y - 1.5, width: 3.0, height: 3.0))
            ctx.fill(inner, with: .color(accent.opacity(0.92)))
        }
        .animation(ShutterMotion.deck, value: progress)
        .animation(ShutterMotion.scrub, value: needle)
    }
}
