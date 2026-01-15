import SwiftUI
import UIKit

// Uses Haptics, Triangle, and Color(hex:) from ContentView.swift

// MARK: - Focus Dial (cohesive with controls)
struct FocusDial: View {
    @Binding var value: Float
    let onChanged: (Float) -> Void

    private let marks: [(String, Float)] = [
        (".4m", 0.0), (".7", 0.17), ("1", 0.33), ("3", 0.5), ("5", 0.67), ("inf", 0.83)
    ]

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = size * 0.42

            ZStack {
                // Outer dark frame (matches WB style)
                Circle()
                    .fill(Color.black)

                // Inner frame (matches controls #2c2c2c)
                Circle()
                    .fill(Color(hex: "2c2c2c"))
                    .padding(2)

                // Inner stroke
                Circle()
                    .stroke(Color(hex: "444444"), lineWidth: 0.5)
                    .padding(2)

                // Dial face (subtle, not too dark)
                Circle()
                    .fill(Color(hex: "252525"))
                    .padding(5)

                // Tick marks (Figma style - clean white)
                ForEach(0..<25, id: \.self) { i in
                    let angle = -150.0 + Double(i) * 12.5
                    let isMajor = i % 4 == 0

                    Rectangle()
                        .fill(Color.white.opacity(isMajor ? 0.7 : 0.25))
                        .frame(width: isMajor ? 1.5 : 1, height: isMajor ? 10 : 5)
                        .offset(y: -radius + (isMajor ? 5 : 2.5))
                        .rotationEffect(.degrees(angle))
                }

                // Labels (Figma: white, monospace)
                ForEach(marks.indices, id: \.self) { i in
                    let mark = marks[i]
                    let angle = -150.0 + Double(mark.1) * 300.0
                    let labelRadius = radius * 0.62

                    Text(mark.0)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
                        .position(
                            x: center.x + labelRadius * cos(angle * .pi / 180),
                            y: center.y + labelRadius * sin(angle * .pi / 180)
                        )
                }

                // Needle (Figma: clean white)
                NeedleShape(length: radius * 0.7)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
                    .rotationEffect(.degrees(-150 + Double(value) * 300))

                // Center hub (small, dark)
                Circle()
                    .fill(Color(hex: "1a1a1a"))
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 0.5))

                // Red indicator at bottom (Figma)
                Circle()
                    .fill(Color.red)
                    .frame(width: 5, height: 5)
                    .offset(y: radius - 8)
            }
            .position(center)
            .contentShape(Circle().scale(1.3)) // Larger touch target
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let vector = CGVector(dx: drag.location.x - center.x, dy: drag.location.y - center.y)
                        var angle = atan2(vector.dy, vector.dx) * 180 / .pi
                        angle = angle + 150
                        if angle < 0 { angle += 360 }
                        if angle > 300 { angle = angle > 330 ? 0 : 300 }
                        let newValue = Float(min(max(angle / 300, 0), 1))
                        // Snap to major marks for delight
                        let snapped = round(newValue * 6) / 6
                        if abs(snapped - value) > 0.02 {
                            value = snapped
                            onChanged(snapped)
                            Haptics.light()
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

// MARK: - Shutter Speed Dial (real iOS control)
struct ShutterSpeedDial: View {
    @Binding var value: Int  // Index into shutter speeds array
    let onChanged: (Int) -> Void

    // Shutter speeds: 1/4000 to 1/15 (index 0-7)
    private let speeds = ["4k", "2k", "1k", "500", "250", "125", "60", "30"]
    private let marks: [(String, Float)] = [
        ("4k", 0.0), ("2k", 0.143), ("1k", 0.286), ("500", 0.429), ("250", 0.571), ("125", 0.714), ("60", 0.857), ("30", 1.0)
    ]

    private var normalizedValue: Float {
        return Float(value) / Float(speeds.count - 1)
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = size * 0.42

            ZStack {
                // Outer dark frame (matches WB style)
                Circle()
                    .fill(Color.black)

                // Inner frame (matches controls #2c2c2c)
                Circle()
                    .fill(Color(hex: "2c2c2c"))
                    .padding(2)

                // Inner stroke
                Circle()
                    .stroke(Color(hex: "444444"), lineWidth: 0.5)
                    .padding(2)

                // Dial face (subtle, not too dark)
                Circle()
                    .fill(Color(hex: "252525"))
                    .padding(5)

                // Tick marks - 8 major for each shutter speed
                ForEach(0..<8, id: \.self) { i in
                    let angle = -150.0 + Double(i) * (300.0 / 7.0)

                    Rectangle()
                        .fill(Color.white.opacity(0.7))
                        .frame(width: 1.5, height: 10)
                        .offset(y: -radius + 5)
                        .rotationEffect(.degrees(angle))
                }

                // Labels
                ForEach(marks.indices, id: \.self) { i in
                    let mark = marks[i]
                    let angle = -150.0 + Double(mark.1) * 300.0
                    let labelRadius = radius * 0.60

                    Text(mark.0)
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.85))
                        .position(
                            x: center.x + labelRadius * cos(angle * .pi / 180),
                            y: center.y + labelRadius * sin(angle * .pi / 180)
                        )
                }

                // Needle
                NeedleShape(length: radius * 0.7)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
                    .rotationEffect(.degrees(-150 + Double(normalizedValue) * 300))

                // Center hub
                Circle()
                    .fill(Color(hex: "1a1a1a"))
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 0.5))
            }
            .position(center)
            .contentShape(Circle().scale(1.3))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let vector = CGVector(dx: drag.location.x - center.x, dy: drag.location.y - center.y)
                        var angle = atan2(vector.dy, vector.dx) * 180 / .pi
                        angle = angle + 150
                        if angle < 0 { angle += 360 }
                        if angle > 300 { angle = angle > 330 ? 0 : 300 }
                        let normalized = Float(min(max(angle / 300, 0), 1))
                        // Find closest shutter speed index
                        let newIndex = Int(round(normalized * Float(speeds.count - 1)))
                        let clampedIndex = max(0, min(speeds.count - 1, newIndex))
                        if clampedIndex != value {
                            value = clampedIndex
                            onChanged(clampedIndex)
                            Haptics.light()
                        }
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

