import SwiftUI
import UIKit

// MARK: - Shot Metadata
// Everything we know about a frame at the moment it was taken,
// written under the print like a silver-pen caption.
struct ShotMetadata: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let iso: Int
    let shutter: String
    let aperture: Float
    let ev: Float
    let filmFilter: String
    let lensFX: String
    let focalLength: Int

    // Stable per-shot tilt so prints look hand-placed, consistent across launches
    // (UUID hashValue is randomized per process, so derive from the string)
    var printTilt: Double {
        let sum = id.uuidString.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return (Double(sum % 100) / 100.0) * 4.4 - 2.2
    }
}

// MARK: - Book
// A little album. Shots live once in the master roll; books hold references.
struct Book: Codable, Identifiable, Equatable {
    var id: UUID
    var title: String
    var createdAt: Date
    var shotIDs: [UUID]
    var pinnedShotIDs: Set<UUID>
}

// MARK: - Gallery Store
// App-side persistence: full-res JPEG + small thumbnail per shot, plus JSON
// indexes for the master roll and the books, all in Documents/PhotoBook.
final class GalleryStore: ObservableObject {
    @Published private(set) var shots: [ShotMetadata] = []
    @Published private(set) var books: [Book] = []
    /// Bumped when a shot's JPEG bytes change so SwiftUI drops stale UIImage views.
    @Published private(set) var imageRevisions: [UUID: Int] = [:]

    private let directory: URL
    private let indexURL: URL
    private let booksURL: URL
    private var thumbCache = NSCache<NSString, UIImage>()
    private let ioQueue = DispatchQueue(label: "com.skylardann.filmcam.gallery", qos: .userInitiated)

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        directory = docs.appendingPathComponent("PhotoBook", isDirectory: true)
        indexURL = directory.appendingPathComponent("index.json")
        booksURL = directory.appendingPathComponent("books.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
        // Older builds wrote into Documents/ProCameraBooks — pull those in once
        // so the shelf isn't empty after the Field Book / GalleryStore switch.
        migrateLegacyProCameraBooksIfNeeded()
    }

    func revision(for shot: ShotMetadata) -> Int {
        imageRevisions[shot.id] ?? 0
    }

    // MARK: Shots

    func add(image: UIImage, metadata: ShotMetadata) {
        // Write files off the main thread, then publish
        ioQueue.async { [weak self] in
            guard let self = self else { return }

            if let data = image.jpegData(compressionQuality: 0.9) {
                try? data.write(to: self.imageURL(for: metadata.id), options: .atomic)
            }
            if let thumb = Self.thumbnail(from: image, longEdge: 900),
               let thumbData = thumb.jpegData(compressionQuality: 0.8) {
                try? thumbData.write(to: self.thumbURL(for: metadata.id), options: .atomic)
            }

            DispatchQueue.main.async {
                if !self.shots.contains(where: { $0.id == metadata.id }) {
                    self.shots.append(metadata)
                    self.saveIndex()
                }
            }
        }
    }

    func delete(_ shot: ShotMetadata) {
        shots.removeAll { $0.id == shot.id }
        imageRevisions[shot.id] = nil
        saveIndex()

        // Strip the frame out of every book too
        for i in books.indices {
            books[i].shotIDs.removeAll { $0 == shot.id }
            books[i].pinnedShotIDs.remove(shot.id)
        }
        saveBooks()

        let imageURL = imageURL(for: shot.id)
        let thumbURL = thumbURL(for: shot.id)
        thumbCache.removeObject(forKey: shot.id.uuidString as NSString)
        ioQueue.async {
            try? FileManager.default.removeItem(at: imageURL)
            try? FileManager.default.removeItem(at: thumbURL)
        }
    }

    func image(for shot: ShotMetadata) -> UIImage? {
        UIImage(contentsOfFile: imageURL(for: shot.id).path)
    }

    // File locations used by the CloudKit uploader to build CKAssets
    func imageFileURL(for shot: ShotMetadata) -> URL { imageURL(for: shot.id) }
    func thumbFileURL(for shot: ShotMetadata) -> URL { thumbURL(for: shot.id) }

    func thumbnail(for shot: ShotMetadata) -> UIImage? {
        let key = shot.id.uuidString as NSString
        if let cached = thumbCache.object(forKey: key) { return cached }
        guard let thumb = UIImage(contentsOfFile: thumbURL(for: shot.id).path)
                ?? image(for: shot) else { return nil }
        thumbCache.setObject(thumb, forKey: key)
        return thumb
    }

