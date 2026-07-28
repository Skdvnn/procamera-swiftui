import SwiftUI
import UIKit

// Simple haptics for this file
private struct VFHaptics {
    static func click() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// MARK: - Cached grain textures (Canvas re-raster was a major lag source)

enum CachedGrainTexture {
    private static var cache: [Int: UIImage] = [:]
    private static var order: [Int] = []
    private static let maxEntries = 12
    private static let lock = NSLock()

    static func image(for size: CGSize, density: CGFloat, seed: UInt64, darkSpeckDensity: CGFloat = 0) -> UIImage {
        let w = max(64, (Int(size.width) / 64) * 64)
        let h = max(64, (Int(size.height) / 64) * 64)
        let key = (w &<< 20)
            ^ (h &<< 4)
            ^ Int(density * 100_000)
            ^ (Int(darkSpeckDensity * 100_000) &<< 8)
            ^ Int(seed & 0xFFFF)
        lock.lock()
        if let hit = cache[key] {
            lock.unlock()
            return hit
        }
        lock.unlock()

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: format)
        let img = renderer.image { ctx in
            UIColor.clear.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            var rng = SeededGenerator(seed: seed)
            let count = Int(CGFloat(w * h) * density)
            for _ in 0..<count {
                let x = CGFloat.random(in: 0...CGFloat(w), using: &rng)
                let y = CGFloat.random(in: 0...CGFloat(h), using: &rng)
                let opacity = CGFloat.random(in: 0.02...0.08, using: &rng)
                let dot = CGFloat.random(in: 0.8...1.6, using: &rng)
                UIColor.white.withAlphaComponent(opacity).setFill()
                ctx.cgContext.fillEllipse(in: CGRect(x: x, y: y, width: dot, height: dot))
            }
            if darkSpeckDensity > 0 {
                let darkCount = Int(CGFloat(w * h) * darkSpeckDensity)
                for _ in 0..<darkCount {
                    let x = CGFloat.random(in: 0...CGFloat(w), using: &rng)
                    let y = CGFloat.random(in: 0...CGFloat(h), using: &rng)
                    let opacity = CGFloat.random(in: 0.08...0.15, using: &rng)
                    UIColor.black.withAlphaComponent(opacity).setFill()
                    ctx.cgContext.fillEllipse(in: CGRect(x: x, y: y, width: 1, height: 1))
                }
            }
        }
        lock.lock()
        cache[key] = img
        order.append(key)
        while order.count > maxEntries {
            cache.removeValue(forKey: order.removeFirst())
        }
        lock.unlock()
        return img
    }
}

// MARK: - Film Grain Overlay
struct FilmGrainOverlay: View {
    var body: some View {
        // One rasterized texture per size bucket — never re-draw thousands of ellipses.
        GeometryReader { geo in
            Image(uiImage: CachedGrainTexture.image(for: geo.size, density: 0.006, seed: 0xC0FFEE))
                .resizable()
                .interpolation(.none)
                .scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()
        }
        .allowsHitTesting(false)
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0xdeadbeef : seed }
    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
}

/// Film / FX / looks menus.
enum ChromePickerMenu: String, Identifiable, CaseIterable {
    case film, fx, looks
    var id: String { rawValue }
}

/// Snapshot of looks for the picker window — never a Binding into ContentView.
@MainActor
final class ChromePickerSession {
    let menu: ChromePickerMenu
    var filmFilter: FilmFilterMode
    var lensFX: LensFXMode
    var focusPeaking: Bool
    var shootMode: ShootMode?
    var compactChrome: Bool

    init(
        menu: ChromePickerMenu,
        filmFilter: FilmFilterMode,
        lensFX: LensFXMode,
        focusPeaking: Bool,
        shootMode: ShootMode?,
        compactChrome: Bool
    ) {
        self.menu = menu
        self.filmFilter = filmFilter
        self.lensFX = lensFX
        self.focusPeaking = focusPeaking
        self.shootMode = shootMode
        self.compactChrome = compactChrome
    }
}

/// Result committed when the picker window closes.
struct ChromePickerCommit {
    var filmFilter: FilmFilterMode
    var lensFX: LensFXMode
    var focusPeaking: Bool
    var shootMode: ShootMode?
    var filmAppliedDirectly: Bool
    var saveLook: Bool
}

/// Presents film/FX/looks in a **separate UIWindow** with a **UIKit** table —
/// no UIHostingController. SwiftUI hosting (even off-camera) still hit
/// `swift::_getWitnessTable` / MetadataCache on device when opened from the
/// Metal finder chrome.
@MainActor
enum ChromePickerGate {
    private static var overlayWindow: UIWindow?
    private static var currentMenu: ChromePickerMenu?
    private static var session: ChromePickerSession?
    private static var onCommit: ((ChromePickerCommit) -> Void)?
    /// Called when the overlay window is gone. `willCommit` is true when a
    /// commit block will run on the next turn — keep Metal parked until then.
    private static var onTeardown: ((Bool) -> Void)?
    /// Park live Metal *after* the touch ends, just before the window appears.
    private static var onWillPresent: (() -> Void)?
    private static var filmAppliedDirectly = false
    private static var pendingSaveLook = false
    /// Invalidates a deferred present if dismiss raced ahead of it.
    private static var presentationToken = UUID()

    static var isPresented: Bool { overlayWindow != nil }

