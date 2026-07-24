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

enum ShutterDeepLinkCenter {
    static func post(_ link: ShutterDeepLink) {
        NotificationCenter.default.post(name: .shutterDeepLink, object: nil, userInfo: ["link": link])
    }

    static func post(url: URL) {
        guard let link = ShutterDeepLink.parse(url) else { return }
        post(link)
    }
}

/// Shared App Group for widgets ↔ app (looks, last mode).
enum ShutterAppGroup {
    static let id = "group.com.skylardann.filmcam"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: id) ?? .standard
    }
}
