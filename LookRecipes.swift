import Foundation
import SwiftUI
import AVFoundation
import MediaPlayer
import UIKit
import GameController

struct LookRecipe: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var filmRaw: String
    var lensFXRaw: String
    var created: Date

    init(id: UUID = UUID(), name: String, film: FilmFilterMode, lensFX: LensFXMode, created: Date = Date()) {
        self.id = id
        self.name = name
        self.filmRaw = film.name
        self.lensFXRaw = lensFX.name
        self.created = created
    }

    var film: FilmFilterMode {
        FilmFilterMode.allCases.first { $0.name == filmRaw } ?? .none
    }

    var lensFX: LensFXMode {
        LensFXMode.allCases.first { $0.name == lensFXRaw } ?? .none
    }

    var subtitle: String {
        let f = film == .none ? "Clean" : film.name
        let x = lensFX == .none ? "—" : lensFX.name
        return "\(f) · \(x)"
    }
}

@MainActor
final class LookRecipeStore: ObservableObject {
    static let shared = LookRecipeStore()
    private static let storageKey = "cam.lookRecipes.v1"
    private static let maxRecipes = 12

    @Published private(set) var recipes: [LookRecipe] = []

    init() { load() }

    func saveCurrent(film: FilmFilterMode, lensFX: LensFXMode, name: String? = nil) {
        guard film != .none || lensFX != .none else { return }
        let label = name ?? Self.defaultName(film: film, lensFX: lensFX)
        // Replace duplicate combo
        recipes.removeAll { $0.film == film && $0.lensFX == lensFX }
        recipes.insert(LookRecipe(name: label, film: film, lensFX: lensFX), at: 0)
        if recipes.count > Self.maxRecipes {
            recipes = Array(recipes.prefix(Self.maxRecipes))
        }
        persist()
    }

    func delete(_ id: UUID) {
        recipes.removeAll { $0.id == id }
        persist()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey),
              let decoded = try? JSONDecoder().decode([LookRecipe].self, from: data) else {
            recipes = []
            return
        }
        recipes = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(recipes) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    private static func defaultName(film: FilmFilterMode, lensFX: LensFXMode) -> String {
        if film != .none && lensFX != .none {
            return "\(film.name)+\(lensFX.name)"
        }
        if film != .none { return film.name }
        return lensFX.name
    }
}

// MARK: - Volume / HID → shutter

/// Steals volume-button presses for shutter (system HUD suppressed via offscreen MPVolumeView).
/// Also listens for connected game-controller / HID remotes that expose a digital shutter button.
@MainActor
final class VolumeShutterObserver: NSObject, ObservableObject {
    var onShutter: (() -> Void)?

    private var observation: NSKeyValueObservation?
    private var lastVolume: Float = AVAudioSession.sharedInstance().outputVolume
    private var ignoring = false
    private let volumeView = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))
    private weak var hostView: UIView?
    private var controllerObservers: [Any] = []

    func start(in view: UIView?) {
        stop()
        hostView = view
        if let view, volumeView.superview == nil {
            view.addSubview(volumeView)
        }
        try? AVAudioSession.sharedInstance().setActive(true)
        lastVolume = AVAudioSession.sharedInstance().outputVolume
        observation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new]) { [weak self] session, _ in
            guard let self else { return }
            Task { @MainActor in
                self.handleVolume(session.outputVolume)
            }
        }
        startControllerListening()
    }

    func stop() {
        observation?.invalidate()
        observation = nil
        volumeView.removeFromSuperview()
        for o in controllerObservers {
            NotificationCenter.default.removeObserver(o)
        }
        controllerObservers.removeAll()
        GCController.controllers().forEach { $0.extendedGamepad?.valueChangedHandler = nil }
    }

    private func handleVolume(_ volume: Float) {
        guard !ignoring else { return }
        if abs(volume - lastVolume) < 0.001 { return }
        lastVolume = volume
        onShutter?()
        restoreMidVolumeIfNeeded(volume)
    }

    private func restoreMidVolumeIfNeeded(_ volume: Float) {
        guard volume < 0.05 || volume > 0.95 else { return }
        ignoring = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            if let slider = self.volumeView.subviews.compactMap({ $0 as? UISlider }).first {
                slider.value = 0.5
            }
            self.lastVolume = 0.5
            self.ignoring = false
        }
    }

    private func startControllerListening() {
        let connect = NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let pad = (note.object as? GCController)?.extendedGamepad else { return }
            Task { @MainActor in
                self?.bind(pad)
            }
        }
        let disconnect = NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect,
            object: nil,
            queue: .main
        ) { _ in }
        controllerObservers = [connect, disconnect]
        for pad in GCController.controllers().compactMap(\.extendedGamepad) {
            bind(pad)
        }
    }

    private func bind(_ pad: GCExtendedGamepad) {
        pad.buttonA.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { Task { @MainActor in self?.onShutter?() } }
        }
        pad.rightTrigger.pressedChangedHandler = { [weak self] _, _, pressed in
            if pressed { Task { @MainActor in self?.onShutter?() } }
        }
    }
}
