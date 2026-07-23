import SwiftUI
import Photos
import AVFoundation

// MARK: - Motion (mechanical film-lever — no springs, no bounce)

enum CullMotion {
    /// Snap-back after a drag miss
    static let flick = Animation.timingCurve(0.2, 0.8, 0.2, 1.0, duration: 0.16)
    /// Frame leaving the gate
    static let advanceOut = Animation.timingCurve(0.4, 0.0, 0.7, 0.3, duration: 0.13)
    /// Next frame seating into the gate
    static let advanceIn = Animation.timingCurve(0.15, 0.7, 0.2, 1.0, duration: 0.2)
    /// Grease-pencil draw-on
    static let draw = Animation.timingCurve(0.25, 0.1, 0.25, 1.0, duration: 0.28)
    /// KEEP / OUT stamp punch
    static let stamp = Animation.timingCurve(0.1, 0.8, 0.2, 1.0, duration: 0.14)
    static let stampFade = Animation.easeOut(duration: 0.18)
    /// Loupe raise / drop
    static let loupeIn = Animation.timingCurve(0.2, 0.75, 0.2, 1.0, duration: 0.16)
    static let loupeOut = Animation.easeOut(duration: 0.12)
    /// Sheet / chrome settle
    static let settle = Animation.timingCurve(0.22, 0.7, 0.2, 1.0, duration: 0.32)
    /// Chip / press micro
    static let press = Animation.easeOut(duration: 0.1)
    /// Drag wash tracking (near-instant)
    static let wash = Animation.easeOut(duration: 0.08)
}

// MARK: - Darkroom ground

struct DarkroomGround: View {
    var intensity: Double = 1.0

    var body: some View {
        ZStack {
            // Warm light-table base
            LinearGradient(
                colors: [
                    Color(hex: "221c16"),
                    Color(hex: "161310"),
                    Color(hex: "0e0c0a")
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            // Soft amber safelight wash from top-left
            RadialGradient(
                colors: [
                    CullPalette.amber.opacity(0.07 * intensity),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 20,
                endRadius: 420
            )

            // Safelight pool bottom-right
            RadialGradient(
                colors: [
                    CullPalette.safelight.opacity(0.05 * intensity),
                    Color.clear
                ],
                center: UnitPoint(x: 0.92, y: 0.88),
                startRadius: 10,
                endRadius: 280
            )

            // Vignette
            RadialGradient(
                colors: [Color.clear, Color.black.opacity(0.55 * intensity)],
                center: .center,
                startRadius: 80,
                endRadius: 520
            )

            ControlsGrain()
                .opacity(0.28 * intensity)
                .blendMode(.overlay)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Machined chrome chip (small control)

struct DarkroomChip: View {
    enum Kind { case amber, quiet, safelight }

    let title: String
    var kind: Kind = .quiet
    var compact: Bool = false

    private var stroke: Color {
        switch kind {
        case .amber: return CullPalette.amber.opacity(0.55)
        case .safelight: return CullPalette.safelight.opacity(0.65)
        case .quiet: return Color.white.opacity(0.18)
        }
    }

    private var fill: Color {
        switch kind {
        case .amber: return CullPalette.amber.opacity(0.08)
        case .safelight: return CullPalette.safelight.opacity(0.1)
        case .quiet: return Color.white.opacity(0.04)
        }
    }

    private var fg: Color {
        switch kind {
        case .amber: return CullPalette.amber
        case .safelight: return Color(red: 0.95, green: 0.55, blue: 0.5)
        case .quiet: return .white.opacity(0.7)
        }
    }

    var body: some View {
        Text(title)
            .font(.system(size: compact ? 9 : 10, weight: .bold, design: .monospaced))
            .tracking(compact ? 1.2 : 1.6)
            .foregroundColor(fg)
            .padding(.horizontal, compact ? 9 : 12)
            .padding(.vertical, compact ? 6 : 8)
            .background(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .stroke(stroke, lineWidth: 0.8)
            )
    }
}

private struct DarkroomChipButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(CullMotion.press, value: configuration.isPressed)
    }
}

struct DarkroomIconButton: View {
    let systemName: String
    var active: Bool = true
    var accent: Bool = false

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(
                accent
                    ? CullPalette.amber
                    : (active ? .white.opacity(0.82) : .white.opacity(0.22))
            )
            .frame(width: 38, height: 38)
            .background(
                Circle()
                    .fill(Color.white.opacity(0.06))
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.1), lineWidth: 0.6)
                    )
            )
    }
}

// MARK: - Grease pencil marks

struct GreasePencilX: Shape {
    var seed: Int = 0

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r1 = CGFloat((seed &* 17) % 9) / 120.0
        let r2 = CGFloat((seed &* 31) % 7) / 120.0
        let r3 = CGFloat((seed &* 13) % 5) / 140.0

