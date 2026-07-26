import WidgetKit
import SwiftUI
import UIKit
import AppIntents

// MARK: - Widget Bundle

@main
struct ShutterWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ShutterLaunchWidget()
        ShutterLooksWidget()
        ShutterLockCircularWidget()
        ShutterLockRectangularWidget()
        ShutterLockInlineWidget()
        if #available(iOS 18.0, *) {
            ShutterControlWidget()
        }
    }
}

// MARK: - Shared chrome

enum WidgetPalette {
    static let accent = Color(red: 1.0, green: 0.85, blue: 0.35)
    static let fx = Color(red: 0.55, green: 0.88, blue: 0.95)
    static let keep = Color(red: 0.55, green: 0.90, blue: 0.60)
}

/// Two nicely overlapping recent stills — the small widget's photo block.
struct WidgetRecentStack: View {
    let images: [UIImage]
    var large: Bool = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let cardW = large ? w * 0.58 : w * 0.62
            let cardH = large ? h * 0.88 : h * 0.92

            ZStack {
                if images.isEmpty {
                    emptyPlaceholders(cardW: cardW, cardH: cardH)
                } else {
                    if images.count >= 2 {
                        photoCard(images[1], width: cardW * 0.92, height: cardH * 0.92)
                            .rotationEffect(.degrees(-9))
                            .offset(x: -w * 0.12, y: h * 0.04)
                            .opacity(0.88)
                    }
                    photoCard(images[0], width: cardW, height: cardH)
                        .rotationEffect(.degrees(images.count >= 2 ? 6 : 0))
                        .offset(x: images.count >= 2 ? w * 0.10 : 0, y: images.count >= 2 ? -h * 0.02 : 0)
                        .shadow(color: .black.opacity(0.45), radius: 6, y: 3)
                }
            }
            .frame(width: w, height: h)
        }
        .accessibilityHidden(true)
    }

    private func photoCard(_ image: UIImage, width: CGFloat, height: CGFloat) -> some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: large ? 8 : 6, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: large ? 8 : 6, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
            )
    }

    /// Soft film frames when the user hasn't shot yet — still fills the blank.
    private func emptyPlaceholders(cardW: CGFloat, cardH: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .frame(width: cardW * 0.9, height: cardH * 0.9)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                )
                .rotationEffect(.degrees(-8))
                .offset(x: -14, y: 6)

            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.09))
                .frame(width: cardW, height: cardH)
                .overlay(
                    VStack(spacing: 4) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: large ? 18 : 14, weight: .semibold))
                            .foregroundStyle(WidgetPalette.accent.opacity(0.7))
                        Text("SHOOT")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(WidgetPalette.accent.opacity(0.25), lineWidth: 0.8)
                )
                .rotationEffect(.degrees(5))
                .offset(x: 10, y: -4)
        }
    }
}