    static func dismiss(commit: Bool = true) {
        presentationToken = UUID()
        let sess = session
        let commitHandler = onCommit
        let teardown = onTeardown
        let applied = filmAppliedDirectly
        let save = pendingSaveLook
        let menu = currentMenu

        overlayWindow?.isHidden = true
        overlayWindow?.rootViewController = nil
        overlayWindow = nil
        session = nil
        currentMenu = nil
        onCommit = nil
        onTeardown = nil
        onWillPresent = nil
        filmAppliedDirectly = false
        pendingSaveLook = false

        let willCommit = commit && sess != nil && commitHandler != nil
        teardown?(willCommit)

        guard willCommit, let sess, let commitHandler else { return }
        let result = ChromePickerCommit(
            filmFilter: sess.filmFilter,
            lensFX: sess.lensFX,
            focusPeaking: sess.focusPeaking,
            shootMode: menu == .film ? sess.shootMode : nil,
            filmAppliedDirectly: applied,
            saveLook: save
        )
        // Apply AFTER the overlay window is gone — never during Metal invalidation.
        DispatchQueue.main.async {
            commitHandler(result)
        }
    }

    static func toggle(
        _ menu: ChromePickerMenu,
        filmFilter: FilmFilterMode,
        lensFX: LensFXMode,
        focusPeaking: Bool,
        shootMode: ShootMode?,
        compactChrome: Bool,
        onWillPresent: (() -> Void)? = nil,
        onCommit: @escaping (ChromePickerCommit) -> Void,
        onTeardown: ((Bool) -> Void)? = nil
    ) {
        // EVERYTHING deferred — sync dismiss/present on the Metal-chrome button
        // turn was freezing the finder (FPS collapse → EXC_BAD_ACCESS witness table).
        let token = UUID()
        presentationToken = token
        self.onWillPresent = onWillPresent
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard presentationToken == token else {
                onTeardown?(false)
                return
            }
            if currentMenu == menu, overlayWindow != nil {
                dismiss(commit: true)
                return
            }
            if overlayWindow != nil {
                dismiss(commit: true)
            }
            present(
                menu,
                filmFilter: filmFilter,
                lensFX: lensFX,
                focusPeaking: focusPeaking,
                shootMode: shootMode,
                compactChrome: compactChrome,
                onCommit: onCommit,
                onTeardown: onTeardown
            )
        }
    }

    private static func present(
        _ menu: ChromePickerMenu,
        filmFilter: FilmFilterMode,
        lensFX: LensFXMode,
        focusPeaking: Bool,
        shootMode: ShootMode?,
        compactChrome: Bool,
        onCommit: @escaping (ChromePickerCommit) -> Void,
        onTeardown: ((Bool) -> Void)?
    ) {
        guard let scene = activeWindowScene() else {
            onTeardown?(false)
            return
        }

        // Park Metal only now — never from the SwiftUI button action.
        onWillPresent?()
        onWillPresent = nil

        let sess = ChromePickerSession(
            menu: menu,
            filmFilter: filmFilter,
            lensFX: lensFX,
            focusPeaking: focusPeaking,
            shootMode: shootMode,
            compactChrome: compactChrome
        )
        session = sess
        currentMenu = menu
        self.onCommit = onCommit
        self.onTeardown = onTeardown
        filmAppliedDirectly = false
        pendingSaveLook = false

        let vc = ChromePickerViewController(
            session: sess,
            onFilmApplied: { filmAppliedDirectly = true },
            onSaveLook: { pendingSaveLook = true },
            onApplyShootMode: { mode in
                sess.shootMode = mode
                dismiss(commit: true)
            },
            onDismiss: { dismiss(commit: true) }
        )

        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear
        window.rootViewController = vc
        window.isHidden = false
        window.makeKeyAndVisible()
        overlayWindow = window
    }

    private static func activeWindowScene() -> UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first(where: { $0.activationState == .foregroundActive })
    }
}

