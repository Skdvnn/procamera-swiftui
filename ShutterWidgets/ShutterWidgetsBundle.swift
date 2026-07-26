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
        if #available(iOS 18.0, *) {
            ShutterControlWidget()
        }
    }
}

// MARK: - Shared: overlapping recent frames

/// Two nicely overlapping recent stills — fills blank widget chrome.
struct WidgetRecentStack: View {
    let images: [UIImage]
    var large: Bool = false

    private let accent = Color(red: 1.0, green: 0.85, blue: 0.35)

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
                            .foregroundStyle(accent.opacity(0.7))
                        Text("SHOOT")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(accent.opacity(0.25), lineWidth: 0.8)
                )
                .rotationEffect(.degrees(5))
                .offset(x: 10, y: -4)
        }
    }
}

// MARK: - Home Screen: Launch

struct ShutterLaunchProvider: TimelineProvider {
    func placeholder(in context: Context) -> ShutterLaunchEntry {
        ShutterLaunchEntry(date: Date(), film: "Portra 400", fx: "None", recents: [])
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
        return ShutterLaunchEntry(
            date: Date(),
            film: ctx.filmName,
            fx: ctx.lensFXName,
            recents: ShutterAppGroup.loadRecentThumbnails()
        )
    }
}

struct ShutterLaunchEntry: TimelineEntry {
    let date: Date
    let film: String
    let fx: String
    let recents: [UIImage]
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
        .description("Jump straight into the viewfinder — with recent frames.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct ShutterLaunchView: View {
    var entry: ShutterLaunchEntry
    @Environment(\.widgetFamily) private var family

    private let accent = Color(red: 1.0, green: 0.85, blue: 0.35)

    var body: some View {
        Link(destination: ShutterDeepLink.openCamera.url) {
            switch family {
            case .systemLarge:
                largeBody
            case .systemMedium:
                mediumBody
            default:
                smallBody
            }
        }
    }

    private var smallBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "camera.fill")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("SHUTTER")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1)
            }
            .foregroundStyle(.white)

            WidgetRecentStack(images: entry.recents, large: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Text(entry.film.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(accent)
                .lineLimit(1)
            Text("TAP TO SHOOT")
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(12)
    }

    private var mediumBody: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Text("SHUTTER")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1)
                }
                .foregroundStyle(.white)

                Spacer(minLength: 0)

                Text(entry.film.uppercased())
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                if entry.fx != "None" {
                    Text(entry.fx.uppercased())
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(red: 0.55, green: 0.88, blue: 0.95))
                        .lineLimit(1)
                }
                Text(entry.recents.isEmpty ? "TAP TO SHOOT" : "RECENTS · TAP TO SHOOT")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            WidgetRecentStack(images: entry.recents, large: false)
                .frame(width: 120, height: 100)
        }
        .padding(14)
    }

    private var largeBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SHUTTER")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(1.5)
                        .foregroundStyle(.white.opacity(0.55))
                    Text(entry.film.uppercased())
                        .font(.system(size: 20, weight: .semibold, design: .monospaced))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                    if entry.fx != "None" {
                        Text(entry.fx.uppercased())
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color(red: 0.55, green: 0.88, blue: 0.95))
                    }
                }
                Spacer()
                Image(systemName: "camera.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(12)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }

            WidgetRecentStack(images: entry.recents, large: true)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Text(entry.recents.isEmpty ? "NO RECENTS YET" : "\(entry.recents.count) RECENT")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(accent.opacity(0.8))
                Spacer()
                Text("TAP TO SHOOT")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(16)
    }
}

// MARK: - Home Screen: Looks shortcuts

struct ShutterLooksProvider: TimelineProvider {
    func placeholder(in context: Context) -> ShutterLooksEntry {
        ShutterLooksEntry(date: Date(), looks: [
            ShutterLookChip(raw: "Portra 400|None", film: "Portra 400", fx: nil),
            ShutterLookChip(raw: "Tri-X 400|None", film: "Tri-X 400", fx: nil),
            ShutterLookChip(raw: "Velvia 50|None", film: "Velvia 50", fx: nil),
            ShutterLookChip(raw: "None|None", film: "Clean", fx: nil)
        ], recents: [])
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
        return ShutterLooksEntry(
            date: Date(),
            looks: looks,
            recents: ShutterAppGroup.loadRecentThumbnails()
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
    let recents: [UIImage]
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
        .description("One-tap film + FX looks, with recent frames.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct ShutterLooksView: View {
    var entry: ShutterLooksEntry
    @Environment(\.widgetFamily) private var family

    private let accent = Color(red: 1.0, green: 0.85, blue: 0.35)

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemLarge ? 12 : 10) {
            HStack {
                Text("LOOKS")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer()
                if family == .systemLarge {
                    Text("LCD")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(accent.opacity(0.7))
                }
            }
            .padding(.horizontal, 4)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(entry.looks, id: \.raw) { chip in
                    Link(destination: ShutterDeepLink.look(
                        film: chip.film == "Clean" ? "None" : chip.film,
                        fx: chip.fx
                    ).url) {
                        Text(chip.title.uppercased())
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, minHeight: family == .systemLarge ? 40 : 36)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 0.6)
                            )
                    }
                }
            }

            if family == .systemLarge {
                // Fill the large blank — overlapping recents + open darkroom.
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("RECENTS")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(accent.opacity(0.85))
                        Spacer()
                        Text(entry.recents.isEmpty ? "SHOOT TO FILL" : "TAP STACK")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.35))
                    }
                    .padding(.horizontal, 4)

                    Link(destination: ShutterDeepLink.darkroom.url) {
                        WidgetRecentStack(images: entry.recents, large: true)
                            .frame(maxWidth: .infinity)
                            .frame(height: 150)
                    }
                }
                .padding(.top, 4)
            } else if !entry.recents.isEmpty {
                // Medium: slim overlapping strip so it isn't empty under the chips.
                Link(destination: ShutterDeepLink.darkroom.url) {
                    HStack(spacing: 8) {
                        WidgetRecentStack(images: entry.recents, large: false)
                            .frame(width: 72, height: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("RECENTS")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(accent.opacity(0.8))
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
}

// MARK: - Lock Screen accessories

struct ShutterLockCircularWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ShutterLockCircular", provider: ShutterLaunchProvider()) { _ in
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "camera.fill")
                    .font(.system(size: 18, weight: .semibold))
            }
            .widgetURL(ShutterDeepLink.openCamera.url)
        }
        .configurationDisplayName("Shutter")
        .description("Open Shutter Cam from Lock Screen.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct ShutterLockRectangularWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ShutterLockRectangular", provider: ShutterLaunchProvider()) { entry in
            HStack(spacing: 8) {
                Image(systemName: "camera.fill")
                VStack(alignment: .leading, spacing: 1) {
                    Text("SHUTTER")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                    Text(entry.film)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .widgetURL(ShutterDeepLink.openCamera.url)
        }
        .configurationDisplayName("Shutter Look")
        .description("Current film look on Lock Screen.")
        .supportedFamilies([.accessoryRectangular])
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