        // Slightly bowed strokes — hand-drawn, not stamped
        path.move(to: CGPoint(
            x: rect.minX + rect.width * (0.10 + r1),
            y: rect.minY + rect.height * (0.12 - r2)
        ))
        path.addQuadCurve(
            to: CGPoint(
                x: rect.maxX - rect.width * (0.09 - r3),
                y: rect.maxY - rect.height * (0.11 + r1)
            ),
            control: CGPoint(
                x: rect.midX + rect.width * (0.04 + r2),
                y: rect.midY - rect.height * (0.03 - r3)
            )
        )
        path.move(to: CGPoint(
            x: rect.maxX - rect.width * (0.12 + r2),
            y: rect.minY + rect.height * (0.11 + r3)
        ))
        path.addQuadCurve(
            to: CGPoint(
                x: rect.minX + rect.width * (0.10 - r1),
                y: rect.maxY - rect.height * (0.12 - r2)
            ),
            control: CGPoint(
                x: rect.midX - rect.width * (0.05 - r1),
                y: rect.midY + rect.height * (0.04 + r3)
            )
        )
        return path
    }
}

struct GreasePencilCircle: Shape {
    var seed: Int = 0

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset = min(rect.width, rect.height) * 0.08
        let r = min(rect.width, rect.height) / 2 - inset
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let wobble = CGFloat((seed &* 7) % 5) / 100.0
        let start = Double((seed &* 11) % 40) / 180.0 * .pi

        var points: [CGPoint] = []
        for i in 0..<28 {
            let t = start + (Double(i) / 27.0) * (.pi * 2.05) // slight overdraw
            let wob = 1.0 + wobble * sin(t * 3 + Double(seed % 5))
            points.append(CGPoint(
                x: c.x + CGFloat(cos(t)) * r * wob,
                y: c.y + CGFloat(sin(t)) * r * wob
            ))
        }
        guard let first = points.first else { return path }
        path.move(to: first)
        for p in points.dropFirst() { path.addLine(to: p) }
        return path
    }
}

struct FrameMarkOverlay: View {
    let state: FrameMarkState
    let seed: Int
    var lineWidth: CGFloat = 2.4
    var padding: CGFloat = 8
    /// When true, strokes draw on (cull canvas). Contact sheet uses false.
    var animated: Bool = false

    @State private var drawProgress: CGFloat = 1

    var body: some View {
        Group {
            switch state {
            case .keep:
                GreasePencilCircle(seed: seed)
                    .trim(from: 0, to: drawProgress)
                    .stroke(
                        CullPalette.amber,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
                    )
                    .shadow(color: CullPalette.amber.opacity(0.35 * drawProgress), radius: 2)
                    .padding(padding)
            case .reject:
                ZStack {
                    GreasePencilX(seed: seed)
                        .trim(from: 0, to: drawProgress)
                        .stroke(
                            CullPalette.safelight.opacity(0.35),
                            style: StrokeStyle(lineWidth: lineWidth + 1.5, lineCap: .round)
                        )
                    GreasePencilX(seed: seed &+ 3)
                        .trim(from: 0, to: max(0, drawProgress - 0.08))
                        .stroke(
                            CullPalette.safelight,
                            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                        )
                }
                .padding(padding)
            case .unmarked:
                EmptyView()
            }
        }
        .opacity(state == .unmarked ? 0 : 1)
        .allowsHitTesting(false)
        .onAppear { bootstrapDraw() }
        .onChange(of: state) { _, new in
            guard animated, new != .unmarked else {
                drawProgress = new == .unmarked ? 0 : 1
                return
            }
            drawProgress = 0
            withAnimation(CullMotion.draw) { drawProgress = 1 }
        }
    }

    private func bootstrapDraw() {
        guard animated, state != .unmarked else {
            drawProgress = state == .unmarked ? 0 : 1
            return
        }
        drawProgress = 0
        withAnimation(CullMotion.draw) { drawProgress = 1 }
    }
}

/// KEEP / OUT punch stamp
struct MarkStampFlash: View {
    let state: FrameMarkState
    @State private var punched = false

    var body: some View {
        Text(state == .keep ? "KEEP" : "OUT")
            .font(.system(size: 44, weight: .bold, design: .monospaced))
            .tracking(10)
            .foregroundColor(state == .keep ? CullPalette.amber : CullPalette.safelight)
            .shadow(color: .black.opacity(0.65), radius: 10, y: 4)
            .scaleEffect(punched ? 1.0 : 1.18)
            .opacity(punched ? 1.0 : 0.0)
            .rotationEffect(.degrees(state == .keep ? -2 : 2))
            .onAppear {
                withAnimation(CullMotion.stamp) { punched = true }
            }
    }
}

private func strokeSeed(for id: UUID) -> Int {
    id.uuidString.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
}

// MARK: - Loupe

struct LoupeView: View {
    let image: UIImage
    let touch: CGPoint
    let container: CGSize
    var diameter: CGFloat = 148
    @State private var raised = false