    /// Rewrite a shot's full-res JPEG + thumb on disk (used by post-capture Lens FX).
    func replaceImage(_ image: UIImage, for shot: ShotMetadata, lensFXName: String? = nil,
                      completion: ((Bool) -> Void)? = nil) {
        ioQueue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion?(false) }
                return
            }

            guard let data = image.jpegData(compressionQuality: 0.9) else {
                DispatchQueue.main.async { completion?(false) }
                return
            }

            do {
                try data.write(to: self.imageURL(for: shot.id), options: .atomic)
                if let thumb = Self.thumbnail(from: image, longEdge: 900),
                   let thumbData = thumb.jpegData(compressionQuality: 0.8) {
                    try thumbData.write(to: self.thumbURL(for: shot.id), options: .atomic)
                }
            } catch {
                DispatchQueue.main.async { completion?(false) }
                return
            }

            DispatchQueue.main.async {
                self.thumbCache.removeObject(forKey: shot.id.uuidString as NSString)
                self.imageRevisions[shot.id, default: 0] += 1
                if let lensFXName = lensFXName,
                   let idx = self.shots.firstIndex(where: { $0.id == shot.id }) {
                    let old = self.shots[idx]
                    self.shots[idx] = ShotMetadata(
                        id: old.id,
                        date: old.date,
                        iso: old.iso,
                        shutter: old.shutter,
                        aperture: old.aperture,
                        ev: old.ev,
                        filmFilter: old.filmFilter,
                        lensFX: lensFXName,
                        focalLength: old.focalLength
                    )
                    self.saveIndex()
                } else {
                    // Bytes changed even if metadata didn't — force observers
                    self.objectWillChange.send()
                }
                completion?(true)
            }
        }
    }

    /// Bake a Lens FX onto an existing frame and persist the result.
    func applyLensFX(_ fx: LensFXMode, to shot: ShotMetadata, completion: ((Bool) -> Void)? = nil) {
        guard fx != .none else {
            completion?(false)
            return
        }
        guard let source = image(for: shot) else {
            completion?(false)
            return
        }
        // Render off-main, then reuse replaceImage (also io-bound) so disk + UI stay in sync.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion?(false) }
                return
            }
            guard let rendered = LensFXEngine.shared.render(fx, on: source) else {
                DispatchQueue.main.async { completion?(false) }
                return
            }
            self.replaceImage(rendered, for: shot, lensFXName: fx.name, completion: completion)
        }
    }

    // MARK: Books

    func createBook(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        books.append(Book(id: UUID(), title: trimmed, createdAt: Date(),
                          shotIDs: [], pinnedShotIDs: []))
        saveBooks()
    }

    func renameBook(_ book: Book, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let i = books.firstIndex(where: { $0.id == book.id }) else { return }
        books[i].title = trimmed
        saveBooks()
    }

    func deleteBook(_ book: Book) {
        books.removeAll { $0.id == book.id }
        saveBooks()
    }

    func book(withID id: UUID?) -> Book? {
        guard let id = id else { return nil }
        return books.first { $0.id == id }
    }

    func add(_ shot: ShotMetadata, to book: Book) {
        guard let i = books.firstIndex(where: { $0.id == book.id }),
              !books[i].shotIDs.contains(shot.id) else { return }
        books[i].shotIDs.append(shot.id)
        saveBooks()
    }

    func remove(_ shot: ShotMetadata, from book: Book) {
        guard let i = books.firstIndex(where: { $0.id == book.id }) else { return }
        books[i].shotIDs.removeAll { $0 == shot.id }
        books[i].pinnedShotIDs.remove(shot.id)
        saveBooks()
    }

    func togglePin(_ shot: ShotMetadata, in book: Book) {
        guard let i = books.firstIndex(where: { $0.id == book.id }) else { return }
        if books[i].pinnedShotIDs.contains(shot.id) {
            books[i].pinnedShotIDs.remove(shot.id)
        } else {
            books[i].pinnedShotIDs.insert(shot.id)
        }
        saveBooks()
    }

    func isPinned(_ shot: ShotMetadata, in book: Book?) -> Bool {
        guard let book = book, let b = books.first(where: { $0.id == book.id }) else { return false }
        return b.pinnedShotIDs.contains(shot.id)
    }

    func contains(_ shot: ShotMetadata, book: Book) -> Bool {
        books.first(where: { $0.id == book.id })?.shotIDs.contains(shot.id) ?? false
    }

    // Pinned frames first, then chronological
    func shots(in book: Book) -> [ShotMetadata] {
        guard let b = books.first(where: { $0.id == book.id }) else { return [] }
        let members = shots.filter { b.shotIDs.contains($0.id) }
        return members.sorted { lhs, rhs in
            let lp = b.pinnedShotIDs.contains(lhs.id)
            let rp = b.pinnedShotIDs.contains(rhs.id)
            if lp != rp { return lp }
            return lhs.date < rhs.date
        }
    }

    func coverShot(for book: Book) -> ShotMetadata? {
        shots(in: book).first
    }

    // MARK: Private

    private func imageURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).jpg")
    }

    private func thumbURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString)_thumb.jpg")
    }

    private func saveIndex() {
        if let data = try? JSONEncoder().encode(shots) {
            try? data.write(to: indexURL)
        }
    }

    private func saveBooks() {
        if let data = try? JSONEncoder().encode(books) {
            try? data.write(to: booksURL)
        }
    }

    private func load() {
        if let data = try? Data(contentsOf: indexURL),
           let saved = try? JSONDecoder().decode([ShotMetadata].self, from: data) {
            shots = saved
        }
        if let data = try? Data(contentsOf: booksURL),
           let saved = try? JSONDecoder().decode([Book].self, from: data) {
            books = saved
        }
    }

    // MARK: Legacy migration (ProCameraBooks → PhotoBook)

    private struct LegacyCatalog: Codable {
        var books: [LegacyBook]
        var shots: [LegacyShot]
        var activeBookID: UUID?
    }

    private struct LegacyBook: Codable {
        let id: UUID
        var title: String
        var createdAt: TimeInterval
        var updatedAt: TimeInterval?
        var coverShotID: UUID?
        var shotIDs: [UUID]
    }

    private struct LegacyShot: Codable {
        let id: UUID
        let bookID: UUID
        let createdAt: TimeInterval
        let filename: String
        let thumbFilename: String
    }

    /// One-time import from the pre–Field Book on-disk layout.
    private func migrateLegacyProCameraBooksIfNeeded() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let legacyRoot = docs.appendingPathComponent("ProCameraBooks", isDirectory: true)
        let catalogURL = legacyRoot.appendingPathComponent("catalog.json")
        let flagURL = directory.appendingPathComponent(".migrated_procamerabooks_v1")

        guard !FileManager.default.fileExists(atPath: flagURL.path),
              FileManager.default.fileExists(atPath: catalogURL.path),
              let data = try? Data(contentsOf: catalogURL),
              let catalog = try? JSONDecoder().decode(LegacyCatalog.self, from: data)
        else { return }

        var existingShotIDs = Set(shots.map(\.id))
        var importedAny = false
        let fm = FileManager.default

        for legacy in catalog.shots {
            guard !existingShotIDs.contains(legacy.id) else { continue }
            let bookDir = legacyRoot.appendingPathComponent(legacy.bookID.uuidString, isDirectory: true)
            let srcImg = bookDir.appendingPathComponent(legacy.filename)
            let srcThumb = bookDir.appendingPathComponent(legacy.thumbFilename)
            guard fm.fileExists(atPath: srcImg.path) else { continue }

            let dstImg = imageURL(for: legacy.id)
            let dstThumb = thumbURL(for: legacy.id)
            try? fm.copyItem(at: srcImg, to: dstImg)
            if fm.fileExists(atPath: srcThumb.path) {
                try? fm.copyItem(at: srcThumb, to: dstThumb)
            } else if let img = UIImage(contentsOfFile: srcImg.path),
                      let thumb = Self.thumbnail(from: img, longEdge: 900),
                      let thumbData = thumb.jpegData(compressionQuality: 0.8) {
                try? thumbData.write(to: dstThumb)
            }

            let meta = ShotMetadata(
                id: legacy.id,
                date: Date(timeIntervalSinceReferenceDate: legacy.createdAt),
                iso: 0,
                shutter: "—",
                aperture: 0,
                ev: 0,
                filmFilter: "None",
                lensFX: "None",
                focalLength: 0
            )
            shots.append(meta)
            existingShotIDs.insert(legacy.id)
            importedAny = true
        }

        var existingBookIDs = Set(books.map(\.id))
        for lb in catalog.books {
            guard !existingBookIDs.contains(lb.id) else { continue }
            // Skip empty placeholder rolls — All Frames already covers the master roll.
            if lb.shotIDs.isEmpty && lb.title.localizedCaseInsensitiveContains("camera roll") {
                continue
            }
            let pinned: Set<UUID> = lb.coverShotID.map { Set([$0]) } ?? []
            // Only keep shot IDs that we actually have files for
            let members = lb.shotIDs.filter { existingShotIDs.contains($0) }
            books.append(Book(
                id: lb.id,
                title: lb.title,
                createdAt: Date(timeIntervalSinceReferenceDate: lb.createdAt),
                shotIDs: members,
                pinnedShotIDs: pinned.intersection(existingShotIDs)
            ))
            existingBookIDs.insert(lb.id)
            importedAny = true
        }

        if importedAny {
            // Newest last to match GalleryStore.add append order
            shots.sort { $0.date < $1.date }
            saveIndex()
            saveBooks()
        }

        try? Data("1".utf8).write(to: flagURL)
    }

    private static func thumbnail(from image: UIImage, longEdge: CGFloat) -> UIImage? {
        let maxDim = max(image.size.width, image.size.height)
        guard maxDim > longEdge else { return image }
        let scale = longEdge / maxDim
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

// MARK: - Library (classic Apple Books-style shelf)
// Physical shelves, upright covers, tap a book to open it, tap another
// cover on the open-book rail to flip through albums without returning.
// CloudKit shared books sit on their own shelf rows below.
struct LibraryView: View {
    @ObservedObject var store: GalleryStore
    @ObservedObject private var cloud = CloudBookManager.shared
    @Environment(\.dismiss) private var dismiss
    @Namespace private var bookNamespace

    @State private var route: BookRoute?
    @State private var openedSharedBook: CloudBookManager.SharedBookRef?
    @State private var showNewBook = false
    @State private var newBookTitle = ""
    @State private var bookPendingRename: Book?
    @State private var renameTitle = ""
    @State private var pressedRouteID: String?

    private let accent = DS.accent
    private let booksPerShelf = 3

    enum BookRoute: Identifiable, Equatable {
        case allFrames
        case book(UUID)

        var id: String {
            switch self {
            case .allFrames: return "all-frames"
            case .book(let id): return id.uuidString
            }
        }
    }

    /// Local shelf: master roll, user books, then the "new book" slot.
    private var shelfItems: [ShelfItem] {
        var items: [ShelfItem] = [
            .allFrames(count: store.shots.count,
                       cover: store.shots.last.flatMap { store.thumbnail(for: $0) })
        ]
        for book in store.books {
            items.append(.book(
                id: book.id,
                title: book.title,
                count: book.shotIDs.count,
                cover: store.coverShot(for: book).flatMap { store.thumbnail(for: $0) }
            ))
        }
        items.append(.newBook)
        return items
    }

    private var sharedShelfItems: [ShelfItem] {
        cloud.sharedBooks.map { .shared($0) }
    }

    private var shelves: [[ShelfItem]] {
        chunked(shelfItems)
    }

    private var sharedShelves: [[ShelfItem]] {
        chunked(sharedShelfItems)
    }

    private func chunked(_ items: [ShelfItem]) -> [[ShelfItem]] {
        stride(from: 0, to: items.count, by: booksPerShelf).map { start in
            Array(items[start..<min(start + booksPerShelf, items.count)])
        }
    }

    var body: some View {
        ZStack {
            // Back wall — dark vulcanite, like the camera body / old iBooks wood stand-in
            bookshelfBackdrop

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 6)
                    // Keep the close control tappable even while a book is open
                    .opacity(route == nil && openedSharedBook == nil ? 1 : 0)
                    .allowsHitTesting(route == nil && openedSharedBook == nil)

                Text("TAP A COVER TO OPEN")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(2.5)
                    .foregroundColor(.white.opacity(0.28))
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 10)
                    .opacity(route == nil && openedSharedBook == nil ? 1 : 0)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(Array(shelves.enumerated()), id: \.offset) { _, row in
                            shelfRow(for: row)
                        }

                        // Books others invited you into — same shelf language, own ledges
                        if !sharedShelves.isEmpty {
                            Text("SHARED WITH ME")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .tracking(3)
                                .foregroundColor(.white.opacity(0.4))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 22)
                                .padding(.top, 10)
                                .padding(.bottom, 8)

                            ForEach(Array(sharedShelves.enumerated()), id: \.offset) { _, row in
                                shelfRow(for: row)
                            }
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 36)
                }
                .opacity(route == nil && openedSharedBook == nil ? 1 : 0)
                .allowsHitTesting(route == nil && openedSharedBook == nil)
            }

            // Opened local book overlays the shelf with a cover-zoom, iBooks-style
            if let route = route {
                PhotoBookView(
                    store: store,
                    bookID: {
                        if case .book(let id) = route { return id }
                        return nil
                    }(),
                    namespace: bookNamespace,
                    coverMatchID: route.id,
                    shelfItems: openableShelfItems,
                    activeRouteID: route.id,
                    onSelectShelfItem: { item in
                        switchBooks(to: item)
                    },
                    onClose: closeBook
                )
                .transition(.identity)
                .zIndex(2)
            }
        }
        .onAppear { cloud.refreshSharedBooks() }
        .fullScreenCover(item: $openedSharedBook) { ref in
            SharedBookView(bookRef: ref, store: store)
        }
        .alert("New Book", isPresented: $showNewBook) {
            TextField("Title (e.g. Big Sur Trip)", text: $newBookTitle)
            Button("Create") {
                store.createBook(title: newBookTitle)
                newBookTitle = ""
            }
            Button("Cancel", role: .cancel) { newBookTitle = "" }
        } message: {
            Text("Name your book, then long-press frames in All Frames to add them.")
        }
        .alert("Rename Book", isPresented: Binding(
            get: { bookPendingRename != nil },
            set: { if !$0 { bookPendingRename = nil } }
        )) {
            TextField("Title", text: $renameTitle)
            Button("Save") {
                if let book = bookPendingRename {
                    store.renameBook(book, to: renameTitle)
                }
                bookPendingRename = nil
            }
            Button("Cancel", role: .cancel) { bookPendingRename = nil }
        }
        .statusBarHidden(true)
    }

    private func shelfRow(for row: [ShelfItem]) -> some View {
        ShelfRow(
            items: row,
            accent: accent,
            namespace: bookNamespace,
            activeRouteID: route?.id,
            pressedRouteID: pressedRouteID,
            onPress: { pressedRouteID = $0 },
            onOpen: handleOpen,
            onNew: {
                newBookTitle = ""
                showNewBook = true
            },
            onRename: { id in
                if let book = store.books.first(where: { $0.id == id }) {
                    bookPendingRename = book
                    renameTitle = book.title
                }
            },
            onDelete: { id in
                if let book = store.books.first(where: { $0.id == id }) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        store.deleteBook(book)
                    }
                }
            }
        )
    }

    private func handleOpen(_ item: ShelfItem) {
        if case .shared(let ref) = item {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            openedSharedBook = ref
            return
        }
        openBook(item)
    }

    /// Entries shown in the open-book shelf rail (local albums only).
    private var openableShelfItems: [ShelfItem] {
        shelfItems.filter {
            switch $0 {
            case .newBook, .shared: return false
            default: return true
            }
        }
    }

    private func openBook(_ item: ShelfItem) {
        guard let route = item.route else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.spring(response: 0.48, dampingFraction: 0.86)) {
            pressedRouteID = nil
            self.route = route
        }
    }

    private func switchBooks(to item: ShelfItem) {
        guard let next = item.route, next != route else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
            route = next
        }
    }

    private func closeBook() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
            route = nil
            pressedRouteID = nil
        }
    }

    private var bookshelfBackdrop: some View {
        ZStack {
            // Warm dark wood-panel stand-in that still fits the camera body
            LinearGradient(
                colors: [
                    Color(hex: "1a1410"),
                    Color(hex: "12100e"),
                    Color(hex: "0e0c0b")
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            LeicaVulcaniteTexture(scale: 28, intensity: 0.55)
                .opacity(0.55)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // Soft vignette so shelf edges fall away
            RadialGradient(
                colors: [Color.clear, Color.black.opacity(0.45)],
                center: .center,
                startRadius: 80,
                endRadius: 520
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("LIBRARY")
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .tracking(4)
                    .foregroundColor(.white.opacity(0.9))
                Text(librarySubtitle)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.35))
            }

            Spacer()

            Button(action: { dismiss() }) {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.5))
                        .frame(width: 34, height: 34)
                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                        .frame(width: 34, height: 34)
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
        }
    }

    private var librarySubtitle: String {
        let local = store.books.count + 1
        let shared = cloud.sharedBooks.count
        if shared > 0 {
            return "\(local) BOOKS  ·  \(shared) SHARED  ·  \(store.shots.count) FRAMES"
        }
        return "\(local) BOOKS  ·  \(store.shots.count) FRAMES"
    }
}