// MARK: - Horizontal Exposure Meter (matches Figma design)
struct HorizontalExposureMeter: View {
    let value: Float // -2 to +2
    let iso: Int

    private let marks = ["+2", "+1", "0", "-1", "-2"]

    var body: some View {
        VStack(spacing: 4) {
            // Meter bar with ticks
            HStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { i in
                    HStack(spacing: 0) {
                        // Major tick
                        VStack(spacing: 2) {
                            Rectangle()
                                .fill(Color.white.opacity(i == 2 ? 0.8 : 0.4))
                                .frame(width: i == 2 ? 2 : 1, height: i == 2 ? 10 : 6)

                            Text(marks[i])
                                .font(.system(size: 7, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(i == 2 ? 0.8 : 0.4))
                        }

                        if i < 4 {
                            Spacer()
                            // Minor ticks between major ones
                            Rectangle()
                                .fill(Color.white.opacity(0.2))
                                .frame(width: 1, height: 4)
                            Spacer()
                        }
                    }
                }
            }
            .frame(width: 80, height: 24)
            .overlay(
                // Indicator triangle
                Triangle()
                    .fill(Color.white)
                    .frame(width: 6, height: 5)
                    .offset(x: CGFloat(value) * -20) // Move based on EV value
                    .offset(y: -14),
                alignment: .center
            )

            // ISO display
            Text("\(iso)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
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

// MARK: - Analog Display Panel (Figma: 355x190, r=95 pill shape)
struct AnalogDisplayPanel: View {
    @Binding var focusPosition: Float
    @Binding var exposureValue: Float
    @Binding var shutterSpeedIndex: Int  // Changed from apertureValue to shutter speed
    let timerSeconds: Int
    let iso: Int
    let flashMode: String
    let macroEnabled: Bool
    let isAutoFocus: Bool
    let onFocusChanged: (Float) -> Void
    let onExposureChanged: (Float) -> Void
    let onShutterSpeedChanged: (Int) -> Void  // Changed from onApertureChanged
    var onTimerTap: () -> Void = {}
    var onMacroTap: () -> Void = {}

    // Figma pill radius
    private let pillRadius: CGFloat = 60

    var body: some View {
        ZStack {
            // Dark background (Figma: pill shape)
            RoundedRectangle(cornerRadius: pillRadius)
                .fill(Color(hex: "0d0d0d"))

            // Subtle border
            RoundedRectangle(cornerRadius: pillRadius)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.1), Color.white.opacity(0.03)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )

            HStack(spacing: 0) {
                // Left: Focus dial
                FocusDial(value: $focusPosition, onChanged: onFocusChanged)
                    .frame(width: 100, height: 100)

                Spacer()

                // Center: AF badge, timer, AUTO/SV, exposure meter with ISO
                CenterDisplay(
                    timerSeconds: timerSeconds,
                    iso: iso,
                    flashMode: flashMode,
                    macroEnabled: macroEnabled,
                    isAutoFocus: isAutoFocus,
                    exposureValue: exposureValue,
                    onTimerTap: onTimerTap,
                    onMacroTap: onMacroTap
                )

                Spacer()

                // Right: Shutter Speed dial (real iOS control)
                ShutterSpeedDial(value: $shutterSpeedIndex, onChanged: onShutterSpeedChanged)
                    .frame(width: 100, height: 100)
            }
            .padding(.horizontal, 12)

            // Bottom label
            VStack {
                Spacer()
                HStack(spacing: 4) {
                    Circle().fill(Color.red).frame(width: 4, height: 4)
                    Text("ANALOG DISPLAY SYSTEM")
                        .font(.system(size: 6, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                        .tracking(1)
                }
                .padding(.bottom, 6)
            }
        }
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
