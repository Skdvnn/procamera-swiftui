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

    private let directory: URL
    private let indexURL: URL
    private let booksURL: URL
    private var thumbCache = NSCache<NSString, UIImage>()

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        directory = docs.appendingPathComponent("PhotoBook", isDirectory: true)
        indexURL = directory.appendingPathComponent("index.json")
        booksURL = directory.appendingPathComponent("books.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
    }

    // MARK: Shots

    func add(image: UIImage, metadata: ShotMetadata) {
        // Write files off the main thread, then publish
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }

            if let data = image.jpegData(compressionQuality: 0.9) {
                try? data.write(to: self.imageURL(for: metadata.id))
            }
            if let thumb = Self.thumbnail(from: image, longEdge: 900),
               let thumbData = thumb.jpegData(compressionQuality: 0.8) {
                try? thumbData.write(to: self.thumbURL(for: metadata.id))
            }

            DispatchQueue.main.async {
                self.shots.append(metadata)
                self.saveIndex()
            }
        }
    }

    func delete(_ shot: ShotMetadata) {
        shots.removeAll { $0.id == shot.id }
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
        DispatchQueue.global(qos: .utility).async {
            try? FileManager.default.removeItem(at: imageURL)
            try? FileManager.default.removeItem(at: thumbURL)
        }
    }

    func image(for shot: ShotMetadata) -> UIImage? {
        UIImage(contentsOfFile: imageURL(for: shot.id).path)
    }

    // File locations, used by the CloudKit uploader to build CKAssets
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

    // MARK: Books

    func createBook(title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        books.append(Book(id: UUID(), title: trimmed, createdAt: Date(),
                          shotIDs: [], pinnedShotIDs: []))
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

// MARK: - Library (the bookshelf)
struct LibraryView: View {
    @ObservedObject var store: GalleryStore
    @ObservedObject private var cloud = CloudBookManager.shared
    @Environment(\.dismiss) private var dismiss

    @State private var route: BookRoute?
    @State private var openedSharedBook: CloudBookManager.SharedBookRef?
    @State private var showNewBook = false
    @State private var newBookTitle = ""

    private let accent = Color(red: 1.0, green: 0.85, blue: 0.35)
    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    enum BookRoute: Identifiable {
        case allFrames
        case book(UUID)

        var id: String {
            switch self {
            case .allFrames: return "all-frames"
            case .book(let id): return id.uuidString
            }
        }
    }

    var body: some View {
        ZStack {
            LeicaVulcaniteTexture(scale: 20, intensity: 0.8)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 16)

                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 14) {
                        // Master roll always comes first
                        BookCoverCard(
                            title: "ALL FRAMES",
                            count: store.shots.count,
                            coverImage: store.shots.last.flatMap { store.thumbnail(for: $0) },
                            accent: accent,
                            isMaster: true
                        )
                        .onTapGesture { route = .allFrames }

                        ForEach(store.books) { book in
                            BookCoverCard(
                                title: book.title.uppercased(),
                                count: book.shotIDs.count,
                                coverImage: store.coverShot(for: book).flatMap { store.thumbnail(for: $0) },
                                accent: accent,
                                isMaster: false
                            )
                            .onTapGesture { route = .book(book.id) }
                            .contextMenu {
                                Button(role: .destructive) {
                                    withAnimation { store.deleteBook(book) }
                                } label: {
                                    Label("Delete book (keeps frames)", systemImage: "trash")
                                }
                            }
                        }

                        NewBookCard(accent: accent)
                            .onTapGesture {
                                newBookTitle = ""
                                showNewBook = true
                            }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)

                    // Books other people invited you into
                    if !cloud.sharedBooks.isEmpty {
                        HStack {
                            Text("SHARED WITH ME")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .tracking(3)
                                .foregroundColor(.white.opacity(0.4))
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)

                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(cloud.sharedBooks) { ref in
                                BookCoverCard(
                                    title: ref.title.uppercased(),
                                    count: 0,
                                    coverImage: nil,
                                    accent: accent,
                                    isMaster: false,
                                    subtitleOverride: "SHARED BOOK"
                                )
                                .onTapGesture { openedSharedBook = ref }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                    }
                }
            }
        }
        .onAppear { cloud.refreshSharedBooks() }
        .fullScreenCover(item: $openedSharedBook) { ref in
            SharedBookView(bookRef: ref, store: store)
        }
        .fullScreenCover(item: $route) { route in
            switch route {
            case .allFrames:
                PhotoBookView(store: store, bookID: nil)
            case .book(let id):
                PhotoBookView(store: store, bookID: id)
            }
        }
        .alert("New Book", isPresented: $showNewBook) {
            TextField("Title (e.g. Big Sur Trip)", text: $newBookTitle)
            Button("Create") { store.createBook(title: newBookTitle) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Name your book, then long-press frames in All Frames to add them.")
        }
        .statusBarHidden(true)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("LIBRARY")
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .tracking(4)
                    .foregroundColor(.white.opacity(0.9))
                Text("\(store.books.count + 1) BOOKS  ·  \(store.shots.count) FRAMES")
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
}

