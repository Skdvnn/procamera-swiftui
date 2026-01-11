import SwiftUI

// MARK: - Rich Focus Dial with Border
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

                // Inner dial face with rich gradient
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

                // Tick marks with gradient
                ForEach(0..<31, id: \.self) { i in
                    let angle = -150.0 + Double(i) * 10
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
                    let angle = -150.0 + Double(mark.1) * 300.0
                    let labelRadius = radius * 0.58

                    Text(mark.0)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
                        .position(
                            x: center.x + labelRadius * cos(angle * .pi / 180),
                            y: center.y + labelRadius * sin(angle * .pi / 180)
                        )
                }

                // Needle with gradient
                NeedleShape(length: radius * 0.75)
                    .fill(
                        LinearGradient(
                            colors: [.white, .white.opacity(0.6)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                    .rotationEffect(.degrees(-150 + Double(value) * 300))

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

                // Red indicator at bottom
                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
                    .offset(y: radius - 4)
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

// MARK: - Rich Exposure Dial
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

// MARK: - Center Display
struct CenterDisplay: View {
    let timerSeconds: Int
    let iso: Int
    let flashMode: String
    let macroEnabled: Bool
    let onTimerTap: () -> Void
    let onMacroTap: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                // Timer button
                Button(action: onTimerTap) {
                    Image(systemName: "timer")
                        .foregroundColor(timerSeconds > 0 ? .white : .white.opacity(0.25))
                }

                // Macro button
                Button(action: onMacroTap) {
                    Image(systemName: "leaf.fill")
                        .foregroundColor(macroEnabled ? .green : .white.opacity(0.25))
                }
            }
            .font(.system(size: 13))

            Text(timerSeconds > 0 ? "\(timerSeconds)s" : "--")
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                .foregroundColor(.white)

            Text("ISO \(iso)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.5))

            Text(flashMode)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
        }
        .frame(width: 85)
    }
}

// MARK: - Analog Display Panel with Border
struct AnalogDisplayPanel: View {
    @Binding var focusPosition: Float
    @Binding var exposureValue: Float
    let timerSeconds: Int
    let iso: Int
    let flashMode: String
    let macroEnabled: Bool
    let isAutoFocus: Bool
    let onFocusChanged: (Float) -> Void
    let onExposureChanged: (Float) -> Void
    var onTimerTap: () -> Void = {}
    var onMacroTap: () -> Void = {}

    var body: some View {
        ZStack {
            // Charcoal background
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(white: 0.06))

            // Border
            RoundedRectangle(cornerRadius: 18)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.12), Color.white.opacity(0.04)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.5
                )

            // Inner shadow
            RoundedRectangle(cornerRadius: 17)
                .fill(
                    LinearGradient(
                        colors: [Color.black.opacity(0.3), Color.clear, Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .padding(2)

            HStack(spacing: 0) {
                FocusDial(value: $focusPosition, onChanged: onFocusChanged)
                    .frame(width: 115, height: 115)

                Spacer()

                CenterDisplay(
                    timerSeconds: timerSeconds,
                    iso: iso,
                    flashMode: flashMode,
                    macroEnabled: macroEnabled,
                    onTimerTap: onTimerTap,
                    onMacroTap: onMacroTap
                )

                Spacer()

                ExposureDial(value: $exposureValue, onChanged: onExposureChanged)
                    .frame(width: 115, height: 115)
            }
            .padding(.horizontal, 6)

            // Bottom label only (removed AF badge - was overlapping)
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

// Convenience init
extension AnalogDisplayPanel {
    init(
        focusPosition: Float,
        aperture: Float,
        ev: Float,
        isAutoFocus: Bool,
        timerSeconds: Int,
        flashMode: String,
        macroEnabled: Bool
    ) {
        self._focusPosition = .constant(focusPosition)
        self._exposureValue = .constant(ev)
        self.timerSeconds = timerSeconds
        self.iso = 100
        self.flashMode = flashMode
        self.macroEnabled = macroEnabled
        self.isAutoFocus = isAutoFocus
        self.onFocusChanged = { _ in }
        self.onExposureChanged = { _ in }
    }
}
