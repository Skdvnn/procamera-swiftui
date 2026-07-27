import Foundation
import SwiftUI
import UIKit
import Photos

// MARK: - Deep links (Shortcuts, widgets, quick actions)

enum ShutterDeepLink: Equatable {
    case openCamera
    case capture
    case darkroom
    case fieldBook
    case look(film: String?, fx: String?)
    /// SCENE preset — Auto / Street / Night / Studio / Film (Build 105).
    case scene(mode: String)
    case timer(seconds: Int)
    case peaking(Bool)
    case flip

    static let schemes = ["shuttercam", "procamera"]

    static func parse(_ url: URL) -> ShutterDeepLink? {
        guard let scheme = url.scheme?.lowercased(), schemes.contains(scheme) else { return nil }
        let host = (url.host ?? "").lowercased()
        let path = url.path.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let route = host.isEmpty ? path : (path.isEmpty ? host : "\(host)/\(path)")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func q(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }

        switch route {
        case "", "open", "camera", "shoot":
            return .openCamera
        case "capture", "shutter":
            return .capture
        case "darkroom", "cull", "library":
            return .darkroom
        case "fieldbook", "books", "book":
            return .fieldBook
        case "look", "recipe":
            return .look(film: q("film"), fx: q("fx"))
        case "scene", "mode":
            let raw = (q("mode") ?? q("name") ?? "auto").lowercased()
            return .scene(mode: raw)
        case "timer":
            let sec = Int(q("seconds") ?? q("s") ?? "3") ?? 3
            // Invalid values → off (not silently 3s).
            let clamped = [0, 3, 10].contains(sec) ? sec : 0
            return .timer(seconds: clamped)
        case "peaking":
            let raw = (q("on") ?? "1").lowercased()
            let on = ["1", "true", "yes", "on"].contains(raw)
            return .peaking(on)
        case "flip":
            return .flip
        default:
            return .openCamera
        }
    }

    var url: URL {
        switch self {
        case .openCamera:
            return URL(string: "shuttercam://camera")!
        case .capture:
            return URL(string: "shuttercam://capture")!
        case .darkroom:
            return URL(string: "shuttercam://darkroom")!
        case .fieldBook:
            return URL(string: "shuttercam://fieldbook")!
        case .look(let film, let fx):
            var c = URLComponents(string: "shuttercam://look")!
            var items: [URLQueryItem] = []
            if let film { items.append(URLQueryItem(name: "film", value: film)) }
            if let fx { items.append(URLQueryItem(name: "fx", value: fx)) }
            c.queryItems = items.isEmpty ? nil : items
            return c.url!
        case .scene(let mode):
            return URL(string: "shuttercam://scene?mode=\(mode)")!
        case .timer(let seconds):
            return URL(string: "shuttercam://timer?seconds=\(seconds)")!
        case .peaking(let on):
            return URL(string: "shuttercam://peaking?on=\(on ? 1 : 0)")!
        case .flip:
            return URL(string: "shuttercam://flip")!
        }
    }
}

extension Notification.Name {
    static let shutterDeepLink = Notification.Name("shutter.deeplink")
    static let shutterHardwareShutter = Notification.Name("shutter.hardwareShutter")
    static let shutterOpenFieldBook = Notification.Name("shutter.openFieldBook")
}

/// Posts deep links immediately once a subscriber is ready; otherwise queues them
/// so cold-start shortcuts/widgets aren't dropped before ContentView mounts.
enum ShutterDeepLinkCenter {
    private static let lock = NSLock()
    private static var pending: [ShutterDeepLink] = []
    private static var isReceiving = false

    static func post(_ link: ShutterDeepLink) {
        lock.lock()
        if isReceiving {
            lock.unlock()
            NotificationCenter.default.post(
                name: .shutterDeepLink,
                object: nil,
                userInfo: ["link": link]
            )
        } else {
            pending.append(link)
            lock.unlock()
        }
    }

    static func post(url: URL) {
        guard let link = ShutterDeepLink.parse(url) else { return }
        post(link)
    }

    /// Call from ContentView once `.onReceive` is live (prefer next main turn).
    static func beginReceiving() {
        lock.lock()
        isReceiving = true
        let queued = pending
        pending.removeAll()
        lock.unlock()
        for link in queued {
            NotificationCenter.default.post(
                name: .shutterDeepLink,
                object: nil,
                userInfo: ["link": link]
            )
        }
    }

