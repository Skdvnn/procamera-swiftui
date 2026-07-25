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
    @Binding var shootMode: ShootMode
    @Binding var showGrid: Bool
    @Binding var focusPeaking: Bool
    @Binding var zebraEnabled: Bool
    @Binding var showLevel: Bool
    @Binding var captureFormat: CaptureFormat
    @Binding var defaultFilm: FilmFilterMode
    @Binding var naturalCapture: Bool
    @Binding var bakeLooksIntoProcessed: Bool
    var onApplyMode: (ShootMode) -> Void
    var onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ShootMode.allCases) { mode in
                        Button {
                            Haptics.click()
                            shootMode = mode
                            onApplyMode(mode)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: mode.icon)
                                    .frame(width: 22)
                                    .foregroundStyle(shootMode == mode
                                                     ? Color(red: 1.0, green: 0.85, blue: 0.35)
                                                     : .primary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mode.title)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(.primary)
                                    Text(mode.blurb)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if shootMode == mode {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color(red: 1.0, green: 0.85, blue: 0.35))
                                }
                            }
                        }
                    }
                } header: {
                    Text("Shoot mode")
                } footer: {
                    Text("Presets tweak shutter, ISO, peaking, and grid — not fake aperture modes.")
                }

                Section {
                    Toggle("Natural capture", isOn: $naturalCapture)
                    if naturalCapture {
                        Toggle("Bake film/FX into JPEG", isOn: $bakeLooksIntoProcessed)
                    }
                } header: {
                    Text("Image honesty")
                } footer: {
                    Text(naturalCapture
                          ? "Speed prioritization, Bayer RAW over ProRAW, no red-eye rewrite, no virtual-cam fusion. Apple has no public “off” for Deep Fusion — this is the honest minimum."
                          : "Polished path: quality prioritization and Apple’s heavier still pipeline.")
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
