import SwiftUI
import CloudKit
import UIKit

// MARK: - Cloud Book Manager
// CloudKit-backed collaborative Field Books. The owner uploads a book into a
// custom zone in their private database and shares the book record; invitees
// see it via the shared database and (with write permission) add their own
// frames as child records.
final class CloudBookManager: ObservableObject {
    static let shared = CloudBookManager()
    static let containerID = "iCloud.com.skylardann.filmcam"

    private let container = CKContainer(identifier: CloudBookManager.containerID)
    private var privateDB: CKDatabase { container.privateCloudDatabase }
    private var sharedDB: CKDatabase { container.sharedCloudDatabase }
    private let zoneID = CKRecordZone.ID(zoneName: "FieldBooks", ownerName: CKCurrentUserDefaultName)

    // Books other people shared with me
    @Published var sharedBooks: [SharedBookRef] = []
    @Published var isUploading = false
    @Published var lastError: String?

    private let zoneLock = NSLock()
    private var _zoneReady = false
    private var zoneReady: Bool {
        get { zoneLock.lock(); defer { zoneLock.unlock() }; return _zoneReady }
        set { zoneLock.lock(); _zoneReady = newValue; zoneLock.unlock() }
    }
    private var uploadGeneration: Int = 0

    struct SharedBookRef: Identifiable, Equatable {
        let recordID: CKRecord.ID
        let title: String

        var id: String { recordID.zoneID.ownerName + "|" + recordID.recordName }
        var zoneID: CKRecordZone.ID { recordID.zoneID }

        static func == (lhs: SharedBookRef, rhs: SharedBookRef) -> Bool { lhs.id == rhs.id }
    }

    struct CloudShot: Identifiable {
        let metadata: ShotMetadata
        let thumb: UIImage?
        let recordID: CKRecord.ID

        var id: UUID { metadata.id }
    }

    struct ShareContext: Identifiable {
        let id = UUID()
        let share: CKShare
        let container: CKContainer
        let title: String
    }

    private init() {}

    // MARK: Owner: share a book

