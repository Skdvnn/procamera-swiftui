import SwiftUI
import Photos

// MARK: - Cull library (new front door)

/// Sessions as contact sheets. Field Book shelf is one tap away.
struct CullLibraryView: View {
    @ObservedObject var store: GalleryStore
    @StateObject private var marks = FrameMarkStore()
    @Environment(\.dismiss) private var dismiss

    @State private var sessions: [ShootSession] = []
    @State private var activeSession: ShootSession?
    @State private var showFieldBooks = false
    @State private var authStatus: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [CullPalette.sheetTop, CullPalette.sheetBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ControlsGrain()
                .opacity(0.35)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                if sessions.isEmpty {
                    emptyState
                } else {
                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 28) {
                            ForEach(sessions) { session in
                                SessionContactSheet(
                                    store: store,
                                    session: session,
                                    marks: marks,
                                    onCull: { activeSession = session },
                                    onOpenFrame: { _ in activeSession = session }
                                )
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        .padding(.bottom, 40)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            rebuildSessions()
            PhotosLibraryService.requestReadWrite { status in
                authStatus = status
            }
        }
        .onChange(of: store.shots) { _, _ in
            rebuildSessions()
        }
        .fullScreenCover(item: $activeSession) { session in
            CullSessionView(
                store: store,
                session: session,
                marks: marks,
                onFinished: {
                    activeSession = nil
                    rebuildSessions()
                }
            )
        }
        .fullScreenCover(isPresented: $showFieldBooks) {
            LibraryView(store: store)
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .accessibilityLabel("Close")

            VStack(alignment: .leading, spacing: 2) {
                Text("DARKROOM")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(3)
                    .foregroundColor(CullPalette.amber.opacity(0.9))
                Text("\(store.shots.count) frames · \(sessions.count) sessions")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
            }

            Spacer()

            Button { showFieldBooks = true } label: {
                Text("FIELD BOOKS")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundColor(CullPalette.amber.opacity(0.85))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(CullPalette.hairline, lineWidth: 1)
                    )
            }
            .accessibilityLabel("Open Field Books")
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Text("NO FRAMES YET")
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundColor(.white.opacity(0.55))
            Text("Shoot a session, then cull it here.\nKeepers export to a Photos album.")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .multilineTextAlignment(.center)
                .foregroundColor(.white.opacity(0.35))
                .padding(.horizontal, 32)
            Button { dismiss() } label: {
                Text("BACK TO CAMERA")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundColor(CullPalette.amber)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(CullPalette.amber.opacity(0.5), lineWidth: 1)
                    )
            }
            .padding(.top, 8)
            Spacer()
        }
    }

    private func rebuildSessions() {
        sessions = SessionClusterer.cluster(store.shots)
    }
}

// MARK: - Session contact sheet block

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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.title.uppercased())
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .tracking(1.5)
                        .foregroundColor(.white.opacity(0.9))
                    Text("\(progress.kept) kept · \(progress.rejected) rejected · \(progress.unmarked) unmarked")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.4))
                }
                Spacer()
                Button(action: onCull) {
                    Text("CULL")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(CullPalette.amber)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(CullPalette.amber.opacity(0.55), lineWidth: 1)
                        )
                }
                .accessibilityLabel("Cull session")
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 12)

            LazyVGrid(columns: columns, spacing: 0) {
                ForEach(Array(session.shots.enumerated()), id: \.element.id) { index, shot in
                    contactCell(shot: shot, index: index)
                }
            }
            .overlay(
                Rectangle()
                    .stroke(CullPalette.hairline, lineWidth: 0.5)
            )
        }
    }

    private func contactCell(shot: ShotMetadata, index: Int) -> some View {
        let state = marks.state(for: shot.id)
        return Button {
            onOpenFrame(index)
        } label: {
            ZStack(alignment: .topLeading) {
                ZStack {
                    Color.black
                    if let thumb = store.thumbnail(for: shot) {
                        Image(uiImage: thumb)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .saturation(state == .reject ? 0.15 : 1.0)
                            .opacity(state == .reject ? 0.55 : 1.0)
                    }
                }
                .aspectRatio(1, contentMode: .fit)
                .clipped()

                Text(String(format: "%03d", index + 1))
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.75))
                    .padding(5)

                if state == .keep {
                    RoundedRectangle(cornerRadius: 0)
                        .stroke(CullPalette.amber, lineWidth: 2)
                        .padding(2)
                }

                if state == .reject {
                    GreasePencilX(seed: Self.strokeSeed(for: shot.id))
                        .stroke(CullPalette.safelight, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                        .padding(10)
                        .opacity(0.9)
                }
            }
            .overlay(alignment: .trailing) {
                Rectangle().fill(CullPalette.hairline).frame(width: 0.5)
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(CullPalette.hairline).frame(height: 0.5)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Frame \(index + 1), \(state.rawValue)")
    }

    private static func strokeSeed(for id: UUID) -> Int {
        id.uuidString.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
    }
}