/// Darkroom contact sheet — every recent frame gets a numbered cell, empty
/// slots read as unexposed film rather than dead space (Build 83).
struct WidgetContactSheet: View {
    let frames: [ShutterAppGroup.WidgetRecentFrame]
    var columns: Int = 3
    var rows: Int = 2
    var spacing: CGFloat = 4
    var corner: CGFloat = 5
    var numbered: Bool = true

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(0..<columns, id: \.self) { column in
                        cell(at: row * columns + column)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func cell(at index: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)
        ZStack(alignment: .topLeading) {
            if index < frames.count {
                Color.white.opacity(0.05)
                    .overlay(
                        Image(uiImage: frames[index].image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    )
                    .clipShape(shape)
                    .overlay(
                        shape.stroke(
                            index == 0
                                ? WidgetPalette.accent.opacity(0.65)
                                : Color.white.opacity(0.14),
                            lineWidth: index == 0 ? 1 : 0.6
                        )
                    )
                if frames[index].meta?.mark == "keep" {
                    Circle()
                        .fill(WidgetPalette.keep)
                        .frame(width: 5, height: 5)
                        .padding(4)
                }
            } else {
                shape
                    .fill(Color.white.opacity(0.04))
                    .overlay(shape.stroke(Color.white.opacity(0.07), lineWidth: 0.6))
            }

            if numbered {
                Text(String(format: "%02d", index + 1))
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(index < frames.count ? 0.55 : 0.18))
                    .padding(.horizontal, 3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Seven-day frame count. The bar you shot today burns accent.
struct WidgetWeekBars: View {
    let week: [Int]
    var labels: [String] = []
    var barHeight: CGFloat = 26
    var showLabels: Bool = true

    private var peak: Int { max(week.max() ?? 0, 1) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(week.enumerated()), id: \.offset) { index, count in
                VStack(spacing: 3) {
                    GeometryReader { geo in
                        let ratio = CGFloat(count) / CGFloat(peak)
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                .fill(
                                    index == week.count - 1
                                        ? WidgetPalette.accent
                                        : Color.white.opacity(count > 0 ? 0.32 : 0.12)
                                )
                                .frame(height: max(2, geo.size.height * ratio))
                        }
                    }
                    .frame(height: barHeight)

                    if showLabels {
                        Text(index < labels.count ? labels[index] : "")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundStyle(
                                .white.opacity(index == week.count - 1 ? 0.6 : 0.28)
                            )
                    }
                }
            }
        }
        .accessibilityLabel("Frames per day this week")
    }
}

/// Number over caption — the stat row under the contact sheet.
struct WidgetStatTile: View {
    let value: String
    let caption: String
    var tint: Color = .white
    var size: CGFloat = 15

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: size, weight: .semibold, design: .monospaced))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(caption)
                .font(.system(size: 7, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.35))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Home Screen: Launch

struct ShutterLaunchProvider: TimelineProvider {
    func placeholder(in context: Context) -> ShutterLaunchEntry {
        ShutterLaunchEntry(
            date: Date(),
            film: "Portra 400",
            fx: "None",
            frames: [],
            stats: ShutterStats.placeholder
        )
    }
    func getSnapshot(in context: Context, completion: @escaping (ShutterLaunchEntry) -> Void) {
        completion(currentEntry())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ShutterLaunchEntry>) -> Void) {
        let entry = currentEntry()
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(300))))
    }
    private func currentEntry() -> ShutterLaunchEntry {
        let ctx = ShutterCaptureContext.loadFromAppGroup()
        let frames = ShutterAppGroup.loadRecentFrames()
        let stats = ShutterAppGroup.loadStats()
        // Prefer film from latest unculled frame when present.
        // Explicit "None" means that frame was clean; do not relabel it with
        // whatever look happens to be selected now.
        let film: String
        let fx: String
        if let meta = frames.first?.meta {
            film = meta.filmFilter == "None" ? "Clean" : meta.filmFilter
            fx = meta.lensFX == "None" ? "None" : meta.lensFX
        } else {
            film = ctx.filmName
            fx = ctx.lensFXName
        }
        return ShutterLaunchEntry(
            date: Date(),
            film: film,
            fx: fx,
            frames: frames,
            stats: stats
        )
    }
}

struct ShutterLaunchEntry: TimelineEntry {
    let date: Date
    let film: String
    let fx: String
    let frames: [ShutterAppGroup.WidgetRecentFrame]
    let stats: ShutterStats

    var recents: [UIImage] { frames.map(\.image) }
    var latestMeta: ShutterAppGroup.WidgetRecentMeta? { frames.first?.meta }
}

