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

    var frameNumber: String {
        String(format: "%02d", (abs(id.uuidString.unicodeScalars.reduce(0) { $0 + Int($1.value) }) % 100))
    }
}

// MARK: - Gallery Store
// App-side persistence: full-res JPEG + small thumbnail per shot, plus a
// JSON index of metadata, all in Documents/PhotoBook.
final class GalleryStore: ObservableObject {
    @Published private(set) var shots: [ShotMetadata] = []

    private let directory: URL
    private let indexURL: URL
    private var thumbCache = NSCache<NSString, UIImage>()

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        directory = docs.appendingPathComponent("PhotoBook", isDirectory: true)
        indexURL = directory.appendingPathComponent("index.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
    }

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

    func thumbnail(for shot: ShotMetadata) -> UIImage? {
        let key = shot.id.uuidString as NSString
        if let cached = thumbCache.object(forKey: key) { return cached }
        guard let thumb = UIImage(contentsOfFile: thumbURL(for: shot.id).path)
                ?? image(for: shot) else { return nil }
        thumbCache.setObject(thumb, forKey: key)
        return thumb
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

    private func load() {
        guard let data = try? Data(contentsOf: indexURL),
              let saved = try? JSONDecoder().decode([ShotMetadata].self, from: data) else { return }
        shots = saved
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

// MARK: - Photo Book (Field Book)
struct PhotoBookView: View {
    @ObservedObject var store: GalleryStore
    @Environment(\.dismiss) private var dismiss

    @State private var currentPage = 0
    @State private var zoomedShot: ShotMetadata?

    private let accent = Color(red: 1.0, green: 0.85, blue: 0.35)

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

                if store.shots.isEmpty {
                    emptyBook
                } else {
                    // Page 0 is the contact-sheet index; then one print per page
                    TabView(selection: $currentPage) {
                        ContactSheetPage(store: store, accent: accent) { index in
                            withAnimation { currentPage = index + 1 }
                        }
                        .tag(0)

                        ForEach(Array(store.shots.enumerated()), id: \.element.id) { index, shot in
                            PrintPage(
                                store: store,
                                shot: shot,
                                pageNumber: index + 1,
                                accent: accent,
                                onZoom: { zoomedShot = shot },
                                onDelete: {
                                    withAnimation { store.delete(shot) }
                                    if currentPage > store.shots.count { currentPage = store.shots.count }
                                }
                            )
                            .tag(index + 1)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))

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
        .statusBarHidden(true)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text("FIELD BOOK")
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .tracking(4)
                    .foregroundColor(.white.opacity(0.9))
                Text("VOL. I  ·  \(store.shots.count) FRAME\(store.shots.count == 1 ? "" : "S")")
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

    private var pageFooter: some View {
        HStack {
            Text(currentPage == 0 ? "INDEX" : "PAGE \(currentPage) / \(store.shots.count)")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .tracking(2)
                .foregroundColor(.white.opacity(0.4))

            Spacer()

            // Page position ticks
            HStack(spacing: 3) {
                ForEach(0...(min(store.shots.count, 24)), id: \.self) { i in
                    Rectangle()
                        .fill(i == pageTickIndex ? accent : Color.white.opacity(0.2))
                        .frame(width: i == pageTickIndex ? 2 : 1, height: i == pageTickIndex ? 8 : 5)
                }
            }
        }
    }

    // Collapse pages onto at most 25 ticks so the footer never overflows
    private var pageTickIndex: Int {
        let tickCount = min(store.shots.count, 24)
        guard store.shots.count > 0, tickCount > 0 else { return 0 }
        return Int(round(Double(currentPage) / Double(store.shots.count) * Double(tickCount)))
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
            Text("Every shot you take is bound into this book")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundColor(.white.opacity(0.3))
            Spacer()
            Spacer()
        }
    }
}

// MARK: - Contact Sheet (index page)
struct ContactSheetPage: View {
    @ObservedObject var store: GalleryStore
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
                        ForEach(Array(store.shots.enumerated()), id: \.element.id) { index, shot in
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
    let pageNumber: Int
    let accent: Color
    let onZoom: () -> Void
    let onDelete: () -> Void

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
                    .contextMenu {
                        Button(role: .destructive, action: onDelete) {
                            Label("Remove from book", systemImage: "trash")
                        }
                    }

                Spacer(minLength: 14)

                caption

                Spacer(minLength: 8)
            }
            .padding(.horizontal, 6)
        }
    }

    // Silver-pen caption under the print: the real shot data
    private var caption: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Nº \(String(format: "%03d", pageNumber))")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(accent.opacity(0.85))
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
