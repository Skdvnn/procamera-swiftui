import SwiftUI
import Fingertips

class FingerTipAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        config.delegateClass = FingerTipSceneDelegate.self
        return config
    }
}

class FingerTipSceneDelegate: NSObject, UIWindowSceneDelegate {
    var window: UIWindow?

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
