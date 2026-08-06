import SwiftUI
import AVFoundation

// MARK: - Shoot modes (not fake P/A/S/M — practical presets)

enum ShootMode: String, CaseIterable, Identifiable {
    /// Continuous AE that watches light and soft-suggests a SCENE (Build 105).
    case auto
    case street, night, studio, film

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "Auto"
        case .street: return "Street"
        case .night: return "Night"
        case .studio: return "Studio"
        case .film: return "Film"
        }
    }

    var blurb: String {
        switch self {
        case .auto: return "Watch light · suggest SCENE"
        case .street: return "Fast shutter · grid on"
        case .night: return "1/15 · ISO 1600 · clean"
        case .studio: return "Manual lock · peaking"
        case .film: return "Stock-first · soft defaults"
        }
    }

    var icon: String {
        switch self {
        case .auto: return "circle.lefthalf.filled"
        case .street: return "figure.walk"
        case .night: return "moon.stars"
        case .studio: return "lamp.desk"
        case .film: return "film"
        }
    }
}

// MARK: - Auto SCENE advisor (ISO / shutter / hist → soft pick)

/// Opt-in chip pick — never silent-applies mid-shoot (same contract as Night tip).
enum AutoScenePick: String, Equatable {
    case night, street, film

    var mode: ShootMode {
        switch self {
        case .night: return .night
        case .street: return .street
        case .film: return .film
        }
    }

    /// LCD chip lead — condition rationale, not the mode name.
    var chipLead: String {
        switch self {
        case .night: return "DARK"
        case .street: return "BRIGHT"
        case .film: return "DAY"
        }
    }

    var chipAction: String {
        switch self {
        case .night: return "TAP FOR NIGHT"
        case .street: return "TAP FOR STREET"
        case .film: return "TAP FOR FILM"
        }
    }

    var toast: String {
        switch self {
        case .night: return "AUTO · NIGHT · 1/15 · ISO 1600"
        case .street: return "AUTO · STREET · 1/250 · ISO 400"
        case .film: return "AUTO · FILM · 1/60 · stock"
        }
    }
}

enum AutoSceneAdvisor {
    /// Pick a SCENE from live AE + optional luminance histogram.
    /// Returns nil when the scene is ambiguous (stay on AUTO).
    static func pick(
        iso: Float,
        shutterLabel: String,
        histogram: [Float] = []
    ) -> AutoScenePick? {
        let seconds = parseShutterSeconds(shutterLabel)
        let lowKey = histogramBias(histogram) < -0.18
        let highKey = histogramBias(histogram) > 0.22

        // Night — same spine as the old Night tip, plus low-key hist boost.
        let darkISO = iso >= 1000 || (lowKey && iso >= 640)
        let darkShutter = (seconds ?? 0) >= (1.0 / 30.0) - 0.0005
        if darkISO || darkShutter { return .night }

        // Street — bright daylight / fast AE (freeze motion).
        if let seconds,
           iso > 0, iso <= 320,
           seconds > 0, seconds <= (1.0 / 200.0) + 0.0005 {
            return .street
        }
        if highKey, iso > 0, iso <= 400 { return .street }

        // Film — moderate daylight; stock-first look without locking AE.
        if let seconds,
           iso >= 100, iso <= 800,
           seconds >= (1.0 / 250.0) - 0.0005,
           seconds <= (1.0 / 30.0) + 0.0005 {
            return .film
        }

        return nil
    }

    /// −1…+1 — negative = crushed shadows, positive = blown highlights.
    private static func histogramBias(_ bins: [Float]) -> Float {
        guard bins.count >= 8 else { return 0 }
        let n = bins.count
        let low = bins.prefix(n / 4).reduce(0, +)
        let high = bins.suffix(n / 4).reduce(0, +)
        let mid = bins.dropFirst(n / 4).prefix(n / 2).reduce(0, +)
        let total = max(0.001, low + mid + high)
        return (high - low) / total
    }

    static func parseShutterSeconds(_ label: String) -> Double? {
        let t = label.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, t != "AUTO" else { return nil }
        if t.hasSuffix("\"") {
            return Double(t.dropLast())
        }
        if t.hasPrefix("1/") {
            let denom = Double(t.dropFirst(2)) ?? 0
            guard denom > 0 else { return nil }
            return 1.0 / denom
        }
        return Double(t)
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
    @Binding var minimalismMode: Bool
    @Binding var compactTop: Bool
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
                                ? "12MP WYSIWYG · no deferred HDR · looks still bake"
                                : "Max-res polished ISP · looks still bake",
                            isOn: $naturalCapture
                        )
                    }

                    dslrSection("Viewfinder") {
                        DSLRToggleRow(
                            title: "Minimalism",
                            blurb: "Finder · shutter · gestures — quiet Minolta",
                            isOn: $minimalismMode
                        )
                        DSLRDivider()
                        DSLRToggleRow(
                            title: "Compact top",
                            blurb: "Focus · EV · level strip — fuller finder",
                            isOn: $compactTop
                        )
                        DSLRDivider()
                        DSLRToggleRow(title: "Grid", blurb: "Rule-of-thirds overlay", isOn: $showGrid)
                        DSLRDivider()
                        DSLRToggleRow(title: "Focus peaking", blurb: "Green edge aid — not a look", isOn: $focusPeaking)
                        DSLRDivider()
                        DSLRToggleRow(title: "Zebra", blurb: "Highlight warning", isOn: $zebraEnabled)
                        DSLRDivider()
                        DSLRToggleRow(title: "Horizon level", blurb: "Spirit bar under the EV meter", isOn: $showLevel)
                    }

                    dslrSection("Assist") {
                        DSLRToggleRow(
                            title: "Scene tip",
                            blurb: "AUTO suggests Night · Street · Film",
                            isOn: $nightAssist
                        )
                        DSLRDivider()
                        DSLRToggleRow(title: "Hold burst", blurb: "Up to 6 stills while held", isOn: $holdBurst)
                    }

                    dslrSection("Saved looks") {
                        if filmFilter != .none || lensFX != .none {
                            Button {
                                LookRecipeStore.shared.saveCurrent(film: filmFilter, lensFX: lensFX)
                                Haptics.medium()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "bookmark.fill")
                                        .font(.system(size: 11))
                                    Text("Save current look")
                                        .font(DS.mono(12, weight: .semibold))
                                }
                                .foregroundStyle(DS.accent)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .stroke(DS.accent.opacity(0.45), lineWidth: 0.7)
                                )
                                .fixedSize(horizontal: true, vertical: true)
                            }
                            .buttonStyle(.plain)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
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