    // Creates (or finds) the cloud copy of the book, returns its CKShare for
    // UICloudSharingController, then uploads any missing frames in the background.
    func share(book: Book, store: GalleryStore, completion: @escaping (Result<ShareContext, Error>) -> Void) {
        let finish: (Result<ShareContext, Error>) -> Void = { result in
            DispatchQueue.main.async { completion(result) }
        }

        ensureZone { [weak self] zoneError in
            guard let self = self else { return }
            if let zoneError = zoneError { finish(.failure(zoneError)); return }

            let bookRecordID = CKRecord.ID(recordName: "book-\(book.id.uuidString)", zoneID: self.zoneID)

            self.privateDB.fetch(withRecordID: bookRecordID) { existing, _ in
                if let existing = existing, let shareRef = existing.share {
                    // Already shared before - reuse the existing share
                    self.privateDB.fetch(withRecordID: shareRef.recordID) { shareRecord, error in
                        if let share = shareRecord as? CKShare {
                            self.uploadMissingShots(for: book, bookRecordID: bookRecordID, store: store)
                            finish(.success(ShareContext(share: share, container: self.container, title: book.title)))
                        } else {
                            finish(.failure(error ?? CKError(.internalError)))
                        }
                    }
                    return
                }

                // First share: save the book root record together with its share
                let bookRecord = existing ?? CKRecord(recordType: "FieldBook", recordID: bookRecordID)
                bookRecord["title"] = book.title
                bookRecord["bookID"] = book.id.uuidString

                let share = CKShare(rootRecord: bookRecord)
                share[CKShare.SystemFieldKey.title] = book.title
                share.publicPermission = .none

                let op = CKModifyRecordsOperation(recordsToSave: [bookRecord, share], recordIDsToDelete: nil)
                op.savePolicy = .ifServerRecordUnchanged
                op.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success:
                        self.uploadMissingShots(for: book, bookRecordID: bookRecordID, store: store)
                        finish(.success(ShareContext(share: share, container: self.container, title: book.title)))
                    case .failure(let error):
                        finish(.failure(error))
                    }
                }
                self.privateDB.add(op)
            }
        }
    }

    // Upload the book's frames as child records, a few at a time.
    // Records that already exist on the server are skipped via the save policy.
    private func uploadMissingShots(for book: Book, bookRecordID: CKRecord.ID, store: GalleryStore) {
        let shots = store.shots(in: book)
        guard !shots.isEmpty else { return }

        uploadGeneration &+= 1
        let gen = uploadGeneration
        DispatchQueue.main.async { self.isUploading = true }

        let bookRecord = CKRecord(recordType: "FieldBook", recordID: bookRecordID)
        let records: [CKRecord] = shots.map { shot in
            let record = self.shotRecord(
                for: shot,
                zoneID: self.zoneID,
                imageURL: store.imageFileURL(for: shot),
                thumbURL: store.thumbFileURL(for: shot)
            )
            record.setParent(bookRecord)
            return record
        }

        uploadInChunks(records, to: privateDB, chunkSize: 4, generation: gen) {
            DispatchQueue.main.async { self.isUploading = false }
        }
    }

    private func uploadInChunks(_ records: [CKRecord], to database: CKDatabase,
                                chunkSize: Int, generation: Int, completion: @escaping () -> Void) {
        guard !records.isEmpty else { completion(); return }
        // Stop if a newer upload superseded us.
        guard generation == uploadGeneration else { completion(); return }

        let chunk = Array(records.prefix(chunkSize))
        let rest = Array(records.dropFirst(chunkSize))

        let op = CKModifyRecordsOperation(recordsToSave: chunk, recordIDsToDelete: nil)
        op.savePolicy = .ifServerRecordUnchanged
        op.qualityOfService = .userInitiated
        op.modifyRecordsResultBlock = { [weak self] result in
            guard let self else { completion(); return }
            if case .failure(let error) = result {
                if let ckError = error as? CKError {
                    // Partial failures (existing records) are expected — continue.
                    if ckError.code != .partialFailure {
                        // Hard failure — surface and abort.
                        DispatchQueue.main.async { self.lastError = error.localizedDescription }
                        completion()
                        return
                    }
                }
            }
            self.uploadInChunks(rest, to: database, chunkSize: chunkSize, generation: generation, completion: completion)
        }
        database.add(op)
    }

    // MARK: Invitee: accept and browse

    func acceptShare(metadata: CKShare.Metadata) {
        let op = CKAcceptSharesOperation(shareMetadatas: [metadata])
        op.acceptSharesResultBlock = { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.refreshSharedBooks()
                case .failure(let error):
                    self?.lastError = error.localizedDescription
                }
            }
        }
        container.add(op)
    }

    func refreshSharedBooks() {
        sharedDB.fetchAllRecordZones { [weak self] zones, error in
            guard let self = self else { return }
            guard let zones = zones, error == nil else { return }

            let lock = NSLock()
            var found: [SharedBookRef] = []
            let group = DispatchGroup()

            for zone in zones {
                group.enter()
                self.queryRecords(type: "FieldBook", zoneID: zone.zoneID, database: self.sharedDB) { records in
                    let refs = records.map { record -> SharedBookRef in
                        let title = record["title"] as? String ?? "Shared Book"
                        return SharedBookRef(recordID: record.recordID, title: title)
                    }
                    lock.lock()
                    found.append(contentsOf: refs)
                    lock.unlock()
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                self.sharedBooks = found.sorted { $0.title < $1.title }
            }
        }
    }

    func loadShots(for ref: SharedBookRef, completion: @escaping ([CloudShot]) -> Void) {
        queryRecords(type: "FieldShot", zoneID: ref.zoneID, database: sharedDB) { records in
            let shots = records.compactMap { self.cloudShot(from: $0) }
                .sorted { $0.metadata.date < $1.metadata.date }
            DispatchQueue.main.async { completion(shots) }
        }
    }

    // Contribute a frame from the local roll into a book shared with me
    func addShot(_ shot: ShotMetadata, from store: GalleryStore, to ref: SharedBookRef,
                 completion: @escaping (Error?) -> Void) {
        let record = shotRecord(
            for: shot,
            zoneID: ref.zoneID,
            imageURL: store.imageFileURL(for: shot),
            thumbURL: store.thumbFileURL(for: shot)
        )
        record.setParent(CKRecord(recordType: "FieldBook", recordID: ref.recordID))

        let op = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        op.savePolicy = .ifServerRecordUnchanged
        op.modifyRecordsResultBlock = { result in
            DispatchQueue.main.async {
                switch result {
                case .success: completion(nil)
                case .failure(let error): completion(error)
                }
            }
        }
        sharedDB.add(op)
    }

    // MARK: Record mapping

    private func shotRecord(for shot: ShotMetadata, zoneID: CKRecordZone.ID,
                            imageURL: URL, thumbURL: URL) -> CKRecord {
        let recordID = CKRecord.ID(recordName: "shot-\(shot.id.uuidString)", zoneID: zoneID)
        let record = CKRecord(recordType: "FieldShot", recordID: recordID)
        record["shotID"] = shot.id.uuidString
        record["date"] = shot.date
        record["iso"] = shot.iso
        record["shutter"] = shot.shutter
        record["aperture"] = Double(shot.aperture)
        record["ev"] = Double(shot.ev)
        record["filmFilter"] = shot.filmFilter
        record["lensFX"] = shot.lensFX
        record["focalLength"] = shot.focalLength
        if FileManager.default.fileExists(atPath: imageURL.path) {
            record["image"] = CKAsset(fileURL: imageURL)
        }
        if FileManager.default.fileExists(atPath: thumbURL.path) {
            record["thumb"] = CKAsset(fileURL: thumbURL)
        }
        return record
    }

    private func cloudShot(from record: CKRecord) -> CloudShot? {
        guard let idString = record["shotID"] as? String,
              let id = UUID(uuidString: idString),
              let date = record["date"] as? Date else { return nil }

        let metadata = ShotMetadata(
            id: id,
            date: date,
            iso: record["iso"] as? Int ?? 0,
            shutter: record["shutter"] as? String ?? "—",
            aperture: Float(record["aperture"] as? Double ?? 0),
            ev: Float(record["ev"] as? Double ?? 0),
            filmFilter: record["filmFilter"] as? String ?? "None",
            lensFX: record["lensFX"] as? String ?? "None",
            focalLength: record["focalLength"] as? Int ?? 24
        )

        // Read the thumb asset only — never fall back to full image for list display.
        var thumb: UIImage?
        if let asset = record["thumb"] as? CKAsset, let url = asset.fileURL {
            thumb = UIImage(contentsOfFile: url.path)
        }

        return CloudShot(metadata: metadata, thumb: thumb, recordID: record.recordID)
    }

    // MARK: Plumbing

    private func ensureZone(completion: @escaping (Error?) -> Void) {
        guard !zoneReady else { completion(nil); return }
        let op = CKModifyRecordZonesOperation(recordZonesToSave: [CKRecordZone(zoneID: zoneID)],
                                              recordZoneIDsToDelete: nil)
        op.modifyRecordZonesResultBlock = { [weak self] result in
            switch result {
            case .success:
                self?.zoneReady = true
                completion(nil)
            case .failure(let error):
                completion(error)
            }
        }
        privateDB.add(op)
    }

    private func queryRecords(type: String, zoneID: CKRecordZone.ID, database: CKDatabase,
                              collected: [CKRecord] = [], cursor: CKQueryOperation.Cursor? = nil,
                              completion: @escaping ([CKRecord]) -> Void) {
        let op: CKQueryOperation
        if let cursor = cursor {
            op = CKQueryOperation(cursor: cursor)
        } else {
            op = CKQueryOperation(query: CKQuery(recordType: type, predicate: NSPredicate(value: true)))
        }
        op.zoneID = zoneID

        var results = collected
        op.recordMatchedBlock = { _, result in
            if case .success(let record) = result {
                results.append(record)
            }
        }
        op.queryResultBlock = { [weak self] result in
            switch result {
            case .success(let nextCursor):
                if let nextCursor = nextCursor {
                    self?.queryRecords(type: type, zoneID: zoneID, database: database,
                                       collected: results, cursor: nextCursor, completion: completion)
                } else {
                    completion(results)
                }
            case .failure:
                completion(results)
            }
        }
        database.add(op)
    }
}

