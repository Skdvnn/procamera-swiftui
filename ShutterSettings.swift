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
        case .night: return "1/15 · ISO 1600 · clean"
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

// MARK: - Settings sheet (iOS List + Nikon LCD readouts)

struct ShutterSettingsSheet: View {
    @Binding var showGrid: Bool
    @Binding var focusPeaking: Bool
    @Binding var zebraEnabled: Bool
    @Binding var showLevel: Bool
    @Binding var captureFormat: CaptureFormat
    @Binding var defaultFilm: FilmFilterMode
    @Binding var naturalCapture: Bool
    @Binding var nightAssist: Bool
    @Binding var holdBurst: Bool
    @Binding var filmFilter: FilmFilterMode
    @Binding var lensFX: LensFXMode
    var onLookApplied: (FilmFilterMode, LensFXMode) -> Void
    var onDismiss: () -> Void

    @ObservedObject private var lookStore = LookRecipeStore.shared

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Natural capture", isOn: $naturalCapture)
                } header: {
                    lcdHeader("IMAGE HONESTY")
                } footer: {
                    Text(naturalCapture
                          ? "Less Apple fusion (speed + Bayer RAW). Selected film/FX still bake into the saved photo — natural is about the ISP, not stripping your looks."
                          : "Polished path: quality prioritization and Apple’s heavier still pipeline. Film/FX always bake either way.")
                        .font(.system(size: 11, design: .monospaced))
                }

                Section {
                    Toggle("Grid", isOn: $showGrid)
                    Toggle("Focus peaking", isOn: $focusPeaking)
                    Toggle("Zebra highlights", isOn: $zebraEnabled)
                    Toggle("Horizon level", isOn: $showLevel)
                } header: {
                    lcdHeader("VIEWFINDER")
                }

                Section {
                    Toggle("Low-light Night tip", isOn: $nightAssist)
                    Toggle("Hold shutter for burst", isOn: $holdBurst)
                } header: {
                    lcdHeader("ASSIST")
                } footer: {
                    Text("Night tip offers an opt-in Night preset when AUTO is dark — it never auto-fires long exposure. Burst (off by default) queues up to 6 stills while you hold.")
                        .font(.system(size: 11, design: .monospaced))
                }

                Section {
                    if filmFilter != .none || lensFX != .none {
                        Button {
                            LookRecipeStore.shared.saveCurrent(film: filmFilter, lensFX: lensFX)
                            Haptics.medium()
                        } label: {
                            HStack {
                                Text("SAVE CURRENT LOOK")
                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(DS.accent)
                                Spacer()
                                Image(systemName: "bookmark.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(DS.accent)
                            }
                        }
                    } else {
                        Text("Apply a film or FX look on the finder, then save it here.")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    if lookStore.recipes.isEmpty {
                        Text("No saved looks yet.")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(lookStore.recipes) { recipe in
                            HStack {
                                Button {
                                    onLookApplied(recipe.film, recipe.lensFX)
                                    Haptics.click()
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(recipe.name.uppercased())
                                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                            .foregroundStyle(.primary)
                                        Text(recipe.subtitle.uppercased())
                                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)

                                Spacer()

                                Button(role: .destructive) {
                                    lookStore.delete(recipe.id)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 13))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                } header: {
                    lcdHeader("SAVED LOOKS")
                } footer: {
                    Text("Film and Lens FX are exclusive — applying one clears the other. Peaking is a focus aid, not a look.")
                        .font(.system(size: 11, design: .monospaced))
                }

                Section {
                    Picker("Format", selection: $captureFormat) {
                        Text("HEIC").tag(CaptureFormat.heic)
                        Text("JPEG").tag(CaptureFormat.jpeg)
                        Text("RAW").tag(CaptureFormat.raw)
                    }
                    .font(.system(size: 13, design: .monospaced))

                    Picker("Default film", selection: $defaultFilm) {
                        ForEach(FilmFilterMode.allCases, id: \.self) { film in
                            Text(film.name).tag(film)
                        }
                    }
                    .font(.system(size: 13, design: .monospaced))
                } header: {
                    lcdHeader("CAPTURE DEFAULTS")
                }

                Section {
                    Text("Volume buttons, Camera Control, and Bluetooth/HID remotes (gamepad A / trigger) fire the shutter.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                } header: {
                    lcdHeader("EXTERNAL SHUTTER")
                }

                Section {
                    LabeledContent("App") {
                        Text("SHUTTER")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(DS.accent)
                    }
                    LabeledContent("Build") {
                        Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(DS.accent)
                    }
                } header: {
                    lcdHeader("ABOUT")
                }
            }
            .listStyle(.insetGrouped)
            .tint(DS.accent)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDismiss() }
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundStyle(DS.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func lcdHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .tracking(1.2)
            .foregroundStyle(DS.accent.opacity(0.85))
    }
}