// MARK: - Grease pencil X (slightly irregular)

struct GreasePencilX: Shape {
    var seed: Int = 0

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let j: CGFloat = 0.06
        let r1 = CGFloat((seed * 17) % 7) / 100.0
        let r2 = CGFloat((seed * 31) % 5) / 100.0
        path.move(to: CGPoint(x: rect.minX + rect.width * (0.12 + r1),
                              y: rect.minY + rect.height * (0.14 - r2)))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * (0.10 - j),
                                 y: rect.maxY - rect.height * (0.12 + r1)))
        path.move(to: CGPoint(x: rect.maxX - rect.width * (0.14 + r2),
                              y: rect.minY + rect.height * (0.12 + j)))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * (0.11 - r1),
                                 y: rect.maxY - rect.height * (0.13 - r2)))
        return path
    }
}

// MARK: - Cull session (one-handed)

struct CullSessionView: View {
    @ObservedObject var store: GalleryStore
    let session: ShootSession
    @ObservedObject var marks: FrameMarkStore
    var onFinished: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var undo = CullUndoStack()
    @State private var index: Int = 0
    @State private var dragOffset: CGSize = .zero
    @State private var showFinish = false
    @State private var isFinishing = false
    @State private var finishMessage: String?

    private var shots: [ShotMetadata] { session.shots }
    private var current: ShotMetadata? {
        guard index >= 0, index < shots.count else { return nil }
        return shots[index]
    }

    private var progress: (kept: Int, rejected: Int, unmarked: Int) {
        session.progress(marks: marks)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let shot = current {
                cullCanvas(shot: shot)
            } else {
                Text("NO FRAMES")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
            }

            VStack {
                topBar
                Spacer()
                metadataStrip
                bottomHint
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .gesture(twoFingerUndoGesture)
        .alert("Finish session", isPresented: $showFinish) {
            Button("Delete rejects + export keepers", role: .destructive) {
                finish(deleteRejects: true)
            }
            Button("Keep rejects, just mark them") {
                finish(deleteRejects: false)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Keeping \(progress.kept). Rejecting \(progress.rejected).")
        }
        .overlay {
            if isFinishing {
                ZStack {
                    Color.black.opacity(0.55).ignoresSafeArea()
                    Text(finishMessage ?? "Working…")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                }
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.1)))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(session.title.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundColor(.white.opacity(0.75))
                    .lineLimit(1)
                Text("\(index + 1) / \(shots.count)  ·  \(progress.kept)↑ \(progress.rejected)↓")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
            }

            Spacer()

            Button { performUndo() } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(undo.canUndo ? CullPalette.amber : .white.opacity(0.25))
                    .frame(width: 36, height: 36)
            }
            .disabled(!undo.canUndo)
            .accessibilityLabel("Undo")

            if progress.unmarked == 0 && !shots.isEmpty {
                Button { showFinish = true } label: {
                    Text("FINISH")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1.5)
                        .foregroundColor(CullPalette.amber)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(CullPalette.amber.opacity(0.55), lineWidth: 1)
                        )
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }

    private func cullCanvas(shot: ShotMetadata) -> some View {
        let state = marks.state(for: shot.id)
        return GeometryReader { geo in
            ZStack {
                if let image = store.image(for: shot) ?? store.thumbnail(for: shot) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .saturation(state == .reject ? 0.2 : 1.0)
                        .opacity(state == .reject ? 0.7 : 1.0)
                        .overlay {
                            if state == .keep {
                                RoundedRectangle(cornerRadius: 0)
                                    .stroke(CullPalette.amber, lineWidth: 3)
                                    .padding(10)
                            }
                            if state == .reject {
                                GreasePencilX(seed: shot.id.uuidString.unicodeScalars.reduce(0) { $0 &+ Int($1.value) })
                                    .stroke(CullPalette.safelight, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                    .padding(geo.size.width * 0.18)
                            }
                        }
                        .offset(dragOffset)
                        .gesture(cullDrag(in: geo.size))
                }

                // Keep / reject ghosts while dragging in the bottom third
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(dragOffset.height < -40 ? "KEEP" : (dragOffset.height > 40 ? "REJECT" : ""))
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .tracking(4)
                            .foregroundColor(dragOffset.height < 0 ? CullPalette.amber : CullPalette.safelight)
                            .opacity(min(1, abs(dragOffset.height) / 80))
                        Spacer()
                    }
                    .padding(.bottom, geo.size.height * 0.28)
                }
                .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
    }