    var body: some View {
        let imgSize = image.size
        let fit = AVMakeRect(
            aspectRatio: imgSize.width > 0 ? imgSize : CGSize(width: 1, height: 1),
            insideRect: CGRect(origin: .zero, size: container)
        )
        let scale: CGFloat = 2.4
        let nx = (touch.x - fit.minX) / max(fit.width, 1)
        let ny = (touch.y - fit.minY) / max(fit.height, 1)
        let pos = CGPoint(
            x: min(max(touch.x, diameter / 2 + 8), container.width - diameter / 2 - 8),
            y: min(max(touch.y - diameter * 0.55, diameter / 2 + 8), container.height - diameter / 2 - 8)
        )

        ZStack {
            Circle()
                .fill(Color.black)
                .frame(width: diameter, height: diameter)
                .overlay(
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: fit.width * scale, height: fit.height * scale)
                        .offset(
                            x: diameter / 2 - nx * fit.width * scale,
                            y: diameter / 2 - ny * fit.height * scale
                        )
                        .frame(width: diameter, height: diameter)
                        .clipped()
                )
                .overlay(
                    Circle()
                        .stroke(
                            LinearGradient(
                                colors: [
                                    CullPalette.amber.opacity(0.7),
                                    Color.white.opacity(0.25),
                                    CullPalette.amber.opacity(0.35)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )
                .overlay(
                    Circle()
                        .stroke(Color.black.opacity(0.5), lineWidth: 0.5)
                        .padding(2)
                )
                .shadow(color: .black.opacity(0.55), radius: 12, y: 6)

            Circle()
                .stroke(CullPalette.amber.opacity(0.35), lineWidth: 0.6)
                .frame(width: 14, height: 14)
            Rectangle()
                .fill(CullPalette.amber.opacity(0.45))
                .frame(width: 10, height: 0.6)
            Rectangle()
                .fill(CullPalette.amber.opacity(0.45))
                .frame(width: 0.6, height: 10)
        }
        .scaleEffect(raised ? 1.0 : 0.72, anchor: .bottom)
        .opacity(raised ? 1 : 0)
        .position(pos)
        .onAppear {
            withAnimation(CullMotion.loupeIn) { raised = true }
        }
    }
}

// MARK: - Cull library (front door)

struct CullLibraryView: View {
    @ObservedObject var store: GalleryStore
    @StateObject private var marks = FrameMarkStore()
    @Environment(\.dismiss) private var dismiss

    @State private var sessions: [ShootSession] = []
    @State private var route: CullRoute?
    @State private var showFieldBooks = false
    @State private var appeared = false

    private struct CullRoute: Identifiable {
        let id = UUID()
        let session: ShootSession
        let startIndex: Int
    }

    var body: some View {
        ZStack {
            DarkroomGround()

            VStack(spacing: 0) {
                header
                divider
                if sessions.isEmpty {
                    emptyState
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 36) {
                            ForEach(Array(sessions.enumerated()), id: \.element.id) { i, session in
                                SessionContactSheet(
                                    store: store,
                                    session: session,
                                    marks: marks,
                                    onCull: { open(session, at: firstUnmarkedIndex(in: session)) },
                                    onOpenFrame: { open(session, at: $0) }
                                )
                                .opacity(appeared ? 1 : 0)
                                .offset(y: appeared ? 0 : 18)
                                .animation(
                                    CullMotion.settle.delay(Double(i) * 0.05),
                                    value: appeared
                                )
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 18)
                        .padding(.bottom, 48)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            rebuildSessions()
            PhotosLibraryService.requestReadWrite { _ in }
            withAnimation(CullMotion.settle) { appeared = true }
        }
        .onChange(of: store.shots) { _, _ in rebuildSessions() }
        .fullScreenCover(item: $route) { r in
            CullSessionView(
                store: store,
                session: r.session,
                marks: marks,
                startIndex: r.startIndex,
                onFinished: {
                    route = nil
                    rebuildSessions()
                }
            )
        }
        .fullScreenCover(isPresented: $showFieldBooks) {
            LibraryView(store: store)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Button { dismiss() } label: {
                DarkroomIconButton(systemName: "xmark")
            }
            .accessibilityLabel("Close")

            VStack(alignment: .leading, spacing: 3) {
                Text("SHUTTERCRAFT")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(3.5)
                    .foregroundColor(CullPalette.amber.opacity(0.75))
                Text("Darkroom")
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                    .foregroundColor(.white.opacity(0.94))
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text("\(store.shots.count)")
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85))
                Text("FRAMES")
                    .font(.system(size: 7, weight: .semibold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundColor(.white.opacity(0.32))
            }

            Button { showFieldBooks = true } label: {
                DarkroomChip(title: "BOOKS", kind: .quiet, compact: true)
            }
            .accessibilityLabel("Open Field Books")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }

    private var divider: some View {
        HStack(spacing: 10) {
            Rectangle().fill(CullPalette.hairline).frame(height: 0.5)
            Text("CONTACT SHEETS")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(2.5)
                .foregroundColor(CullPalette.amber.opacity(0.45))
            Rectangle().fill(CullPalette.hairline).frame(height: 0.5)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                // Empty contact sheet silhouette
                RoundedRectangle(cornerRadius: 2)
                    .stroke(CullPalette.hairline.opacity(0.5), lineWidth: 0.6)
                    .frame(width: 220, height: 160)
                    .overlay(
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 1),
                                GridItem(.flexible(), spacing: 1),
                                GridItem(.flexible(), spacing: 1)
                            ],
                            spacing: 1
                        ) {
                            ForEach(0..<9, id: \.self) { _ in
                                Rectangle()
                                    .fill(Color.white.opacity(0.03))
                                    .aspectRatio(1, contentMode: .fit)
                                    .overlay(Rectangle().stroke(CullPalette.hairline.opacity(0.25), lineWidth: 0.4))
                            }
                        }
                        .padding(8)
                    )

                Image(systemName: "camera.aperture")
                    .font(.system(size: 28, weight: .ultraLight))
                    .foregroundColor(CullPalette.amber.opacity(0.55))
            }
            .padding(.bottom, 28)

            Text("Nothing on the table")
                .font(.system(size: 20, weight: .semibold, design: .serif))
                .foregroundColor(.white.opacity(0.88))
                .padding(.bottom, 8)

            Text("Shoot a session outdoors.\nCome back here to cull it down.")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .multilineTextAlignment(.center)
                .foregroundColor(.white.opacity(0.38))
                .lineSpacing(4)
                .padding(.horizontal, 40)
                .padding(.bottom, 28)

            Button { dismiss() } label: {
                DarkroomChip(title: "BACK TO CAMERA", kind: .amber)
            }
            Spacer()
        }
    }

    private func rebuildSessions() {
        sessions = SessionClusterer.cluster(store.shots)
    }

    private func open(_ session: ShootSession, at index: Int) {
        route = CullRoute(session: session, startIndex: max(0, min(index, session.shots.count - 1)))
    }

    private func firstUnmarkedIndex(in session: ShootSession) -> Int {
        session.shots.firstIndex { marks.state(for: $0.id) == .unmarked } ?? 0
    }
}

// MARK: - Session contact sheet

struct SessionContactSheet: View {
    let store: GalleryStore
    let session: ShootSession
    @ObservedObject var marks: FrameMarkStore
    let onCull: () -> Void
    let onOpenFrame: (Int) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 0),
        GridItem(.flexible(), spacing: 0),
        GridItem(.flexible(), spacing: 0)
    ]

    private var progress: (kept: Int, rejected: Int, unmarked: Int) {
        session.progress(marks: marks)
    }

    private var spanText: String {
        let df = DateFormatter()
        df.dateFormat = "h:mm a"
        guard let first = session.shots.first, let last = session.shots.last else { return "" }
        if first.id == last.id { return df.string(from: first.date) }
        return "\(df.string(from: first.date)) – \(df.string(from: last.date))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Sheet header
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(session.title)
                        .font(.system(size: 17, weight: .semibold, design: .serif))
                        .foregroundColor(.white.opacity(0.94))
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        Text("\(session.shots.count) FRAMES")
                        Text("·")
                        Text(spanText.uppercased())
                    }
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.38))
                    .tracking(0.6)

                    // Live cull tally
                    HStack(spacing: 10) {
                        tally(progress.kept, "KEPT", CullPalette.amber)
                        tally(progress.rejected, "OUT", CullPalette.safelight)
                        tally(progress.unmarked, "OPEN", Color.white.opacity(0.45))
                    }
                    .padding(.top, 4)
                }

                Spacer(minLength: 8)

                Button(action: onCull) {
                    DarkroomChip(
                        title: progress.unmarked == 0 && progress.kept + progress.rejected > 0
                            ? "REVIEW"
                            : "CULL",
                        kind: .amber
                    )
                }
                .accessibilityLabel("Cull session")
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 14)

            // Physical sheet plate
            VStack(spacing: 0) {
                // Plate top rule with frame count stamp
                HStack {
                    Text("PROOF")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(CullPalette.amber.opacity(0.5))
                    Spacer()
                    Text(String(format: "Nº %03d–%03d", 1, session.shots.count))
                        .font(.system(size: 7, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.28))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.black.opacity(0.25))

                LazyVGrid(columns: columns, spacing: 0) {
                    ForEach(Array(session.shots.enumerated()), id: \.element.id) { index, shot in
                        contactCell(shot: shot, index: index)
                    }
                }
            }
            .background(
                LinearGradient(
                    colors: [Color(hex: "1a1612"), Color(hex: "12100e")],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 1)
                    .stroke(
                        LinearGradient(
                            colors: [
                                CullPalette.amber.opacity(0.35),
                                CullPalette.hairline.opacity(0.4),
                                CullPalette.amber.opacity(0.15)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.7
                    )
            )
            .shadow(color: .black.opacity(0.45), radius: 16, y: 10)
        }
    }

    private func tally(_ n: Int, _ label: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(n)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(0.8)
                .foregroundColor(color.opacity(0.55))
        }
    }

    private func contactCell(shot: ShotMetadata, index: Int) -> some View {
        let state = marks.state(for: shot.id)
        let seed = strokeSeed(for: shot.id)
        return Button {
            onOpenFrame(index)
        } label: {
            ZStack {
                Color.black

                if let thumb = store.thumbnail(for: shot) {
                    Image(uiImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .saturation(state == .reject ? 0.12 : 1.0)
                        .brightness(state == .reject ? -0.08 : 0)
                        .opacity(state == .reject ? 0.5 : 1.0)
                } else {
                    // Loading plate
                    Rectangle()
                        .fill(Color.white.opacity(0.03))
                        .overlay(
                            Text("···")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.2))
                        )
                }

                // Frame number — bottom-left, like a proof stamp
                VStack {
                    Spacer()
                    HStack {
                        Text(String(format: "%03d", index + 1))
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(state == .reject ? 0.35 : 0.72))
                            .shadow(color: .black.opacity(0.8), radius: 1)
                            .padding(.leading, 5)
                            .padding(.bottom, 4)
                        Spacer()
                    }
                }

                FrameMarkOverlay(state: state, seed: seed, lineWidth: 2.0, padding: 7)
            }
            .aspectRatio(1, contentMode: .fit)
            .clipped()
            .overlay(alignment: .trailing) {
                Rectangle().fill(CullPalette.hairline.opacity(0.7)).frame(width: 0.5)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(CullPalette.hairline.opacity(0.7)).frame(height: 0.5)
            }
        }
        .buttonStyle(ContactPressStyle())
        .accessibilityLabel("Frame \(index + 1), \(state.rawValue)")
    }
}