// MARK: - Pure UIKit chrome picker (no SwiftUI / no witness tables)
@MainActor
final class ChromePickerViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private enum Row {
        case section(String)
        case scene(ShootMode)
        case film(FilmFilterMode)
        case peaking
        case fx(LensFXMode)
        case recipe(LookRecipe)
        case emptyLooks
        case save
    }

    private let session: ChromePickerSession
    private let onFilmApplied: () -> Void
    private let onSaveLook: () -> Void
    private let onApplyShootMode: (ShootMode) -> Void
    private let onDismiss: () -> Void
    private var rows: [Row] = []
    private let table = UITableView(frame: .zero, style: .plain)
    private let panel = UIView()

    init(
        session: ChromePickerSession,
        onFilmApplied: @escaping () -> Void,
        onSaveLook: @escaping () -> Void,
        onApplyShootMode: @escaping (ShootMode) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.session = session
        self.onFilmApplied = onFilmApplied
        self.onSaveLook = onSaveLook
        self.onApplyShootMode = onApplyShootMode
        self.onDismiss = onDismiss
        super.init(nibName: nil, bundle: nil)
        rebuildRows()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Nikon digital-display yellow (matches DS.accent).
    private static let lcdYellow = UIColor(red: 1.0, green: 0.85, blue: 0.35, alpha: 1)
    private static let lcdPeak = UIColor(red: 0.35, green: 0.95, blue: 0.45, alpha: 1)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.32)

        let tap = UITapGestureRecognizer(target: self, action: #selector(dimTapped(_:)))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)

        // Tight Nikon/DSLR inset panel — dark LCD well, not a floating sheet.
        panel.backgroundColor = UIColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 0.97)
        panel.layer.cornerRadius = 8
        panel.layer.borderWidth = 2
        panel.layer.borderColor = UIColor(white: 0.10, alpha: 1).cgColor
        panel.clipsToBounds = true
        // Inner hairline for machined inset feel.
        panel.layer.shadowColor = UIColor.black.cgColor
        panel.layer.shadowOpacity = 0.55
        panel.layer.shadowRadius = 8
        panel.layer.shadowOffset = CGSize(width: 0, height: 3)
        panel.layer.masksToBounds = false
        view.addSubview(panel)

        // Clip content inside the bordered well.
        let well = UIView()
        well.backgroundColor = UIColor(red: 0.05, green: 0.05, blue: 0.05, alpha: 1)
        well.layer.cornerRadius = 6
        well.clipsToBounds = true
        well.tag = 7701
        panel.addSubview(well)

        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.dataSource = self
        table.delegate = self
        table.rowHeight = UITableView.automaticDimension
        table.estimatedRowHeight = 32
        table.showsVerticalScrollIndicator = false
        table.contentInset = UIEdgeInsets(top: 4, left: 0, bottom: 4, right: 0)
        table.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        well.addSubview(table)

        layoutPanel()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutPanel()
    }

    private func layoutPanel() {
        let compact = session.compactChrome
        // Slightly tighter widths — denser Nikon menu.
        let width: CGFloat = session.menu == .looks ? 196 : (session.menu == .film ? 188 : 176)
        let maxH: CGFloat = compact ? 268 : 320
        let top: CGFloat = {
            switch session.menu {
            case .film: return compact ? 44 : 92
            case .fx: return compact ? 68 : 132
            case .looks: return compact ? 90 : 168
            }
        }()
        let trailing: CGFloat = compact ? 10 : 14
        let x = view.bounds.width - trailing - width
        let h = min(maxH, view.bounds.height - top - 24)
        panel.frame = CGRect(x: x, y: top, width: width, height: h)
        let well = panel.viewWithTag(7701) ?? panel
        well.frame = panel.bounds.insetBy(dx: 2, dy: 2)
        table.frame = well.bounds
    }

    private func rebuildRows() {
        switch session.menu {
        case .film:
            rows = [.section("SCENE")]
            rows += ShootMode.allCases.map { .scene($0) }
            rows.append(.section("FILM"))
            rows += FilmFilterMode.allCases.map { .film($0) }
            rows.append(.save)
        case .fx:
            rows = [.section("AIDS"), .peaking, .section("WARP")]
            rows += LensFXMode.pickerCases.filter { $0 == .none || $0.pickerSection == .warp }.map { .fx($0) }
            rows.append(.section("LOOK"))
            rows += LensFXMode.pickerCases.filter { $0 != .none && $0.pickerSection == .look }.map { .fx($0) }
        case .looks:
            rows = [.save]
            let recipes = LookRecipeStore.shared.recipes
            if recipes.isEmpty {
                rows.append(.emptyLooks)
            } else {
                rows += recipes.map { .recipe($0) }
            }
        }
    }

    @objc private func dimTapped(_ gr: UITapGestureRecognizer) {
        let p = gr.location(in: view)
        if !panel.frame.contains(p) { onDismiss() }
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows.count }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        switch rows[indexPath.row] {
        case .section: return 22
        case .scene: return 36
        case .emptyLooks: return 48
        case .save: return 30
        default: return 28
        }
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        cell.backgroundColor = .clear
        cell.contentView.backgroundColor = .clear
        cell.selectionStyle = .none
        cell.textLabel?.numberOfLines = 2
        cell.textLabel?.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        cell.textLabel?.textColor = UIColor.white.withAlphaComponent(0.65)
        cell.textLabel?.textAlignment = .left
        cell.accessoryType = .none
        // Reset selected wash each reuse.
        cell.contentView.layer.cornerRadius = 0
        cell.contentView.backgroundColor = .clear

        let yellow = Self.lcdYellow

        switch rows[indexPath.row] {
        case .section(let title):
            cell.textLabel?.text = "  " + title
            cell.textLabel?.font = .monospacedSystemFont(ofSize: 8, weight: .semibold)
            cell.textLabel?.textColor = UIColor.white.withAlphaComponent(0.32)
        case .scene(let mode):
            let on = session.shootMode == mode
            let cursor = on ? "> " : "  "
            cell.textLabel?.text = cursor + mode.title.uppercased() + "\n  " + mode.blurb.uppercased()
            cell.textLabel?.textColor = on ? .white : UIColor.white.withAlphaComponent(0.58)
            cell.textLabel?.font = .monospacedSystemFont(ofSize: 10, weight: on ? .semibold : .regular)
            if on {
                cell.contentView.backgroundColor = UIColor.white.withAlphaComponent(0.05)
                // Yellow cursor via attributed first line prefix feel — tint whole selected row warm.
                cell.textLabel?.textColor = yellow
            }
        case .film(let filter):
            let on = session.filmFilter == filter
            let cursor = on ? "> " : "  "
            let iso = Self.isoBadge(for: filter)
            let pad = iso.isEmpty ? "" : String(repeating: " ", count: max(1, 14 - filter.name.count))
            cell.textLabel?.text = cursor + filter.name.uppercased() + (iso.isEmpty ? "" : pad + iso)
            cell.textLabel?.textColor = on ? yellow : UIColor.white.withAlphaComponent(0.62)
            cell.textLabel?.font = .monospacedSystemFont(ofSize: 11, weight: on ? .semibold : .regular)
            if on { cell.contentView.backgroundColor = UIColor.white.withAlphaComponent(0.05) }
        case .peaking:
            let on = session.focusPeaking
            cell.textLabel?.text = (on ? "> " : "  ") + "PEAKING  " + (on ? "ON" : "OFF")
            cell.textLabel?.textColor = on ? Self.lcdPeak : UIColor.white.withAlphaComponent(0.62)
            cell.textLabel?.font = .monospacedSystemFont(ofSize: 11, weight: on ? .semibold : .regular)
            if on { cell.contentView.backgroundColor = UIColor.white.withAlphaComponent(0.04) }
        case .fx(let fx):
            let on = session.lensFX == fx
            let badge = fx == .none ? "" : "  \(fx.badge)"
            cell.textLabel?.text = (on ? "> " : "  ") + fx.name.uppercased() + badge
            cell.textLabel?.textColor = on ? yellow : UIColor.white.withAlphaComponent(0.62)
            cell.textLabel?.font = .monospacedSystemFont(ofSize: 11, weight: on ? .semibold : .regular)
            if on { cell.contentView.backgroundColor = UIColor.white.withAlphaComponent(0.05) }
        case .recipe(let recipe):
            cell.textLabel?.text = "  " + recipe.name.uppercased() + "\n  " + recipe.subtitle.uppercased()
            cell.textLabel?.textColor = .white
            cell.textLabel?.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        case .emptyLooks:
            cell.textLabel?.text = "Save film + FX combos\nfor one-tap recall."
            cell.textLabel?.textColor = UIColor.white.withAlphaComponent(0.38)
            cell.textLabel?.textAlignment = .center
            cell.textLabel?.font = .monospacedSystemFont(ofSize: 9, weight: .regular)
        case .save:
            // Hug the label — no leading pad / no tail truncate in the narrow LCD well.
            let title = session.menu == .looks ? "SAVE" : "SAVE LOOK"
            cell.textLabel?.text = title
            cell.textLabel?.textAlignment = .right
            cell.textLabel?.numberOfLines = 1
            cell.textLabel?.lineBreakMode = .byClipping
            cell.textLabel?.textColor = yellow
            cell.textLabel?.font = .monospacedSystemFont(ofSize: 10, weight: .semibold)
            cell.layoutMargins = UIEdgeInsets(top: 0, left: 10, bottom: 0, right: 12)
            cell.separatorInset = .zero
        }
        return cell
    }

    private static func isoBadge(for filter: FilmFilterMode) -> String {
        switch filter {
        case .none: return ""
        case .portra400: return "400"
        case .kodakGold: return "200"
        case .ektar100: return "100"
        case .trix400: return "400"
        case .velvia50: return "50"
        case .cinestill800: return "800T"
        case .instant: return "SX70"
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        switch rows[indexPath.row] {
        case .section, .emptyLooks:
            return
        case .scene(let mode):
            onApplyShootMode(mode)
        case .film(let filter):
            // Exclusive — film and Lens FX cannot both be on.
            session.filmFilter = filter
            if filter != .none { session.lensFX = .none }
            // A direct stock choice leaves the previous scene. Otherwise the
            // commit reapplies Night/Film and immediately overwrites this row.
            session.shootMode = nil
            onFilmApplied()
            onDismiss()
        case .peaking:
            session.focusPeaking.toggle()
            tableView.reloadRows(at: [indexPath], with: .none)
        case .fx(let fx):
            // Exclusive — FX overrides / clears film.
            session.lensFX = fx
            if fx != .none { session.filmFilter = .none }
            onDismiss()
        case .recipe(let recipe):
            // Saved looks: prefer FX when both stored; keep exclusive.
            if recipe.lensFX != .none {
                session.lensFX = recipe.lensFX
                session.filmFilter = .none
            } else {
                session.filmFilter = recipe.film
                session.lensFX = .none
            }
            onDismiss()
        case .save:
            onSaveLook()
            onDismiss()
        }
    }
}

