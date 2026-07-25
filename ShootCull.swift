import Foundation
import UIKit
import SwiftUI
import Photos
import CoreLocation
import Combine

// MARK: - Tunable session clustering

enum SessionClustering {
    /// Break a session when consecutive frames are farther apart than this.
    static let maxGap: TimeInterval = 90 * 60
    /// Also break when both frames have locations and are farther than this (meters).
    static let maxDistanceMeters: CLLocationDistance = 2_000
}

// MARK: - Cull palette (darkroom)

enum CullPalette {
    static let amber = Color(red: 1.0, green: 0.82, blue: 0.38)
    /// Safelight red — never system red
    static let safelight = Color(red: 0x8B / 255.0, green: 0x1A / 255.0, blue: 0x1A / 255.0)
    static let safelightGlow = Color(red: 0.72, green: 0.22, blue: 0.18)
    static let hairline = Color(red: 1.0, green: 0.82, blue: 0.38).opacity(0.32)
    static let sheetTop = Color(red: 0x1C / 255.0, green: 0x19 / 255.0, blue: 0x16 / 255.0)
    static let sheetBottom = Color(red: 0x14 / 255.0, green: 0x12 / 255.0, blue: 0x10 / 255.0)
    static let paper = Color(red: 0x1A / 255.0, green: 0x16 / 255.0, blue: 0x12 / 255.0)
}

// MARK: - Frame mark

enum FrameMarkState: String, Codable, CaseIterable {
    case unmarked
    case keep
    case reject
}

struct FrameMark: Codable, Equatable {
    var shotID: UUID
    var photosAssetLocalIdentifier: String?
    var creationDate: Date
    var state: FrameMarkState
    var markedAt: Date
}

// MARK: - Mark store (local JSON — cull flags Photos doesn't know about)

final class FrameMarkStore: ObservableObject {
    @Published private(set) var marks: [UUID: FrameMark] = [:]

    private let url: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("PhotoBook", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("frame_marks.json")
        load()
    }

    func state(for shotID: UUID) -> FrameMarkState {
        marks[shotID]?.state ?? .unmarked
    }

    func mark(
        shotID: UUID,
        photosAssetLocalIdentifier: String?,
        creationDate: Date,
        state: FrameMarkState
    ) {
        marks[shotID] = FrameMark(
            shotID: shotID,
            photosAssetLocalIdentifier: photosAssetLocalIdentifier,
            creationDate: creationDate,
            state: state,
            markedAt: Date()
        )
        save()
    }

    func clear(shotIDs: [UUID]) {
        for id in shotIDs { marks.removeValue(forKey: id) }
        save()
    }

    private func save() {
        let list = Array(marks.values)
        if let data = try? JSONEncoder().encode(list) {
            try? data.write(to: url, options: .atomic)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([FrameMark].self, from: data) else { return }
        marks = Dictionary(uniqueKeysWithValues: list.map { ($0.shotID, $0) })
    }
}

// MARK: - Shoot session

struct ShootSession: Identifiable, Equatable {
    let id: UUID
    let shots: [ShotMetadata]
    var title: String

    var startDate: Date { shots.first?.date ?? .distantPast }
    var endDate: Date { shots.last?.date ?? .distantPast }

    func progress(marks: FrameMarkStore) -> (kept: Int, rejected: Int, unmarked: Int) {
        var kept = 0, rejected = 0, unmarked = 0
        for shot in shots {
            switch marks.state(for: shot.id) {
            case .keep: kept += 1
            case .reject: rejected += 1
            case .unmarked: unmarked += 1
            }
        }
        return (kept, rejected, unmarked)
    }
}

enum SessionClusterer {
    /// Chronological clustering; returns newest-first sessions.
    /// Location breaks (SessionClustering.maxDistanceMeters) apply when both
    /// neighboring frames resolve to a PHAsset with location.
    static func cluster(_ shots: [ShotMetadata]) -> [ShootSession] {
        let sorted = shots.sorted { $0.date < $1.date }
        guard !sorted.isEmpty else { return [] }

        var groups: [[ShotMetadata]] = [[sorted[0]]]
        for i in 1..<sorted.count {
            let prev = sorted[i - 1]
            let cur = sorted[i]
            let gap = cur.date.timeIntervalSince(prev.date)
            let far = Self.locationBreak(from: prev, to: cur)
            if gap > SessionClustering.maxGap || far {
                groups.append([cur])
            } else {
                groups[groups.count - 1].append(cur)
            }
        }

        let sessions: [ShootSession] = groups.map { group in
            let sid = group.first?.id ?? UUID()
            return ShootSession(
                id: sid,
                shots: group,
                title: SessionTitle.fallback(for: group)
            )
        }
        return sessions.reversed()
    }