    /// Call from ContentView.onDisappear so links queue again across remounts.
    static func endReceiving() {
        lock.lock()
        isReceiving = false
        lock.unlock()
    }

    /// Test helper — reset queue/subscriber state between stress cases.
    static func resetForTests() {
        lock.lock()
        pending.removeAll()
        isReceiving = false
        lock.unlock()
    }
}

/// Shared App Group for widgets ↔ app (looks, last mode, recent thumbs).
enum ShutterAppGroup {
    static let id = "group.com.skylardann.filmcam"
    /// Enough frames for a contact sheet on the large widget (Build 83).
    static let recentThumbnailSlots = 6

    static var defaults: UserDefaults {
        UserDefaults(suiteName: id) ?? .standard
    }

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
    }

    /// `widget-recents/recent-0.jpg` (newest) … `recent-1.jpg`
    static var recentsDirectoryURL: URL? {
        guard let base = containerURL else { return nil }
        let dir = base.appendingPathComponent("widget-recents", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Widget look payload: `"Film Name|FX Name"` (FX may be empty / None).
    static func encodeLook(film: String, fx: String?) -> String {
        let f = film.isEmpty ? "None" : film
        let x = (fx?.isEmpty == false) ? fx! : "None"
        return "\(f)|\(x)"
    }

    static func decodeLook(_ raw: String) -> (film: String, fx: String?) {
        let parts = raw.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let film = parts.first.map(String.init) ?? raw
        let fx = parts.count > 1 ? String(parts[1]) : nil
        let cleanFX = (fx == nil || fx == "None" || fx == "—") ? nil : fx
        return (film, cleanFX)
    }

    /// Metadata sidecar next to each widget thumb (Build 74).
    struct WidgetRecentMeta: Codable, Equatable {
        var shotID: String
        var capturedAt: TimeInterval
        var iso: Int
        var shutter: String
        var aperture: Float
        var filmFilter: String
        var lensFX: String
        var focalLength: Int
        /// "unmarked" | "keep" | "reject"
        var mark: String

        var exposureLine: String {
            var parts: [String] = []
            if !shutter.isEmpty { parts.append(shutter) }
            if iso > 0 { parts.append("ISO \(iso)") }
            if aperture > 0.5 { parts.append(String(format: "ƒ%.1f", aperture)) }
            return parts.joined(separator: " · ")
        }

        var relativeTime: String {
            let date = Date(timeIntervalSince1970: capturedAt)
            let secs = Int(Date().timeIntervalSince(date))
            if secs < 60 { return "NOW" }
            if secs < 3600 { return "\(secs / 60)m" }
            if secs < 86_400 { return "\(secs / 3600)h" }
            return "\(secs / 86_400)d"
        }
    }

    struct WidgetRecentFrame {
        let image: UIImage
        let meta: WidgetRecentMeta?
    }

    static let statsKey = "widget.stats"

    static func saveStats(_ stats: ShutterStats) {
        guard let data = try? JSONEncoder().encode(stats) else { return }
        defaults.set(data, forKey: statsKey)
    }

    static func loadStats() -> ShutterStats {
        if let data = defaults.data(forKey: statsKey),
           let stats = try? JSONDecoder().decode(ShutterStats.self, from: data),
           stats.hasHistory {
            return stats
        }
        // App Group empty or Debug without entitlements — derive from Photos.
        if let photos = loadPhotosFallbackStats() { return photos }
        if let data = defaults.data(forKey: statsKey),
           let stats = try? JSONDecoder().decode(ShutterStats.self, from: data) {
            return stats
        }
        return ShutterStats()
    }

    /// Downsample + persist newest still for widget stacks (App Group).
    static func pushRecentThumbnail(_ image: UIImage, meta: WidgetRecentMeta? = nil) {
        guard let dir = recentsDirectoryURL else { return }
        let fm = FileManager.default
        // Shift every slot down one: recent-(n-2) → recent-(n-1), oldest falls off.
        let last = recentThumbnailSlots - 1
        try? fm.removeItem(at: dir.appendingPathComponent("recent-\(last).jpg"))
        try? fm.removeItem(at: dir.appendingPathComponent("recent-\(last).json"))
        for slot in stride(from: last - 1, through: 0, by: -1) {
            for ext in ["jpg", "json"] {
                let from = dir.appendingPathComponent("recent-\(slot).\(ext)")
                let to = dir.appendingPathComponent("recent-\(slot + 1).\(ext)")
                if fm.fileExists(atPath: from.path) {
                    try? fm.moveItem(at: from, to: to)
                }
            }
        }
        let newest = dir.appendingPathComponent("recent-0.jpg")
        let newestJSON = dir.appendingPathComponent("recent-0.json")
        let thumb = image.shutterWidgetThumbnail(maxSide: 360)
        guard let data = thumb.jpegData(compressionQuality: 0.78) else { return }
        try? data.write(to: newest, options: .atomic)
        if let meta, let encoded = try? JSONEncoder().encode(meta) {
            try? encoded.write(to: newestJSON, options: .atomic)
        } else {
            try? fm.removeItem(at: newestJSON)
        }
        defaults.set(Date().timeIntervalSince1970, forKey: "widget.recentsUpdatedAt")
    }

    /// Replace both slots atomically (unculled rebuild after cull — Build 74).
    static func rebuildRecentFrames(_ frames: [WidgetRecentFrame]) {
        guard let dir = recentsDirectoryURL else { return }
        let fm = FileManager.default
        for i in 0..<recentThumbnailSlots {
            try? fm.removeItem(at: dir.appendingPathComponent("recent-\(i).jpg"))
            try? fm.removeItem(at: dir.appendingPathComponent("recent-\(i).json"))
        }
        // Write newest-first: frames[0] → recent-0
        for (i, frame) in frames.prefix(recentThumbnailSlots).enumerated() {
            let thumb = frame.image.shutterWidgetThumbnail(maxSide: 360)
            guard let data = thumb.jpegData(compressionQuality: 0.78) else { continue }
            try? data.write(
                to: dir.appendingPathComponent("recent-\(i).jpg"),
                options: .atomic
            )
            if let meta = frame.meta, let encoded = try? JSONEncoder().encode(meta) {
                try? encoded.write(
                    to: dir.appendingPathComponent("recent-\(i).json"),
                    options: .atomic
                )
            }
        }
        defaults.set(Date().timeIntervalSince1970, forKey: "widget.recentsUpdatedAt")
    }

    /// Newest first. Empty when the user hasn't shot yet (or App Group unavailable).
    static func loadRecentThumbnails(max: Int = recentThumbnailSlots) -> [UIImage] {
        loadRecentFrames(max: max).map(\.image)
    }

    /// Newest first with sidecar metadata when present.
    /// Prefers the App Group sheet written by the host app; when that container
    /// is empty (Cmd+R Debug has no App Groups, or a fresh install), falls back
    /// to the Photos "Shutter" album / recent camera-roll stills so the widget
    /// still shows the user's real frames.
    static func loadRecentFrames(max: Int = recentThumbnailSlots) -> [WidgetRecentFrame] {
        let local = loadAppGroupFrames(max: max)
        if !local.isEmpty { return local }
        return loadPhotosFallbackFrames(max: max)
    }

    /// App Group only — no Photos hop. Used by the stats reconciler.
    static func loadAppGroupFrames(max: Int = recentThumbnailSlots) -> [WidgetRecentFrame] {
        guard let dir = recentsDirectoryURL else { return [] }
        var out: [WidgetRecentFrame] = []
        for i in 0..<max {
            let url = dir.appendingPathComponent("recent-\(i).jpg")
            guard let data = try? Data(contentsOf: url),
                  let img = UIImage(data: data) else { continue }
            var meta: WidgetRecentMeta?
            let jsonURL = dir.appendingPathComponent("recent-\(i).json")
            if let jdata = try? Data(contentsOf: jsonURL) {
                meta = try? JSONDecoder().decode(WidgetRecentMeta.self, from: jdata)
            }
            // Skip rejects that somehow lingered in the App Group.
            if let mark = meta?.mark, mark == "reject" { continue }
            out.append(WidgetRecentFrame(image: img, meta: meta))
        }
        return out
    }

    /// Whether the App Group container is actually usable from this process.
    /// Debug entitlements leave this false so widgets must use Photos.
    static var appGroupAvailable: Bool {
        containerURL != nil
            && UserDefaults(suiteName: id) != nil
    }

    // MARK: Photos fallback (Debug / empty App Group)

    /// Pull recent stills from the Photos "Shutter" album, or the camera roll
    /// when that album hasn't been seeded yet. Synchronous — WidgetKit timeline
    /// providers run off the main actor and need the images before returning.
    static func loadPhotosFallbackFrames(max: Int = recentThumbnailSlots) -> [WidgetRecentFrame] {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return [] }

        let assets = fetchShutterPhotoAssets(limit: max)
        guard !assets.isEmpty else { return [] }

        var out: [WidgetRecentFrame] = []
        let manager = PHImageManager.default()
        let opts = PHImageRequestOptions()
        opts.deliveryMode = .fastFormat
        opts.resizeMode = .fast
        opts.isNetworkAccessAllowed = false
        opts.isSynchronous = true

        let target = CGSize(width: 360, height: 360)
        for asset in assets {
            var image: UIImage?
            manager.requestImage(
                for: asset,
                targetSize: target,
                contentMode: .aspectFill,
                options: opts
            ) { result, _ in
                image = result
            }
            guard let image else { continue }
            let captured = asset.creationDate ?? Date()
            let meta = WidgetRecentMeta(
                shotID: asset.localIdentifier,
                capturedAt: captured.timeIntervalSince1970,
                iso: 0,
                shutter: "",
                aperture: 0,
                filmFilter: "None",
                lensFX: "None",
                focalLength: 0,
                mark: asset.isFavorite ? "keep" : "unmarked"
            )
            out.append(WidgetRecentFrame(image: image, meta: meta))
            if out.count >= max { break }
        }
        return out
    }

    /// Prefer the dedicated Shutter album; otherwise recent camera-roll stills.
    static func fetchShutterPhotoAssets(limit: Int) -> [PHAsset] {
        let opts = PHFetchOptions()
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        opts.fetchLimit = limit

        // Named album first — only contains frames this app dual-wrote.
        let albums = PHAssetCollection.fetchAssetCollections(
            with: .album, subtype: .any, options: nil
        )
        var shutterAlbum: PHAssetCollection?
        albums.enumerateObjects { collection, _, stop in
            if collection.localizedTitle == "Shutter" {
                shutterAlbum = collection
                stop.pointee = true
            }
        }
        if let shutterAlbum {
            let result = PHAsset.fetchAssets(in: shutterAlbum, options: opts)
            if result.count > 0 {
                var assets: [PHAsset] = []
                result.enumerateObjects { asset, _, _ in
                    if asset.mediaType == .image { assets.append(asset) }
                }
                if !assets.isEmpty { return assets }
            }
        }

        // Camera roll fallback so a brand-new install still fills the sheet
        // before the first cull export creates the album.
        opts.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        let recent = PHAsset.fetchAssets(with: .image, options: opts)
        var assets: [PHAsset] = []
        recent.enumerateObjects { asset, _, stop in
            assets.append(asset)
            if assets.count >= limit { stop.pointee = true }
        }
        return assets
    }

    /// Stats derived from Photos when the App Group blob is missing.
    static func loadPhotosFallbackStats() -> ShutterStats? {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return nil }

        // A wider window than the contact sheet so the week histogram is honest.
        let opts = PHFetchOptions()
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        opts.fetchLimit = 400
        opts.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)

        var entries: [ShutterStats.Entry] = []
        let albums = PHAssetCollection.fetchAssetCollections(
            with: .album, subtype: .any, options: nil
        )
        var shutterAlbum: PHAssetCollection?
        albums.enumerateObjects { collection, _, stop in
            if collection.localizedTitle == "Shutter" {
                shutterAlbum = collection
                stop.pointee = true
            }
        }

        let result: PHFetchResult<PHAsset>
        if let shutterAlbum {
            let albumOpts = PHFetchOptions()
            albumOpts.sortDescriptors = opts.sortDescriptors
            albumOpts.fetchLimit = 400
            result = PHAsset.fetchAssets(in: shutterAlbum, options: albumOpts)
        } else {
            result = PHAsset.fetchAssets(with: .image, options: opts)
        }

        result.enumerateObjects { asset, _, stop in
            guard let date = asset.creationDate else { return }
            entries.append(
                ShutterStats.Entry(
                    date: date,
                    film: "",
                    mark: asset.isFavorite ? "keep" : "unmarked"
                )
            )
            if entries.count >= 400 { stop.pointee = true }
        }
        guard !entries.isEmpty else { return nil }
        return ShutterStats.compute(entries)
    }
}

