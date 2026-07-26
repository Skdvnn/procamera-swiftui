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

// MARK: - Settings sheet (dark liquid glass + DSLR inset menu — no lame List toggles)

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
                        DSLRToggleRow(title: "HORIZON LEVEL", blurb: "Spirit bar under the EV meter", isOn: $showLevel)
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
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        // Always dark liquid glass — never the light system sheet (Build 84).
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground {
            SettingsLiquidGlassBackground()
        }
    }

    private func dslrSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                // Tiny instrument screw — same language as the dial faces.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.28),
                                Color.white.opacity(0.06),
                                Color.black.opacity(0.55)
                            ],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: 4
                        )
                    )
                    .frame(width: 5, height: 5)
                    .overlay(
                        Circle()
                            .stroke(Color.black.opacity(0.65), lineWidth: 0.5)
                    )
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(DS.accent.opacity(0.9))
                Spacer(minLength: 0)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.22),
                                Color.white.opacity(0.05),
                                Color.black.opacity(0.55)
                            ],
                            center: .topLeading,
                            startRadius: 0,
                            endRadius: 4
                        )
                    )
                    .frame(width: 5, height: 5)
                    .overlay(
                        Circle()
                            .stroke(Color.black.opacity(0.65), lineWidth: 0.5)
                    )
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 6)

            VStack(spacing: 0) {
                content()
            }
            .background {
                SettingsDSLRWell()
            }
        }
    }
}

/// Dark liquid glass under the settings sheet — black wash + material so it
/// never washes out over a bright finder (Build 84).
private struct SettingsLiquidGlassBackground: View {
    var body: some View {
        ZStack {
            // Deep ink base — the sheet is always night.
            Color.black.opacity(0.72)
            Rectangle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
            // Soft vignette so the glass reads as a panel, not a flat film.
            LinearGradient(
                colors: [
                    Color.white.opacity(0.07),
                    Color.clear,
                    Color.black.opacity(0.35)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            // Hairline top lip — liquid edge catching a little light.
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.22),
                        Color.white.opacity(0.04),
                        Color.clear
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 18)
                Spacer(minLength: 0)
            }
        }
        .ignoresSafeArea()
    }
}

/// Inset instrument well for each settings group — deeper lip, inner rail,
/// and corner screws so the containers feel machined, not flat cards.
private struct SettingsDSLRWell: View {
    private let corner: CGFloat = 12

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(Color.black.opacity(0.55))
            // LCD wash — barely lifts the well off pure black.
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.055),
                            Color.white.opacity(0.015),
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            // Outer bevel lip
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.22),
                            Color.white.opacity(0.06),
                            Color.black.opacity(0.70),
                            Color.white.opacity(0.08)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.1
                )
            // Inner rail — the machined recess.
            RoundedRectangle(cornerRadius: corner - 2.5, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0.75),
                            Color.black.opacity(0.25),
                            Color.white.opacity(0.05)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.4
                )
                .padding(2.5)
            // Hairline floor shadow inside the well
            RoundedRectangle(cornerRadius: corner - 3, style: .continuous)
                .stroke(Color.black.opacity(0.45), lineWidth: 0.8)
                .padding(4)
            // Corner screws
            GeometryReader { geo in
                let inset: CGFloat = 7
                let screws: [(CGFloat, CGFloat, Double)] = [
                    (inset, inset, -28),
                    (geo.size.width - inset, inset, 28),
                    (inset, geo.size.height - inset, 28),
                    (geo.size.width - inset, geo.size.height - inset, -28)
                ]
                ForEach(Array(screws.enumerated()), id: \.offset) { _, screw in
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color.white.opacity(0.30),
                                    Color(white: 0.18),
                                    Color.black.opacity(0.85)
                                ],
                                center: .topLeading,
                                startRadius: 0,
                                endRadius: 5
                            )
                        )
                        .frame(width: 4.5, height: 4.5)
                        .overlay(
                            Circle()
                                .stroke(Color.black.opacity(0.7), lineWidth: 0.4)
                        )
                        // Slot mark
                        .overlay(
                            Capsule()
                                .fill(Color.black.opacity(0.55))
                                .frame(width: 2.4, height: 0.6)
                                .rotationEffect(.degrees(screw.2))
                        )
                        .position(x: screw.0, y: screw.1)
                }
            }
            .allowsHitTesting(false)
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
            .background(isOn ? Color.white.opacity(0.07) : Color.clear)
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
