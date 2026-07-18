import SwiftUI
import UIKit

extension Notification.Name {
    static let toggleFingerTips = Notification.Name("toggleFingerTips")
}

// Uses Haptics, Triangle, and Color(hex:) from ContentView.swift

// MARK: - Circular dial drag helper
/// Accumulates finger arc (radians) so needles stay fluid across the dead zone
/// instead of absolute-atan2 wrapping that jumps 0 ↔ 1 at the bottom gap.
private enum DialDragMath {
    /// Returns `(normalized, rawAngleToStore)`.
    static func applyArcDelta(
        location: CGPoint,
        center: CGPoint,
        lastRawAngle: Double?,
        currentNormalized: Float,
        sweepDegrees: Double = 300
    ) -> (Float, Double) {
        let raw = atan2(Double(location.y - center.y), Double(location.x - center.x))

        guard let previous = lastRawAngle else {
            // First sample: seed from absolute angle when finger is on the arc.
            var dial = raw * 180 / .pi + 150
            if dial < 0 { dial += 360 }
            if dial <= sweepDegrees {
                return (Float(min(max(dial / sweepDegrees, 0), 1)), raw)
            }
            return (currentNormalized, raw)
        }

        var delta = raw - previous
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }
        let next = Double(currentNormalized) + (delta * 180 / .pi) / sweepDegrees
        return (Float(min(max(next, 0), 1)), raw)
    }
}

// MARK: - Focus Dial (premium Leica/Nikon style)
struct FocusDial: View {
    @Binding var value: Float
    let onChanged: (Float) -> Void

    private let marks: [(String, Float)] = [
        (".4m", 0.0), (".7", 0.17), ("1", 0.33), ("3", 0.5), ("5", 0.67), ("inf", 0.83)
    ]

    /// Continuous while dragging; binding snaps softly on release.
    @State private var isDragging = false
    @State private var lastHapticBucket: Int = .min
    @State private var lastRawAngle: Double? = nil

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = size * 0.42

            ZStack {
                // Outer bezel (slightly lighter than pure black)
                Circle()
                    .fill(Color(hex: "0a0a0a"))

                // Knurled grip texture ring
                Circle()
                    .stroke(Color(hex: "222222"), lineWidth: 2)
                    .padding(1)

                // Inner bezel highlight
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.1), Color(hex: "0a0a0a")],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
                    .padding(3)

                // Dial face (slightly lighter)
                Circle()
                    .fill(Color(hex: "0f0f0f"))
                    .padding(4)

                // Tick marks (Leica-style - crisp white)
                ForEach(0..<25, id: \.self) { i in
                    let angle = -150.0 + Double(i) * 12.5
                    let isMajor = i % 4 == 0

                    Rectangle()
                        .fill(Color.white.opacity(isMajor ? 0.85 : 0.3))
                        .frame(width: isMajor ? 1.5 : 1, height: isMajor ? 10 : 5)
                        .offset(y: -radius + (isMajor ? 5 : 2.5))
                        .rotationEffect(.degrees(angle))
                }

                // Labels (white, monospace)
                ForEach(marks.indices, id: \.self) { i in
                    let mark = marks[i]
                    let angle = -150.0 + Double(mark.1) * 300.0
                    let labelRadius = radius * 0.62

                    Text(mark.0)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.9))
                        .position(
                            x: center.x + labelRadius * cos(angle * .pi / 180),
                            y: center.y + labelRadius * sin(angle * .pi / 180)
                        )
                }

                // Needle (clean white with glow)
                NeedleShape(length: radius * 0.7)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.8), radius: 2, y: 1)
                    .rotationEffect(.degrees(-150 + Double(value) * 300))
                    .animation(isDragging ? nil : .interactiveSpring(response: 0.28, dampingFraction: 0.86), value: value)

                // Center hub (Leica-style)
                Circle()
                    .fill(Color(hex: "0a0a0a"))
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
            }
            .position(center)
            .contentShape(Circle().scale(1.3)) // Larger touch target
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        isDragging = true
                        let (newValue, raw) = DialDragMath.applyArcDelta(
                            location: drag.location,
                            center: center,
                            lastRawAngle: lastRawAngle,
                            currentNormalized: value
                        )
                        lastRawAngle = raw
                        guard abs(newValue - value) > 0.0005 else { return }
                        value = newValue
                        onChanged(newValue)
                        let bucket = Int((newValue * 20).rounded())
                        if bucket != lastHapticBucket {
                            lastHapticBucket = bucket
                            Haptics.light()
                        }
                    }
                    .onEnded { _ in
                        isDragging = false
                        lastRawAngle = nil
                        lastHapticBucket = .min
                        // Soft settle to CompactMeter-style 0.05 steps
                        let snapped = (value * 20).rounded() / 20
                        if abs(snapped - value) > 0.0005 {
                            value = snapped
                            onChanged(snapped)
                        }
                    }
            )
            .simultaneousGesture(
                // Double tap to reset
                TapGesture(count: 2)
                    .onEnded {
                        Haptics.medium()
                        value = 0.5
                        onChanged(0.5)
                    }
            )
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Shutter Speed Dial (premium Leica/Nikon style)
struct ShutterSpeedDial: View {
    @Binding var value: Int  // Index into shutter speeds array
    let onChanged: (Int) -> Void