// MARK: - Viewfinder Overlay (matches Figma design)
struct ViewfinderOverlay: View {
    let showGrid: Bool
    @Binding var aspectRatio: AspectRatioMode
    @Binding var filmFilter: FilmFilterMode
    @Binding var lensFX: LensFXMode
    @Binding var focusPeaking: Bool
    /// Landscape: tuck chrome padding.
    var compactChrome: Bool = false
    /// Quiet Minolta finder — brackets only; no aspect/flip/film/FX stack (Build 118).
    var minimalChrome: Bool = false
    var onFlipCamera: (() -> Void)? = nil
    /// Tap film / FX — ContentView presents via UIKit (no @State flip).
    var onTogglePicker: ((ChromePickerMenu) -> Void)? = nil
    /// Long-press film / FX clears the look (Build 73 — tap always opens).
    var onClearLook: ((ChromePickerMenu) -> Void)? = nil

    var body: some View {
        // Chrome ONLY — pickers are pure UIKit (ChromePickerGate).
        // No SwiftUI film/FX buttons here: UIButton avoids AttributeGraph
        // walking the Metal preview on press (_getWitnessTable crash).
        // No grain/scanline SwiftUI overlays next to MTKView — CI owns looks.
        ZStack(alignment: .topTrailing) {
            GeometryReader { geo in
                ZStack {
                    CenterFocusBrackets()
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    if showGrid && !minimalChrome {
                        GridLines()
                    }
                    if aspectRatio != .full && !minimalChrome {
                        AspectRatioMask(mode: aspectRatio, size: geo.size)
                    }
                }
            }
            .allowsHitTesting(false)

            if !minimalChrome {
                VStack {
                    HStack(alignment: .top) {
                        VStack(spacing: 8) {
                            chromeButton {
                                aspectRatio = aspectRatio.next
                            } label: {
                                Text(aspectRatio.label)
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.9))
                            }

                            chromeButton {
                                onFlipCamera?()
                            } label: {
                                Image(systemName: "arrow.triangle.2.circlepath.camera")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white.opacity(0.85))
                            }
                        }
                        .padding(compactChrome ? 10 : 16)

                        Spacer().allowsHitTesting(false)

                        // Film + FX — tap opens, long-press clears (Build 73).
                        UIKitChromeLookButtons(
                            filmActive: filmFilter != .none,
                            fxActive: lensFX != .none,
                            peakingOnly: focusPeaking && lensFX == .none,
                            onFilm: { onTogglePicker?(.film) },
                            onFX: { onTogglePicker?(.fx) },
                            onFilmClear: { onClearLook?(.film) },
                            onFXClear: { onClearLook?(.fx) }
                        )
                        .frame(width: 32, height: 32 * 2 + 8)
                        .padding(compactChrome ? 10 : 16)
                    }
                    Spacer().allowsHitTesting(false)
                }
            }
        }
        .transaction { $0.animation = nil }
    }

    private func chromeButton<Label: View>(
        action: @escaping () -> Void,
        @ViewBuilder label: () -> Label
    ) -> some View {
        Button(action: {
            VFHaptics.click()
            action()
        }) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.4))
                    .frame(width: 32, height: 32)
                label()
            }
        }
        .buttonStyle(.plain)
    }
}

