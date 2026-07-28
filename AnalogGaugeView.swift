import SwiftUI
import UIKit

extension Notification.Name {
    static let toggleFingerTips = Notification.Name("toggleFingerTips")
}

// Uses Haptics, Triangle, and Color(hex:) from ContentView.swift

// MARK: - Focus Dial (premium Leica/Nikon style)
struct FocusDial: View {
    @Binding var value: Float
    let onChanged: (Float) -> Void

    private let marks: [(String, Float)] = [
        (".4m", 0.0), (".7", 0.17), ("1", 0.33), ("3", 0.5), ("5", 0.67), ("inf", 1.0)
    ]

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

                // Center hub (Leica-style)
                Circle()
                    .fill(Color(hex: "0a0a0a"))
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
            }
            .position(center)
            .contentShape(Circle().scale(1.3)) // Larger touch target
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let vector = CGVector(dx: drag.location.x - center.x, dy: drag.location.y - center.y)
                        var angle = atan2(vector.dy, vector.dx) * 180 / .pi
                        angle = angle + 150
                        if angle < 0 { angle += 360 }
                        if angle > 300 { angle = angle > 330 ? 0 : 300 }
                        let newValue = Float(min(max(angle / 300, 0), 1))
                        // Snap to the same mark table as CompactFocusScrubber (∞ = 1.0).
                        let snapped = marks.min(by: {
                            abs($0.1 - newValue) < abs($1.1 - newValue)
                        })?.1 ?? newValue
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

// MARK: - Shutter Speed Dial (premium Leica/Nikon style)
struct ShutterSpeedDial: View {
    /// Binding is the **CameraManager / ContentView shutterSpeedIndex** (0=4″ … 14=1/4000).
    @Binding var value: Int
    let onChanged: (Int) -> Void

    // Full useful range: 1/4000…4″ so Night/LE aren't nearest-neighbor snapped to 1/30.
    private let dialLabels = ["4k", "1k", "500", "125", "30", "1/8", "1\"", "4\""]
    private let cameraIndices = [14, 12, 11, 9, 7, 5, 2, 0]
    private let marks: [(String, Float)] = [
        ("4k", 0.0), ("1k", 0.143), ("500", 0.286), ("125", 0.429),
        ("30", 0.571), ("1/8", 0.714), ("1\"", 0.857), ("4\"", 1.0)
    ]

    private var dialPosition: Int {
        var best = 0
        var bestDist = Int.max
        for (i, camIdx) in cameraIndices.enumerated() {
            let d = abs(camIdx - value)
            if d < bestDist {
                bestDist = d
                best = i
            }
        }
        return best
    }

