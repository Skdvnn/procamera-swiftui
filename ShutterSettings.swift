import SwiftUI
import AVFoundation

// MARK: - Shoot modes (not fake P/A/S/M — practical presets)

enum ShootMode: String, CaseIterable, Identifiable {
    case street, night, studio, film

    var id: String { rawValue }

    var title: String {
        switch self {
        case .street: return "Street"
        case .night: return "Night"
        case .studio: return "Studio"
        case .film: return "Film"
        }
    }

    var blurb: String {
        switch self {
        case .street: return "Fast shutter · grid on"
        case .night: return "Slow shutter · peaking"
        case .studio: return "Manual lock · peaking"
        case .film: return "Stock-first · soft defaults"
        }
    }

    var icon: String {
        switch self {
        case .street: return "figure.walk"
        case .night: return "moon.stars"
        case .studio: return "lamp.desk"
        case .film: return "film"
        }
    }
}

// MARK: - Settings sheet

struct ShutterSettingsSheet: View {
    @Binding var showGrid: Bool
    @Binding var focusPeaking: Bool
    @Binding var zebraEnabled: Bool
    @Binding var showLevel: Bool
    @Binding var captureFormat: CaptureFormat
    @Binding var defaultFilm: FilmFilterMode
    @Binding var naturalCapture: Bool
    var onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            List {
                // Scene presets: viewfinder film button → SCENE section.

                Section {
                    Toggle("Natural capture", isOn: $naturalCapture)
                } header: {
                    Text("Image honesty")
                } footer: {
                    Text(naturalCapture
                          ? "Less Apple fusion (speed + Bayer RAW). Selected film/FX still bake into the saved photo — natural is about the ISP, not stripping your looks."
                          : "Polished path: quality prioritization and Apple’s heavier still pipeline. Film/FX always bake either way.")
                }

                Section("Viewfinder") {
                    Toggle("Grid", isOn: $showGrid)
                    Toggle("Focus peaking", isOn: $focusPeaking)
                    Toggle("Zebra highlights", isOn: $zebraEnabled)
                    Toggle("Horizon level", isOn: $showLevel)
                }

                Section("Capture defaults") {
                    Picker("Format", selection: $captureFormat) {
                        Text("HEIC").tag(CaptureFormat.heic)
                        Text("JPEG").tag(CaptureFormat.jpeg)
                        Text("RAW").tag(CaptureFormat.raw)
                    }
                    Picker("Default film", selection: $defaultFilm) {
                        ForEach(FilmFilterMode.allCases, id: \.self) { film in
                            Text(film.name).tag(film)
                        }
                    }
                }

                Section("External shutter") {
                    Text("Volume buttons, Camera Control, and Bluetooth/HID remotes (gamepad A / trigger) fire the shutter.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Section("About") {
                    LabeledContent("App", value: "Shutter")
                    LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
