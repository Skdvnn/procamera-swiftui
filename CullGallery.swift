import SwiftUI
import Photos
import AVFoundation
import CoreLocation

// MARK: - Motion (page-turn cull — no springs, no bounce)

enum CullMotion {
    /// Snap-back after a drag miss
    static let flick = Animation.timingCurve(0.2, 0.8, 0.2, 1.0, duration: 0.16)
    /// Page leaf curling away (keep / reject / swipe)
    static let pageTurn = Animation.timingCurve(0.22, 0.7, 0.18, 1.0, duration: 0.46)
    /// Cancelled peel settling back
    static let pageCancel = Animation.timingCurve(0.2, 0.85, 0.2, 1.0, duration: 0.22)
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
    var magnification: CGFloat = 2.4
    @State private var raised = false

    var body: some View {
        let imgSize = image.size
        let fit = AVMakeRect(
            aspectRatio: imgSize.width > 0 ? imgSize : CGSize(width: 1, height: 1),
            insideRect: CGRect(origin: .zero, size: container)
        )
        let scale = magnification
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

            Text(String(format: "%.1f×", magnification))
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(CullPalette.amber.opacity(0.9))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.black.opacity(0.65)))
                .offset(y: diameter * 0.42)
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
    /// Deep link / Shortcut: open Field Book shelf once this cover is up.
    var openFieldBooksOnAppear: Bool = false
    var onConsumedFieldBookOpen: (() -> Void)? = nil
    @StateObject private var marks = FrameMarkStore()
    @Environment(\.dismiss) private var dismiss

    @State private var sessions: [ShootSession] = []
    @State private var route: CullRoute?
    @State private var showFieldBooks = false
    /// Book to open after a cull finish handoff.
    @State private var openBookID: UUID?
    @State private var appeared = false
    @State private var sheetLoupe: UIImage?
    @State private var comparePair: ComparePair?

    private struct CullRoute: Identifiable {
        let id = UUID()
        let session: ShootSession
        let startIndex: Int
    }

    private struct ComparePair: Identifiable {
        let id = UUID()
        let session: ShootSession
        let left: ShotMetadata
        let right: ShotMetadata
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
                                    onOpenFrame: { open(session, at: $0) },
                                    onLoupe: { shot in
                                        sheetLoupe = store.image(for: shot) ?? store.thumbnail(for: shot)
                                    },
                                    onCompare: { a, b in
                                        comparePair = ComparePair(session: session, left: a, right: b)
                                    }
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

            if let sheetLoupe {
                SheetLoupeOverlay(image: sheetLoupe) {
                    self.sheetLoupe = nil
                }
                .zIndex(40)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            rebuildSessions()
            PhotosLibraryService.requestReadWrite { _ in }
            withAnimation(CullMotion.settle) { appeared = true }
            if openFieldBooksOnAppear {
                showFieldBooks = true
                onConsumedFieldBookOpen?()
            }
        }
        .onChange(of: store.shots) { _, _ in rebuildSessions() }
        .onChange(of: openFieldBooksOnAppear) { _, open in
            // Cover already up when a late deep link arrives.
            guard open else { return }
            showFieldBooks = true
            onConsumedFieldBookOpen?()
        }
        .onReceive(NotificationCenter.default.publisher(for: .shutterOpenFieldBook)) { _ in
            showFieldBooks = true
        }
        .fullScreenCover(item: $route) { r in
            CullSessionView(
                store: store,
                session: r.session,
                marks: marks,
                startIndex: r.startIndex,
                onFinished: { bookID in
                    route = nil
                    rebuildSessions()
                    if let bookID {
                        openBookID = bookID
                        showFieldBooks = true
                    }
                }
            )
        }
        .fullScreenCover(item: $comparePair) { pair in
            CompareFramesView(
                store: store,
                left: pair.left,
                right: pair.right,
                onKeepLeft: {
                    promote(pair.left, demote: pair.right, in: pair.session)
                    comparePair = nil
                },
                onKeepRight: {
                    promote(pair.right, demote: pair.left, in: pair.session)
                    comparePair = nil
                },
                onDismiss: { comparePair = nil }
            )
        }
        .fullScreenCover(isPresented: $showFieldBooks, onDismiss: {
            openBookID = nil
        }) {
            LibraryView(store: store, initialBookID: openBookID)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Button { dismiss() } label: {
                DarkroomIconButton(systemName: "xmark")
            }
            .accessibilityLabel("Close")

            VStack(alignment: .leading, spacing: 3) {
                Text("SHUTTER")
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
        // Wire dead reverse-geocode path → place-named session titles.
        for session in sessions {
            guard let coord = session.mapCoordinate else { continue }
            let location = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            SessionTitle.refine(session: session, location: location) { title in
                DispatchQueue.main.async {
                    guard let idx = sessions.firstIndex(where: { $0.id == session.id }) else { return }
                    if sessions[idx].title != title {
                        sessions[idx].title = title
                    }
                }
            }
        }
    }

    private func open(_ session: ShootSession, at index: Int) {
        route = CullRoute(session: session, startIndex: max(0, min(index, session.shots.count - 1)))
    }

    private func firstUnmarkedIndex(in session: ShootSession) -> Int {
        session.shots.firstIndex { marks.state(for: $0.id) == .unmarked } ?? 0
    }

    private func promote(_ keep: ShotMetadata, demote: ShotMetadata, in session: ShootSession) {
        marks.mark(
            shotID: keep.id,
            photosAssetLocalIdentifier: keep.photosAssetLocalIdentifier,
            creationDate: keep.date,
            state: .keep
        )
        marks.mark(
            shotID: demote.id,
            photosAssetLocalIdentifier: demote.photosAssetLocalIdentifier,
            creationDate: demote.date,
            state: .reject
        )
        PhotosLibraryService.setFavorite(assetLocalIdentifier: keep.photosAssetLocalIdentifier, favorite: true)
        PhotosLibraryService.setFavorite(assetLocalIdentifier: demote.photosAssetLocalIdentifier, favorite: false)
        Haptics.click()
        // Jump into cull at the kept frame so the user can continue
        open(session, at: session.shots.firstIndex(where: { $0.id == keep.id }) ?? 0)
    }
}

// MARK: - Session contact sheet

struct SessionContactSheet: View {
    let store: GalleryStore
    let session: ShootSession
    @ObservedObject var marks: FrameMarkStore
    let onCull: () -> Void
    let onOpenFrame: (Int) -> Void
    var onLoupe: ((ShotMetadata) -> Void)? = nil
    var onCompare: ((ShotMetadata, ShotMetadata) -> Void)? = nil

    @State private var selectedForCompare: Set<UUID> = []

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

    private var compareReady: Bool { selectedForCompare.count == 2 }

    /// Leading place fragment from a refined title ("Ocean Beach — Aug 14, morning").
    private func placeLabel(from title: String) -> String? {
        let parts = title.split(separator: "—", maxSplits: 1, omittingEmptySubsequences: true)
        guard parts.count == 2 else { return nil }
        let place = parts[0].trimmingCharacters(in: .whitespaces)
        return place.isEmpty ? nil : place
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

                    CullProgressRail(
                        kept: progress.kept,
                        rejected: progress.rejected,
                        unmarked: progress.unmarked
                    )
                    .padding(.top, 6)
                    .padding(.trailing, 40)

                    HStack(spacing: 10) {
                        tally(progress.kept, "KEPT", CullPalette.amber)
                        tally(progress.rejected, "OUT", CullPalette.safelight)
                        tally(progress.unmarked, "OPEN", Color.white.opacity(0.45))
                    }
                    .padding(.top, 4)

                    if let coord = session.mapCoordinate {
                        SessionMapChip(
                            coordinate: coord,
                            placeLabel: placeLabel(from: session.title)
                        )
                            .padding(.top, 8)
                            .padding(.trailing, 8)
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 8) {
                    Button(action: onCull) {
                        DarkroomChip(
                            title: progress.unmarked == 0 && progress.kept + progress.rejected > 0
                                ? "REVIEW"
                                : "CULL",
                            kind: .amber
                        )
                    }
                    .buttonStyle(DarkroomChipButtonStyle())
                    .accessibilityLabel("Cull session")

                    if compareReady {
                        Button {
                            let picks = session.shots.filter { selectedForCompare.contains($0.id) }
                            guard picks.count == 2 else { return }
                            onCompare?(picks[0], picks[1])
                            selectedForCompare.removeAll()
                        } label: {
                            DarkroomChip(title: "COMPARE", kind: .quiet, compact: true)
                        }
                        .buttonStyle(DarkroomChipButtonStyle())
                        .transition(.opacity.combined(with: .scale(scale: 0.94)))
                    }
                }
                .animation(CullMotion.settle, value: compareReady)
            }
            .padding(.horizontal, 2)
            .padding(.bottom, 14)

            // Physical sheet plate
            VStack(spacing: 0) {
                HStack {
                    Text("PROOF")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(CullPalette.amber.opacity(0.5))
                    Spacer()
                    Text(selectedForCompare.isEmpty
                          ? String(format: "Nº %03d–%03d", 1, session.shots.count)
                          : "HOLD TO PICK  ·  \(selectedForCompare.count)/2")
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
                .contentTransition(.numericText())
            Text(label)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .tracking(0.8)
                .foregroundColor(color.opacity(0.55))
        }
    }

    private func contactCell(shot: ShotMetadata, index: Int) -> some View {
        let state = marks.state(for: shot.id)
        let seed = strokeSeed(for: shot.id)
        let picked = selectedForCompare.contains(shot.id)
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
                    Rectangle()
                        .fill(Color.white.opacity(0.03))
                        .overlay(
                            Text("···")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.2))
                        )
                }

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

                if picked {
                    Rectangle()
                        .stroke(CullPalette.amber, lineWidth: 2)
                        .padding(1)
                    VStack {
                        HStack {
                            Spacer()
                            Text("COMPARE")
                                .font(.system(size: 6, weight: .bold, design: .monospaced))
                                .tracking(0.6)
                                .foregroundColor(.black)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(CullPalette.amber)
                                .padding(4)
                        }
                        Spacer()
                    }
                }
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
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.35)
                .onEnded { _ in
                    Haptics.medium()
                    // Long-press opens loupe; compare stays on context menu / COMPARE chip.
                    onLoupe?(shot)
                }
        )
        .accessibilityLabel("Frame \(index + 1), \(state.rawValue)")
        .accessibilityHint("Long press to loupe; use context menu to compare")
        .contextMenu {
            Button {
                onLoupe?(shot)
            } label: {
                Label("Loupe", systemImage: "plus.magnifyingglass")
            }
            Button {
                toggleCompare(shot)
            } label: {
                Label(picked ? "Deselect compare" : "Select for compare", systemImage: "square.split.2x1")
            }
        }
    }

    private func toggleCompare(_ shot: ShotMetadata) {
        withAnimation(CullMotion.press) {
            if selectedForCompare.contains(shot.id) {
                selectedForCompare.remove(shot.id)
            } else if selectedForCompare.count < 2 {
                selectedForCompare.insert(shot.id)
            } else {
                // Replace oldest by clearing and starting fresh with this one
                selectedForCompare = [shot.id]
            }
        }
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
    /// Called when the session finishes; pass a book ID to open Field Book onto it.
    var onFinished: (_ openBookID: UUID?) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var undo = CullUndoStack()
    @State private var index: Int = 0
    @State private var dragOffset: CGSize = .zero
    @State private var showFinish = false
    @State private var isFinishing = false
    @State private var shareProofURL: URL?
    @State private var shareKeeperItems: [Any] = []
    @State private var showFinishDone = false
    @State private var doneBookID: UUID?
    @State private var doneAlbumName: String = ""
    @State private var doneKeeperShots: [ShotMetadata] = []
    @State private var finishMessage: String?
    @State private var flashMark: FrameMarkState?
    @State private var loupeTouch: CGPoint?
    @State private var loupeImage: UIImage?
    @State private var loupeLoading = false
    /// 1 = turn forward (next), -1 = turn back (previous)
    @State private var turnDirection: Int = 1
    /// 0…1 committed page-curl progress (after keep/reject or swipe release)
    @State private var turnProgress: CGFloat = 0
    @State private var incomingIndex: Int? = nil
    @State private var isAdvancing = false
    @State private var markDrawKey: Int = 0
    @State private var showCoach = false
    @State private var crossedKeep = false
    @State private var crossedReject = false
    @AppStorage("darkroom.thumbCoach.seen") private var coachSeen = false

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

                // First-run thumb coach
                ThumbZoneCoach(visible: $showCoach)

                // Chrome overlays — dim while loupe is up
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
                .opacity(loupeTouch == nil ? 1 : 0.15)
                .allowsHitTesting(loupeTouch == nil)
                .animation(CullMotion.loupeOut, value: loupeTouch != nil)

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
        .onAppear {
            index = startIndex
            if !coachSeen {
                withAnimation(CullMotion.settle.delay(0.35)) { showCoach = true }
            }
        }
        .sheet(isPresented: $showFinish) {
            FinishSessionSheet(
                kept: progress.kept,
                rejected: progress.rejected,
                sessionTitle: session.title,
                onDeleteAndExport: { finish(deleteRejects: true) },
                onMarkOnly: { finish(deleteRejects: false) },
                onExportProof: { exportProofPDF() },
                onCancel: { showFinish = false }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: Binding(
            get: { shareProofURL != nil },
            set: { if !$0 {
                shareProofURL = nil
                // Return to done sheet after share cancel/complete.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    showFinishDone = true
                }
            } }
        )) {
            if let url = shareProofURL {
                ShareSheet(items: [url])
                    .preferredColorScheme(.dark)
            }
        }
        .sheet(isPresented: Binding(
            get: { !shareKeeperItems.isEmpty },
            set: { if !$0 {
                shareKeeperItems = []
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    showFinishDone = true
                }
            } }
        )) {
            ShareSheet(
                items: shareKeeperItems,
                subject: "Shutter · \(doneAlbumName)",
                onComplete: { shareKeeperItems = [] }
            )
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $showFinishDone) {
            FinishDoneSheet(
                albumName: doneAlbumName,
                hasBook: doneBookID != nil,
                keeperCount: doneKeeperShots.count,
                onOpenBook: {
                    showFinishDone = false
                    let id = doneBookID
                    onFinished(id)
                    dismiss()
                },
                onShareKeepers: {
                    // Dismiss done sheet first so share isn't nested underneath.
                    showFinishDone = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        shareKeeperImages()
                    }
                },
                onShareProof: {
                    showFinishDone = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        shareDoneProofPDF()
                    }
                },
                onOpenPhotos: {
                    PhotosLibraryService.openPhotosApp()
                },
                onDone: {
                    showFinishDone = false
                    onFinished(nil)
                    dismiss()
                }
            )
            .presentationDetents([.medium, .large])
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

            // Mini tally + progress
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 8) {
                    Text("\(progress.kept)")
                        .foregroundColor(CullPalette.amber)
                        .contentTransition(.numericText())
                    Text("·")
                        .foregroundColor(.white.opacity(0.25))
                    Text("\(progress.rejected)")
                        .foregroundColor(Color(red: 0.95, green: 0.55, blue: 0.5))
                        .contentTransition(.numericText())
                }
                .font(.system(size: 12, weight: .bold, design: .monospaced))

                CullProgressRail(
                    kept: progress.kept,
                    rejected: progress.rejected,
                    unmarked: progress.unmarked,
                    height: 2
                )
                .frame(width: 56)
            }

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
                    .id(shot.id)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                    .animation(CullMotion.press, value: shot.id)
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
                    .buttonStyle(DarkroomChipButtonStyle())
                    .accessibilityLabel("Reject frame")

                    Button { applyMark(.keep) } label: {
                        DarkroomChip(title: "↑  KEEP", kind: .amber)
                    }
                    .buttonStyle(DarkroomChipButtonStyle())
                    .accessibilityLabel("Keep frame")
                }

                Text("HOLD TO LOUPE  ·  SWIPE TO MARK  ·  PAGE TURNS NEXT  ·  DOUBLE-TAP UNDO")
                    .font(.system(size: 7, weight: .semibold, design: .monospaced))
                    .tracking(1.0)
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
        HStack(spacing: 0) {
            FilmSprocketEdge()
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
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
                                .frame(width: 34, height: 42)
                                .clipped()
                                .overlay(
                                    Rectangle()
                                        .stroke(
                                            i == index ? CullPalette.amber : Color.white.opacity(0.1),
                                            lineWidth: i == index ? 1.2 : 0.4
                                        )
                                )
                                .scaleEffect(i == index ? 1.08 : 1.0)
                                .animation(CullMotion.press, value: index)
                            }
                            .buttonStyle(.plain)
                            .id(i)
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                }
                .background(Color(hex: "14110e"))
                .onChange(of: index) { _, new in
                    withAnimation(CullMotion.pageTurn) {
                        proxy.scrollTo(new, anchor: .center)
                    }
                }
                .onAppear {
                    proxy.scrollTo(index, anchor: .center)
                }
            }
            FilmSprocketEdge()
        }
        .overlay(
            Rectangle()
                .stroke(CullPalette.hairline.opacity(0.35), lineWidth: 0.5)
        )
        .padding(.horizontal, 10)
        .frame(height: 52)
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
        let peel = pagePeelAmount(in: size)
        let forward = pageTurningForward(in: size)
        let underIdx = incomingIndex ?? (forward ? index + 1 : index - 1)
        let underShot = (underIdx >= 0 && underIdx < shots.count) ? shots[underIdx] : nil

        return ZStack {
            // Page underneath the turning leaf
            if peel > 0.02, let underShot {
                cullFrameImage(shot: underShot, size: size, animatedMark: false)
                    .scaleEffect(0.985 + 0.015 * peel)
                    .opacity(0.55 + 0.45 * Double(peel))
            }

            interactiveCullLeaf(shot: shot, size: size, peel: peel, forward: forward)

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

    private func interactiveCullLeaf(
        shot: ShotMetadata,
        size: CGSize,
        peel: CGFloat,
        forward: Bool
    ) -> some View {
        cullFrameImage(shot: shot, size: size, animatedMark: true)
            .contentShape(Rectangle())
            .offset(y: isAdvancing ? 0 : dragOffset.height)
            .rotation3DEffect(
                .degrees(Double(peel) * (forward ? -118 : 118)),
                axis: (x: 0, y: 1, z: 0),
                anchor: forward ? .leading : .trailing,
                perspective: 0.62
            )
            .overlay(alignment: forward ? .leading : .trailing) {
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.55 * Double(peel)),
                        Color.black.opacity(0.12 * Double(peel)),
                        .clear
                    ],
                    startPoint: forward ? .leading : .trailing,
                    endPoint: forward ? .trailing : .leading
                )
                .frame(width: size.width * 0.22)
                .allowsHitTesting(false)
            }
            .shadow(
                color: Color.black.opacity(0.45 * Double(min(1, peel * 1.4))),
                radius: 18 * peel,
                x: forward ? 10 * peel : -10 * peel,
                y: 4
            )
            .gesture(cullDrag(in: size))
            .simultaneousGesture(
                loupeGesture(
                    in: size,
                    fallback: store.image(for: shot) ?? store.thumbnail(for: shot) ?? UIImage()
                )
            )
            .onTapGesture(count: 2) { performUndo() }
    }

    private func cullFrameImage(shot: ShotMetadata, size: CGSize, animatedMark: Bool) -> some View {
        let state = marks.state(for: shot.id)
        let seed = strokeSeed(for: shot.id)
        let image = store.image(for: shot) ?? store.thumbnail(for: shot)

        return Group {
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
                            animated: animatedMark
                        )
                        .id("\(shot.id)-\(state.rawValue)-\(markDrawKey)")
                    }
            } else {
                Color.black.opacity(0.001)
                    .frame(width: size.width, height: size.height)
            }
        }
    }

    /// Interactive horizontal peel + committed turn progress.
    private func pagePeelAmount(in size: CGSize) -> CGFloat {
        if isAdvancing || turnProgress > 0 {
            return min(1, max(0, turnProgress))
        }
        guard abs(dragOffset.width) > abs(dragOffset.height) else { return 0 }
        return min(1, abs(dragOffset.width) / max(120, size.width * 0.52))
    }

    private func pageTurningForward(in _: CGSize) -> Bool {
        if isAdvancing || turnProgress > 0 {
            return turnDirection > 0
        }
        // Swipe left → turn forward to next page
        return dragOffset.width <= 0
    }

    private func cullDrag(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 16, coordinateSpace: .local)
            .onChanged { value in
                guard loupeTouch == nil, !isAdvancing else { return }
                let startY = value.startLocation.y
                let inThumbZone = startY > size.height * 0.52
                if inThumbZone || abs(value.translation.height) > abs(value.translation.width) * 1.1 {
                    dragOffset = CGSize(width: 0, height: value.translation.height * 0.85)
                    // Threshold haptics — click once when crossing commit line
                    if value.translation.height < -48, !crossedKeep {
                        crossedKeep = true
                        crossedReject = false
                        UISelectionFeedbackGenerator().selectionChanged()
                    } else if value.translation.height > 48, !crossedReject {
                        crossedReject = true
                        crossedKeep = false
                        UISelectionFeedbackGenerator().selectionChanged()
                    } else if abs(value.translation.height) < 40 {
                        crossedKeep = false
                        crossedReject = false
                    }
                } else {
                    dragOffset = CGSize(width: value.translation.width, height: 0)
                    crossedKeep = false
                    crossedReject = false
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
                        commitDragMark(.keep)
                    } else if dy > 48 {
                        commitDragMark(.reject)
                    } else {
                        withAnimation(CullMotion.flick) { dragOffset = .zero }
                    }
                } else if abs(dx) > 56 {
                    let dir = dx < 0 ? 1 : -1
                    // Finish the peel as a page turn
                    let peel = min(1, abs(dx) / max(120, size.width * 0.52))
                    turnDirection = dir
                    turnProgress = peel
                    dragOffset = .zero
                    advance(dir, fromPeel: peel)
                } else {
                    withAnimation(CullMotion.pageCancel) { dragOffset = .zero }
                }
            }
    }

    private func commitDragMark(_ state: FrameMarkState) {
        // Seat the vertical mark gesture, then page-turn to the next leaf
        withAnimation(CullMotion.flick) { dragOffset = .zero }
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

        // Dismiss coach after first real mark
        if showCoach || !coachSeen {
            coachSeen = true
            withAnimation(CullMotion.settle) { showCoach = false }
        }

        markDrawKey &+= 1
        withAnimation(CullMotion.stamp) { flashMark = state }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.26) {
            withAnimation(CullMotion.stampFade) { flashMark = nil }
        }

        // Seat the mark, then curl the leaf to the next frame
        let delay: TimeInterval = alreadyLifted ? 0.16 : 0.28
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

    private func advance(_ delta: Int, fromPeel: CGFloat = 0) {
        let next = index + delta
        guard next >= 0, next < shots.count else {
            withAnimation(CullMotion.pageCancel) {
                dragOffset = .zero
                turnProgress = 0
                incomingIndex = nil
            }
            isAdvancing = false
            if progress.unmarked == 0 { showFinish = true }
            return
        }
        advance(to: next, dir: delta, fromPeel: fromPeel)
    }

    private func advance(to next: Int, dir: Int? = nil, fromPeel: CGFloat = 0) {
        guard next != index, !isAdvancing else {
            if next == index {
                withAnimation(CullMotion.pageCancel) {
                    dragOffset = .zero
                    turnProgress = 0
                }
            }
            return
        }
        let direction = dir ?? (next > index ? 1 : -1)
        turnDirection = direction
        incomingIndex = next
        isAdvancing = true
        dragOffset = .zero

        // Resume from interactive peel when the finger already started the curl
        if fromPeel > 0.02 {
            var seed = Transaction()
            seed.disablesAnimations = true
            withTransaction(seed) { turnProgress = fromPeel }
        } else {
            var seed = Transaction()
            seed.disablesAnimations = true
            withTransaction(seed) { turnProgress = 0 }
        }

        withAnimation(CullMotion.pageTurn) {
            turnProgress = 1
        }

        // Keep the outgoing leaf bound to the old index until the curl finishes,
        // then seat the next page face-up with no reverse spin.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.46) {
            var end = Transaction()
            end.disablesAnimations = true
            withTransaction(end) {
                index = next
                turnProgress = 0
                incomingIndex = nil
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
        PhotosLibraryService.exportKeepers(albumName: albumName, assetLocalIdentifiers: keeperIDs) { albumOK in
            let albumFailed = !albumOK && !keeperIDs.isEmpty
            var createdBookID: UUID?
            if !keepers.isEmpty, let book = store.createBook(title: albumName) {
                for shot in keepers { store.add(shot, to: book) }
                createdBookID = book.id
            }

            let complete: () -> Void = {
                marks.clear(shotIDs: rejects.map(\.id) + keepers.map(\.id))
                doneKeeperShots = keepers
                doneBookID = createdBookID
                doneAlbumName = albumName
                isFinishing = false
                if albumFailed {
                    finishMessage = "Album export failed — keepers in Field Book"
                }
                showFinishDone = true
            }

            if deleteRejects {
                finishMessage = albumFailed
                    ? "Album export failed — deleting rejects…"
                    : "Deleting rejects…"
                let rejectAssetIDs: [String] = rejects.compactMap { shot in
                    PhotosLibraryService.resolveAsset(
                        preferredID: shot.photosAssetLocalIdentifier,
                        creationDate: shot.date
                    )?.localIdentifier ?? shot.photosAssetLocalIdentifier
                }
                PhotosLibraryService.deleteAssets(localIdentifiers: rejectAssetIDs) { success in
                    guard success else {
                        finishMessage = albumFailed
                            ? "Album export + Photos delete failed — local frames kept."
                            : "Photos delete failed — local frames kept."
                        // Still clear marks + offer handoff for keepers that made it.
                        complete()
                        return
                    }
                    for shot in rejects { store.delete(shot) }
                    complete()
                }
            } else {
                if albumFailed {
                    finishMessage = "Album export failed — keepers in Field Book"
                }
                complete()
            }
        }
    }

    private func shareKeeperImages() {
        let images: [UIImage] = doneKeeperShots.compactMap { store.image(for: $0) ?? store.thumbnail(for: $0) }
        guard !images.isEmpty else {
            // Done sheet was dismissed — bring it back if packing failed.
            showFinishDone = true
            return
        }
        let urls = KeeperSharePackager.jpegFileURLs(from: images)
        // Prefer files; fall back to UIImages so a partial JPEG write never drops keepers.
        if urls.count == images.count {
            shareKeeperItems = urls
        } else if !urls.isEmpty {
            shareKeeperItems = urls
        } else {
            shareKeeperItems = images
        }
    }

    private func shareDoneProofPDF() {
        let frames = doneKeeperShots.isEmpty ? shots : doneKeeperShots
        if let url = ProofPDFExporter.makePDF(title: doneAlbumName.isEmpty ? session.title : doneAlbumName, shots: frames, store: store) {
            shareProofURL = url
        } else {
            // Re-offer the done sheet if PDF failed.
            showFinishDone = true
        }
    }

    private func exportProofPDF() {
        let keepers = shots.filter { marks.state(for: $0.id) == .keep }
        let frames = keepers.isEmpty ? shots : keepers
        showFinish = false
        if let url = ProofPDFExporter.makePDF(title: session.title, shots: frames, store: store) {
            shareProofURL = url
        }
    }
}