    private static func locationBreak(from a: ShotMetadata, to b: ShotMetadata) -> Bool {
        guard let idA = a.photosAssetLocalIdentifier,
              let idB = b.photosAssetLocalIdentifier,
              let assetA = PhotosLibraryService.asset(withLocalIdentifier: idA),
              let assetB = PhotosLibraryService.asset(withLocalIdentifier: idB),
              let locA = assetA.location,
              let locB = assetB.location else { return false }
        return locA.distance(from: locB) > SessionClustering.maxDistanceMeters
    }
}

enum SessionTitle {
    private static var cache: [String: String] = [:]
    private static let lock = NSLock()

    static func fallback(for shots: [ShotMetadata]) -> String {
        guard let first = shots.first else { return "Untitled session" }
        let df = DateFormatter()
        df.dateFormat = "MMM d"
        let day = df.string(from: first.date)
        let hour = Calendar.current.component(.hour, from: first.date)
        let period: String
        switch hour {
        case 5..<12: period = "morning"
        case 12..<17: period = "afternoon"
        case 17..<21: period = "evening"
        default: period = "night"
        }
        return "\(day) — \(period)"
    }

    /// Reverse-geocode when a centroid is available.
    /// Caches **place name only** (not the full title) so morning/evening sessions
    /// at the same spot don't steal each other's period strings. Failures are not cached.
    static func refine(session: ShootSession, location: CLLocation?, completion: @escaping (String) -> Void) {
        guard let location else {
            completion(session.title)
            return
        }
        let key = String(format: "%.2f,%.2f", location.coordinate.latitude, location.coordinate.longitude)
        lock.lock()
        let cachedPlace = cache[key]
        lock.unlock()

        func titled(place: String?) -> String {
            let base = fallback(for: session.shots)
            guard let place, !place.isEmpty else { return base }
            let df = DateFormatter()
            df.dateFormat = "MMM d"
            let day = df.string(from: session.startDate)
            let hour = Calendar.current.component(.hour, from: session.startDate)
            let period: String
            switch hour {
            case 5..<12: period = "morning"
            case 12..<17: period = "afternoon"
            case 17..<21: period = "evening"
            default: period = "night"
            }
            return "\(place) — \(day), \(period)"
        }

        if let cachedPlace {
            completion(titled(place: cachedPlace))
            return
        }

        CLGeocoder().reverseGeocodeLocation(location) { placemarks, _ in
            let place = placemarks?.first
            let name = place?.name
                ?? place?.locality
                ?? place?.subLocality
                ?? place?.inlandWater
                ?? place?.ocean
            if let name, !name.isEmpty {
                lock.lock()
                cache[key] = name
                lock.unlock()
                completion(titled(place: name))
            } else {
                // Do not cache failures — CLGeocoder rate limits are common.
                completion(titled(place: nil))
            }
        }
    }
}

// MARK: - Photos library bridge (dual-write helper)

enum PhotosLibraryService {
    static let albumTitle = "Shutter"

    static func requestReadWrite(completion: @escaping (PHAuthorizationStatus) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .readWrite, handler: completion)
    }

    /// Saves image to the camera roll and returns the new asset localIdentifier.
    static func saveImage(_ image: UIImage, completion: @escaping (String?) -> Void) {
        requestReadWrite { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            var placeholderID: String?
            PHPhotoLibrary.shared().performChanges({
                let req = PHAssetCreationRequest.creationRequestForAsset(from: image)
                placeholderID = req.placeholderForCreatedAsset?.localIdentifier
            }, completionHandler: { success, _ in
                DispatchQueue.main.async {
                    completion(success ? placeholderID : nil)
                }
            })
        }
    }