/// UIKit film / FX toggles — never SwiftUI `Button` next to MTKView.
/// Tap opens menu; long-press clears (Build 73).
struct UIKitChromeLookButtons: UIViewRepresentable {
    var filmActive: Bool
    var fxActive: Bool
    var peakingOnly: Bool
    var onFilm: () -> Void
    var onFX: () -> Void
    var onFilmClear: () -> Void = {}
    var onFXClear: () -> Void = {}

    final class Coordinator: NSObject {
        var onFilm: () -> Void = {}
        var onFX: () -> Void = {}
        var onFilmClear: () -> Void = {}
        var onFXClear: () -> Void = {}

        @objc func film() {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onFilm()
        }
        @objc func fx() {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onFX()
        }
        @objc func filmLong(_ gr: UILongPressGestureRecognizer) {
            guard gr.state == .began else { return }
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.85)
            onFilmClear()
        }
        @objc func fxLong(_ gr: UILongPressGestureRecognizer) {
            guard gr.state == .began else { return }
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred(intensity: 0.85)
            onFXClear()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIStackView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        stack.alignment = .center
        stack.distribution = .equalSpacing

        let film = makeCircleButton(
            systemName: "film",
            tap: #selector(Coordinator.film),
            longPress: #selector(Coordinator.filmLong(_:)),
            coord: context.coordinator
        )
        let fx = makeCircleButton(
            systemName: "water.waves",
            tap: #selector(Coordinator.fx),
            longPress: #selector(Coordinator.fxLong(_:)),
            coord: context.coordinator
        )
        film.tag = 1
        fx.tag = 2
        stack.addArrangedSubview(film)
        stack.addArrangedSubview(fx)
        return stack
    }

    func updateUIView(_ stack: UIStackView, context: Context) {
        context.coordinator.onFilm = onFilm
        context.coordinator.onFX = onFX
        context.coordinator.onFilmClear = onFilmClear
        context.coordinator.onFXClear = onFXClear
        if let film = stack.viewWithTag(1) as? UIButton {
            film.tintColor = filmActive
                ? UIColor(red: 1, green: 0.85, blue: 0.35, alpha: 1)
                : UIColor.white.withAlphaComponent(0.8)
            film.accessibilityLabel = "Film"
            film.accessibilityValue = filmActive ? "On" : "Off"
            film.accessibilityHint = "Opens film menu. Long press clears film."
            film.accessibilityTraits = filmActive ? [.button, .selected] : [.button]
        }
        if let fx = stack.viewWithTag(2) as? UIButton {
            if peakingOnly {
                fx.tintColor = UIColor(red: 0.35, green: 0.95, blue: 0.45, alpha: 1)
            } else if fxActive {
                fx.tintColor = UIColor(red: 0.55, green: 0.88, blue: 0.95, alpha: 1)
            } else {
                fx.tintColor = UIColor.white.withAlphaComponent(0.8)
            }
            fx.accessibilityLabel = "Effects"
            fx.accessibilityValue = peakingOnly ? "Focus peaking" : (fxActive ? "On" : "Off")
            fx.accessibilityHint = "Opens effects menu. Long press clears effects."
            fx.accessibilityTraits = (fxActive || peakingOnly) ? [.button, .selected] : [.button]
        }
    }

    private func makeCircleButton(
        systemName: String,
        tap: Selector,
        longPress: Selector,
        coord: Coordinator
    ) -> UIButton {
        let b = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        b.setImage(UIImage(systemName: systemName, withConfiguration: config), for: .normal)
        b.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        b.tintColor = UIColor.white.withAlphaComponent(0.8)
        b.layer.cornerRadius = 16
        b.clipsToBounds = true
        b.contentEdgeInsets = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        NSLayoutConstraint.activate([
            b.widthAnchor.constraint(equalToConstant: 32),
            b.heightAnchor.constraint(equalToConstant: 32)
        ])
        b.addTarget(coord, action: tap, for: .touchUpInside)
        let lp = UILongPressGestureRecognizer(target: coord, action: longPress)
        lp.minimumPressDuration = 0.38
        // UIKit cancels touchUpInside after recognition, so no tap suppression
        // flag is needed (and such a flag swallowed the next real tap).
        lp.cancelsTouchesInView = true
        b.addGestureRecognizer(lp)
        return b
    }
}

// MARK: - Aspect Ratio Mode
enum AspectRatioMode: CaseIterable {
    case full, ratio4x3, ratio1x1, ratio16x9, ratio3x2

    var label: String {
        switch self {
        case .full: return "FULL"
        case .ratio4x3: return "4:3"
        case .ratio1x1: return "1:1"
        case .ratio16x9: return "16:9"
        case .ratio3x2: return "3:2"
        }
    }

    var next: AspectRatioMode {
        let all = AspectRatioMode.allCases
        let idx = all.firstIndex(of: self) ?? 0
        return all[(idx + 1) % all.count]
    }
}

// MARK: - Film Filter Mode (classic color grades / film stocks)
/// Single source of truth for UI + CameraManager pipeline (Int raw values stable).
enum FilmFilterMode: Int, CaseIterable, Hashable {
    case none = 0
    case portra400 = 1
    case ektar100 = 2
    case kodakGold = 3
    case trix400 = 4
    case cinestill800 = 5
    case velvia50 = 6
    case instant = 7

    var name: String {
        switch self {
        case .none: return "None"
        case .portra400: return "Portra 400"
        case .kodakGold: return "Kodak Gold"
        case .ektar100: return "Ektar 100"
        case .trix400: return "Tri-X 400"
        case .velvia50: return "Velvia 50"
        case .cinestill800: return "CineStill 800T"
        case .instant: return "Instant"
        }
    }
}