// MARK: - Shelf data
enum ShelfItem: Identifiable {
    case allFrames(count: Int, cover: UIImage?)
    case book(id: UUID, title: String, count: Int, cover: UIImage?)
    case shared(CloudBookManager.SharedBookRef)
    case newBook

    var id: String {
        switch self {
        case .allFrames: return "all-frames"
        case .book(let id, _, _, _): return id.uuidString
        case .shared(let ref): return "shared-\(ref.id)"
        case .newBook: return "new-book"
        }
    }

    var route: LibraryView.BookRoute? {
        switch self {
        case .allFrames: return .allFrames
        case .book(let id, _, _, _): return .book(id)
        case .shared, .newBook: return nil
        }
    }

    var title: String {
        switch self {
        case .allFrames: return "ALL FRAMES"
        case .book(_, let title, _, _): return title.uppercased()
        case .shared(let ref): return ref.title.uppercased()
        case .newBook: return "NEW BOOK"
        }
    }

    var count: Int {
        switch self {
        case .allFrames(let count, _): return count
        case .book(_, _, let count, _): return count
        case .shared, .newBook: return 0
        }
    }

    var coverImage: UIImage? {
        switch self {
        case .allFrames(_, let cover): return cover
        case .book(_, _, _, let cover): return cover
        case .shared, .newBook: return nil
        }
    }