    // Matches ContentView shutter ladder (15 stops) so the needle maps correctly.
    private let speedCount = 15
    private let marks: [(String, Float)] = [
        ("4\"", 0.0), ("1\"", 2.0 / 14.0), ("1/8", 5.0 / 14.0),
        ("1/60", 8.0 / 14.0), ("250", 10.0 / 14.0), ("1k", 12.0 / 14.0), ("4k", 1.0)
    ]

    /// Live needle while dragging; settles onto the discrete stop on release.
    @State private var isDragging = false
    @State private var liveNormalized: Float? = nil
    @State private var lastRawAngle: Double? = nil

    private var settledNormalized: Float {
        let maxIndex = Float(speedCount - 1)
        return maxIndex > 0 ? Float(value) / maxIndex : 0
    }

    private var displayNormalized: Float {
        liveNormalized ?? settledNormalized
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = size * 0.42

            ZStack {
                // Outer bezel (slightly lighter than pure black)
                Circle()
                    .fill(Color(hex: "0a0a0a"))

                // Knurled grip texture ring
                Circle()
                    .stroke(Color(hex: "222222"), lineWidth: 2)
                    .padding(1)

                // Inner bezel highlight
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.1), Color(hex: "0a0a0a")],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
                    .padding(3)

                // Dial face (slightly lighter)
                Circle()
                    .fill(Color(hex: "0f0f0f"))
                    .padding(4)

                // Minor ticks for every stop + major ticks at labeled marks
                ForEach(0..<speedCount, id: \.self) { i in
                    let angle = -150.0 + Double(i) * (300.0 / Double(speedCount - 1))
                    let isMajor = marks.contains { abs(Double($0.1) - Double(i) / Double(speedCount - 1)) < 0.02 }

                    Rectangle()
                        .fill(Color.white.opacity(isMajor ? 0.85 : 0.28))
                        .frame(width: isMajor ? 1.5 : 1, height: isMajor ? 10 : 5)
                        .offset(y: -radius + (isMajor ? 5 : 2.5))
                        .rotationEffect(.degrees(angle))
                }

