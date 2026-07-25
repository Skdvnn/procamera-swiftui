import SwiftUI
import Fingertips
import CloudKit
import AppIntents

class FingerTipAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = FingerTipSceneDelegate.self
        return config
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Cold-start shortcuts are handled in FingerTipSceneDelegate only —
        // posting here too double-fired capture.
        return true
    }

    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        // Prefer scene windowScene(performActionFor:). This path is a fallback
        // for hosts that only call the app-delegate API.
        FingerTipSceneDelegate.postShortcut(shortcutItem)
        completionHandler(true)
    }
}

class FingerTipSceneDelegate: NSObject, UIWindowSceneDelegate {
    var window: UIWindow?

    /// Shared shortcut → deep-link mapping (app delegate + scene).
    static func postShortcut(_ item: UIApplicationShortcutItem) {
        switch item.type {
        case "com.skylardann.filmcam.capture":
            ShutterDeepLinkCenter.post(.capture)
        case "com.skylardann.filmcam.darkroom":
            ShutterDeepLinkCenter.post(.darkroom)
        case "com.skylardann.filmcam.timer":
            ShutterDeepLinkCenter.post(.timer(seconds: 3))
        default:
            ShutterDeepLinkCenter.post(.openCamera)
        }
    }

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let fingerTipWindow = FingerTipWindow(windowScene: windowScene)
        fingerTipWindow.alwaysShowTouches = false
        fingerTipWindow.rootViewController = UIHostingController(rootView: ContentView())
        fingerTipWindow.makeKeyAndVisible()
        self.window = fingerTipWindow

        NotificationCenter.default.addObserver(
            forName: .toggleFingerTips,
            object: nil,
            queue: .main
        ) { [weak fingerTipWindow] _ in
            guard let w = fingerTipWindow else { return }
            w.alwaysShowTouches.toggle()
        }

        // Cold-start deep links / universal activities / shortcuts
        for context in connectionOptions.urlContexts {
            ShutterDeepLinkCenter.post(url: context.url)
        }
        if let activity = connectionOptions.userActivities.first {
            handleUserActivity(activity)
        }
        if let shortcut = connectionOptions.shortcutItem {
            Self.postShortcut(shortcut)
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        for context in URLContexts {
            ShutterDeepLinkCenter.post(url: context.url)
        }
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        handleUserActivity(userActivity)
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        Self.postShortcut(shortcutItem)
        completionHandler(true)
    }

    private func handleUserActivity(_ activity: NSUserActivity) {
        // LockedCameraCapture framework constant — use string so iOS 17 builds link cleanly.
        if activity.activityType == "NSUserActivityTypeLockedCameraCapture" {
            let film = activity.userInfo?["film"] as? String
            let fx = activity.userInfo?["fx"] as? String
            ShutterDeepLinkCenter.post(.look(film: film, fx: fx))
            return
        }
        if let url = activity.webpageURL {
            ShutterDeepLinkCenter.post(url: url)
        }
    }

    // Invitee tapped a Field Book share link
    func windowScene(_ windowScene: UIWindowScene,
                     userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        CloudBookManager.shared.acceptShare(metadata: cloudKitShareMetadata)
    }
}

@main
struct ProCameraApp: App {
    @UIApplicationDelegateAdaptor(FingerTipAppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            EmptyView()
        }
    }
}