    var isMaster: Bool {
        if case .allFrames = self { return true }
        return false
    }

    var isShared: Bool {
        if case .shared = self { return true }
        return false
    }

    var subtitle: String? {
        if case .shared = self { return "SHARED" }
        return nil
    }
}

// MARK: - Open-book album rail (tap through covers)
struct AlbumShelfRail: View {
    let items: [ShelfItem]
    let activeRouteID: String?
    let accent: Color
    let namespace: Namespace.ID
    let onSelect: (ShelfItem) -> Void

    var body: some View {
        VStack(spacing: 6) {
            Text("YOUR SHELF")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundColor(.white.opacity(0.3))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 14) {
                    ForEach(items) { item in
                        let isActive = activeRouteID == item.id
                        Button {
                            onSelect(item)
                        } label: {
                            BookCover(
                                title: item.title,
                                count: item.count,
                                coverImage: item.coverImage,
                                accent: accent,
                                isMaster: item.isMaster,
                                matchID: "rail-\(item.id)",
                                namespace: namespace,
                                isRailMiniature: true,
                                coverHeight: 64,
                                subtitleOverride: item.subtitle,
                                isShared: item.isShared
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(isActive ? accent.opacity(0.9) : Color.clear, lineWidth: 1.5)
                            )
                            .opacity(isActive ? 1 : 0.72)
                            .scaleEffect(isActive ? 1.06 : 1.0)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
            }

            // Mini ledge under the rail
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "3a2c22"), Color(hex: "1a1511")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 6)
                .padding(.horizontal, 12)
                .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
        }
    }
}