                // Labels (white, semibold)
                ForEach(marks.indices, id: \.self) { i in
                    let mark = marks[i]
                    let angle = -150.0 + Double(mark.1) * 300.0
                    let labelRadius = radius * 0.60

                    Text(mark.0)
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.9))
                        .position(
                            x: center.x + labelRadius * cos(angle * .pi / 180),
                            y: center.y + labelRadius * sin(angle * .pi / 180)
                        )
                }

                // Needle (clean white with glow) — follows finger continuously while scrubbing
                NeedleShape(length: radius * 0.7)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.8), radius: 2, y: 1)
                    .rotationEffect(.degrees(-150 + Double(displayNormalized) * 300))
                    .animation(isDragging ? nil : .interactiveSpring(response: 0.28, dampingFraction: 0.86), value: displayNormalized)

                // Center hub (Leica-style)
                Circle()
                    .fill(Color(hex: "0a0a0a"))
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
            }
            .position(center)
            .contentShape(Circle().scale(1.3))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        isDragging = true
                        let base = liveNormalized ?? settledNormalized
                        let (normalized, raw) = DialDragMath.applyArcDelta(
                            location: drag.location,
                            center: center,
                            lastRawAngle: lastRawAngle,
                            currentNormalized: base
                        )
                        lastRawAngle = raw
                        liveNormalized = normalized
                        // Commit discrete stop when crossing midpoints; needle stays continuous.
                        let newIndex = Int((normalized * Float(speedCount - 1)).rounded())
                        let clampedIndex = max(0, min(speedCount - 1, newIndex))
                        if clampedIndex != value {
                            value = clampedIndex
                            onChanged(clampedIndex)
                            Haptics.light()
                        }
                    }
                    .onEnded { _ in
                        isDragging = false
                        lastRawAngle = nil
                        liveNormalized = nil
                    }
            )
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// Keep ApertureDial as alias for backward compatibility
typealias ApertureDial = ShutterSpeedDial

// MARK: - Rich Exposure Dial (keeping for backward compatibility)
struct ExposureDial: View {
    @Binding var value: Float
    let onChanged: (Float) -> Void

    private let marks: [(String, Float)] = [
        ("-2", 0.0), ("-1", 0.25), ("0", 0.5), ("+1", 0.75), ("+2", 1.0)
    ]

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = size * 0.40

            ZStack {
                // Outer border ring
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.15), Color.white.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 2
                    )
                    .padding(2)

                // Background
                Circle()
                    .fill(Color(white: 0.04))
                    .padding(4)

                // Inner dial
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(white: 0.18), Color(white: 0.06)],
                            center: .init(x: 0.3, y: 0.3),
                            startRadius: 0,
                            endRadius: radius * 1.2
                        )
                    )
                    .padding(8)

                // Tick marks
                ForEach(0..<21, id: \.self) { i in
                    let angle = -135.0 + Double(i) * 13.5
                    let isMajor = i % 5 == 0

                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: isMajor ? [.white.opacity(0.9), .white.opacity(0.5)] : [.white.opacity(0.3), .white.opacity(0.15)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: isMajor ? 2 : 1, height: isMajor ? 12 : 7)
                        .offset(y: -radius + (isMajor ? 6 : 3.5))
                        .rotationEffect(.degrees(angle))
                }

                // Labels
                ForEach(marks.indices, id: \.self) { i in
                    let mark = marks[i]
                    let angle = -135.0 + Double(mark.1) * 270.0
                    let labelRadius = radius * 0.58

                    Text(mark.0)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
                        .position(
                            x: center.x + labelRadius * cos(angle * .pi / 180),
                            y: center.y + labelRadius * sin(angle * .pi / 180)
                        )
                }

                // Needle
                let normalizedValue = (value + 2) / 4
                NeedleShape(length: radius * 0.75)
                    .fill(
                        LinearGradient(
                            colors: [.white, .white.opacity(0.6)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                    .rotationEffect(.degrees(-135 + Double(normalizedValue) * 270))

                // Center hub
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color(white: 0.3), Color(white: 0.1)],
                            center: .center,
                            startRadius: 0,
                            endRadius: 10
                        )
                    )
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Color.white.opacity(0.3), lineWidth: 0.5))

                // "A" badge
                Text("A")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                    .position(x: center.x + radius - 8, y: center.y - radius + 14)
            }
            .position(center)
            .contentShape(Circle().scale(1.3)) // Larger touch target
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let vector = CGVector(dx: drag.location.x - center.x, dy: drag.location.y - center.y)
                        var angle = atan2(vector.dy, vector.dx) * 180 / .pi
                        angle = angle + 135
                        if angle < 0 { angle += 360 }
                        if angle > 270 { angle = angle > 315 ? 0 : 270 }
                        let normalized = Float(min(max(angle / 270, 0), 1))
                        // Snap to EV stops (-2, -1, 0, +1, +2)
                        let rawValue = (normalized * 4) - 2
                        let snapped = round(rawValue * 2) / 2 // Snap to 0.5 EV stops
                        if abs(snapped - value) > 0.1 {
                            value = snapped
                            onChanged(snapped)
                            Haptics.light()
                        }
                    }
            )
            .simultaneousGesture(
                // Double tap to reset to 0 EV
                TapGesture(count: 2)
                    .onEnded {
                        Haptics.medium()
                        value = 0
                        onChanged(0)
                    }
            )
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - Needle Shape
struct NeedleShape: Shape {
    let length: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)

        path.move(to: CGPoint(x: center.x, y: center.y - length))
        path.addLine(to: CGPoint(x: center.x + 3, y: center.y))
        path.addLine(to: CGPoint(x: center.x - 3, y: center.y))
        path.closeSubpath()

        return path
    }
}