// MARK: - Aspect Ratio Mask
struct AspectRatioMask: View {
    let mode: AspectRatioMode
    let size: CGSize

    var body: some View {
        // No AnyView — type erasure next to Metal correlated with witness-table crashes.
        Group {
            if size.width > 1, size.height > 1 {
                let targetRatio: CGFloat = mode.framedAspect(fitting: size) ?? (size.width / size.height)
                let currentRatio = size.width / size.height
                GeometryReader { _ in
                    if targetRatio > currentRatio {
                        let newHeight = size.width / targetRatio
                        let barHeight = (size.height - newHeight) / 2
                        VStack(spacing: 0) {
                            Rectangle().fill(Color.black.opacity(0.7)).frame(height: barHeight)
                            Spacer()
                            Rectangle().fill(Color.black.opacity(0.7)).frame(height: barHeight)
                        }
                    } else {
                        let newWidth = size.height * targetRatio
                        let barWidth = (size.width - newWidth) / 2
                        HStack(spacing: 0) {
                            Rectangle().fill(Color.black.opacity(0.7)).frame(width: barWidth)
                            Spacer()
                            Rectangle().fill(Color.black.opacity(0.7)).frame(width: barWidth)
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Viewfinder Bracket
struct ViewfinderBracket: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            let length: CGFloat = 24
            let thickness: CGFloat = 2

            // Vertical line
            path.move(to: CGPoint(x: 0, y: length))
            path.addLine(to: CGPoint(x: 0, y: 0))
            // Horizontal line
            path.addLine(to: CGPoint(x: length, y: 0))

            context.stroke(path, with: .color(.white.opacity(0.7)), lineWidth: thickness)
        }
        .frame(width: 28, height: 28)
    }
}

// MARK: - Center Focus Brackets
struct CenterFocusBrackets: View {
    var body: some View {
        HStack(spacing: 8) {
            // Left bracket - curved
            CurvedBracket(facing: .left)
                .frame(width: 20, height: 24)

            // Horizontal line
            Rectangle()
                .fill(Color.white.opacity(0.7))
                .frame(width: 16, height: 1.5)

            // Center oval
            Capsule()
                .stroke(Color.white.opacity(0.7), lineWidth: 1.5)
                .frame(width: 32, height: 18)

            // Horizontal line
            Rectangle()
                .fill(Color.white.opacity(0.7))
                .frame(width: 16, height: 1.5)

            // Right bracket - curved
            CurvedBracket(facing: .right)
                .frame(width: 20, height: 24)
        }
    }
}

enum BracketDirection {
    case left, right
}

struct CurvedBracket: View {
    let facing: BracketDirection

    var body: some View {
        Canvas { context, size in
            var path = Path()

            if facing == .left {
                path.move(to: CGPoint(x: size.width, y: 0))
                path.addQuadCurve(
                    to: CGPoint(x: size.width, y: size.height),
                    control: CGPoint(x: 0, y: size.height/2)
                )
            } else {
                path.move(to: CGPoint(x: 0, y: 0))
                path.addQuadCurve(
                    to: CGPoint(x: 0, y: size.height),
                    control: CGPoint(x: size.width, y: size.height/2)
                )
            }

            context.stroke(path, with: .color(.white.opacity(0.7)), lineWidth: 1.5)
        }
    }
}

// MARK: - Grid Lines
struct GridLines: View {
    var body: some View {
        GeometryReader { geo in
            Path { path in
                let w = geo.size.width
                let h = geo.size.height

                // Vertical lines
                path.move(to: CGPoint(x: w/3, y: 0))
                path.addLine(to: CGPoint(x: w/3, y: h))
                path.move(to: CGPoint(x: 2*w/3, y: 0))
                path.addLine(to: CGPoint(x: 2*w/3, y: h))

                // Horizontal lines
                path.move(to: CGPoint(x: 0, y: h/3))
                path.addLine(to: CGPoint(x: w, y: h/3))
                path.move(to: CGPoint(x: 0, y: 2*h/3))
                path.addLine(to: CGPoint(x: w, y: 2*h/3))
            }
            .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
        }
    }
}

// MARK: - Histogram View
struct HistogramView: View {
    var body: some View {
        Canvas { context, size in
            let barCount = 40
            let barWidth = size.width / CGFloat(barCount)

            for i in 0..<barCount {
                let x = CGFloat(i) * barWidth
                let normalizedI = CGFloat(i) / CGFloat(barCount)

                // Create realistic histogram shape
                var heightMultiplier: CGFloat = 0

                // Shadow peak (left)
                heightMultiplier += exp(-pow((normalizedI - 0.15) * 5, 2)) * 0.4

                // Midtone peak (center-left)
                heightMultiplier += exp(-pow((normalizedI - 0.35) * 4, 2)) * 0.7

                // Highlight peak (right)
                heightMultiplier += exp(-pow((normalizedI - 0.75) * 5, 2)) * 0.5

                // Add some noise
                heightMultiplier += CGFloat.random(in: 0.05...0.15)

                let barHeight = size.height * min(heightMultiplier, 1.0)

                let rect = CGRect(x: x, y: size.height - barHeight, width: barWidth - 0.5, height: barHeight)
                context.fill(Path(rect), with: .color(.white.opacity(0.8)))
            }
        }
        .frame(width: 70, height: 35)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
        )
    }
}

// MARK: - Info Bar (matches Figma design)
struct InfoBar: View {
    let iso: Int
    let shutterSpeed: String
    let aperture: Float
    let photoCount: Int
    let isAutoISO: Bool

    init(iso: Int, shutterSpeed: String, aperture: Float, photoCount: Int, isAutoISO: Bool = true) {
        self.iso = iso
        self.shutterSpeed = shutterSpeed
        self.aperture = aperture
        self.photoCount = photoCount
        self.isAutoISO = isAutoISO
    }

    var body: some View {
        HStack(spacing: 8) {
            // Histogram with blue tint (matches Figma)
            HistogramView()

            // Center info - matches Figma layout
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("HEIC")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)

                    // Large badge
                    Text("L")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(2)

                    Text("1:1")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.7))
                }

                HStack(spacing: 8) {
                    Text(formatNumber(photoCount))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))