// MARK: - One physical shelf row
struct ShelfRow: View {
    let items: [ShelfItem]
    let accent: Color
    let namespace: Namespace.ID
    let activeRouteID: String?
    let pressedRouteID: String?
    let onPress: (String?) -> Void
    let onOpen: (ShelfItem) -> Void
    let onNew: () -> Void
    var onRename: ((UUID) -> Void)? = nil
    let onDelete: (UUID) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    shelfSlot(item: item, index: index)
                        .frame(maxWidth: .infinity)
                }
                // Pad empty slots so a short bottom shelf still spans the ledge
                if items.count < 3 {
                    ForEach(0..<(3 - items.count), id: \.self) { _ in
                        Color.clear.frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 2)

            // The ledge the books sit on
            ShelfLedge()
                .padding(.horizontal, 8)
        }
        .padding(.bottom, 22)
    }

    @ViewBuilder
    private func shelfSlot(item: ShelfItem, index: Int) -> some View {
        let lean = ShelfRow.lean(for: item.id, index: index)
        let isActive = activeRouteID == item.id
        let isPressed = pressedRouteID == item.id

        Group {
            switch item {
            case .newBook:
                NewBookCover(accent: accent)
                    .onTapGesture(perform: onNew)
            default:
                Button {
                    onOpen(item)
                } label: {
                    BookCover(
                        title: item.title,
                        count: item.count,
                        coverImage: item.coverImage,
                        accent: accent,
                        isMaster: item.isMaster,
                        matchID: item.id,
                        namespace: namespace,
                        subtitleOverride: item.subtitle,
                        isShared: item.isShared
                    )
                    .scaleEffect(isPressed ? 0.94 : 1.0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isPressed)
                    // Stay in the hierarchy (opacity 0) so matched-geometry can reverse on close
                    .opacity(isActive ? 0 : 1)
                }
                .buttonStyle(ShelfBookButtonStyle(
                    onPressChanged: { pressing in
                        onPress(pressing ? item.id : nil)
                    }
                ))
                .disabled(isActive)
                .contextMenu {
                    if case .book(let id, _, _, _) = item {
                        Button {
                            onRename?(id)
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            onDelete(id)
                        } label: {
                            Label("Delete book (keeps frames)", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .rotationEffect(.degrees(lean))
        .padding(.horizontal, 6)
    }

    /// Stable per-book lean so the shelf feels hand-arranged, not rigid.
    private static func lean(for id: String, index: Int) -> Double {
        let sum = id.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        let base = Double((sum + index * 17) % 100) / 100.0 * 4.0 - 2.0
        return base
    }
}

// MARK: - Shelf ledge
struct ShelfLedge: View {
    var body: some View {
        VStack(spacing: 0) {
            // Top lip catching light
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "5a4535").opacity(0.9),
                            Color(hex: "3a2c22")
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 5)
                .overlay(
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(height: 1),
                    alignment: .top
                )

            // Front face of the plank
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: "2a211a"),
                            Color(hex: "1a1511")
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: 14)
                .overlay(
                    // Subtle grain lines
                    HStack(spacing: 18) {
                        ForEach(0..<12, id: \.self) { _ in
                            Rectangle()
                                .fill(Color.white.opacity(0.015))
                                .frame(width: 1)
                        }
                    }
                )
                .shadow(color: .black.opacity(0.55), radius: 8, x: 0, y: 6)
        }
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }
}

// MARK: - Upright book cover (iBooks-style)
struct BookCover: View {
    let title: String
    let count: Int
    let coverImage: UIImage?
    let accent: Color
    let isMaster: Bool
    let matchID: String
    let namespace: Namespace.ID
    /// Compact rail miniatures use unique IDs and skip morph participation
    var isRailMiniature: Bool = false
    var coverHeight: CGFloat = 168
    /// Destination of a shelf→open morph (hero cover). Shelf slots leave this false.
    var isOpenDestination: Bool = false
    var subtitleOverride: String? = nil
    var isShared: Bool = false

    var body: some View {
        coverBody
            .aspectRatio(0.68, contentMode: .fit)
            .frame(height: coverHeight)
            .shadow(color: .black.opacity(isRailMiniature ? 0.35 : 0.55),
                    radius: isRailMiniature ? 4 : 8, x: 2, y: isRailMiniature ? 3 : 6)
            .modifier(BookCoverMatchModifier(
                matchID: matchID,
                namespace: namespace,
                // Shared books open via fullScreenCover (cloud viewer), not cover morph
                enabled: !isRailMiniature && !isShared,
                isSource: !isOpenDestination
            ))
            .accessibilityLabel(isShared ? "\(title), shared book" : "\(title), \(count) frames")
    }

    private var coverBody: some View {
        ZStack(alignment: .bottom) {
            // Page-edge stack on the right for thickness
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(white: 0.85))
                .frame(width: isRailMiniature ? 3 : 5)
                .offset(x: isRailMiniature ? 2 : 4)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(.vertical, 3)

            // Spine edge on the left
            RoundedRectangle(cornerRadius: 3)
                .fill(
                    LinearGradient(
                        colors: [Color.black.opacity(0.7), Color.black.opacity(0.25)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: isRailMiniature ? 4 : 7)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            // Cover face
            ZStack(alignment: .bottom) {
                Group {
                    if let coverImage = coverImage {
                        Image(uiImage: coverImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        ZStack {
                            LinearGradient(
                                colors: [
                                    isMaster ? Color(hex: "2a2418")
                                        : isShared ? Color(hex: "1a2228")
                                        : Color(hex: "1c1c1c"),
                                    Color(hex: "0e0e0e")
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            Image(systemName: isMaster ? "camera.aperture"
                                  : isShared ? "person.2" : "book.closed")
                                .font(.system(size: isRailMiniature ? 14 : 26, weight: .ultraLight))
                                .foregroundColor(.white.opacity(0.22))
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

                // Bottom title band
                VStack(spacing: 2) {
                    Text(title)
                        .font(.system(size: isRailMiniature ? 7 : 9, weight: .bold, design: .monospaced))
                        .tracking(isRailMiniature ? 0.5 : 1.2)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .foregroundColor(isMaster || isShared ? accent : .white.opacity(0.92))
                    if !isRailMiniature {
                        Text(subtitleOverride ?? "\(count)")
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundColor(.white.opacity(0.45))
                    }
                }
                .padding(.horizontal, isRailMiniature ? 3 : 6)
                .padding(.vertical, isRailMiniature ? 5 : 8)
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(
                        colors: [Color.black.opacity(0.05), Color.black.opacity(0.78)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.28),
                                Color.white.opacity(0.05),
                                Color.black.opacity(0.4)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.7
                    )
            )
            .overlay(
                LinearGradient(
                    colors: [Color.white.opacity(0.14), Color.clear, Color.clear],
                    startPoint: .topLeading,
                    endPoint: UnitPoint(x: 0.55, y: 0.45)
                )
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .allowsHitTesting(false)
            )
        }
    }
}

private struct BookCoverMatchModifier: ViewModifier {
    let matchID: String
    let namespace: Namespace.ID
    let enabled: Bool
    let isSource: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.matchedGeometryEffect(id: matchID, in: namespace, isSource: isSource)
        } else {
            content
        }
    }
}

// Press feedback for shelf covers without eating the tap
private struct ShelfBookButtonStyle: ButtonStyle {
    let onPressChanged: (Bool) -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, pressed in
                onPressChanged(pressed)
            }
    }
}

// MARK: - Empty slot / new book
struct NewBookCover: View {
    let accent: Color

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(accent.opacity(0.75))
            Text("NEW")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundColor(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(0.68, contentMode: .fit)
        .frame(height: 168)
        .background(
            RoundedRectangle(cornerRadius: 3)
                .strokeBorder(
                    Color.white.opacity(0.22),
                    style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])
                )
                .background(
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.03))
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 3))
    }
}

// MARK: - Photo Book (one book's pages)
struct PhotoBookView: View {
    @ObservedObject var store: GalleryStore
    let bookID: UUID?

    /// Matched-geometry open from the shelf cover (classic iBooks tap-to-open).
    var namespace: Namespace.ID? = nil
    var coverMatchID: String? = nil
    var shelfItems: [ShelfItem] = []
    var activeRouteID: String? = nil
    var onSelectShelfItem: ((ShelfItem) -> Void)? = nil
    var onClose: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var currentPage = 0
    @State private var zoomedShot: ShotMetadata?
    @State private var contentRevealed = false
    /// Rail taps should swap albums without replaying the shelf→cover open morph
    @State private var skipNextOpenMorph = false
    @State private var shareContext: CloudBookManager.ShareContext?
    @State private var isPreparingShare = false
    @State private var shareError: String?
    @State private var frameShare: FrameSharePayload?
    @State private var fxBusyShotID: UUID?
    @State private var fxError: String?

    private let accent = DS.accent

    private struct FrameSharePayload: Identifiable {
        let id = UUID()
        let items: [Any]
    }

    private var book: Book? { store.book(withID: bookID) }

    private var bookShots: [ShotMetadata] {
        if let book = book { return store.shots(in: book) }
        return shotsIfMaster
    }

    private var shotsIfMaster: [ShotMetadata] {
        bookID == nil ? store.shots : []
    }

    private var coverTitle: String {
        (book?.title ?? "ALL FRAMES").uppercased()
    }

    private var coverImage: UIImage? {
        if let book = book {
            return store.coverShot(for: book).flatMap { store.thumbnail(for: $0) }
        }
        return store.shots.last.flatMap { store.thumbnail(for: $0) }
    }

    var body: some View {
        ZStack {
            // Vulcanite album cover, same material as the camera body
            LeicaVulcaniteTexture(scale: 20, intensity: 0.8)
                .ignoresSafeArea()
                .opacity(contentRevealed ? 1 : 0.35)

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 10)
                    .opacity(contentRevealed ? 1 : 0)

                if bookShots.isEmpty {
                    emptyBook
                        .opacity(contentRevealed ? 1 : 0)
                } else {
                    // Page 0 is the contact-sheet index; then one print per page.
                    // Real page-curl transitions - swipe or tap the page edges.
                    PageCurlView(pageCount: bookShots.count + 1, currentPage: $currentPage) { index in
                        pageContent(at: index)
                    }
                    .opacity(contentRevealed ? 1 : 0)
                    .id(bookID?.uuidString ?? "all-frames")

                    pageFooter
                        .padding(.horizontal, 24)
                        .padding(.bottom, shelfItems.count > 1 ? 6 : 14)
                        .opacity(contentRevealed ? 1 : 0)
                }

                // Tap other covers to flip through albums without closing
                if shelfItems.count > 1, let namespace = namespace {
                    AlbumShelfRail(
                        items: shelfItems,
                        activeRouteID: activeRouteID,
                        accent: accent,
                        namespace: namespace,
                        onSelect: { item in
                            skipNextOpenMorph = true
                            currentPage = 0
                            onSelectShelfItem?(item)
                        }
                    )
                    .padding(.bottom, 10)
                    .opacity(contentRevealed ? 1 : 0)
                }
            }