// MARK: - Horizontal Exposure Meter (Nikon-style accurate scale)
// Based on real camera meters: -2 to +2 scale with 1/3 stop increments
struct HorizontalExposureMeter: View {
    let value: Float // -2 to +2
    let iso: Int
    // The expanded dial deck shows the meter alone; the viewfinder info bar
    // already carries the numeric ISO readout.
    var showISO: Bool = true

    // Major marks at full stops, minor marks at 1/3 stops
    private let majorMarks = ["-2", "-1", "0", "+1", "+2"]
    private let meterWidth: CGFloat = 128
    private let meterHeight: CGFloat = 40
    /// Half-scale travel for ±2 EV across the labeled major ticks.
    private var stopPitch: CGFloat { (meterWidth - 26) / 4 }

    var body: some View {
        VStack(spacing: showISO ? 8 : 0) {
            // Meter scale - sized to sit between the two dials without ISO chrome
            ZStack {
                // Dark background panel
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(hex: "0a0a0a"))
                    .frame(width: meterWidth, height: meterHeight)

                // Inner border
                RoundedRectangle(cornerRadius: 5)
                    .stroke(Color(hex: "2a2a2a"), lineWidth: 0.5)
                    .frame(width: meterWidth, height: meterHeight)

                // Soft top sheen so the plate matches dial bezels
                RoundedRectangle(cornerRadius: 5)
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.12), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 0.5
                    )
                    .frame(width: meterWidth, height: meterHeight)

                // Scale with ticks
                VStack(spacing: 0) {
                    // Tick marks row
                    HStack(spacing: 0) {
                        ForEach(0..<13, id: \.self) { i in
                            let isMajor = i % 3 == 0
                            let stopIndex = i / 3
                            let edgeFade: Double = {
                                if stopIndex == 0 || stopIndex == 4 { return 0.5 }
                                if stopIndex == 1 || stopIndex == 3 { return 0.75 }
                                return 1.0
                            }()

                            VStack(spacing: 1) {
                                Rectangle()
                                    .fill(Color.white.opacity((isMajor ? 0.85 : 0.35) * edgeFade))
                                    .frame(width: isMajor ? 1.5 : 1, height: isMajor ? 11 : 5)

                                if isMajor {
                                    Text(majorMarks[stopIndex])
                                        .font(.system(size: 7, weight: stopIndex == 2 ? .bold : .medium, design: .monospaced))
                                        .foregroundColor(.white.opacity((stopIndex == 2 ? 0.9 : 0.7) * edgeFade))
                                }
                            }
                            .frame(width: (meterWidth - 18) / 13)
                        }
                    }

                    // Moving indicator triangle (DS.accent keyline)
                    ZStack {
                        let indicatorOffset = CGFloat(value) * stopPitch

                        Triangle()
                            .fill(DS.accent)
                            .frame(width: 8, height: 6)
                            .rotationEffect(.degrees(180))
                            .shadow(color: DS.accent.opacity(0.35), radius: 2, y: 0)
                            .offset(x: indicatorOffset)
                    }
                    .frame(height: 8)
                    .offset(y: -1)
                }
            }
            .frame(width: meterWidth, height: meterHeight)

            if showISO {
                HStack(spacing: 4) {
                    Text("ISO")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                    Text("\(iso)")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 5) {
            NotificationCenter.default.post(name: .toggleFingerTips, object: nil)
        }
    }
}

