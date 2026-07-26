import SwiftUI
import UIKit
import LockedCameraCapture
import AppIntents

@main
struct ShutterCaptureExtension: LockedCameraCaptureExtension {
    var body: some LockedCameraCaptureExtensionScene {
        LockedCameraCaptureUIScene { session in
            ShutterLockedCaptureView(session: session)
        }
    }
}

struct ShutterLockedCaptureView: View {
    let session: LockedCameraCaptureSession
    @State private var context = ShutterCaptureContext.loadFromAppGroup()

    var body: some View {
        ZStack {
            ShutterLockedPicker(session: session, context: context)
                .ignoresSafeArea()

            VStack {
                HStack {
                    Text("SHUTTER")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(.black.opacity(0.45)))
                    Spacer()
                    Button {
                        openFullApp()
                    } label: {
                        Text("FULL APP")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(.black.opacity(0.45)))
                    }
                }
                .padding()
                Spacer()
                // Lock Screen capture uses the system picker — film/FX only bake in FULL APP.
                VStack(spacing: 4) {
                    Text("SYSTEM CAMERA")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.75))
                    Text("LOOKS IN FULL APP")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(red: 1.0, green: 0.85, blue: 0.35).opacity(0.9))
                    if context.filmName.uppercased() != "NONE" {
                        Text(context.filmName.uppercased())
                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                .padding(.bottom, 28)
            }
        }
        .task {
            if #available(iOS 18.0, *) {
                if let remote = try? await ShutterCameraCaptureIntent.appContext {
                    context = remote
                }
            }
        }
    }

    private func openFullApp() {
        let activity = NSUserActivity(activityType: "NSUserActivityTypeLockedCameraCapture")
        activity.title = "Shutter Cam"
        activity.userInfo = [
            "film": context.filmName,
            "fx": context.lensFXName
        ]
        Task {
            try? await session.openApplication(for: activity)
        }
    }
}

/// Lock Screen capture uses UIImagePickerController + system shutter events.
struct ShutterLockedPicker: UIViewControllerRepresentable {
    let session: LockedCameraCaptureSession
    let context: ShutterCaptureContext

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.showsCameraControls = true
        picker.cameraDevice = self.context.useFrontCamera ? .front : .rear
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
}