            // Hero cover morphs from the shelf slot, then yields to the open pages
            if let namespace = namespace, let matchID = coverMatchID, !contentRevealed {
                BookCover(
                    title: coverTitle,
                    count: bookShots.count,
                    coverImage: coverImage,
                    accent: accent,
                    isMaster: bookID == nil,
                    matchID: matchID,
                    namespace: namespace,
                    isOpenDestination: true
                )
                .frame(maxWidth: 220)
                .allowsHitTesting(false)
            }
        }
        .overlay {
            if let shot = zoomedShot {
                // Resolve latest metadata so post-FX caption/revision stay live
                let live = store.shots.first(where: { $0.id == shot.id }) ?? shot
                Lightbox(
                    image: store.image(for: live),
                    revision: store.revision(for: live),
                    accent: accent,
                    isApplyingFX: fxBusyShotID == live.id,
                    onApplyFX: { fx in applyLensFX(fx, to: live) },
                    onShare: { shareFrame(live) },
                    onDismiss: { zoomedShot = nil }
                )
            }
        }
        .sheet(item: $shareContext) { context in
            CloudSharingSheet(share: context.share, container: context.container, title: context.title)
        }
        .sheet(item: $frameShare) { payload in
            ActivityShareSheet(items: payload.items)
        }
        .alert("Couldn't share book", isPresented: Binding(
            get: { shareError != nil },
            set: { if !$0 { shareError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(shareError ?? "")
        }
        .alert("Couldn't apply Lens FX", isPresented: Binding(
            get: { fxError != nil },
            set: { if !$0 { fxError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(fxError ?? "")
        }
        .onAppear { revealContent(after: 0.3) }
        .onChange(of: bookID) { _, _ in
            currentPage = 0
            if skipNextOpenMorph {
                skipNextOpenMorph = false
                withAnimation(.easeInOut(duration: 0.2)) {
                    contentRevealed = true
                }
            } else {
                contentRevealed = false
                revealContent(after: 0.22)
            }
        }
        .statusBarHidden(true)
    }

    private func revealContent(after delay: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                contentRevealed = true
            }
        }
    }

    // Upload the book to iCloud and show the system invite sheet
    private func prepareShare() {
        guard let book = book, !isPreparingShare else { return }
        guard CloudBookManager.shared.isCloudAvailable else {
            shareError = "iCloud sharing isn't available in this build."
            return
        }
        isPreparingShare = true
        CloudBookManager.shared.share(book: book, store: store) { result in
            isPreparingShare = false
            switch result {
            case .success(let context):
                shareContext = context
            case .failure(let error):
                shareError = error.localizedDescription
            }
        }
    }

    private func shareFrame(_ shot: ShotMetadata) {
        let url = store.imageFileURL(for: shot)
        if FileManager.default.fileExists(atPath: url.path) {
            frameShare = FrameSharePayload(items: [url])
        } else if let image = store.image(for: shot) {
            frameShare = FrameSharePayload(items: [image])
        }
    }

    private func applyLensFX(_ fx: LensFXMode, to shot: ShotMetadata) {
        guard fxBusyShotID == nil else { return }
        fxBusyShotID = shot.id
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        store.applyLensFX(fx, to: shot) { ok in
            fxBusyShotID = nil
            if ok {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                // Keep lightbox on the same shot; revision bump refreshes pixels
                zoomedShot = store.shots.first(where: { $0.id == shot.id }) ?? shot
            } else {
                fxError = "The effect couldn’t be baked onto this frame."
            }
        }
    }

    private func clampPageAfterRemoval() {
        // Pages: 0 = contact sheet, 1...n = prints. Max index == shot count.
        let maxPage = bookShots.count
        if currentPage > maxPage {
            currentPage = maxPage
        }
    }

    @ViewBuilder
    private func pageContent(at index: Int) -> some View {
        let shots = bookShots
        if index == 0 {
            ContactSheetPage(store: store, shots: shots, accent: accent) { selected in
                currentPage = selected + 1
            }
        } else if index - 1 < shots.count {
            let shot = shots[index - 1]
            PrintPage(
                store: store,
                shot: shot,
                bookID: bookID,
                pageNumber: index,
                accent: accent,
                isApplyingFX: fxBusyShotID == shot.id,
                onZoom: { zoomedShot = shot },
                onShare: { shareFrame(shot) },
                onApplyFX: { fx in applyLensFX(fx, to: shot) },
                onRemoved: { clampPageAfterRemoval() }
            )
            .id("\(shot.id)-\(store.revision(for: shot))")
        } else {
            Color.clear
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Button(action: close) {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.5))
                        .frame(width: 34, height: 34)
                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                        .frame(width: 34, height: 34)
                    Image(systemName: "books.vertical")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(coverTitle)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .tracking(4)
                    .lineLimit(1)
                    .foregroundColor(.white.opacity(0.9))
                Text("FIELD BOOK  ·  \(bookShots.count) FRAME\(bookShots.count == 1 ? "" : "S")")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.35))
            }

            Spacer()

            // Invite people into this book (user books only — not the master roll).
            // Hidden on Shutter DEV / NoCloud builds where CKContainer isn't entitled.
            if book != nil, CloudBookManager.shared.isCloudAvailable {
                Button(action: prepareShare) {
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.5))
                            .frame(width: 34, height: 34)
                        Circle()
                            .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                            .frame(width: 34, height: 34)
                        if isPreparingShare {
                            ProgressView()
                                .scaleEffect(0.6)
                                .tint(.white.opacity(0.8))
                        } else {
                            Image(systemName: "person.crop.circle.badge.plus")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white.opacity(0.8))
                        }
                    }
                }
                .disabled(isPreparingShare)
                .padding(.trailing, 6)
            }

            Button(action: close) {
                Text("SHELF")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundColor(accent.opacity(0.9))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.45))
                            .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.5))
                    )
            }
        }
    }

    private func close() {
        if let onClose = onClose {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                contentRevealed = false
            }
            // Let the cover re-form before the shelf morph runs
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                onClose()
            }
        } else {
            dismiss()
        }
    }

    private var pageFooter: some View {
        HStack {
            Text(currentPage == 0 ? "INDEX" : "PAGE \(currentPage) / \(bookShots.count)")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(2)
                .foregroundColor(.white.opacity(0.4))

            Spacer()

            // Page position ticks
            HStack(spacing: 3) {
                ForEach(0...(min(bookShots.count, 24)), id: \.self) { i in
                    Rectangle()
                        .fill(i == pageTickIndex ? accent : Color.white.opacity(0.2))
                        .frame(width: i == pageTickIndex ? 2 : 1, height: i == pageTickIndex ? 8 : 5)
                }
            }
        }
    }

    // Collapse pages onto at most 25 ticks so the footer never overflows
    private var pageTickIndex: Int {
        let tickCount = min(bookShots.count, 24)
        guard bookShots.count > 0, tickCount > 0 else { return 0 }
        return Int(round(Double(currentPage) / Double(bookShots.count) * Double(tickCount)))
    }

    private var emptyBook: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: bookID == nil ? "camera.aperture" : "book.closed")
                .font(.system(size: 40, weight: .thin))
                .foregroundColor(.white.opacity(0.25))
            Text("NO FRAMES YET")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .tracking(3)
                .foregroundColor(.white.opacity(0.5))
            Text(bookID == nil
                 ? "Every shot you take is bound into this book"
                 : "Long-press frames in All Frames to add them here")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Spacer()
            Spacer()
        }
    }
}

