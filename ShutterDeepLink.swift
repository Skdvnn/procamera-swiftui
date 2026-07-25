import Foundation
import SwiftUI

// MARK: - Deep links (Shortcuts, widgets, quick actions)

enum ShutterDeepLink: Equatable {
    case openCamera
    case capture
    case darkroom
    case look(film: String?, fx: String?)
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
        case "look", "recipe":
            return .look(film: q("film"), fx: q("fx"))
        case "timer":
            return .timer(seconds: Int(q("seconds") ?? q("s") ?? "3") ?? 3)
        case "peaking":
            return .peaking((q("on") ?? "1") != "0")
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
        case .look(let film, let fx):
            var c = URLComponents(string: "shuttercam://look")!
            var items: [URLQueryItem] = []
            if let film { items.append(URLQueryItem(name: "film", value: film)) }
            if let fx { items.append(URLQueryItem(name: "fx", value: fx)) }
            c.queryItems = items.isEmpty ? nil : items
            return c.url!
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

/// Shared App Group for widgets ↔ app (looks, last mode).
enum ShutterAppGroup {
    static let id = "group.com.skylardann.filmcam"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: id) ?? .standard
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
}