    private var normalizedValue: Float {
        Float(dialPosition) / Float(max(dialLabels.count - 1, 1))
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

                // Tick marks - 8 major for each shutter speed (crisp white)
                ForEach(0..<8, id: \.self) { i in
                    let angle = -150.0 + Double(i) * (300.0 / 7.0)

                    Rectangle()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: 1.5, height: 10)
                        .offset(y: -radius + 5)
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

                // Needle (clean white with glow)
                NeedleShape(length: radius * 0.7)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.8), radius: 2, y: 1)
                    .rotationEffect(.degrees(-150 + Double(normalizedValue) * 300))

                // Center hub (Leica-style)
                Circle()
                    .fill(Color(hex: "0a0a0a"))
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 0.5))
            }
            .position(center)
            .contentShape(Circle().scale(1.3))
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let vector = CGVector(dx: drag.location.x - center.x, dy: drag.location.y - center.y)
                        var angle = atan2(vector.dy, vector.dx) * 180 / .pi
                        angle = angle + 150
                        if angle < 0 { angle += 360 }
                        if angle > 300 { angle = angle > 330 ? 0 : 300 }
                        let normalized = Float(min(max(angle / 300, 0), 1))
                        let dialIdx = Int(round(normalized * Float(dialLabels.count - 1)))
                        let clampedDial = max(0, min(dialLabels.count - 1, dialIdx))
                        let camIdx = cameraIndices[clampedDial]
                        if camIdx != value {
                            value = camIdx
                            onChanged(camIdx)
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

// MARK: - Horizontal Exposure Meter (Nikon-style accurate scale)
// Based on real camera meters: -2 to +2 scale with 1/3 stop increments
struct HorizontalExposureMeter: View {
    let value: Float // typically −2…+2; device bias can exceed that
    /// Level sits under the EV scale — ISO/S live in the hist info bar (Build 73).
    var showLevel: Bool = false

    // Major marks at full stops, minor marks at 1/3 stops
    private let majorMarks = ["-2", "-1", "0", "+1", "+2"]
    /// One third-stop slot — 13 marks × 8.5pt; full stop = 3 slots.
    private let tickSlot: CGFloat = 8.5
    private let scaleMin: Float = -2
    private let scaleMax: Float = 2

    var body: some View {
        VStack(spacing: 6) {
            // Meter scale - larger and more detailed
            ZStack {
                // Dark background panel
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(hex: "0a0a0a"))
                    .frame(width: 120, height: 36)

                // Inner border
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(hex: "2a2a2a"), lineWidth: 0.5)
                    .frame(width: 120, height: 36)

                // Scale with ticks
                VStack(spacing: 0) {
                    // Tick marks — yellow only on the focused/leading mark (Build 97).
                    HStack(spacing: 0) {
                        ForEach(0..<13, id: \.self) { i in
                            let isMajor = i % 3 == 0
                            let stopIndex = i / 3
                            let markEV = Float(i - 6) / 3.0
                            // Lead off the clamped display value so a +3 bias
                            // still lights the +2 rail instead of nothing (Build 119).
                            let displayEV = min(scaleMax, max(scaleMin, value))
                            let leading = abs(markEV - displayEV) <= 1.0 / 6.0
                            let edgeFade: Double = {
                                if stopIndex == 0 || stopIndex == 4 { return 0.5 }
                                if stopIndex == 1 || stopIndex == 3 { return 0.75 }
                                return 1.0
                            }()

                            VStack(spacing: 1) {
                                Rectangle()
                                    .fill(
                                        leading
                                            ? DS.accent
                                            : Color.white.opacity((isMajor ? 0.8 : 0.35) * edgeFade)
                                    )
                                    .frame(
                                        width: isMajor ? 1.5 : 1,
                                        height: (isMajor ? 10 : 5) + (leading ? 3 : 0)
                                    )
                                    // Fixed slot, bottom-aligned: ticks grow off a shared
                                    // baseline so the degree labels never jitter.
                                    .frame(height: 13, alignment: .bottom)

                                if isMajor {
                                    Text(majorMarks[stopIndex])
                                        .font(.system(size: 7, weight: stopIndex == 2 ? .bold : .medium, design: .monospaced))
                                        .foregroundColor(
                                            leading
                                                ? DS.accent.opacity(0.85)
                                                : .white.opacity(0.7 * edgeFade)
                                        )
                                }
                            }
                            .frame(width: tickSlot)
                            .animation(.easeOut(duration: 0.12), value: leading)
                        }
                    }

                    // Moving indicator triangle (yellow/accent color)
                    ZStack {
                        // Pin to the painted −2…+2 rail — device bias can be ±3…±8
                        // and used to send the pip off the panel (Build 119).
                        let displayEV = min(scaleMax, max(scaleMin, value))
                        let pxPerStop = tickSlot * 3 // 25.5
                        let indicatorOffset = CGFloat(displayEV) * pxPerStop

                        // Yellow triangle indicator pointing up at the scale
                        Triangle()
                            .fill(Color(red: 1.0, green: 0.85, blue: 0.35))  // Always yellow/accent
                            .frame(width: 8, height: 6)
                            .rotationEffect(.degrees(180))  // Point upward
                            .offset(x: indicatorOffset)
                    }
                    .frame(height: 8)
                    .offset(y: -1)
                }
            }
            .frame(width: 120, height: 36)
            .clipped()

            // Level replaces ISO/S under the meter — those live in the hist bar.
            // fixedSize: the 110pt dial row used to compress this away (Build 121).
            if showLevel {
                InfoBarMetalLevel(compact: false)
                    .fixedSize()
            }
        }
        .fixedSize(horizontal: false, vertical: true)
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
    var isoIsAuto: Bool = false
    var shutterLabel: String = ""
    var shutterIsAuto: Bool = false
    let flashMode: String
    let macroEnabled: Bool
    let isAutoFocus: Bool
    let exposureValue: Float
    var showLevel: Bool = false
    let onTimerTap: () -> Void
    let onMacroTap: () -> Void

    var body: some View {
        // EV meter + optional level under it (ISO/S are in the hist info bar).
        HorizontalExposureMeter(
            value: exposureValue,
            showLevel: showLevel
        )
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
    var isoIsAuto: Bool = false
    var shutterLabel: String = ""
    var shutterIsAuto: Bool = false
    let flashMode: String
    let macroEnabled: Bool
    let isAutoFocus: Bool
    var compact: Bool = false
    /// Horizon level under EV / between compact scrubbers (Build 73).
    var showLevel: Bool = false
    let onFocusChanged: (Float) -> Void
    let onExposureChanged: (Float) -> Void
    let onShutterSpeedChanged: (Int) -> Void  // Changed from onApertureChanged
    var onFocusScrubActive: ((Bool) -> Void)? = nil
    var onEVScrubActive: ((Bool) -> Void)? = nil
    var onTimerTap: () -> Void = {}
    var onMacroTap: () -> Void = {}

    // Corner radius for dials panel
    private let cornerRadius: CGFloat = 10

    var body: some View {
        Group {
            if compact {
                // Compact strip — 38pt instrument face with outer dark bezel (Build 100).
                HStack(alignment: .center, spacing: 4) {
                    CompactFocusScrubber(
                        focusPosition: $focusPosition,
                        isAutoFocus: isAutoFocus,
                        onChanged: onFocusChanged,
                        onActiveChanged: onFocusScrubActive
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)

                    if showLevel {
                        InfoBarMetalLevel(compact: true)
                    }

                    CompactEVScrubber(
                        exposureValue: $exposureValue,
                        onChanged: onExposureChanged,
                        onActiveChanged: onEVScrubActive
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                }
            } else {
                // Expanded dials — Level under EV is required when armed (Build 121).
                // Slightly shorter dials when Level is on so the stack clears the panel.
                let dialSize: CGFloat = showLevel ? 90 : 98
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.black)

                    RoundedRectangle(cornerRadius: cornerRadius - 2)
                        .fill(Color(hex: "1a1a1a"))
                        .padding(2)

                    RoundedRectangle(cornerRadius: cornerRadius - 2)
                        .stroke(Color(hex: "333333"), lineWidth: 0.5)
                        .padding(2)

                    HStack(alignment: .center, spacing: 0) {
                        FocusDial(value: $focusPosition, onChanged: onFocusChanged)
                            .frame(width: dialSize, height: dialSize)

                        Spacer(minLength: 4)

                        CenterDisplay(
                            timerSeconds: timerSeconds,
                            iso: iso,
                            isoIsAuto: isoIsAuto,
                            shutterLabel: shutterLabel,
                            shutterIsAuto: shutterIsAuto,
                            flashMode: flashMode,
                            macroEnabled: macroEnabled,
                            isAutoFocus: isAutoFocus,
                            exposureValue: exposureValue,
                            showLevel: showLevel,
                            onTimerTap: onTimerTap,
                            onMacroTap: onMacroTap
                        )
                        .fixedSize()

                        Spacer(minLength: 4)

                        ShutterSpeedDial(value: $shutterSpeedIndex, onChanged: onShutterSpeedChanged)
                            .frame(width: dialSize, height: dialSize)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, showLevel ? 4 : 6)
                }
            }
        }
    }

    private static let speedLabels = [
        "4\"", "2\"", "1\"", "1/2", "1/4", "1/8", "1/15", "1/30",
        "1/60", "1/125", "1/250", "1/500", "1/1000", "1/2000", "1/4000"
    ]
}