private struct ContactPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.08 : 0)
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(CullMotion.press, value: configuration.isPressed)
    }
}

// MARK: - Cull session

struct CullSessionView: View {
    @ObservedObject var store: GalleryStore
    let session: ShootSession
    @ObservedObject var marks: FrameMarkStore
    var startIndex: Int = 0
    var onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var undo = CullUndoStack()
    @State private var index: Int = 0
    @State private var dragOffset: CGSize = .zero
    @State private var showFinish = false
    @State private var isFinishing = false
    @State private var finishMessage: String?
    @State private var flashMark: FrameMarkState?
    @State private var loupeTouch: CGPoint?
    @State private var loupeImage: UIImage?
    @State private var loupeLoading = false
    @State private var advanceDir: Int = 0
    /// Film-gate slide (points). Negative = advancing forward.
    @State private var gateOffset: CGFloat = 0
    @State private var gateOpacity: Double = 1
    @State private var gateScale: CGFloat = 1
    @State private var isAdvancing = false
    @State private var markDrawKey: Int = 0

    private var shots: [ShotMetadata] { session.shots }
    private var current: ShotMetadata? {
        guard index >= 0, index < shots.count else { return nil }
        return shots[index]
    }

    private var progress: (kept: Int, rejected: Int, unmarked: Int) {
        session.progress(marks: marks)
    }

