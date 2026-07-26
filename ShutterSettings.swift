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

// MARK: - Settings sheet (frosted glass + DSLR inset menu — no lame List toggles)

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
                VStack(alignment: .leading, spacing: 18) {
                    dslrSection("IMAGE HONESTY") {
                        DSLRToggleRow(
                            title: "NATURAL CAPTURE",
                            blurb: naturalCapture
                                ? "Less Apple fusion · looks still bake"
                                : "Polished ISP · looks still bake",
                            isOn: $naturalCapture
                        )
                    }

                    dslrSection("VIEWFINDER") {
                        DSLRToggleRow(title: "GRID", blurb: "Rule-of-thirds overlay", isOn: $showGrid)
                        DSLRDivider()
                        DSLRToggleRow(title: "FOCUS PEAKING", blurb: "Green edge aid — not a look", isOn: $focusPeaking)
                        DSLRDivider()
                        DSLRToggleRow(title: "ZEBRA", blurb: "Highlight warning", isOn: $zebraEnabled)
                        DSLRDivider()
                        DSLRToggleRow(title: "HORIZON LEVEL", blurb: "Spirit bar in the info glass", isOn: $showLevel)
                    }

                    dslrSection("ASSIST") {
                        DSLRToggleRow(title: "NIGHT TIP", blurb: "Opt-in when AUTO is dark", isOn: $nightAssist)
                        DSLRDivider()
                        DSLRToggleRow(title: "HOLD BURST", blurb: "Up to 6 stills while held", isOn: $holdBurst)
                    }

                    dslrSection("SAVED LOOKS") {
                        if filmFilter != .none || lensFX != .none {
                            Button {
                                LookRecipeStore.shared.saveCurrent(film: filmFilter, lensFX: lensFX)
                                Haptics.medium()
                            } label: {
                                HStack(spacing: 8) {
                                    Text(">")
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        .foregroundStyle(DS.accent)
                                        .frame(width: 12)
                                    Text("SAVE CURRENT LOOK")
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
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
                            Text("  Apply film or FX on the finder, then save.")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.35))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                            DSLRDivider()
                        }

                        if lookStore.recipes.isEmpty {
                            Text("  NO SAVED LOOKS YET")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
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
                                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                                .foregroundStyle(DS.accent.opacity(0.7))
                                                .frame(width: 12)
                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(recipe.name.uppercased())
                                                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                                    .foregroundStyle(.white)
                                                Text(recipe.subtitle.uppercased())
                                                    .font(.system(size: 9, weight: .medium, design: .monospaced))
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
                                        Text("DEL")
                                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                                            .foregroundStyle(Color(red: 1.0, green: 0.45, blue: 0.38))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 5)
                                            .background(
                                                RoundedRectangle(cornerRadius: 4)
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

                    dslrSection("CAPTURE DEFAULTS") {
                        DSLRCycleRow(
                            title: "FORMAT",
                            value: captureFormat.label,
                            accent: captureFormat == .raw
                        ) {
                            Haptics.click()
                            captureFormat = captureFormat.next
                        }
                        DSLRDivider()
                        DSLRCycleRow(
                            title: "DEFAULT FILM",
                            value: defaultFilm.name.uppercased(),
                            accent: defaultFilm != .none
                        ) {
                            Haptics.click()
                            let all = FilmFilterMode.allCases
                            if let i = all.firstIndex(of: defaultFilm) {
                                defaultFilm = all[(i + 1) % all.count]
                            }
                        }
                    }

                    dslrSection("EXTERNAL SHUTTER") {
                        Text("  Volume · Camera Control · HID remotes")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.4))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                    }

                    dslrSection("ABOUT") {
                        DSLRInfoRow(title: "APP", value: "SHUTTER")
                        DSLRDivider()
                        DSLRInfoRow(
                            title: "BUILD",
                            value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
                        )
                    }

                    Text("FILM + FX ARE EXCLUSIVE · PEAKING IS AN AID")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(.white.opacity(0.28))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                        .padding(.bottom, 12)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(Color.clear)
            .navigationTitle("SETTINGS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDismiss() }
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundStyle(DS.accent)
                }
            }
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.ultraThinMaterial)
    }

    private func dslrSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(DS.accent.opacity(0.9))
                .padding(.horizontal, 4)
                .padding(.bottom, 6)

            VStack(spacing: 0) {
                content()
            }
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black.opacity(0.42))
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                    // Inset DSLR well lip
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.14),
                                    Color.black.opacity(0.55),
                                    Color.white.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.black.opacity(0.55), lineWidth: 1.5)
                        .padding(2)
                }
            )
        }
    }
}

// MARK: - DSLR menu rows

private struct DSLRDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(height: 1)
            .padding(.horizontal, 10)
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
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(DS.accent)
                    .frame(width: 12)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 12, weight: isOn ? .semibold : .medium, design: .monospaced))
                        .foregroundStyle(isOn ? .white : .white.opacity(0.62))
                    if let blurb {
                        Text(blurb.uppercased())
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.32))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                Text(isOn ? "ON" : "OFF")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(isOn ? DS.accent : .white.opacity(0.35))
                    .frame(minWidth: 28, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
            .background(isOn ? Color.white.opacity(0.05) : Color.clear)
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
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundStyle(accent ? DS.accent : .white.opacity(0.35))
                    .frame(width: 12)
                Text(title)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text(value)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(accent ? DS.accent : .white)
                Text("›")
                    .font(.system(size: 14, weight: .semibold))
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
            Text("  " + title)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(DS.accent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}