// MARK: - Cloud Sharing Sheet (system invite UI)
struct CloudSharingSheet: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    let title: String

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowPrivate, .allowReadWrite, .allowReadOnly]
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(title: title)
    }

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let title: String

        init(title: String) {
            self.title = title
        }

        func itemTitle(for csc: UICloudSharingController) -> String? { title }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            DispatchQueue.main.async {
                CloudBookManager.shared.lastError = error.localizedDescription
            }
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {}
        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {}
    }
}

// MARK: - Shared Book View (a book someone shared with me)
struct SharedBookView: View {
    let bookRef: CloudBookManager.SharedBookRef
    @ObservedObject var store: GalleryStore
    @Environment(\.dismiss) private var dismiss

    @State private var shots: [CloudBookManager.CloudShot] = []
    @State private var isLoading = true
    @State private var currentPage = 0
    @State private var zoomedShot: CloudBookManager.CloudShot?
    @State private var showAddPicker = false

    private let accent = Color(red: 1.0, green: 0.85, blue: 0.35)

    var body: some View {
        ZStack {
            LeicaVulcaniteTexture(scale: 20, intensity: 0.8)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                if isLoading {
                    Spacer()
                    ProgressView()
                        .tint(.white.opacity(0.6))
                    Text("DEVELOPING…")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .tracking(3)
                        .foregroundColor(.white.opacity(0.35))
                        .padding(.top, 12)
                    Spacer()
                } else if shots.isEmpty {
                    Spacer()
                    Text("NO FRAMES YET")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .tracking(3)
                        .foregroundColor(.white.opacity(0.5))
                    Text("Be the first to add one")
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                        .padding(.top, 6)
                    Button(action: { showAddPicker = true }) {
                        Text("ADD FRAMES")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .tracking(2)
                            .foregroundColor(.black)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(accent)
                            )
                    }
                    .padding(.top, 10)
                    Spacer()
                } else {
                    PageCurlView(pageCount: shots.count + 1, currentPage: $currentPage) { index in
                        pageContent(at: index)
                    }

                    HStack {
                        Text(currentPage == 0 ? "INDEX" : "PAGE \(currentPage) / \(shots.count)")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .tracking(2)
                            .foregroundColor(.white.opacity(0.4))
                        Spacer()
                        Text("SHARED BOOK")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .tracking(2)
                            .foregroundColor(accent.opacity(0.6))
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 14)
                }
            }
        }
        .overlay {
            if let shot = zoomedShot {
                Lightbox(image: shot.thumb) { zoomedShot = nil }
            }
        }
        .sheet(isPresented: $showAddPicker) {
            AddFramesPicker(store: store, bookRef: bookRef) {
                reload()
            }
        }
        .onAppear { reload() }
        .statusBarHidden(true)
    }

    @ViewBuilder
    private func pageContent(at index: Int) -> some View {
        if index == 0 {
            CloudContactSheetPage(shots: shots, accent: accent) { i in
                currentPage = i + 1
            }
        } else if index - 1 < shots.count {
            let shot = shots[index - 1]
            CloudPrintPage(shot: shot, pageNumber: index, accent: accent) {
                zoomedShot = shot
            }
        } else {
            Color.clear
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(bookRef.title.uppercased())
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .tracking(4)
                    .lineLimit(1)
                    .foregroundColor(.white.opacity(0.9))
                Text("SHARED  ·  \(shots.count) FRAME\(shots.count == 1 ? "" : "S")")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.white.opacity(0.35))
            }

            Spacer()

            headerButton(icon: "plus") {
                showAddPicker = true
            }

            headerButton(icon: "arrow.clockwise") {
                reload()
            }

            headerButton(icon: "chevron.left") {
                dismiss()
            }
        }
    }

    private func headerButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.5))
                    .frame(width: 34, height: 34)
                Circle()
                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
            }
        }
    }

    private func reload() {
        isLoading = true
        CloudBookManager.shared.loadShots(for: bookRef) { loaded in
            shots = loaded
            isLoading = false
            if currentPage > shots.count { currentPage = shots.count }
        }
    }
}