    static func setFavorite(assetLocalIdentifier: String?, favorite: Bool) {
        guard let id = assetLocalIdentifier,
              let asset = asset(withLocalIdentifier: id) else { return }
        PHPhotoLibrary.shared().performChanges({
            let req = PHAssetChangeRequest(for: asset)
            req.isFavorite = favorite
        }, completionHandler: { _, error in
            if let error { print("Favorite mirror failed: \(error)") }
        })
    }

    static func deleteAssets(localIdentifiers: [String], completion: @escaping (Bool) -> Void) {
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: localIdentifiers, options: nil)
        guard assets.count > 0 else {
            completion(true)
            return
        }
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets(assets)
        }, completionHandler: { success, error in
            if let error { print("Batch delete failed: \(error)") }
            DispatchQueue.main.async { completion(success) }
        })
    }

    /// Creates (or reuses) an album and adds the given assets. One album per finished session title.
    static func exportKeepers(
        albumName: String,
        assetLocalIdentifiers: [String],
        completion: @escaping (Bool) -> Void
    ) {
        guard !assetLocalIdentifiers.isEmpty else {
            completion(true)
            return
        }
        requestReadWrite { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { completion(false) }
                return
            }

            guard let album = fetchOrCreateAlbum(named: albumName) else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: assetLocalIdentifiers, options: nil)
            guard assets.count > 0 else {
                DispatchQueue.main.async { completion(false) }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                guard let add = PHAssetCollectionChangeRequest(for: album) else { return }
                add.addAssets(assets)
            }, completionHandler: { success, error in
                if let error { print("Album export failed: \(error)") }
                DispatchQueue.main.async { completion(success) }
            })
        }
    }

    static func fetchOrCreateAlbum(named title: String) -> PHAssetCollection? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title = %@", title)
        let existing = PHAssetCollection.fetchAssetCollections(
            with: .album, subtype: .any, options: options
        )
        if let found = existing.firstObject { return found }

        var placeholder: PHObjectPlaceholder?
        do {
            try PHPhotoLibrary.shared().performChangesAndWait {
                let req = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
                placeholder = req.placeholderForCreatedAssetCollection
            }
        } catch {
            print("Album create failed: \(error)")
            return nil
        }
        guard let id = placeholder?.localIdentifier else { return nil }
        return PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [id], options: nil
        ).firstObject
    }

    static func asset(withLocalIdentifier id: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    }

    /// Fallback match when localIdentifier is stale: exact creationDate.
    /// Opens the Photos app (no public deep link to a named album).
    static func openPhotosApp() {
        // `photos-redirect://` is the supported springboard jump into Photos.
        guard let url = URL(string: "photos-redirect://") else { return }
        DispatchQueue.main.async {
            UIApplication.shared.open(url)
        }
    }

    static func resolveAsset(
        preferredID: String?,
        creationDate: Date
    ) -> PHAsset? {
        if let preferredID, let asset = asset(withLocalIdentifier: preferredID) {
            return asset
        }
        let opts = PHFetchOptions()
        opts.predicate = NSPredicate(
            format: "creationDate == %@",
            creationDate as NSDate
        )
        opts.fetchLimit = 2
        let result = PHAsset.fetchAssets(with: .image, options: opts)
        if result.count == 1 {
            print("Photos ID miss — recovered via creationDate \(creationDate)")
            return result.firstObject
        }
        if result.count > 1 {
            print("Photos ID miss — ambiguous creationDate match for \(creationDate)")
        }
        return nil
    }
}

// MARK: - Undo stack for a cull session

struct CullAction: Equatable {
    let shotID: UUID
    let previous: FrameMarkState
    let next: FrameMarkState
}

final class CullUndoStack: ObservableObject {
    @Published private(set) var stack: [CullAction] = []

    var canUndo: Bool { !stack.isEmpty }

    func push(_ action: CullAction) {
        stack.append(action)
    }

    func pop() -> CullAction? {
        guard !stack.isEmpty else { return nil }
        return stack.removeLast()
    }

    func clear() { stack.removeAll() }
}