// MARK: - Shooting stats for widgets (Build 83)

/// What the Home and Lock Screen widgets show besides thumbnails. Rebuilt by the
/// app on every capture and cull, so it never lags the frames beside it.
struct ShutterStats: Codable, Equatable {
    /// A roll of 35mm — the daily arc the Lock Screen gauge fills against.
    static let rollLength = 36
    static let weekSpan = 7

    var framesToday: Int = 0
    var framesWeek: Int = 0
    var framesTotal: Int = 0
    var keepers: Int = 0
    var rejects: Int = 0
    var unculled: Int = 0
    var topFilm: String = ""
    var topFilmCount: Int = 0
    var lastCaptureAt: TimeInterval = 0
    /// Frames per day, oldest first, always `weekSpan` long and ending today.
    var week: [Int] = Array(repeating: 0, count: ShutterStats.weekSpan)
    /// Day initials matched to `week`, so the widget never recomputes a calendar.
    var weekLabels: [String] = []
    var updatedAt: TimeInterval = 0

    struct Entry {
        let date: Date
        let film: String
        let mark: String

        init(date: Date, film: String, mark: String) {
            self.date = date
            self.film = film
            self.mark = mark
        }
    }

    static func compute(
        _ entries: [Entry],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> ShutterStats {
        var stats = ShutterStats()
        stats.updatedAt = now.timeIntervalSince1970
        stats.framesTotal = entries.count
        stats.weekLabels = dayLabels(now: now, calendar: calendar)

        let today = calendar.startOfDay(for: now)
        var filmCounts: [String: Int] = [:]

        for entry in entries {
            switch entry.mark {
            case "keep": stats.keepers += 1
            case "reject": stats.rejects += 1
            default: stats.unculled += 1
            }

            let name = entry.film.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty, name != "None", name != "Clean" {
                filmCounts[name, default: 0] += 1
            }

            stats.lastCaptureAt = Swift.max(stats.lastCaptureAt, entry.date.timeIntervalSince1970)

            let day = calendar.startOfDay(for: entry.date)
            guard let back = calendar.dateComponents([.day], from: day, to: today).day,
                  back >= 0, back < weekSpan
            else { continue }
            stats.week[weekSpan - 1 - back] += 1
        }

        // Ties go to the alphabetically first name so the label doesn't flicker
        // between equally-shot stocks on every refresh.
        if let top = filmCounts.max(by: { a, b in
            a.value == b.value ? a.key > b.key : a.value < b.value
        }) {
            stats.topFilm = top.key
            stats.topFilmCount = top.value
        }
        stats.framesToday = stats.week.last ?? 0
        stats.framesWeek = stats.week.reduce(0, +)
        return stats
    }

    static func dayLabels(now: Date = Date(), calendar: Calendar = .current) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let todayIndex = calendar.component(.weekday, from: now) - 1
        return (0..<weekSpan).map { offset in
            let back = weekSpan - 1 - offset
            let index = ((todayIndex - back) % symbols.count + symbols.count) % symbols.count
            return symbols[index].uppercased()
        }
    }