// MARK: - Center Display (Simplified - just exposure meter centered)
struct CenterDisplay: View {
    let timerSeconds: Int
    let iso: Int
    let flashMode: String
    let macroEnabled: Bool
    let isAutoFocus: Bool
    let exposureValue: Float
    let onTimerTap: () -> Void
    let onMacroTap: () -> Void

    var body: some View {
        // Just the horizontal exposure meter, centered between gauges
        HorizontalExposureMeter(value: exposureValue, iso: iso)
    }
}

// Legacy initializer for backward compatibility
extension CenterDisplay {
    init(
        timerSeconds: Int,
        iso: Int,
        flashMode: String,
        macroEnabled: Bool,
        onTimerTap: @escaping () -> Void,
        onMacroTap: @escaping () -> Void
    ) {
        self.timerSeconds = timerSeconds
        self.iso = iso
        self.flashMode = flashMode
        self.macroEnabled = macroEnabled
        self.isAutoFocus = true
        self.exposureValue = 0
        self.onTimerTap = onTimerTap
        self.onMacroTap = onMacroTap
    }
}

// MARK: - Analog Display Panel (10px corner radius)
struct AnalogDisplayPanel: View {
    @Binding var focusPosition: Float
    @Binding var exposureValue: Float
    @Binding var shutterSpeedIndex: Int  // Changed from apertureValue to shutter speed
    let timerSeconds: Int
    let iso: Int
    let flashMode: String
    let macroEnabled: Bool
    let isAutoFocus: Bool
    var compact: Bool = false
    let onFocusChanged: (Float) -> Void
    let onExposureChanged: (Float) -> Void
    let onShutterSpeedChanged: (Int) -> Void  // Changed from onApertureChanged
    var onTimerTap: () -> Void = {}
    var onMacroTap: () -> Void = {}
    /// Fired when a compact meter locks onto a horizontal scrub so the parent
    /// deck-swipe gesture can ignore that drag (avoids accidental expand).
    var onCompactScrubActive: ((Bool) -> Void)? = nil

    // Corner radius for dials panel
    private let cornerRadius: CGFloat = 10

