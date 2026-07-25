import WidgetKit
import SwiftUI
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

// MARK: - Home Screen: Launch

struct ShutterLaunchProvider: TimelineProvider {
    func placeholder(in context: Context) -> ShutterLaunchEntry {
        ShutterLaunchEntry(date: Date(), film: "Portra 400", fx: "None")
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
        return ShutterLaunchEntry(date: Date(), film: ctx.filmName, fx: ctx.lensFXName)
    }
}

struct ShutterLaunchEntry: TimelineEntry {
    let date: Date
    let film: String
    let fx: String
}

struct ShutterLaunchWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ShutterLaunchWidget", provider: ShutterLaunchProvider()) { entry in
            ShutterLaunchView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(
                        colors: [Color.black, Color(red: 0.12, green: 0.12, blue: 0.14)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
        }
        .configurationDisplayName("Shutter Cam")
        .description("Jump straight into the viewfinder.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ShutterLaunchView: View {
    var entry: ShutterLaunchEntry

    var body: some View {
        Link(destination: ShutterDeepLink.openCamera.url) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Text("SHUTTER")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1)
                }
                .foregroundStyle(.white)

                Spacer(minLength: 0)

                Text(entry.film.uppercased())
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(red: 1.0, green: 0.85, blue: 0.35))
                    .lineLimit(1)
                if entry.fx != "None" {
                    Text(entry.fx.uppercased())
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Color(red: 0.55, green: 0.88, blue: 0.95))
                        .lineLimit(1)
                }
                Text("TAP TO SHOOT")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(14)
        }
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
        ])
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
        return ShutterLooksEntry(date: Date(), looks: looks)
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
}

struct ShutterLooksWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ShutterLooksWidget", provider: ShutterLooksProvider()) { entry in
            ShutterLooksView(entry: entry)
                .containerBackground(for: .widget) { Color.black }
        }
        .configurationDisplayName("Shutter Looks")
        .description("One-tap film + FX looks.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct ShutterLooksView: View {
    var entry: ShutterLooksEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LOOKS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.5))
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
                            .frame(maxWidth: .infinity, minHeight: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.white.opacity(0.08))
                            )
                    }
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