// MARK: - Page Curl Container
// UIPageViewController with the classic page-curl transition, bridged so the
// book's pages physically turn. Swipe to flip, or tap near the page edges.
struct PageCurlView<Page: View>: UIViewControllerRepresentable {
    let pageCount: Int
    @Binding var currentPage: Int
    @ViewBuilder let pageBuilder: (Int) -> Page

    func makeUIViewController(context: Context) -> UIPageViewController {
        let pvc = UIPageViewController(transitionStyle: .pageCurl, navigationOrientation: .horizontal)
        pvc.dataSource = context.coordinator
        pvc.delegate = context.coordinator
        pvc.view.backgroundColor = .clear
        let start = min(max(currentPage, 0), max(pageCount - 1, 0))
        pvc.setViewControllers([context.coordinator.controller(for: start)], direction: .forward, animated: false)
        return pvc
    }

    func updateUIViewController(_ pvc: UIPageViewController, context: Context) {
        context.coordinator.parent = self

        guard pageCount > 0 else { return }

        let target = min(max(currentPage, 0), pageCount - 1)

        guard let visible = pvc.viewControllers?.first as? IndexedHostingController<Page> else {
            pvc.setViewControllers([context.coordinator.controller(for: target)],
                                   direction: .forward, animated: false)
            return
        }

        // Drop stale pages when the book shrinks (delete / remove from book)
        if visible.pageIndex >= pageCount {
            pvc.setViewControllers([context.coordinator.controller(for: target)],
                                   direction: .reverse, animated: false)
            if currentPage != target {
                DispatchQueue.main.async { self.currentPage = target }
            }
            return
        }

        if visible.pageIndex != target {
            // External page change (contact-sheet jump, deletion clamp)
            let direction: UIPageViewController.NavigationDirection =
                target >= visible.pageIndex ? .forward : .reverse
            pvc.setViewControllers([context.coordinator.controller(for: target)],
                                   direction: direction, animated: true)
        } else {
            // Same page - refresh its SwiftUI content in place
            visible.rootView = pageBuilder(visible.pageIndex)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
        var parent: PageCurlView

        init(parent: PageCurlView) {
            self.parent = parent
        }

        func controller(for index: Int) -> UIViewController {
            let host = IndexedHostingController(rootView: parent.pageBuilder(index), pageIndex: index)
            host.view.backgroundColor = .clear
            return host
        }

        func pageViewController(_ pageViewController: UIPageViewController,
                                viewControllerBefore viewController: UIViewController) -> UIViewController? {
            guard let host = viewController as? IndexedHostingController<Page>,
                  host.pageIndex > 0 else { return nil }
            return controller(for: host.pageIndex - 1)
        }

        func pageViewController(_ pageViewController: UIPageViewController,
                                viewControllerAfter viewController: UIViewController) -> UIViewController? {
            guard let host = viewController as? IndexedHostingController<Page>,
                  host.pageIndex < parent.pageCount - 1 else { return nil }
            return controller(for: host.pageIndex + 1)
        }

        func pageViewController(_ pageViewController: UIPageViewController,
                                didFinishAnimating finished: Bool,
                                previousViewControllers: [UIViewController],
                                transitionCompleted completed: Bool) {
            guard completed,
                  let visible = pageViewController.viewControllers?.first as? IndexedHostingController<Page> else { return }
            let index = visible.pageIndex
            DispatchQueue.main.async {
                self.parent.currentPage = index
            }
        }
    }
}

final class IndexedHostingController<Content: View>: UIHostingController<Content> {
    let pageIndex: Int

    init(rootView: Content, pageIndex: Int) {
        self.pageIndex = pageIndex
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}

// MARK: - Contact Sheet (index page)
struct ContactSheetPage: View {
    let store: GalleryStore
    let shots: [ShotMetadata]
    let accent: Color
    let onSelect: (Int) -> Void

    private let columns = [GridItem(.adaptive(minimum: 74), spacing: 8)]

    var body: some View {
        BookPage {
            VStack(alignment: .leading, spacing: 10) {
                Text("CONTACT SHEET")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(3)
                    .foregroundColor(.white.opacity(0.4))

                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(Array(shots.enumerated()), id: \.element.id) { index, shot in
                            Button(action: { onSelect(index) }) {
                                VStack(spacing: 3) {
                                    ZStack {
                                        Rectangle().fill(Color.black)
                                        if let thumb = store.thumbnail(for: shot) {
                                            Image(uiImage: thumb)
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                        }
                                    }
                                    .frame(height: 74)
                                    .clipped()
                                    .overlay(Rectangle().stroke(Color.white.opacity(0.12), lineWidth: 0.5))

                                    Text("Nº \(String(format: "%03d", index + 1))")
                                        .font(.system(size: 7, weight: .medium, design: .monospaced))
                                        .foregroundColor(accent.opacity(0.7))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
    }
}

// MARK: - Print Page (one mounted photo)
struct PrintPage: View {
    let store: GalleryStore
    let shot: ShotMetadata
    let bookID: UUID?
    let pageNumber: Int
    let accent: Color
    var isApplyingFX: Bool = false
    let onZoom: () -> Void
    var onShare: (() -> Void)? = nil
    var onApplyFX: ((LensFXMode) -> Void)? = nil
    let onRemoved: () -> Void

    private var currentBook: Book? { store.book(withID: bookID) }
    private var isPinned: Bool { store.isPinned(shot, in: currentBook) }

    var body: some View {
        BookPage {
            VStack(spacing: 0) {
                Spacer(minLength: 8)

                // The print, slightly tilted like it was mounted by hand
                ZStack {
                    MountedPrint(image: store.thumbnail(for: shot))
                        .aspectRatio(0.78, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .rotationEffect(.degrees(shot.printTilt))
                        .opacity(isApplyingFX ? 0.45 : 1)

                    if isApplyingFX {
                        VStack(spacing: 8) {
                            ProgressView()
                                .tint(accent)
                            Text("BAKING FX")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .tracking(2)
                                .foregroundColor(accent.opacity(0.85))
                        }
                    }
                }
                .onTapGesture { onZoom() }
                .contextMenu { printMenu }
                .disabled(isApplyingFX)

                Spacer(minLength: 14)

                caption

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 6)
        }
    }

    @ViewBuilder
    private var printMenu: some View {
        Button {
            onShare?()
        } label: {
            Label("Share frame", systemImage: "square.and.arrow.up")
        }

        if let onApplyFX = onApplyFX {
            Menu {
                ForEach(LensFXMode.pickerCases.filter { $0 != .none }, id: \.self) { fx in
                    Button {
                        onApplyFX(fx)
                    } label: {
                        if shot.lensFX == fx.name {
                            Label(fx.name, systemImage: "checkmark")
                        } else {
                            Text(fx.name)
                        }
                    }
                }
            } label: {
                Label("Apply Lens FX", systemImage: "wand.and.rays")
            }
        }

        Divider()

        if let book = currentBook {
            // Inside a book: pin and remove-from-book
            Button {
                withAnimation { store.togglePin(shot, in: book) }
            } label: {
                Label(isPinned ? "Unpin" : "Pin to front", systemImage: isPinned ? "pin.slash" : "pin")
            }

            Button(role: .destructive) {
                withAnimation { store.remove(shot, from: book) }
                onRemoved()
            } label: {
                Label("Remove from this book", systemImage: "minus.circle")
            }
        } else {
            // Master roll: add to books, or delete the frame everywhere
            if !store.books.isEmpty {
                Menu {
                    ForEach(store.books) { book in
                        Button {
                            store.add(shot, to: book)
                        } label: {
                            if store.contains(shot, book: book) {
                                Label(book.title, systemImage: "checkmark")
                            } else {
                                Text(book.title)
                            }
                        }
                    }
                } label: {
                    Label("Add to book", systemImage: "book.closed")
                }
            }

            Button(role: .destructive) {
                withAnimation { store.delete(shot) }
                onRemoved()
            } label: {
                Label("Delete frame", systemImage: "trash")
            }
        }
    }

    // Silver-pen caption under the print: the real shot data
    private var caption: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Text("Nº \(String(format: "%03d", pageNumber))")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(accent.opacity(0.85))
                if isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8))
                        .foregroundColor(accent.opacity(0.7))
                        .rotationEffect(.degrees(30))
                }
                Spacer()
                Text(Self.dateFormatter.string(from: shot.date).uppercased())
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.55))
            }

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5)