// MARK: - Compact FOCUS scrubber (NativeSnapScrubber chrome)
struct CompactFocusScrubber: View {
    @Binding var focusPosition: Float
    let isAutoFocus: Bool
    let onChanged: (Float) -> Void
    var onActiveChanged: ((Bool) -> Void)? = nil

    /// Discrete focus stops matching the FocusDial major marks (shared table).
    private let stops: [Int] = Array(0...5)
    private let stopValues: [Float] = [0.0, 0.17, 0.33, 0.5, 0.67, 1.0]
    private let stopLabels = [".4m", ".7m", "1m", "3m", "5m", "∞"]

    /// Stable index — avoids Binding get/set snap ping-pong with ScrollView.
    @State private var index: Int = 3
    /// Ignore pinch/AF streaming updates briefly after a local scrub (prevents scroll thrash).
    @State private var suppressExternalUntil: TimeInterval = 0
    @State private var pendingExternal: DispatchWorkItem?

    private func nearestIndex(to value: Float) -> Int {
        stopValues.enumerated().min(by: {
            abs($0.element - value) < abs($1.element - value)
        })?.offset ?? 3
    }

    var body: some View {
        NativeSnapScrubber(
            label: "FOCUS",
            values: stops,
            selection: $index,
            sideLabelWidth: 28,
            tickCount: 14,
            tickMajorEvery: 2,
            instrumentFace: true,
            title: { idx in
                let safe = min(max(idx, 0), stopLabels.count - 1)
                if isAutoFocus && safe == index { return "AF" }
                return stopLabels[safe]
            },
            onChanged: { idx in
                suppressExternalUntil = Date().timeIntervalSince1970 + 0.35
                let safe = min(max(idx, 0), stopValues.count - 1)
                let value = stopValues[safe]
                if focusPosition != value {
                    focusPosition = value
                }
                onChanged(value)
            },
            onActiveChanged: onActiveChanged
        )
        .onAppear { index = nearestIndex(to: focusPosition) }
        .onChange(of: focusPosition) { _, newValue in
            // Debounce continuous AF/pinch updates so scrollPosition isn't spammed
            pendingExternal?.cancel()
            let work = DispatchWorkItem {
                guard Date().timeIntervalSince1970 >= suppressExternalUntil else { return }
                let nearest = nearestIndex(to: newValue)
                if nearest != index { index = nearest }
            }
            pendingExternal = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
        }
    }
}