// MARK: - Book Cover Card
struct BookCoverCard: View {
    let title: String
    let count: Int
    let coverImage: UIImage?
    let accent: Color
    let isMaster: Bool
    var subtitleOverride: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Cover photo as a tiny mounted print
            ZStack {
                Rectangle().fill(Color.black.opacity(0.4))
                if let coverImage = coverImage {
                    Image(uiImage: coverImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "camera.aperture")
                        .font(.system(size: 22, weight: .thin))
                        .foregroundColor(.white.opacity(0.2))
                }
            }
            .frame(height: 110)
            .clipped()
            .padding(6)
            .background(Color(white: 0.9))
            .padding(.top, 16)
            .padding(.horizontal, 22)
            .rotationEffect(.degrees(-1.2))
            .shadow(color: .black.opacity(0.5), radius: 6, x: 0, y: 4)

            Spacer(minLength: 10)

            // Embossed spine label
            VStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(2)
                    .lineLimit(1)
                    .foregroundColor(isMaster ? accent.opacity(0.85) : .white.opacity(0.75))
                Text(subtitleOverride ?? "\(count) FRAME\(count == 1 ? "" : "S")")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(.bottom, 14)
        }
        .frame(height: 196)
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(hex: "161616"))
                GrainTextureView(density: 0.01, opacity: 0.05)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
            }
        )
    }
}

// MARK: - New Book Card
struct NewBookCard: View {
    let accent: Color

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(accent.opacity(0.7))
            Text("NEW BOOK")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(2)
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(height: 196)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    Color.white.opacity(0.2),
                    style: StrokeStyle(lineWidth: 1, dash: [5, 5])
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Photo Book (one book's pages)
struct PhotoBookView: View {
    @ObservedObject var store: GalleryStore
    let bookID: UUID?
    @Environment(\.dismiss) private var dismiss

    @State private var currentPage = 0
    @State private var zoomedShot: ShotMetadata?
    @State private var shareContext: CloudBookManager.ShareContext?
    @State private var isPreparingShare = false
    @State private var shareError: String?

    private let accent = Color(red: 1.0, green: 0.85, blue: 0.35)

    private var book: Book? { store.book(withID: bookID) }

    private var bookShots: [ShotMetadata] {
        if let book = book { return store.shots(in: book) }
        return shotsIfMaster
    }

    private var shotsIfMaster: [ShotMetadata] {
        bookID == nil ? store.shots : []
    }

    var body: some View {
        ZStack {
            // Vulcanite album cover, same material as the camera body
            LeicaVulcaniteTexture(scale: 20, intensity: 0.8)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                if bookShots.isEmpty {
                    emptyBook
                } else {
                    // Page 0 is the contact-sheet index; then one print per page.
                    // Real page-curl transitions - swipe or tap the page edges.
                    PageCurlView(pageCount: bookShots.count + 1, currentPage: $currentPage) { index in
                        pageContent(at: index)
                    }

                    pageFooter
                        .padding(.horizontal, 24)
                        .padding(.bottom, 14)
                }
            }
        }
        .overlay {
            if let shot = zoomedShot {
                Lightbox(image: store.image(for: shot)) { zoomedShot = nil }
            }
        }
        .sheet(item: $shareContext) { context in
            CloudSharingSheet(share: context.share, container: context.container, title: context.title)
        }
        .alert("Couldn't share book", isPresented: Binding(
            get: { shareError != nil },
            set: { if !$0 { shareError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(shareError ?? "")
        }
        .statusBarHidden(true)
    }

    // Upload the book to iCloud and show the system invite sheet
    private func prepareShare() {
        guard let book = book, !isPreparingShare else { return }
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
                onZoom: { zoomedShot = shot },
                onRemoved: {
                    if currentPage > max(shots.count - 1, 0) {
                        currentPage = max(shots.count - 1, 0)
                    }
                }
            )
        } else {
            Color.clear
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text((book?.title ?? "ALL FRAMES").uppercased())
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

            // Invite people into this book (user books only, not the master roll)
            if book != nil {
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

            Button(action: { dismiss() }) {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.5))
                        .frame(width: 34, height: 34)
                    Circle()
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                        .frame(width: 34, height: 34)
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
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
            Image(systemName: "camera.aperture")
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

        guard let visible = pvc.viewControllers?.first as? IndexedHostingController<Page> else { return }

        let target = min(max(currentPage, 0), max(pageCount - 1, 0))
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
    let onZoom: () -> Void
    let onRemoved: () -> Void

    private var currentBook: Book? { store.book(withID: bookID) }
    private var isPinned: Bool { store.isPinned(shot, in: currentBook) }

    var body: some View {
        BookPage {
            VStack(spacing: 0) {
                Spacer(minLength: 8)

                // The print, slightly tilted like it was mounted by hand
                MountedPrint(image: store.thumbnail(for: shot))
                    .aspectRatio(0.78, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .rotationEffect(.degrees(shot.printTilt))
                    .onTapGesture { onZoom() }
                    .contextMenu { printMenu }

                Spacer(minLength: 14)

                caption

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 6)
        }
    }

    @ViewBuilder
    private var printMenu: some View {
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
    let onDismiss: () -> Void

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = min(max(lastScale * value, 1.0), 5.0)
                            }
                            .onEnded { _ in
                                lastScale = scale
                            }
                    )
            }

            VStack {
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        ZStack {
                            Circle().fill(Color.white.opacity(0.12)).frame(width: 34, height: 34)
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                    .padding(.trailing, 20)
                    .padding(.top, 16)
                }
                Spacer()
            }
        }
        .onTapGesture {
            if scale <= 1.01 { onDismiss() } else {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    scale = 1.0
                    lastScale = 1.0
                }
            }
        }
    }
}