                    Text("F\(String(format: "%.1f", aperture))")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.6))
                }
            }

            Spacer()

            // Right info - matches Figma
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 3) {
                    // Auto badge
                    Text("A")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(2)
                        .opacity(isAutoISO ? 1 : 0)

                    Text("ISO \(iso)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                }

                Text(shutterSpeed)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.6))
        )
    }

    private func formatNumber(_ num: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: num)) ?? "\(num)"
    }
}

// MARK: - Film Picker (DSLR-style inset menu)
struct LeicaFilmPicker: View {
    @Binding var selectedFilter: FilmFilterMode
    /// Gate dismiss — do not flip a local isPresented (double-dismiss crash).
    var onDismiss: (() -> Void)? = nil
    /// Nil when exposure is AUTO (no scene owns the dials).
    var shootMode: ShootMode? = nil
    var onApplyShootMode: ((ShootMode) -> Void)? = nil
    var onSaveLook: (() -> Void)? = nil
    /// Called when a film stock is directly applied (not via SCENE) — used to clear SCENE highlight.
    var onFilmApplied: (() -> Void)? = nil

    private let accent = Color(red: 1.0, green: 0.85, blue: 0.35)

    var body: some View {
        // No entrance animation — animating picker insert walks Metal shutter chrome.
        VStack(spacing: 0) {
            HStack {
                Text("LOOKS")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                if selectedFilter != .none || onSaveLook != nil {
                    Button {
                        VFHaptics.click()
                        onSaveLook?()
                    } label: {
                        Text("SAVE LOOK")
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundColor(accent.opacity(0.9))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .stroke(accent.opacity(0.35), lineWidth: 0.6)
                            )
                            .fixedSize(horizontal: true, vertical: true)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("STOCK")
                        .font(.system(size: 8, weight: .regular, design: .monospaced))
                        .foregroundColor(.white.opacity(0.28))
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Rectangle()
                .fill(Color(hex: "2a2a2a"))
                .frame(height: 1)
                .padding(.horizontal, 8)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    if onApplyShootMode != nil {
                        sectionLabel("SCENE")
                        ForEach(ShootMode.allCases) { mode in
                            Button {
                                VFHaptics.click()
                                // Gate dismisses — do not also call onDismiss (double-dismiss).
                                onApplyShootMode?(mode)
                            } label: {
                                HStack(spacing: 8) {
                                    Text(shootMode == mode ? ">" : " ")
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        .foregroundColor(accent)
                                        .frame(width: 12)

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(mode.title.uppercased())
                                            .font(.system(
                                                size: 11,
                                                weight: shootMode == mode ? .semibold : .regular,
                                                design: .monospaced
                                            ))
                                            .foregroundColor(shootMode == mode ? .white : .white.opacity(0.6))
                                        Text(mode.blurb.uppercased())
                                            .font(.system(size: 8, weight: .regular, design: .monospaced))
                                            .foregroundColor(.white.opacity(0.28))
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(shootMode == mode ? Color.white.opacity(0.05) : Color.clear)
                            }
                            .buttonStyle(.plain)
                        }

                        Rectangle()
                            .fill(Color(hex: "2a2a2a"))
                            .frame(height: 1)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)

                        sectionLabel("FILM")
                    }

                    ForEach(FilmFilterMode.allCases, id: \.self) { filter in
                        Button(action: {
                            VFHaptics.click()
                            // Snapshot on the session, then gate-dismiss once.
                            selectedFilter = filter
                            // Clear SCENE highlight — user picked a film stock directly.
                            onFilmApplied?()
                            onDismiss?()
                        }) {
                            HStack(spacing: 8) {
                                Text(selectedFilter == filter ? ">" : " ")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(accent)
                                    .frame(width: 12)

                                Text(filter.name.uppercased())
                                    .font(.system(size: 11, weight: selectedFilter == filter ? .semibold : .regular, design: .monospaced))
                                    .foregroundColor(selectedFilter == filter ? .white : .white.opacity(0.6))

                                Spacer()

                                if filter != .none {
                                    Text(isoLabel(for: filter))
                                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.3))
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(selectedFilter == filter ? Color.white.opacity(0.05) : Color.clear)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: onApplyShootMode != nil ? 320 : 250)

            Spacer().frame(height: 6)
        }
        .background(dsPickerChrome())
        .frame(width: 196)
    }

    private func sectionLabel(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.35))
                .tracking(1.0)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    private func isoLabel(for filter: FilmFilterMode) -> String {
        switch filter {
        case .none: return ""
        case .portra400: return "400"
        case .kodakGold: return "200"
        case .ektar100: return "100"
        case .trix400: return "400"
        case .velvia50: return "50"
        case .cinestill800: return "800T"
        case .instant: return "SX70"
        }
    }
}

// MARK: - Shared DSLR inset chrome for film / FX pickers
private struct DSLRPickerChrome: ViewModifier {
    func body(content: Content) -> some View {
        content.background(
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex: "0d0d0d"))

                VStack(spacing: 0) {
                    LinearGradient(colors: [Color.black.opacity(0.5), Color.clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 10)
                    Spacer()
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack(spacing: 0) {
                    LinearGradient(colors: [Color.black.opacity(0.4), Color.clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 8)
                    Spacer()
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))

                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color(hex: "1a1a1a"), lineWidth: 2)
            }
        )
    }
}

private extension View {
    func dsPickerChrome() -> some View {
        modifier(DSLRPickerChrome())
    }
}