// MARK: - Cloud Contact Sheet (matches local proof-sheet index)
struct CloudContactSheetPage: View {
    let shots: [CloudBookManager.CloudShot]
    let accent: Color
    let onSelect: (Int) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(hex: "181614"))
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CONTACT SHEET")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .tracking(2.5)
                            .foregroundColor(.white.opacity(0.88))
                        Text("TAP A FRAME TO OPEN  ·  \(shots.count) TOTAL")
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .tracking(1.2)
                            .foregroundColor(.white.opacity(0.35))
                    }
                    Spacer()
                    Text("SHARED")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundColor(accent.opacity(0.7))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .stroke(accent.opacity(0.35), lineWidth: 1)
                        )
                }
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 12)

                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 0.5)
                    .padding(.horizontal, 14)

                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(Array(shots.enumerated()), id: \.element.id) { i, shot in
                            Button(action: { onSelect(i) }) {
                                VStack(spacing: 0) {
                                    ZStack {
                                        Color.black
                                        if let thumb = shot.thumb {
                                            Image(uiImage: thumb)
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                        }
                                    }
                                    .aspectRatio(0.8, contentMode: .fit)
                                    .clipped()
                                    .padding(5)
                                    .background(Color(white: 0.9))
                                    .shadow(color: .black.opacity(0.35), radius: 3, y: 2)

                                    HStack {
                                        Text("Nº \(String(format: "%03d", i + 1))")
                                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                            .foregroundColor(accent.opacity(0.8))
                                        Spacer()
                                    }
                                    .padding(.top, 6)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 14)
                    .padding(.bottom, 18)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }
}