    private var dragProgress: CGFloat {
        min(1, abs(dragOffset.height) / 90)
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                // Safelight / amber wash while dragging
                Group {
                    if dragOffset.height < -20 {
                        CullPalette.amber
                            .opacity(0.07 * Double(dragProgress))
                    } else if dragOffset.height > 20 {
                        CullPalette.safelight
                            .opacity(0.12 * Double(dragProgress))
                    } else {
                        Color.clear
                    }
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .animation(CullMotion.wash, value: dragOffset.height)

                if let shot = current {
                    cullCanvas(shot: shot, size: geo.size)
                }

                // Chrome overlays
                VStack(spacing: 0) {
                    topBar
                        .background(
                            LinearGradient(
                                colors: [Color.black.opacity(0.72), Color.black.opacity(0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .ignoresSafeArea(edges: .top)
                        )
                    Spacer()
                    bottomChrome
                }

                // Mark flash stamp
                if let flashMark {
                    MarkStampFlash(state: flashMark)
                        .id(markDrawKey)
                        .transition(.opacity)
                        .zIndex(30)
                }
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .onAppear { index = startIndex }
        .sheet(isPresented: $showFinish) {
            FinishSessionSheet(
                kept: progress.kept,
                rejected: progress.rejected,
                sessionTitle: session.title,
                onDeleteAndExport: { finish(deleteRejects: true) },
                onMarkOnly: { finish(deleteRejects: false) },
                onCancel: { showFinish = false }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .preferredColorScheme(.dark)
        }
        .overlay {
            if isFinishing {
                ZStack {
                    Color.black.opacity(0.7).ignoresSafeArea()
                    VStack(spacing: 14) {
                        ProgressView()
                            .tint(CullPalette.amber)
                        Text(finishMessage ?? "Working…")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            Button { dismiss() } label: {
                DarkroomIconButton(systemName: "chevron.down")
            }
            .accessibilityLabel("Close cull")

            VStack(alignment: .leading, spacing: 3) {
                Text(session.title)
                    .font(.system(size: 14, weight: .semibold, design: .serif))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
                Text(String(format: "FRAME %03d  /  %03d", index + 1, shots.count))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.38))
                    .tracking(0.8)
            }

            Spacer()

            // Mini tally
            HStack(spacing: 8) {
                Text("\(progress.kept)")
                    .foregroundColor(CullPalette.amber)
                Text("·")
                    .foregroundColor(.white.opacity(0.25))
                Text("\(progress.rejected)")
                    .foregroundColor(Color(red: 0.95, green: 0.55, blue: 0.5))
            }
            .font(.system(size: 12, weight: .bold, design: .monospaced))

            Button { performUndo() } label: {
                DarkroomIconButton(systemName: "arrow.uturn.backward", active: undo.canUndo, accent: undo.canUndo)
            }
            .disabled(!undo.canUndo)
            .accessibilityLabel("Undo")

            if progress.unmarked == 0 && !shots.isEmpty {
                Button { showFinish = true } label: {
                    DarkroomChip(title: "FINISH", kind: .amber, compact: true)
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.92)),
                    removal: .opacity
                ))
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .animation(CullMotion.settle, value: progress.unmarked)
        .animation(CullMotion.press, value: progress.kept)
        .animation(CullMotion.press, value: progress.rejected)
    }

    private var bottomChrome: some View {
        VStack(spacing: 0) {
            // Filmstrip scrubber
            filmStrip
                .padding(.bottom, 8)

            if let shot = current {
                metadataStrip(shot)
            }

            // Thumb-zone hint + accessible controls
            VStack(spacing: 12) {
                // Drag intent label
                Text(dragLabel)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(3)
                    .foregroundColor(dragLabelColor)
                    .frame(height: 16)
                    .opacity(dragProgress > 0.15 ? 1 : 0.35)
                    .scaleEffect(dragProgress > 0.15 ? 1.0 + dragProgress * 0.06 : 1.0)
                    .animation(CullMotion.wash, value: dragProgress)

                HStack(spacing: 14) {
                    Button { applyMark(.reject) } label: {
                        DarkroomChip(title: "↓  REJECT", kind: .safelight)
                    }
                    .accessibilityLabel("Reject frame")

                    Button { applyMark(.keep) } label: {
                        DarkroomChip(title: "↑  KEEP", kind: .amber)
                    }
                    .accessibilityLabel("Keep frame")
                }

                Text("HOLD TO LOUPE  ·  SWIPE TO MARK  ·  DOUBLE-TAP UNDO")
                    .font(.system(size: 7, weight: .semibold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundColor(.white.opacity(0.22))
            }
            .padding(.top, 10)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [Color.black.opacity(0), Color.black.opacity(0.88), Color.black],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    private var dragLabel: String {
        if dragOffset.height < -40 { return "KEEP" }
        if dragOffset.height > 40 { return "REJECT" }
        return "THUMB ZONE"
    }

    private var dragLabelColor: Color {
        if dragOffset.height < -40 { return CullPalette.amber }
        if dragOffset.height > 40 { return Color(red: 0.95, green: 0.55, blue: 0.5) }
        return .white.opacity(0.28)
    }

    private var filmStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(Array(shots.enumerated()), id: \.element.id) { i, shot in
                        let state = marks.state(for: shot.id)
                        Button {
                            advance(to: i)
                        } label: {
                            ZStack {
                                if let thumb = store.thumbnail(for: shot) {
                                    Image(uiImage: thumb)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .saturation(state == .reject ? 0.2 : 1)
                                        .opacity(state == .reject ? 0.45 : 1)
                                } else {
                                    Color.white.opacity(0.06)
                                }
                                FrameMarkOverlay(state: state, seed: strokeSeed(for: shot.id), lineWidth: 1.4, padding: 3)
                            }
                            .frame(width: 36, height: 44)
                            .clipped()
                            .overlay(
                                RoundedRectangle(cornerRadius: 1)
                                    .stroke(
                                        i == index ? CullPalette.amber : Color.white.opacity(0.12),
                                        lineWidth: i == index ? 1.2 : 0.5
                                    )
                            )
                            .scaleEffect(i == index ? 1.06 : 1.0)
                            .animation(CullMotion.press, value: index)
                        }
                        .buttonStyle(.plain)
                        .id(i)
                    }
                }
                .padding(.horizontal, 14)
            }
            .onChange(of: index) { _, new in
                withAnimation(CullMotion.advanceIn) {
                    proxy.scrollTo(new, anchor: .center)
                }
            }
        }
        .frame(height: 48)
    }

    private func metadataStrip(_ shot: ShotMetadata) -> some View {
        HStack(spacing: 0) {
            metaCell("ISO", "\(shot.iso)")
            metaRule()
            metaCell("SHUTTER", shot.shutter)
            metaRule()
            metaCell("ƒ", String(format: "%.1f", shot.aperture))
            metaRule()
            metaCell("LENS", "\(shot.focalLength)mm")
            if shot.filmFilter != "None" {
                metaRule()
                metaCell("FILM", shot.filmFilter.uppercased())
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.45))
        .overlay(alignment: .top) {
            Rectangle().fill(CullPalette.hairline.opacity(0.4)).frame(height: 0.5)
        }
    }

    private func metaCell(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.system(size: 7, weight: .semibold, design: .monospaced))
                .tracking(0.8)
                .foregroundColor(.white.opacity(0.28))
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.88))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private func metaRule() -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 0.5, height: 26)
    }

    private func cullCanvas(shot: ShotMetadata, size: CGSize) -> some View {
        let state = marks.state(for: shot.id)
        let seed = strokeSeed(for: shot.id)
        let image = store.image(for: shot) ?? store.thumbnail(for: shot)

        return ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size.width, height: size.height)
                    .saturation(state == .reject ? 0.18 : 1.0)
                    .opacity(state == .reject ? 0.65 : 1.0)
                    .overlay {
                        FrameMarkOverlay(
                            state: state,
                            seed: seed,
                            lineWidth: 4.5,
                            padding: size.width * 0.14,
                            animated: true
                        )
                        .id("\(shot.id)-\(state.rawValue)-\(markDrawKey)")
                    }
                    .scaleEffect(gateScale)
                    .offset(x: gateOffset + dragOffset.width, y: dragOffset.height)
                    .opacity(gateOpacity * (1.0 - Double(min(0.28, abs(dragOffset.width) / 420))))
                    .rotationEffect(.degrees(Double(dragOffset.width) / 80 + Double(gateOffset) / 140))
                    .gesture(cullDrag(in: size))
                    .simultaneousGesture(loupeGesture(in: size, fallback: image))
                    .onTapGesture(count: 2) { performUndo() }
            }

