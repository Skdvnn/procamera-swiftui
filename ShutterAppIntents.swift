import AppIntents
import Foundation

// MARK: - Shortcut parameter enums

enum ShutterFilmLookEntity: String, AppEnum {
    case portra400 = "Portra 400"
    case ektar100 = "Ektar 100"
    case kodakGold = "Kodak Gold"
    case triX400 = "Tri-X 400"
    case velvia50 = "Velvia 50"
    case cinestill800 = "CineStill 800T"
    case instant = "Instant"
    case none = "None"

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Film")
    static var caseDisplayRepresentations: [ShutterFilmLookEntity: DisplayRepresentation] = [
        .portra400: "Portra 400",
        .ektar100: "Ektar 100",
        .kodakGold: "Kodak Gold",
        .triX400: "Tri-X 400",
        .velvia50: "Velvia 50",
        .cinestill800: "CineStill 800T",
        .instant: "Instant",
        .none: "None"
    ]
}

enum ShutterTimerSecondsEntity: Int, AppEnum {
    case off = 0
    case three = 3
    case ten = 10

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Timer")
    static var caseDisplayRepresentations: [ShutterTimerSecondsEntity: DisplayRepresentation] = [
        .off: "Off",
        .three: "3 seconds",
        .ten: "10 seconds"
    ]
}

enum ShutterSceneEntity: String, AppEnum {
    case auto = "auto"
    case street = "street"
    case night = "night"
    case studio = "studio"
    case film = "film"
    case naturalManual = "naturalmanual"

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Scene")
    static var caseDisplayRepresentations: [ShutterSceneEntity: DisplayRepresentation] = [
        .auto: "Auto",
        .street: "Street",
        .night: "Night",
        .studio: "Studio",
        .film: "Film",
        .naturalManual: "Natural Manual"
    ]
}

// MARK: - Shortcuts / Siri App Intents (main app)

struct OpenShutterCamIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Shutter Cam"
    static var description = IntentDescription("Open the Shutter Cam viewfinder.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        ShutterDeepLinkCenter.post(.openCamera)
        return .result()
    }
}

struct CaptureWithShutterIntent: AppIntent {
    static var title: LocalizedStringResource = "Capture with Shutter Cam"
    static var description = IntentDescription("Fire the shutter in Shutter Cam.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        ShutterDeepLinkCenter.post(.capture)
        return .result()
    }
}

struct OpenDarkroomIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Darkroom"
    static var description = IntentDescription("Open Shutter Darkroom to cull shots.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        ShutterDeepLinkCenter.post(.darkroom)
        return .result()
    }
}

struct OpenFieldBookIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Field Book"
    static var description = IntentDescription("Open the Field Book shelf in Shutter.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        ShutterDeepLinkCenter.post(.fieldBook)
        return .result()
    }
}

struct ApplyShutterLookIntent: AppIntent {
    static var title: LocalizedStringResource = "Apply Shutter Look"
    static var description = IntentDescription("Apply a film stock and optional Lens FX.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Film")
    var film: ShutterFilmLookEntity?

    @Parameter(title: "Lens FX")
    var lensFX: String?

    @MainActor
    func perform() async throws -> some IntentResult {
        // Pass "None" explicitly — nil means "leave film unchanged" in ContentView.
        let filmName = film.map(\.rawValue)
        ShutterDeepLinkCenter.post(.look(film: filmName, fx: lensFX))
        return .result()
    }
}

struct ApplyShutterSceneIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Shutter Scene"
    static var description = IntentDescription(
        "Pick a SCENE mode — Auto watches light and soft-suggests Night, Street, or Film."
    )
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Scene")
    var scene: ShutterSceneEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        ShutterDeepLinkCenter.post(.scene(mode: scene.rawValue))
        return .result()
    }
}

struct SetShutterTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Shutter Timer"
    static var description = IntentDescription("Set the self-timer (0, 3, or 10 seconds).")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Seconds")
    var seconds: ShutterTimerSecondsEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        ShutterDeepLinkCenter.post(.timer(seconds: seconds.rawValue))
        return .result()
    }
}

struct ShutterAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenShutterCamIntent(),
            phrases: [
                "Open \(.applicationName)",
                "Open \(.applicationName) camera",
                "Shoot with \(.applicationName)"
            ],
            shortTitle: "Open Camera",
            systemImageName: "camera.fill"
        )
        AppShortcut(
            intent: CaptureWithShutterIntent(),
            phrases: [
                "Take a photo with \(.applicationName)",
                "Capture with \(.applicationName)"
            ],
            shortTitle: "Capture",
            systemImageName: "camera.shutter.button"
        )
        AppShortcut(
            intent: OpenDarkroomIntent(),
            phrases: [
                "Open \(.applicationName) darkroom",
                "Cull photos in \(.applicationName)"
            ],
            shortTitle: "Darkroom",
            systemImageName: "square.stack.3d.up"
        )
        AppShortcut(
            intent: OpenFieldBookIntent(),
            phrases: [
                "Open \(.applicationName) field book",
                "Show \(.applicationName) books"
            ],
            shortTitle: "Field Book",
            systemImageName: "book.closed"
        )
        AppShortcut(
            intent: ApplyShutterLookIntent(),
            phrases: [
                "Apply a look in \(.applicationName)",
                "Set film look in \(.applicationName)"
            ],
            shortTitle: "Apply Look",
            systemImageName: "camera.filters"
        )
        AppShortcut(
            intent: ApplyShutterSceneIntent(),
            phrases: [
                "Set scene in \(.applicationName)",
                "Auto scene with \(.applicationName)",
                "Night mode in \(.applicationName)"
            ],
            shortTitle: "Set Scene",
            systemImageName: "camera.metering.spot"
        )
        AppShortcut(
            intent: SetShutterTimerIntent(),
            phrases: [
                "Set \(.applicationName) timer",
                "Self timer with \(.applicationName)"
            ],
            shortTitle: "Timer",
            systemImageName: "timer"
        )
    }
}
