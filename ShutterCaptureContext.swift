import AppIntents
import Foundation

// MARK: - Shared capture context (app + widgets + lock-screen capture)

/// Passed through Camera Control / Lock Screen capture (≤4KB).
struct ShutterCaptureContext: Codable, Sendable {
    var useFrontCamera: Bool
    var filmName: String
    var lensFXName: String
    var timerSeconds: Int
    var peaking: Bool

    nonisolated init(
        useFrontCamera: Bool = false,
        filmName: String = "None",
        lensFXName: String = "None",
        timerSeconds: Int = 0,
        peaking: Bool = false
    ) {
        self.useFrontCamera = useFrontCamera
        self.filmName = filmName
        self.lensFXName = lensFXName
        self.timerSeconds = timerSeconds
        self.peaking = peaking
    }

    enum CodingKeys: String, CodingKey {
        case useFrontCamera, filmName, lensFXName, timerSeconds, peaking
    }

    nonisolated init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        useFrontCamera = try c.decodeIfPresent(Bool.self, forKey: .useFrontCamera) ?? false
        filmName = try c.decodeIfPresent(String.self, forKey: .filmName) ?? "None"
        lensFXName = try c.decodeIfPresent(String.self, forKey: .lensFXName) ?? "None"
        timerSeconds = try c.decodeIfPresent(Int.self, forKey: .timerSeconds) ?? 0
        peaking = try c.decodeIfPresent(Bool.self, forKey: .peaking) ?? false
    }

    nonisolated func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(useFrontCamera, forKey: .useFrontCamera)
        try c.encode(filmName, forKey: .filmName)
        try c.encode(lensFXName, forKey: .lensFXName)
        try c.encode(timerSeconds, forKey: .timerSeconds)
        try c.encode(peaking, forKey: .peaking)
    }

    static func loadFromAppGroup() -> ShutterCaptureContext {
        let d = ShutterAppGroup.defaults
        return ShutterCaptureContext(
            useFrontCamera: d.bool(forKey: "ctx.front"),
            filmName: d.string(forKey: "ctx.film") ?? "None",
            lensFXName: d.string(forKey: "ctx.fx") ?? "None",
            timerSeconds: d.integer(forKey: "ctx.timer"),
            peaking: d.bool(forKey: "ctx.peaking")
        )
    }

    func saveToAppGroup() {
        let d = ShutterAppGroup.defaults
        d.set(useFrontCamera, forKey: "ctx.front")
        d.set(filmName, forKey: "ctx.film")
        d.set(lensFXName, forKey: "ctx.fx")
        d.set(timerSeconds, forKey: "ctx.timer")
        d.set(peaking, forKey: "ctx.peaking")
    }
}

// MARK: - Camera Control / Lock Screen capture intent (iOS 18+)

@available(iOS 18.0, *)
struct ShutterCameraCaptureIntent: CameraCaptureIntent {
    static let title: LocalizedStringResource = "Shutter Cam"
    static let description = IntentDescription("Open Shutter Cam to capture a photo.")

    typealias AppContext = ShutterCaptureContext

    @MainActor
    func perform() async throws -> some IntentResult {
        ShutterDeepLinkCenter.post(.openCamera)
        return .result()
    }
}