// MARK: - Finish done (handoff after export)

struct FinishDoneSheet: View {
    let albumName: String
    let hasBook: Bool
    let keeperCount: Int
    let onOpenBook: () -> Void
    let onShareKeepers: () -> Void
    var onShareProof: (() -> Void)? = nil
    let onOpenPhotos: () -> Void
    let onDone: () -> Void

    var body: some View {
        ZStack {
            DarkroomGround(intensity: 0.85)
            VStack(alignment: .leading, spacing: 0) {
                Text("SHEET FILED")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(3)
                    .foregroundColor(CullPalette.amber.opacity(0.7))
                    .padding(.bottom, 8)

                Text(albumName)
                    .font(.system(size: 24, weight: .semibold, design: .serif))
                    .foregroundColor(.white.opacity(0.95))
                    .padding(.bottom, 6)

                Text("\(keeperCount) keepers · album “\(albumName)”")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                    .padding(.bottom, 24)

                VStack(spacing: 12) {
                    if hasBook {
                        Button(action: onOpenBook) {
                            finishActionRow(
                                title: "OPEN FIELD BOOK",
                                subtitle: "Jump straight to the new book",
                                accent: true
                            )
                        }
                    }

                    Button(action: onShareKeepers) {
                        finishActionRow(
                            title: "SHARE KEEPERS",
                            subtitle: "JPEG files via system share sheet",
                            accent: false
                        )
                    }

                    if let onShareProof {
                        Button(action: onShareProof) {
                            finishActionRow(
                                title: "SHARE PROOF PDF",
                                subtitle: "Contact sheet of keepers",
                                accent: false
                            )
                        }
                    }

                    Button(action: onOpenPhotos) {
                        finishActionRow(
                            title: "OPEN PHOTOS",
                            subtitle: "Find the album in Photos",
                            accent: false
                        )
                    }

                    Button(action: onDone) {
                        Text("DONE")
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

    private func finishActionRow(title: String, subtitle: String, accent: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                Text(subtitle)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45))
            }
            Spacer()
        }
        .foregroundColor(accent ? CullPalette.amber : .white.opacity(0.9))
        .padding(14)
        .background(accent ? CullPalette.amber.opacity(0.1) : Color.white.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(
                    accent ? CullPalette.amber.opacity(0.5) : CullPalette.hairline.opacity(0.6),
                    lineWidth: accent ? 0.8 : 0.6
                )
        )
    }
}

// MARK: - Finish sheet (darkroom, not system alert)

struct FinishSessionSheet: View {
    let kept: Int
    let rejected: Int
    let sessionTitle: String
    let onDeleteAndExport: () -> Void
    let onMarkOnly: () -> Void
    var onExportProof: (() -> Void)? = nil
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            DarkroomGround(intensity: 0.85)

            VStack(alignment: .leading, spacing: 0) {
                Text("SHUTTER")
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

                    if let onExportProof {
                        Button(action: onExportProof) {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("EXPORT PROOF PDF")
                                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                                        .tracking(0.8)
                                    Text("Contact sheet of keepers (or all frames)")
                                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.45))
                                }
                                Spacer()
                            }
                            .foregroundColor(.white.opacity(0.9))
                            .padding(14)
                            .background(Color.white.opacity(0.06))
                            .overlay(
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(CullPalette.hairline.opacity(0.6), lineWidth: 0.6)
                            )
                        }
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