// MARK: - Cloud Print Page (photo-first leaf — matches local books)
struct CloudPrintPage: View {
    let shot: CloudBookManager.CloudShot
    let pageNumber: Int
    let accent: Color
    let onZoom: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            GeometryReader { geo in
                ZStack {
                    Color(hex: "121212")
                    if let image = shot.thumb {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { onZoom() }

            caption
                .padding(.horizontal, 14)
                .padding(.top, 28)
                .padding(.bottom, 12)
                .background(
                    LinearGradient(
                        colors: [Color.black.opacity(0.82), Color.black.opacity(0.35), Color.clear],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
    }

    private var caption: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Nº \(String(format: "%03d", pageNumber))")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(accent.opacity(0.85))
                Spacer()
                Text(Self.dateFormatter.string(from: shot.metadata.date).uppercased())
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(1)
                    .foregroundColor(.white.opacity(0.55))
            }

            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(height: 0.5)

            HStack(spacing: 0) {
                captionCell("ISO", "\(shot.metadata.iso)")
                captionCell("SHUTTER", shot.metadata.shutter)
                captionCell("EV", String(format: "%+.1f", shot.metadata.ev))
                captionCell("LENS", "\(shot.metadata.focalLength)MM")
            }
        }
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

    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "EEE d MMM yyyy · HH:mm"
        return df
    }()
}

// MARK: - Add Frames Picker (contribute from the local roll)
struct AddFramesPicker: View {
    @ObservedObject var store: GalleryStore
    let bookRef: CloudBookManager.SharedBookRef
    let onUploaded: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var selected: Set<UUID> = []
    @State private var isUploading = false

    private let accent = Color(red: 1.0, green: 0.85, blue: 0.35)
    private let columns = [GridItem(.adaptive(minimum: 90), spacing: 6)]

    var body: some View {
        ZStack {
            Color(hex: "141414").ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Text("ADD FRAMES")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .tracking(3)
                        .foregroundColor(.white.opacity(0.9))
                    Spacer()
                    Button("Cancel") { dismiss() }
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

                ScrollView {
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(store.shots) { shot in
                            Button {
                                if selected.contains(shot.id) {
                                    selected.remove(shot.id)
                                } else {
                                    selected.insert(shot.id)
                                }
                            } label: {
                                ZStack(alignment: .topTrailing) {
                                    ZStack {
                                        Rectangle().fill(Color.black)
                                        if let thumb = store.thumbnail(for: shot) {
                                            Image(uiImage: thumb)
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                        }
                                    }
                                    .frame(height: 90)
                                    .clipped()

                                    if selected.contains(shot.id) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 16))
                                            .foregroundColor(accent)
                                            .padding(4)
                                    }
                                }
                                .overlay(
                                    Rectangle().stroke(
                                        selected.contains(shot.id) ? accent.opacity(0.8) : Color.white.opacity(0.1),
                                        lineWidth: selected.contains(shot.id) ? 1.5 : 0.5
                                    )
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 20)
                }

                Button(action: upload) {
                    HStack(spacing: 8) {
                        if isUploading {
                            ProgressView().tint(.black)
                        }
                        Text(isUploading ? "UPLOADING…" : "ADD \(selected.count) TO BOOK")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .tracking(2)
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(selected.isEmpty || isUploading ? accent.opacity(0.3) : accent)
                    )
                }
                .disabled(selected.isEmpty || isUploading)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
        }
    }

    private func upload() {
        isUploading = true
        let shotsToSend = store.shots.filter { selected.contains($0.id) }
        var remaining = shotsToSend.count

        guard remaining > 0 else { isUploading = false; return }

        for shot in shotsToSend {
            CloudBookManager.shared.addShot(shot, from: store, to: bookRef) { _ in
                remaining -= 1
                if remaining == 0 {
                    isUploading = false
                    onUploaded()
                    dismiss()
                }
            }
        }
    }
}