    var body: some View {
        ZStack {
            // Outer black frame (matches scrubbers/buttons)
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.black)

            // Inner frame (cohesive with controls)
            RoundedRectangle(cornerRadius: cornerRadius - 2)
                .fill(Color(hex: "1a1a1a"))
                .padding(2)

            // Inner stroke
            RoundedRectangle(cornerRadius: cornerRadius - 2)
                .stroke(Color(hex: "333333"), lineWidth: 0.5)
                .padding(2)

            if compact {
                // Minimized: slim analog meters instead of dials
                // (the dials don't render legibly below full size).
                // Horizontal scrub on each meter; vertical flicks still
                // expand/collapse via the parent's simultaneousGesture.
                HStack(alignment: .center, spacing: 12) {
                    CompactMeter(
                        label: "FOCUS",
                        value: CGFloat(focusPosition),
                        display: isAutoFocus ? "AF" : String(format: "%.2f", focusPosition),
                        snapDivisions: 20, // 0.05 steps on release
                        onScrubActive: onCompactScrubActive
                    ) { normalized in
                        let v = Float(normalized)
                        guard abs(v - focusPosition) > 0.0005 else { return }
                        focusPosition = v
                        onFocusChanged(v)
                    }

                    CompactMeter(
                        label: "EV",
                        value: CGFloat((exposureValue + 2) / 4),
                        display: String(format: "%+.1f", exposureValue),
                        snapDivisions: 12, // 1/3-stop across −2…+2
                        onScrubActive: onCompactScrubActive
                    ) { normalized in
                        let raw = Float(normalized) * 4 - 2
                        let clamped = max(-2, min(2, raw))
                        guard abs(clamped - exposureValue) > 0.0005 else { return }
                        exposureValue = clamped
                        onExposureChanged(clamped)
                    }

                    // Readout only — not a scrubber. Vertical deck swipes
                    // still work here via the parent's simultaneousGesture.
                    VStack(alignment: .trailing, spacing: 3) {
                        Text("ISO \(iso)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.85))
                        Text(Self.speedLabels[max(0, min(Self.speedLabels.count - 1, shutterSpeedIndex))])
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    .frame(width: 58, alignment: .trailing)
                    .allowsHitTesting(false)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
            } else {
                // Content: two analog dials with the horizontal EV meter
                // between them. The numeric ISO readout stays out - the
                // viewfinder info bar below already shows it.
                HStack(alignment: .center, spacing: 0) {
                    // Left: Focus dial
                    FocusDial(value: $focusPosition, onChanged: onFocusChanged)
                        .frame(width: 98, height: 98)

                    Spacer(minLength: 6)

                    // Center: horizontal EV meter (also hosts the hidden
                    // 5-tap finger-tips toggle via its own tap gesture)
                    HorizontalExposureMeter(value: exposureValue, iso: iso, showISO: false)

                    Spacer(minLength: 6)

                    // Right: Shutter Speed dial
                    ShutterSpeedDial(value: $shutterSpeedIndex, onChanged: onShutterSpeedChanged)
                        .frame(width: 98, height: 98)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
            }
        }
    }

    private static let speedLabels = [
        "4\"", "2\"", "1\"", "1/2", "1/4", "1/8", "1/15", "1/30",
        "1/60", "1/125", "1/250", "1/500", "1/1000", "1/2000", "1/4000"
    ]
}

// MARK: - Compact Meter (scrubbable needle on a ticked track)
struct CompactMeter: View {
    let label: String
    let value: CGFloat  // 0...1 needle position
    let display: String
    /// Equal steps across 0...1 applied on release (nil = leave final continuous).
    var snapDivisions: Int? = nil
    /// Notifies parent when a horizontal scrub claims the drag (deck swipe must ignore it).
    var onScrubActive: ((Bool) -> Void)? = nil
    var onScrub: ((CGFloat) -> Void)? = nil

    /// Once a drag proves horizontal, keep scrubbing even if the finger wobbles.
    @State private var scrubLocked = false
    @State private var liveNormalized: CGFloat? = nil
    @State private var lastHapticBucket: Int = .min

    private var needlePosition: CGFloat {
        min(max(liveNormalized ?? value, 0), 1)
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(label)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                Spacer()
                Text(display)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(scrubLocked ? DS.accent : .white.opacity(0.85))
            }

            GeometryReader { geo in
                let width = geo.size.width

                ZStack(alignment: .leading) {
                    // Tick marks
                    Canvas { ctx, size in
                        let tickCount = 9
                        for i in 0..<tickCount {
                            let x = CGFloat(i) / CGFloat(tickCount - 1) * (size.width - 1)
                            let isMajor = i % 2 == 0
                            let rect = CGRect(x: x, y: isMajor ? 2 : 4,
                                              width: 1, height: isMajor ? 8 : 4)
                            ctx.fill(Path(rect), with: .color(.white.opacity(isMajor ? 0.3 : 0.15)))
                        }
                    }

                    // Track line
                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 1)
                        .offset(y: 0)

                    // Needle - golden-yellow keyline (DS.accent, matches the
                    // tick/icon accents on the bottom controls)
                    Capsule()
                        .fill(DS.accent)
                        .frame(width: 2, height: 12)
                        .shadow(color: DS.accent.opacity(scrubLocked ? 0.45 : 0), radius: 2, y: 0)
                        .offset(x: needlePosition * (width - 2))
                        .animation(scrubLocked ? nil : .spring(response: 0.3, dampingFraction: 0.8), value: needlePosition)
                }
                // Tall hit strip so the slim track is easy to grab
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { drag in
                            guard let onScrub else { return }
                            let dx = drag.translation.width
                            let dy = drag.translation.height
                            // Strict horizontal axis-lock: vertical flicks must
                            // reach the parent deckSwipe unclaimed (DeckScrubLock).
                            if !scrubLocked {
                                guard abs(dx) > 8, abs(dx) > abs(dy) * 1.4 else { return }
                                scrubLocked = true
                                onScrubActive?(true)
                            }
                            let x = min(max(drag.location.x, 0), width)
                            let normalized = width > 0 ? x / width : 0
                            liveNormalized = normalized
                            onScrub(normalized)
                            // Light tick every ~1/12 of travel
                            let bucket = Int((normalized * 12).rounded())
                            if bucket != lastHapticBucket {
                                lastHapticBucket = bucket
                                Haptics.light()
                            }
                        }
                        .onEnded { _ in
                            if scrubLocked {
                                if let live = liveNormalized, let onScrub {
                                    let final: CGFloat
                                    if let divisions = snapDivisions, divisions > 0 {
                                        final = (live * CGFloat(divisions)).rounded() / CGFloat(divisions)
                                    } else {
                                        final = live
                                    }
                                    onScrub(min(max(final, 0), 1))
                                }
                                onScrubActive?(false)
                            }
                            liveNormalized = nil
                            scrubLocked = false
                            lastHapticBucket = .min
                        }
                )
            }
            .frame(height: 14)
        }
        // Generous vertical padding expands the hit target without growing chrome
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }
}