// MARK: - Compact EV scrubber (NativeSnapScrubber chrome)
struct CompactEVScrubber: View {
    @Binding var exposureValue: Float
    let onChanged: (Float) -> Void
    var onActiveChanged: ((Bool) -> Void)? = nil

    private let stops: [Int] = Array(0...8)
    private let stopValues: [Float] = [-2, -1.5, -1, -0.5, 0, 0.5, 1, 1.5, 2]

    @State private var index: Int = 4
    @State private var suppressExternalUntil: TimeInterval = 0
    @State private var pendingExternal: DispatchWorkItem?

    private func nearestIndex(to value: Float) -> Int {
        stopValues.enumerated().min(by: {
            abs($0.element - value) < abs($1.element - value)
        })?.offset ?? 4
    }

    var body: some View {
        NativeSnapScrubber(
            label: "EV",
            values: stops,
            selection: $index,
            sideLabelWidth: 28,
            tickCount: 14,
            tickMajorEvery: 2,
            instrumentFace: true,
            title: { idx in
                let v = stopValues[min(max(idx, 0), stopValues.count - 1)]
                return String(format: "%+.1f", v)
            },
            onChanged: { idx in
                suppressExternalUntil = Date().timeIntervalSince1970 + 0.35
                let safe = min(max(idx, 0), stopValues.count - 1)
                let value = stopValues[safe]
                if exposureValue != value {
                    exposureValue = value
                }
                onChanged(value)
            },
            onActiveChanged: onActiveChanged
        )
        .onAppear { index = nearestIndex(to: exposureValue) }
        .onChange(of: exposureValue) { _, newValue in
            // Debounce viewfinder EV-drag streaming into scrollPosition
            pendingExternal?.cancel()
            let work = DispatchWorkItem {
                guard Date().timeIntervalSince1970 >= suppressExternalUntil else { return }
                let nearest = nearestIndex(to: newValue)
                if nearest != index { index = nearest }
            }
            pendingExternal = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
        }
    }
}

// MARK: - Compact Meter (needle on a ticked track) — kept for other readouts
struct CompactMeter: View {
    let label: String
    let value: CGFloat  // 0...1 needle position
    let display: String

    private let accentYellow = Color(red: 1.0, green: 0.85, blue: 0.35)

    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Text(label)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                Spacer()
                Text(display)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))
            }

            GeometryReader { geo in
                let width = geo.size.width
                let clamped = min(max(value, 0), 1)

                ZStack(alignment: .leading) {
                    Canvas { ctx, size in
                        let tickCount = max(11, Int(size.width / 12))
                        for i in 0..<tickCount {
                            let x = CGFloat(i) / CGFloat(tickCount - 1) * (size.width - 1)
                            let isEnd = i == 0 || i == tickCount - 1
                            let isMajor = i % 2 == 0
                            let h: CGFloat = isEnd ? 10 : (isMajor ? 8 : 4)
                            let y: CGFloat = isEnd ? 1 : (isMajor ? 2 : 4)
                            let w: CGFloat = isEnd ? 1.5 : 1
                            let rect = CGRect(x: x - (w - 1) / 2, y: y, width: w, height: h)
                            let color: Color = {
                                if isEnd { return accentYellow.opacity(0.85) }
                                if isMajor { return accentYellow.opacity(0.55) }
                                return accentYellow.opacity(0.22)
                            }()
                            ctx.fill(Path(rect), with: .color(color))
                        }
                    }

                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    accentYellow.opacity(0.18),
                                    Color.white.opacity(0.1),
                                    accentYellow.opacity(0.18)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 1)

                    Capsule()
                        .fill(Color(red: 1.0, green: 0.62, blue: 0.3))
                        .frame(width: 2, height: 12)
                        .shadow(color: Color(red: 1.0, green: 0.62, blue: 0.3).opacity(0.35), radius: 1.5, y: 0)
                        .offset(x: clamped * (width - 2))
                        .animation(ShutterMotion.scrub, value: clamped)
                }
            }
            .frame(height: 12)
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
        self._shutterSpeedIndex = .constant(10)  // Default to 1/250
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