// MARK: - Lens FX Picker (warp shaders vs look shaders)
struct LensFXPicker: View {
    @Binding var selectedFX: LensFXMode
    @Binding var focusPeaking: Bool
    /// Gate dismiss — do not flip a local isPresented (double-dismiss crash).
    var onDismiss: (() -> Void)? = nil

    private let accent = Color(red: 0.55, green: 0.88, blue: 0.95)
    private let peakAccent = Color(red: 0.35, green: 0.95, blue: 0.45)

    /// Stable lists — avoid rebuilding ForEach identity every body pass.
    private static let warpCases: [LensFXMode] = LensFXMode.pickerCases.filter {
        $0 == .none || $0.pickerSection == .warp
    }
    private static let lookCases: [LensFXMode] = LensFXMode.pickerCases.filter {
        $0 != .none && $0.pickerSection == .look
    }

    var body: some View {
        // Apply/dismiss stay transaction-frozen — no entrance animation over Metal.
        VStack(spacing: 0) {
            HStack {
                Text("LENS FX")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Text("SHADER")
                    .font(.system(size: 8, weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.28))
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Rectangle()
                .fill(Color(hex: "2a2a2a"))
                .frame(height: 1)
                .padding(.horizontal, 8)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    sectionHeader("AIDS")
                    peakingRow

                    sectionHeader("WARP")
                    ForEach(Self.warpCases, id: \.self) { fx in
                        fxRow(fx)
                    }

                    sectionHeader("LOOK")
                    ForEach(Self.lookCases, id: \.self) { fx in
                        fxRow(fx)
                    }
                }
            }
            .frame(maxHeight: 260)

            Spacer().frame(height: 6)
        }
        .background(dsPickerChrome())
        .frame(width: 180)
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                .foregroundColor(.white.opacity(0.32))
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    private var peakingRow: some View {
        Button(action: {
            VFHaptics.click()
            // Snapshot only — peaking hits the live pipeline on gate commit.
            focusPeaking.toggle()
        }) {
            HStack(spacing: 8) {
                Text(focusPeaking ? ">" : " ")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(peakAccent)
                    .frame(width: 12)

                Text("PEAKING")
                    .font(.system(size: 11, weight: focusPeaking ? .semibold : .regular, design: .monospaced))
                    .foregroundColor(focusPeaking ? .white : .white.opacity(0.6))

                Spacer()

                Text(focusPeaking ? "ON" : "OFF")
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundColor(focusPeaking ? peakAccent : .white.opacity(0.3))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(focusPeaking ? Color.white.opacity(0.05) : Color.clear)
        }
        .buttonStyle(.plain)
    }

    private func fxRow(_ fx: LensFXMode) -> some View {
        Button(action: {
            VFHaptics.click()
            // Snapshot FX on the session, then gate-dismiss once.
            // Live Metal stays parked until ContentView commits + unsuspends.
            selectedFX = fx
            onDismiss?()
        }) {
            HStack(spacing: 8) {
                Text(selectedFX == fx ? ">" : " ")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(accent)
                    .frame(width: 12)

                Text(fx.name.uppercased())
                    .font(.system(size: 11, weight: selectedFX == fx ? .semibold : .regular, design: .monospaced))
                    .foregroundColor(selectedFX == fx ? .white : .white.opacity(0.6))

                Spacer()

                if fx != .none {
                    Text(fx.badge)
                        .font(.system(size: 9, weight: .regular, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(selectedFX == fx ? Color.white.opacity(0.05) : Color.clear)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Look recipe picker (saved film + FX combos)
struct LookRecipePicker: View {
    @ObservedObject var store: LookRecipeStore
    @Binding var filmFilter: FilmFilterMode
    @Binding var lensFX: LensFXMode
    /// Gate dismiss — same path as film / Lens FX rows.
    var onDismiss: (() -> Void)? = nil
    var onSaveCurrent: (() -> Void)? = nil

    private let accent = Color(red: 1.0, green: 0.75, blue: 0.45)

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("LOOKS")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.5))
                Spacer()
                Button {
                    VFHaptics.click()
                    onSaveCurrent?()
                } label: {
                    Text("SAVE")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundColor(accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .stroke(accent.opacity(0.35), lineWidth: 0.6)
                        )
                        .fixedSize(horizontal: true, vertical: true)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)

            Rectangle()
                .fill(Color(hex: "2a2a2a"))
                .frame(height: 1)
                .padding(.horizontal, 8)

            if store.recipes.isEmpty {
                Text("Save film + FX combos\nfor one-tap recall.")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .padding(16)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(store.recipes) { recipe in
                            HStack(spacing: 8) {
                                Button {
                                    VFHaptics.click()
                                    filmFilter = recipe.film
                                    lensFX = recipe.lensFX
                                    onDismiss?()
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(recipe.name.uppercased())
                                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                            .foregroundColor(.white)
                                            .lineLimit(1)
                                        Text(recipe.subtitle.uppercased())
                                            .font(.system(size: 8, weight: .regular, design: .monospaced))
                                            .foregroundColor(.white.opacity(0.35))
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)

                                Button {
                                    VFHaptics.click()
                                    store.delete(recipe.id)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.white.opacity(0.35))
                                        .frame(width: 28, height: 28)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                    }
                }
                .frame(maxHeight: 220)
            }

            Spacer().frame(height: 6)
        }
        .background(dsPickerChrome())
        .frame(width: 200)
    }
}

// MARK: - Scanline Overlay (VHS mode) — kept for non-camera surfaces if needed.
// Not mounted beside MTKView (Build 64) — that Canvas + opacity walk crashed.
struct ScanlineShaderOverlay: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 3
            var y: CGFloat = 0
            while y < size.height {
                let rect = CGRect(x: 0, y: y, width: size.width, height: 1)
                context.fill(Path(rect), with: .color(.black.opacity(0.28)))
                y += spacing
            }
        }
        .allowsHitTesting(false)
    }
}