            if let loupeTouch, let loupeImage {
                LoupeView(image: loupeImage, touch: loupeTouch, container: size)
                    .zIndex(20)
            } else if loupeLoading, let loupeTouch {
                ProgressView()
                    .tint(CullPalette.amber)
                    .position(x: loupeTouch.x, y: max(60, loupeTouch.y - 90))
            }
        }
    }

    private func cullDrag(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 16, coordinateSpace: .local)
            .onChanged { value in
                guard loupeTouch == nil, !isAdvancing else { return }
                let startY = value.startLocation.y
                let inThumbZone = startY > size.height * 0.52
                if inThumbZone || abs(value.translation.height) > abs(value.translation.width) * 1.1 {
                    dragOffset = CGSize(width: 0, height: value.translation.height * 0.85)
                } else {
                    dragOffset = CGSize(width: value.translation.width, height: 0)
                }
            }
            .onEnded { value in
                guard loupeTouch == nil, !isAdvancing else {
                    withAnimation(CullMotion.flick) { dragOffset = .zero }
                    return
                }
                let dx = value.translation.width
                let dy = value.translation.height
                let inThumbZone = value.startLocation.y > size.height * 0.52

                if abs(dy) > abs(dx) && (inThumbZone || abs(dy) > 48) {
                    if dy < -48 {
                        // Commit keep — lift out the top of the gate
                        commitDragMark(.keep, lift: CGSize(width: 0, height: -size.height * 0.12))
                    } else if dy > 48 {
                        commitDragMark(.reject, lift: CGSize(width: 0, height: size.height * 0.12))
                    } else {
                        withAnimation(CullMotion.flick) { dragOffset = .zero }
                    }
                } else if abs(dx) > 56 {
                    let dir = dx < 0 ? 1 : -1
                    // Carry residual horizontal into the advance
                    let carry = dx
                    dragOffset = .zero
                    advance(dir, carryX: carry)
                } else {
                    withAnimation(CullMotion.flick) { dragOffset = .zero }
                }
            }
    }

    private func commitDragMark(_ state: FrameMarkState, lift: CGSize) {
        withAnimation(CullMotion.advanceOut) {
            dragOffset = lift
            gateOpacity = 0.55
            gateScale = 0.97
        }
        applyMark(state, alreadyLifted: true)
    }

    private func loupeGesture(in size: CGSize, fallback: UIImage) -> some Gesture {
        LongPressGesture(minimumDuration: 0.28)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
            .onChanged { value in
                switch value {
                case .second(true, let drag):
                    let point = drag?.location ?? CGPoint(x: size.width / 2, y: size.height / 2)
                    if loupeTouch == nil {
                        Haptics.light()
                        loupeLoading = true
                        loupeImage = fallback
                        if let shot = current, let full = store.image(for: shot) {
                            loupeImage = full
                        }
                        loupeLoading = false
                    }
                    // Track without animating every point (keeps loupe tight to thumb)
                    var t = Transaction()
                    t.disablesAnimations = true
                    withTransaction(t) { loupeTouch = point }
                default:
                    break
                }
            }
            .onEnded { _ in
                withAnimation(CullMotion.loupeOut) {
                    loupeTouch = nil
                    loupeImage = nil
                    loupeLoading = false
                }
            }
    }

    private func applyMark(_ state: FrameMarkState, alreadyLifted: Bool = false) {
        guard let shot = current, !isAdvancing else { return }
        let previous = marks.state(for: shot.id)
        marks.mark(
            shotID: shot.id,
            photosAssetLocalIdentifier: shot.photosAssetLocalIdentifier,
            creationDate: shot.date,
            state: state
        )
        undo.push(CullAction(shotID: shot.id, previous: previous, next: state))

        PhotosLibraryService.setFavorite(
            assetLocalIdentifier: shot.photosAssetLocalIdentifier,
            favorite: state == .keep
        )
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()

        markDrawKey &+= 1
        withAnimation(CullMotion.stamp) { flashMark = state }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
            withAnimation(CullMotion.stampFade) { flashMark = nil }
        }

        // Seat the mark, then film-advance
        let delay: TimeInterval = alreadyLifted ? 0.18 : 0.3
        if !alreadyLifted {
            withAnimation(CullMotion.draw) {
                // brief hold so the grease pencil reads
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            advance(1)
        }
    }

    private func performUndo() {
        guard let action = undo.pop(),
              let shot = shots.first(where: { $0.id == action.shotID }),
              !isAdvancing else { return }
        marks.mark(
            shotID: shot.id,
            photosAssetLocalIdentifier: shot.photosAssetLocalIdentifier,
            creationDate: shot.date,
            state: action.previous
        )
        PhotosLibraryService.setFavorite(
            assetLocalIdentifier: shot.photosAssetLocalIdentifier,
            favorite: action.previous == .keep
        )
        if let i = shots.firstIndex(where: { $0.id == action.shotID }) {
            advance(to: i)
        }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    private func advance(_ delta: Int, carryX: CGFloat = 0) {
        let next = index + delta
        guard next >= 0, next < shots.count else {
            withAnimation(CullMotion.flick) {
                dragOffset = .zero
                gateOffset = 0
                gateOpacity = 1
                gateScale = 1
            }
            if progress.unmarked == 0 { showFinish = true }
            return
        }
        advance(to: next, dir: delta, carryX: carryX)
    }

    private func advance(to next: Int, dir: Int? = nil, carryX: CGFloat = 0) {
        guard next != index, !isAdvancing else {
            if next == index {
                withAnimation(CullMotion.flick) { dragOffset = .zero }
            }
            return
        }
        let width = UIScreen.main.bounds.width
        let direction = dir ?? (next > index ? 1 : -1)
        advanceDir = direction
        isAdvancing = true

        // 1) Current frame exits the gate (film lever out)
        withAnimation(CullMotion.advanceOut) {
            gateOffset = carryX + CGFloat(-direction) * width * 0.42
            gateOpacity = 0
            gateScale = 0.96
            dragOffset = .zero
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.13) {
            // 2) Swap frame while off-gate, stage incoming from the opposite side
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                index = next
                gateOffset = CGFloat(direction) * width * 0.28
                gateOpacity = 0.35
                gateScale = 1.02
            }

            // 3) Seat into the gate
            withAnimation(CullMotion.advanceIn) {
                gateOffset = 0
                gateOpacity = 1
                gateScale = 1
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isAdvancing = false
            }
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    private func finish(deleteRejects: Bool) {
        showFinish = false
        isFinishing = true
        finishMessage = "Exporting keepers…"

        let keepers = shots.filter { marks.state(for: $0.id) == .keep }
        let rejects = shots.filter { marks.state(for: $0.id) == .reject }

        let keeperIDs: [String] = keepers.compactMap { shot in
            PhotosLibraryService.resolveAsset(
                preferredID: shot.photosAssetLocalIdentifier,
                creationDate: shot.date
            )?.localIdentifier ?? shot.photosAssetLocalIdentifier
        }

        let albumName = session.title
        PhotosLibraryService.exportKeepers(albumName: albumName, assetLocalIdentifiers: keeperIDs) { _ in
            if !keepers.isEmpty, let book = store.createBook(title: albumName) {
                for shot in keepers { store.add(shot, to: book) }
            }

            if deleteRejects {
                finishMessage = "Deleting rejects…"
                let rejectAssetIDs: [String] = rejects.compactMap { shot in
                    PhotosLibraryService.resolveAsset(
                        preferredID: shot.photosAssetLocalIdentifier,
                        creationDate: shot.date
                    )?.localIdentifier ?? shot.photosAssetLocalIdentifier
                }
                PhotosLibraryService.deleteAssets(localIdentifiers: rejectAssetIDs) { _ in
                    for shot in rejects { store.delete(shot) }
                    marks.clear(shotIDs: rejects.map(\.id) + keepers.map(\.id))
                    isFinishing = false
                    onFinished()
                    dismiss()
                }
            } else {
                isFinishing = false
                onFinished()
                dismiss()
            }
        }
    }
}

// MARK: - Finish sheet (darkroom, not system alert)

struct FinishSessionSheet: View {
    let kept: Int
    let rejected: Int
    let sessionTitle: String
    let onDeleteAndExport: () -> Void
    let onMarkOnly: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            DarkroomGround(intensity: 0.85)

            VStack(alignment: .leading, spacing: 0) {
                Text("SHUTTERCRAFT")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(3)
                    .foregroundColor(CullPalette.amber.opacity(0.7))
                    .padding(.bottom, 8)

                Text("Finish the sheet")
                    .font(.system(size: 26, weight: .semibold, design: .serif))
                    .foregroundColor(.white.opacity(0.95))
                    .padding(.bottom, 6)

                Text(sessionTitle)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.bottom, 22)

                HStack(spacing: 0) {
                    finishStat("\(kept)", "KEEPING", CullPalette.amber)
                    Rectangle().fill(Color.white.opacity(0.1)).frame(width: 0.5, height: 44)
                    finishStat("\(rejected)", "REJECTING", CullPalette.safelight)
                }
                .padding(.vertical, 16)
                .background(Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(CullPalette.hairline.opacity(0.5), lineWidth: 0.6)
                )
                .padding(.bottom, 28)

                VStack(spacing: 12) {
                    Button(action: onDeleteAndExport) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("DELETE REJECTS · EXPORT KEEPERS")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .tracking(0.8)
                                Text("One Photos prompt · album + Field Book")
                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.45))
                            }
                            Spacer()
                        }
                        .foregroundColor(CullPalette.amber)
                        .padding(14)
                        .background(CullPalette.amber.opacity(0.1))
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(CullPalette.amber.opacity(0.5), lineWidth: 0.8)
                        )
                    }

                    Button(action: onMarkOnly) {
                        HStack {
                            Text("KEEP REJECTS · JUST MARK THEM")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .tracking(0.8)
                            Spacer()
                        }
                        .foregroundColor(.white.opacity(0.7))
                        .padding(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 2)
                                .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
                        )
                    }

                    Button(action: onCancel) {
                        Text("CANCEL")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .tracking(1.5)
                            .foregroundColor(.white.opacity(0.35))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 4)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(24)
        }
    }

    private func finishStat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1.5)
                .foregroundColor(color.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
    }
}