    private var metadataStrip: some View {
        Group {
            if let shot = current {
                HStack(spacing: 12) {
                    meta("ISO", "\(shot.iso)")
                    meta("SHUTTER", shot.shutter)
                    meta("ƒ", String(format: "%.1f", shot.aperture))
                    meta("LENS", "\(shot.focalLength)mm")
                    if shot.filmFilter != "None" {
                        meta("FILM", shot.filmFilter)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(Color.black.opacity(0.55))
            }
        }
    }

    private func meta(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 7, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.35))
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.85))
        }
    }

    private var bottomHint: some View {
        VStack(spacing: 10) {
            // Accessible equivalents for swipe gestures
            HStack(spacing: 20) {
                Button {
                    applyMark(.reject)
                } label: {
                    Text("REJECT")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(CullPalette.safelight)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(CullPalette.safelight.opacity(0.6), lineWidth: 1)
                        )
                }
                .accessibilityLabel("Reject frame")

                Button {
                    applyMark(.keep)
                } label: {
                    Text("KEEP")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(CullPalette.amber)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(CullPalette.amber.opacity(0.6), lineWidth: 1)
                        )
                }
                .accessibilityLabel("Keep frame")
            }

            Text("↑ KEEP   ·   ↓ REJECT   ·   ← → BROWSE")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(1)
                .foregroundColor(.white.opacity(0.3))
        }
        .padding(.bottom, 18)
        .padding(.top, 4)
    }

    private func cullDrag(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                // Prefer vertical marks only when the gesture starts in the bottom third
                // or when vertical dominates — keeps one-handed outdoor use reliable.
                let startY = value.startLocation.y
                let inThumbZone = startY > size.height * 0.55
                if inThumbZone || abs(value.translation.height) > abs(value.translation.width) {
                    dragOffset = CGSize(width: 0, height: value.translation.height)
                } else {
                    dragOffset = CGSize(width: value.translation.width, height: 0)
                }
            }
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                let startY = value.startLocation.y
                let inThumbZone = startY > size.height * 0.55

                withAnimation(.easeOut(duration: 0.15)) {
                    dragOffset = .zero
                }

                if abs(dy) > abs(dx) && (inThumbZone || abs(dy) > 50) {
                    if dy < -50 {
                        applyMark(.keep)
                    } else if dy > 50 {
                        applyMark(.reject)
                    }
                } else if abs(dx) > 60 {
                    if dx < 0 { advance(1) } else { advance(-1) }
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                }
            }
    }

    private var twoFingerUndoGesture: some Gesture {
        // Visible undo button is primary; two-finger tap via simultaneous SpatialTap is limited
        // in SwiftUI — we expose the button and also respond to a shake-free double-tap area.
        TapGesture(count: 2).onEnded { performUndo() }
    }

    private func applyMark(_ state: FrameMarkState) {
        guard let shot = current else { return }
        let previous = marks.state(for: shot.id)
        marks.mark(
            shotID: shot.id,
            photosAssetLocalIdentifier: shot.photosAssetLocalIdentifier,
            creationDate: shot.date,
            state: state
        )
        undo.push(CullAction(shotID: shot.id, previous: previous, next: state))

        if state == .keep {
            PhotosLibraryService.setFavorite(
                assetLocalIdentifier: shot.photosAssetLocalIdentifier,
                favorite: true
            )
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        } else if state == .reject {
            PhotosLibraryService.setFavorite(
                assetLocalIdentifier: shot.photosAssetLocalIdentifier,
                favorite: false
            )
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        }

        advance(1)
    }

    private func performUndo() {
        guard let action = undo.pop(),
              let shot = shots.first(where: { $0.id == action.shotID }) else { return }
        marks.mark(
            shotID: shot.id,
            photosAssetLocalIdentifier: shot.photosAssetLocalIdentifier,
            creationDate: shot.date,
            state: action.previous
        )
        if action.previous == .keep {
            PhotosLibraryService.setFavorite(
                assetLocalIdentifier: shot.photosAssetLocalIdentifier,
                favorite: true
            )
        } else {
            PhotosLibraryService.setFavorite(
                assetLocalIdentifier: shot.photosAssetLocalIdentifier,
                favorite: false
            )
        }
        if let i = shots.firstIndex(where: { $0.id == action.shotID }) {
            index = i
        }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    private func advance(_ delta: Int) {
        let next = index + delta
        guard next >= 0, next < shots.count else { return }
        withAnimation(.easeOut(duration: 0.12)) {
            index = next
        }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func finish(deleteRejects: Bool) {
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
            // Field Book from keepers
            if !keepers.isEmpty {
                let book = store.createBook(title: albumName)
                if let book {
                    for shot in keepers {
                        store.add(shot, to: book)
                    }
                }
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
                    for shot in rejects {
                        store.delete(shot)
                    }
                    marks.clear(shotIDs: rejects.map(\.id))
                    // Clear keep marks too — session is done
                    marks.clear(shotIDs: keepers.map(\.id))
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

extension ShootSession: Hashable {
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