            HStack(spacing: 0) {
                captionCell("ISO", "\(shot.iso)")
                captionCell("SHUTTER", shot.shutter)
                captionCell("EV", String(format: "%+.1f", shot.ev))
                captionCell("LENS", "\(shot.focalLength)MM")
            }

            if shot.filmFilter != "None" || shot.lensFX != "None" {
                HStack(spacing: 6) {
                    if shot.filmFilter != "None" {
                        stampBadge(shot.filmFilter.uppercased())
                    }
                    if shot.lensFX != "None" {
                        stampBadge(shot.lensFX.uppercased())
                    }
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 10)
    }

    private func captionCell(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 7, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
            Text(value)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity)
    }

    // Little rubber-stamp style badge for film stock / FX
    private func stampBadge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .tracking(1)
            .foregroundColor(accent.opacity(0.75))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .stroke(accent.opacity(0.4), lineWidth: 1)
            )
            .rotationEffect(.degrees(-1.5))
    }

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "EEE d MMM yyyy · HH:mm"
        return df
    }()
}

// MARK: - Mounted Print (white-border print + corner mounts)
struct MountedPrint: View {
    let image: UIImage?

    var body: some View {
        ZStack {
            // The print itself: photo on white stock, heavier bottom border
            VStack(spacing: 0) {
                ZStack {
                    Rectangle().fill(Color.black)
                    if let image = image {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    }
                }
            }
            .padding(.top, 10)
            .padding(.horizontal, 10)
            .padding(.bottom, 26)
            .background(Color(white: 0.92))
            .shadow(color: .black.opacity(0.55), radius: 10, x: 0, y: 6)
            .overlay(alignment: .topLeading) { PhotoCorner(rotation: 0) }
            .overlay(alignment: .topTrailing) { PhotoCorner(rotation: 90) }
            .overlay(alignment: .bottomTrailing) { PhotoCorner(rotation: 180) }
            .overlay(alignment: .bottomLeading) { PhotoCorner(rotation: 270) }
        }
    }
}

// Classic album photo-corner mount
struct PhotoCorner: View {
    let rotation: Double

    var body: some View {
        Path { path in
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: 22, y: 0))
            path.addLine(to: CGPoint(x: 0, y: 22))
            path.closeSubpath()
        }
        .fill(
            LinearGradient(
                colors: [Color(white: 0.22), Color(white: 0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            Path { path in
                path.move(to: CGPoint(x: 22, y: 0))
                path.addLine(to: CGPoint(x: 0, y: 22))
            }
            .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
        )
        .frame(width: 22, height: 22)
        .rotationEffect(.degrees(rotation))
        .offset(x: rotation == 90 || rotation == 180 ? 4 : -4,
                y: rotation == 180 || rotation == 270 ? 4 : -4)
    }
}

// MARK: - Book Page (black paper with grain and binding crease)
struct BookPage<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            // Black paper
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(hex: "1b1b1b"))

            // Paper grain
            GrainTextureView(density: 0.012, opacity: 0.05)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            // Binding crease on the left edge
            HStack(spacing: 0) {
                LinearGradient(
                    colors: [Color.black.opacity(0.55), Color.clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 14)
                Spacer()
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Page edge highlight
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.07), lineWidth: 0.5)

            content
                .padding(16)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}

// MARK: - Lightbox (full-screen zoomable view)
struct Lightbox: View {
    let image: UIImage?
    var revision: Int = 0
    var accent: Color = DS.accent
    var isApplyingFX: Bool = false
    var onApplyFX: ((LensFXMode) -> Void)? = nil
    var onShare: (() -> Void)? = nil
    let onDismiss: () -> Void

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var showFXPicker = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .id("lightbox-\(revision)")
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = min(max(lastScale * value, 1.0), 5.0)
                            }
                            .onEnded { _ in
                                lastScale = scale
                            }
                    )
                    .opacity(isApplyingFX ? 0.4 : 1)
            } else {
                Text("FRAME UNAVAILABLE")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.4))
            }

            if isApplyingFX {
                VStack(spacing: 10) {
                    ProgressView()
                        .tint(accent)
                    Text("BAKING LENS FX")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(accent.opacity(0.9))
                }
            }

            VStack {
                HStack(spacing: 10) {
                    if onShare != nil {
                        lightboxButton(icon: "square.and.arrow.up") {
                            onShare?()
                        }
                    }
                    if onApplyFX != nil {
                        lightboxButton(icon: "wand.and.rays", accented: true) {
                            showFXPicker = true
                        }
                        .disabled(isApplyingFX)
                    }
                    Spacer()
                    lightboxButton(icon: "xmark", action: onDismiss)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                Spacer()

                if showFXPicker, let onApplyFX = onApplyFX {
                    lensFXTray(onApplyFX)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .onTapGesture {
            if showFXPicker {
                withAnimation(.easeOut(duration: 0.2)) { showFXPicker = false }
                return
            }
            if scale <= 1.01 { onDismiss() } else {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    scale = 1.0
                    lastScale = 1.0
                }
            }
        }
    }

    private func lightboxButton(icon: String, accented: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(accented ? 0.18 : 0.12))
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(accented ? accent : .white.opacity(0.9))
            }
        }
    }

    private func lensFXTray(_ onApplyFX: @escaping (LensFXMode) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LENS FX")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(3)
                .foregroundColor(.white.opacity(0.55))
                .padding(.horizontal, 4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(LensFXMode.pickerCases.filter { $0 != .none }, id: \.self) { fx in
                        Button {
                            showFXPicker = false
                            onApplyFX(fx)
                        } label: {
                            Text(fx.name.uppercased())
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .tracking(1)
                                .foregroundColor(.black)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 9)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(accent)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(hex: "141414").opacity(0.94))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 28)
    }
}

// MARK: - System share sheet
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
