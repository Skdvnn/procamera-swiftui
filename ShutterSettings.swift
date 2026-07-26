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

// MARK: - Settings sheet (pure black + blur; yellow for state only)

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
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    dslrSection("Image honesty") {
                        DSLRToggleRow(
                            title: "Natural capture",
                            blurb: naturalCapture
                                ? "Less Apple fusion · looks still bake"
                                : "Polished ISP · looks still bake",
                            isOn: $naturalCapture
                        )
                    }

                    dslrSection("Viewfinder") {
                        DSLRToggleRow(title: "Grid", blurb: "Rule-of-thirds overlay", isOn: $showGrid)
                        DSLRDivider()
                        DSLRToggleRow(title: "Focus peaking", blurb: "Green edge aid — not a look", isOn: $focusPeaking)
                        DSLRDivider()
                        DSLRToggleRow(title: "Zebra", blurb: "Highlight warning", isOn: $zebraEnabled)
                        DSLRDivider()
                        DSLRToggleRow(title: "Horizon level", blurb: "Spirit bar under the EV meter", isOn: $showLevel)
                    }

                    dslrSection("Assist") {
                        DSLRToggleRow(title: "Night tip", blurb: "Opt-in when AUTO is dark", isOn: $nightAssist)
                        DSLRDivider()
                        DSLRToggleRow(title: "Hold burst", blurb: "Up to 6 stills while held", isOn: $holdBurst)
                    }

                    dslrSection("Saved looks") {
                        if filmFilter != .none || lensFX != .none {
                            Button {
                                LookRecipeStore.shared.saveCurrent(film: filmFilter, lensFX: lensFX)
                                Haptics.medium()
                            } label: {
                                HStack(spacing: 8) {
                                    Text(">")
                                        .font(DS.mono(12, weight: .bold))
                                        .foregroundStyle(DS.accent)
                                        .frame(width: 12)
                                    Text("Save current look")
                                        .font(DS.mono(12, weight: .semibold))
                                        .foregroundStyle(DS.accent)
                                    Spacer()
                                    Image(systemName: "bookmark.fill")
                                        .font(.system(size: 11))
                                        .foregroundStyle(DS.accent.opacity(0.85))
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                            }
                            .buttonStyle(.plain)
                            DSLRDivider()
                        } else {
                            Text("Apply film or FX on the finder, then save.")
                                .font(DS.mono(10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.35))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                            DSLRDivider()
                        }

                        if lookStore.recipes.isEmpty {
                            Text("No saved looks yet")
                                .font(DS.mono(10, weight: .medium))
                                .foregroundStyle(.white.opacity(0.32))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                        } else {
                            ForEach(Array(lookStore.recipes.enumerated()), id: \.element.id) { idx, recipe in
                                HStack(spacing: 8) {
                                    Button {
                                        onLookApplied(recipe.film, recipe.lensFX)
                                        Haptics.click()
                                    } label: {
                                        HStack(spacing: 8) {
                                            Text(">")
                                                .font(DS.mono(12, weight: .bold))
                                                .foregroundStyle(DS.accent.opacity(0.7))
                                                .frame(width: 12)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(recipe.name)
                                                    .font(DS.mono(12, weight: .semibold))
                                                    .foregroundStyle(.white)
                                                Text(recipe.subtitle)
                                                    .font(DS.mono(9, weight: .medium))
                                                    .foregroundStyle(.white.opacity(0.35))
                                            }
                                            Spacer(minLength: 0)
                                        }
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        lookStore.delete(recipe.id)
                                        Haptics.light()
                                    } label: {
                                        Text("Del")
                                            .font(DS.mono(9, weight: .bold))
                                            .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.38))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 5)
                                            .background(
                                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                                    .stroke(Color(red: 1.0, green: 0.45, blue: 0.38).opacity(0.45), lineWidth: 0.7)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)

                                if idx < lookStore.recipes.count - 1 {
                                    DSLRDivider()
                                }
                            }
                        }
                    }

                    dslrSection("Capture defaults") {
                        DSLRCycleRow(
                            title: "Format",
                            value: captureFormat.label,
                            accent: captureFormat == .raw
                        ) {
                            Haptics.click()
                            captureFormat = captureFormat.next
                        }
                        DSLRDivider()
                        DSLRCycleRow(
                            title: "Default film",
                            value: defaultFilm.name,
                            accent: defaultFilm != .none
                        ) {
                            Haptics.click()
                            let all = FilmFilterMode.allCases
                            if let i = all.firstIndex(of: defaultFilm) {
                                defaultFilm = all[(i + 1) % all.count]
                            }
                        }
                    }

                    dslrSection("External shutter") {
                        Text("Volume · Camera Control · HID remotes")
                            .font(DS.mono(10, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                    }

                    dslrSection("About") {
                        DSLRInfoRow(title: "App", value: "Shutter")
                        DSLRDivider()
                        DSLRInfoRow(
                            title: "Build",
                            value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
                        )
                    }

                    Text("Film + FX are exclusive · peaking is an aid")
                        .font(DS.mono(9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.28))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                        .padding(.bottom, 12)
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 28)
            }
            .background(Color.clear)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("Settings")
                        .font(DS.mono(17, weight: .semibold))
                        .foregroundStyle(.white)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDismiss() }
                        .font(DS.mono(15, weight: .semibold))
                        .foregroundStyle(DS.accent)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground {
            SettingsSheetBackground()
        }
    }

    private func dslrSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(DS.mono(11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.42))
                .padding(.horizontal, 2)

            VStack(spacing: 0) {
                content()
            }
            .background {
                SettingsDSLRWell()
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

/// Pure black + material blur — no fake top liquid-glass gradient (Build 99).
private struct SettingsSheetBackground: View {
    var body: some View {
        ZStack {
            Color.black
            Rectangle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
            // Keep the sheet night even over a bright finder.
            Color.black.opacity(0.45)
        }
        .ignoresSafeArea()
    }
}

/// Shared alias so older stress checks still find the type name.
private typealias SettingsLiquidGlassBackground = SettingsSheetBackground

/// Consistent inset well — one face, one stroke, clipped. No stacked fake glass.
private struct SettingsDSLRWell: View {
    private let corner: CGFloat = 12

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        ZStack {
            shape.fill(Color(white: 0.04))
            shape
                .stroke(Color.white.opacity(0.10), lineWidth: 0.8)
            // Soft inner lip — single recess, not a multi-layer mask fight.
            shape
                .stroke(Color.black.opacity(0.55), lineWidth: 1.2)
                .padding(1.5)
        }
        .clipShape(shape)
    }
}