    var hasHistory: Bool { framesTotal > 0 }
    var weekPeak: Int { Swift.max(week.max() ?? 0, 1) }
    /// 0…1 against a 36-exposure roll — the Lock Screen gauge.
    var rollProgress: Double {
        Swift.min(Double(framesToday) / Double(Self.rollLength), 1)
    }

    var lastCaptureRelative: String {
        guard lastCaptureAt > 0 else { return "—" }
        let secs = Int(Date().timeIntervalSince(Date(timeIntervalSince1970: lastCaptureAt)))
        if secs < 60 { return "NOW" }
        if secs < 3600 { return "\(secs / 60)m" }
        if secs < 86_400 { return "\(secs / 3600)h" }
        return "\(secs / 86_400)d"
    }

    /// Plausible numbers for the widget gallery, where no App Group data exists.
    static var placeholder: ShutterStats {
        var stats = ShutterStats()
        stats.framesToday = 12
        stats.framesWeek = 47
        stats.framesTotal = 318
        stats.keepers = 96
        stats.rejects = 41
        stats.unculled = 181
        stats.topFilm = "Portra 400"
        stats.topFilmCount = 84
        stats.lastCaptureAt = Date().addingTimeInterval(-540).timeIntervalSince1970
        stats.week = [4, 9, 2, 7, 6, 7, 12]
        stats.weekLabels = dayLabels()
        stats.updatedAt = Date().timeIntervalSince1970
        return stats
    }
}

extension UIImage {
    /// Small JPEG-friendly thumb for Home Screen widgets.
    func shutterWidgetThumbnail(maxSide: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxSide, longest > 0 else { return self }
        let scale = maxSide / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