struct ShutterLaunchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ShutterLaunchWidget", provider: ShutterLaunchProvider()) { entry in
            ShutterLaunchView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [
                            Color.black,
                            Color(red: 0.10, green: 0.10, blue: 0.12),
                            Color(red: 0.06, green: 0.06, blue: 0.07)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        }
        .configurationDisplayName("Shutter Cam")
        .description("Contact sheet, week of frames, and tap to shoot.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct ShutterLaunchView: View {
    var entry: ShutterLaunchEntry
    @Environment(\.widgetFamily) private var family

    private var accent: Color { WidgetPalette.accent }
    private var stats: ShutterStats { entry.stats }

    var body: some View {
        switch family {
        case .systemLarge:
            largeBody
        case .systemMedium:
            mediumBody
        default:
            smallBody
        }
    }

    /// Exposure of the newest frame, or the armed look before the first shot.
    private var headline: String {
        if let meta = entry.latestMeta, !meta.exposureLine.isEmpty {
            return meta.exposureLine.uppercased()
        }
        return entry.film.uppercased()
    }

    private var smallBody: some View {
        Link(destination: ShutterDeepLink.capture.url) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Text("SHUTTER")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(.white)
                    Spacer(minLength: 0)
                    Text("\(stats.framesToday)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(accent)
                    Text("TDY")
                        .font(.system(size: 7, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                }

                WidgetRecentStack(images: entry.recents, large: false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                WidgetWeekBars(
                    week: stats.week,
                    labels: stats.weekLabels,
                    barHeight: 14,
                    showLabels: false
                )

                Text(headline)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(footerLine)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(12)
        }
    }

    private var footerLine: String {
        guard stats.hasHistory else { return "TAP TO SHOOT" }
        return "\(stats.lastCaptureRelative) · \(stats.framesWeek) THIS WEEK"
    }

    private var mediumBody: some View {
        HStack(spacing: 12) {
            // Spacing is tight on purpose: an SE medium widget only offers
            // ~127pt of content height and this column stacks five rows.
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Text("SHUTTER")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(.white)
                    Spacer(minLength: 0)
                    Text("\(stats.framesToday)/\(ShutterStats.rollLength)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(accent)
                }

                WidgetWeekBars(
                    week: stats.week,
                    labels: stats.weekLabels,
                    barHeight: 24
                )

                VStack(alignment: .leading, spacing: 1) {
                    Text(headline)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(subhead)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 0)

                Link(destination: ShutterDeepLink.capture.url) {
                    HStack(spacing: 6) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text("SHOOT")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(accent))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Link(destination: ShutterDeepLink.darkroom.url) {
                VStack(spacing: 5) {
                    WidgetContactSheet(
                        frames: Array(entry.frames.prefix(4)),
                        columns: 2,
                        rows: 2,
                        numbered: false
                    )
                    .frame(width: 122, height: 96)

                    Text(
                        stats.hasHistory
                            ? "\(stats.unculled) UNCULLED · \(stats.keepers) KEEP"
                            : "NO FRAMES YET"
                    )
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                }
            }
        }
        .padding(12)
    }

    private var subhead: String {
        guard stats.hasHistory else { return "TAP SHOOT TO START THE ROLL" }
        var parts = ["\(stats.lastCaptureRelative) AGO"]
        if let meta = entry.latestMeta, meta.focalLength > 0 {
            parts.append("\(meta.focalLength)mm")
        }
        if !stats.topFilm.isEmpty {
            parts.append(stats.topFilm.uppercased())
        }
        return parts.joined(separator: " · ")
    }

    private var largeBody: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("SHUTTER")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(1.5)
                        .foregroundStyle(.white.opacity(0.55))
                    Text(entry.film.uppercased())
                        .font(.system(size: 19, weight: .semibold, design: .monospaced))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let meta = entry.latestMeta {
                        Text(meta.exposureLine.uppercased())
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                        Text("\(meta.relativeTime) AGO · \(meta.focalLength)mm")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.4))
                    } else if entry.fx != "None" {
                        Text(entry.fx.uppercased())
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(WidgetPalette.fx)
                    }
                }
                Spacer(minLength: 6)
                Link(destination: ShutterDeepLink.capture.url) {
                    VStack(spacing: 3) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(accent)
                        Text("SHOOT")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(9)
                    .background(Circle().fill(Color.white.opacity(0.08)))
                }
            }

            Link(destination: ShutterDeepLink.darkroom.url) {
                WidgetContactSheet(frames: entry.frames, columns: 3, rows: 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack(alignment: .bottom, spacing: 10) {
                WidgetWeekBars(week: stats.week, labels: stats.weekLabels, barHeight: 28)
                    .frame(width: 116)
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        WidgetStatTile(
                            value: "\(stats.framesToday)",
                            caption: "TODAY",
                            tint: accent
                        )
                        WidgetStatTile(value: "\(stats.framesWeek)", caption: "WEEK")
                        WidgetStatTile(value: "\(stats.keepers)", caption: "KEEP")
                        WidgetStatTile(value: "\(stats.unculled)", caption: "UNCULLED")
                    }
                    Text(rollLine)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.35))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }
        .padding(16)
    }

    private var rollLine: String {
        guard stats.hasHistory else { return "TAP A FRAME FOR THE DARKROOM" }
        var parts = ["\(stats.framesTotal) TOTAL"]
        if !stats.topFilm.isEmpty {
            parts.append("\(stats.topFilm.uppercased()) ×\(stats.topFilmCount)")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Home Screen: Looks shortcuts

struct ShutterLooksProvider: TimelineProvider {
    func placeholder(in context: Context) -> ShutterLooksEntry {
        ShutterLooksEntry(
            date: Date(),
            looks: [
                ShutterLookChip(raw: "Portra 400|None", film: "Portra 400", fx: nil),
                ShutterLookChip(raw: "Tri-X 400|None", film: "Tri-X 400", fx: nil),
                ShutterLookChip(raw: "Velvia 50|None", film: "Velvia 50", fx: nil),
                ShutterLookChip(raw: "None|None", film: "Clean", fx: nil)
            ],
            armed: "Portra 400|None",
            frames: [],
            stats: ShutterStats.placeholder
        )
    }
    func getSnapshot(in context: Context, completion: @escaping (ShutterLooksEntry) -> Void) {
        completion(current())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<ShutterLooksEntry>) -> Void) {
        completion(Timeline(entries: [current()], policy: .after(Date().addingTimeInterval(600))))
    }
    private func current() -> ShutterLooksEntry {
        let defaults = ShutterAppGroup.defaults
        let saved = defaults.stringArray(forKey: "widget.lookNames") ?? []
        let tokens = saved.isEmpty
            ? ["Portra 400|None", "Tri-X 400|None", "Velvia 50|None", "None|None"]
            : Array(saved.prefix(4))
        let looks = tokens.map { raw -> ShutterLookChip in
            // Backward compatible: plain film name without "|" still works.
            if raw.contains("|") {
                let decoded = ShutterAppGroup.decodeLook(raw)
                return ShutterLookChip(raw: raw, film: decoded.film, fx: decoded.fx)
            }
            return ShutterLookChip(raw: raw, film: raw == "None" ? "Clean" : raw, fx: nil)
        }
        let ctx = ShutterCaptureContext.loadFromAppGroup()
        return ShutterLooksEntry(
            date: Date(),
            looks: looks,
            armed: ShutterAppGroup.encodeLook(film: ctx.filmName, fx: ctx.lensFXName),
            frames: ShutterAppGroup.loadRecentFrames(),
            stats: ShutterAppGroup.loadStats()
        )
    }
}

struct ShutterLookChip: Hashable {
    let raw: String
    let film: String
    let fx: String?
    var title: String {
        if let fx, fx != "None", !fx.isEmpty {
            return "\(film) · \(fx)"
        }
        return film
    }
}

struct ShutterLooksEntry: TimelineEntry {
    let date: Date
    let looks: [ShutterLookChip]
    /// Encoded `film|fx` currently loaded in the app, so one chip reads as armed.
    let armed: String
    let frames: [ShutterAppGroup.WidgetRecentFrame]
    let stats: ShutterStats

    var recents: [UIImage] { frames.map(\.image) }
}

struct ShutterLooksWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ShutterLooksWidget", provider: ShutterLooksProvider()) { entry in
            ShutterLooksView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [Color.black, Color(red: 0.08, green: 0.08, blue: 0.09)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
        }
        .configurationDisplayName("Shutter Looks")
        .description("One-tap film + FX looks, armed look, and recent frames.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct ShutterLooksView: View {
    var entry: ShutterLooksEntry
    @Environment(\.widgetFamily) private var family

    private var accent: Color { WidgetPalette.accent }
    private var stats: ShutterStats { entry.stats }

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemLarge ? 10 : 6) {
            HStack {
                Text("LOOKS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                Text(armedTitle.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(accent.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 4)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(entry.looks, id: \.raw) { chip in
                    Link(destination: ShutterDeepLink.look(
                        film: chip.film == "Clean" ? "None" : chip.film,
                        fx: chip.fx
                    ).url) {
                        chipBody(chip)
                    }
                }
            }

            if family == .systemLarge {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("RECENTS")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(accent.opacity(0.85))
                        Spacer()
                        Text(entry.recents.isEmpty ? "SHOOT TO FILL" : "TAP THE SHEET")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    .padding(.horizontal, 4)

                    Link(destination: ShutterDeepLink.darkroom.url) {
                        WidgetContactSheet(frames: entry.frames, columns: 3, rows: 2)
                            .frame(maxWidth: .infinity)
                            .frame(height: 132)
                    }

                    HStack(alignment: .bottom, spacing: 10) {
                        WidgetWeekBars(
                            week: stats.week,
                            labels: stats.weekLabels,
                            barHeight: 22
                        )
                        .frame(width: 110)
                        HStack(spacing: 8) {
                            WidgetStatTile(
                                value: "\(stats.framesToday)",
                                caption: "TODAY",
                                tint: accent,
                                size: 13
                            )
                            WidgetStatTile(
                                value: "\(stats.framesWeek)",
                                caption: "WEEK",
                                size: 13
                            )
                            WidgetStatTile(
                                value: "\(stats.unculled)",
                                caption: "UNCULLED",
                                size: 13
                            )
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .padding(.top, 2)
            } else {
                // Medium: slim sheet + counts so the space under the chips works.
                Link(destination: ShutterDeepLink.darkroom.url) {
                    HStack(spacing: 8) {
                        WidgetContactSheet(
                            frames: Array(entry.frames.prefix(3)),
                            columns: 3,
                            rows: 1,
                            numbered: false
                        )
                        .frame(width: 132, height: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(
                                stats.hasHistory
                                    ? "\(stats.framesToday) TODAY · \(stats.framesWeek) WK"
                                    : "RECENTS"
                            )
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(accent.opacity(0.85))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            Text("OPEN DARKROOM")
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(12)
    }

    private var armedTitle: String {
        let decoded = ShutterAppGroup.decodeLook(entry.armed)
        let film = decoded.film == "None" ? "Clean" : decoded.film
        if let fx = decoded.fx {
            return "ARMED \(film) · \(fx)"
        }
        return "ARMED \(film)"
    }

    private func chipBody(_ chip: ShutterLookChip) -> some View {
        let isArmed = chip.raw == entry.armed
        return HStack(spacing: 5) {
            Circle()
                .fill(isArmed ? accent : Color.white.opacity(0.18))
                .frame(width: 5, height: 5)
            Text(chip.title.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(isArmed ? accent : .white)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: family == .systemLarge ? 38 : 28)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(isArmed ? 0.13 : 0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isArmed ? accent.opacity(0.55) : Color.white.opacity(0.08),
                    lineWidth: isArmed ? 1 : 0.6
                )
        )
    }
}

// MARK: - Lock Screen accessories

struct ShutterLockCircularWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ShutterLockCircular", provider: ShutterLaunchProvider()) { entry in
            ZStack {
                AccessoryWidgetBackground()
                Gauge(value: entry.stats.rollProgress) {
                    Image(systemName: "camera.fill")
                } currentValueLabel: {
                    Text("\(entry.stats.framesToday)")
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                }
                .gaugeStyle(.accessoryCircularCapacity)
            }
            .widgetURL(ShutterDeepLink.capture.url)
        }
        .configurationDisplayName("Shutter Roll")
        .description("Frames shot today against a 36-exposure roll.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct ShutterLockRectangularWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ShutterLockRectangular", provider: ShutterLaunchProvider()) { entry in
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("SHUTTER")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                    Spacer(minLength: 0)
                    Text("\(entry.stats.framesToday)/\(ShutterStats.rollLength)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }
                if let meta = entry.latestMeta {
                    Text(meta.exposureLine)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("\(meta.relativeTime) · \(entry.film.uppercased())")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } else {
                    Text(entry.film)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                    Text("TAP TO SHOOT")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(ShutterDeepLink.capture.url)
        }
        .configurationDisplayName("Shutter Frame")
        .description("Last exposure, roll count, and tap to shoot.")
        .supportedFamilies([.accessoryRectangular])
    }
}

struct ShutterLockInlineWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ShutterLockInline", provider: ShutterLaunchProvider()) { entry in
            Label(inlineText(entry), systemImage: "camera.fill")
                .widgetURL(ShutterDeepLink.capture.url)
        }
        .configurationDisplayName("Shutter Count")
        .description("Today's frame count above the clock.")
        .supportedFamilies([.accessoryInline])
    }

    private func inlineText(_ entry: ShutterLaunchEntry) -> String {
        guard entry.stats.hasHistory else { return "Shutter · tap to shoot" }
        if let meta = entry.latestMeta, !meta.exposureLine.isEmpty {
            return "\(entry.stats.framesToday) today · \(meta.exposureLine)"
        }
        return "\(entry.stats.framesToday) today · \(entry.film)"
    }
}

// MARK: - Control Center / Action Button (iOS 18)

@available(iOS 18.0, *)
struct ShutterControlWidget: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "ShutterControlWidget") {
            ControlWidgetButton(action: ShutterCameraCaptureIntent()) {
                Label("Shutter Cam", systemImage: "camera.fill")
            }
        }
        .displayName("Shutter Cam")
        .description("Open Shutter Cam capture.")
    }
}