// Legacy initializer for backward compatibility (without shutter speed)
extension AnalogDisplayPanel {
    init(
        focusPosition: Binding<Float>,
        exposureValue: Binding<Float>,
        timerSeconds: Int,
        iso: Int,
        flashMode: String,
        macroEnabled: Bool,
        isAutoFocus: Bool,
        onFocusChanged: @escaping (Float) -> Void,
        onExposureChanged: @escaping (Float) -> Void,
        onTimerTap: @escaping () -> Void = {},
        onMacroTap: @escaping () -> Void = {}
    ) {
        self._focusPosition = focusPosition
        self._exposureValue = exposureValue
        self._shutterSpeedIndex = .constant(4)  // Default to 1/250
        self.timerSeconds = timerSeconds
        self.iso = iso
        self.flashMode = flashMode
        self.macroEnabled = macroEnabled
        self.isAutoFocus = isAutoFocus
        self.onFocusChanged = onFocusChanged
        self.onExposureChanged = onExposureChanged
        self.onShutterSpeedChanged = { _ in }
        self.onTimerTap = onTimerTap
        self.onMacroTap = onMacroTap
    }
}

// MARK: - Mode Badge
struct ModeBadge: View {
    let text: String
    let active: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(active ? .white : .white.opacity(0.4))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.white.opacity(active ? 0.4 : 0.15), lineWidth: 0.5)
            )
    }
}

// Convenience init (for previews/static use)
extension AnalogDisplayPanel {
    init(
        focusPosition: Float,
        shutterSpeedIdx: Int = 4,
        ev: Float,
        isAutoFocus: Bool,
        timerSeconds: Int,
        flashMode: String,
        macroEnabled: Bool
    ) {
        self._focusPosition = .constant(focusPosition)
        self._exposureValue = .constant(ev)
        self._shutterSpeedIndex = .constant(shutterSpeedIdx)
        self.timerSeconds = timerSeconds
        self.iso = 100
        self.flashMode = flashMode
        self.macroEnabled = macroEnabled
        self.isAutoFocus = isAutoFocus
        self.onFocusChanged = { _ in }
        self.onExposureChanged = { _ in }
        self.onShutterSpeedChanged = { _ in }
    }
}