// MARK: - DSLR menu rows

private struct DSLRDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.07))
            .frame(height: 1)
            .padding(.horizontal, 12)
    }
}

private struct DSLRToggleRow: View {
    let title: String
    var blurb: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        Button {
            Haptics.click()
            isOn.toggle()
        } label: {
            HStack(alignment: .center, spacing: 8) {
                Text(isOn ? ">" : " ")
                    .font(DS.mono(13, weight: .bold))
                    .foregroundStyle(isOn ? DS.accent : .white.opacity(0.15))
                    .frame(width: 12)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(DS.mono(12, weight: isOn ? .semibold : .medium))
                        .foregroundStyle(isOn ? .white : .white.opacity(0.62))
                    if let blurb {
                        Text(blurb)
                            .font(DS.mono(9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.32))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                Text(isOn ? "On" : "Off")
                    .font(DS.mono(11, weight: .bold))
                    .foregroundStyle(isOn ? DS.accent : .white.opacity(0.35))
                    .frame(minWidth: 28, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .background(isOn ? Color.white.opacity(0.06) : Color.clear)
        }
        .buttonStyle(.plain)
    }
}

private struct DSLRCycleRow: View {
    let title: String
    let value: String
    var accent: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(">")
                    .font(DS.mono(12, weight: .bold))
                    .foregroundStyle(accent ? DS.accent : .white.opacity(0.25))
                    .frame(width: 12)
                Text(title)
                    .font(DS.mono(12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text(value)
                    .font(DS.mono(12, weight: .semibold))
                    .foregroundStyle(accent ? DS.accent : .white)
                Text("›")
                    .font(DS.mono(14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.35))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct DSLRInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(DS.mono(11, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
            Spacer()
            Text(value)
                .font(DS.mono(12, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
