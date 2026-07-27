import Combine
import CoreImage
import Metal

/// Shared GPU resources. Preview/bake share a Metal CIContext but ALL access
/// goes through `ciQueue` so concurrent render/createCGImage cannot race.
enum ShutterRender {
    static let device: MTLDevice? = MTLCreateSystemDefaultDevice()

    /// Serial queue owning `ciContext` (preview Metal, still bake, LE flatten).
    static let ciQueue = DispatchQueue(label: "shutter.render.ci", qos: .userInitiated)

    static let ciContext: CIContext = {
        if let device {
            return CIContext(
                mtlDevice: device,
                options: [
                    .workingColorSpace: CGColorSpaceCreateDeviceRGB(),
                    .cacheIntermediates: false
                ]
            )
        }
        return CIContext(options: [
            .useSoftwareRenderer: false,
            .cacheIntermediates: false
        ])
    }()

    /// Tiny CPU context for histogram only — never fights the Metal preview context.
    static let histogramContext: CIContext = {
        CIContext(options: [
            .workingColorSpace: CGColorSpaceCreateDeviceRGB(),
            .cacheIntermediates: false,
            .useSoftwareRenderer: false
        ])
    }()

    @discardableResult
    static func syncCI<T>(_ work: () -> T) -> T {
        ciQueue.sync(execute: work)
    }

    static func asyncCI(_ work: @escaping () -> Void) {
        ciQueue.async(execute: work)
    }
}

/// Histogram bins live here so ~2 Hz updates do not invalidate the entire finder
/// (`ContentView` observing `CameraManager`). Only `RefractiveGlassInfoBar` watches this.
final class HistogramBus: ObservableObject {
    static let shared = HistogramBus()

    @Published private(set) var bins: [Float] = []

    func publish(_ normalized: [Float]) {
        if Self.nearlyEqual(normalized, bins) { return }
        bins = normalized
    }

    private static func nearlyEqual(_ a: [Float], _ b: [Float]) -> Bool {
        guard a.count == b.count, !a.isEmpty else { return false }
        var err: Float = 0
        for i in a.indices {
            err += abs(a[i] - b[i])
        }
        return err < 0.4
    }
}

/// Live AUTO ISO / shutter — kept off CameraManager so ContentView does not rebuild
/// the entire finder ~2.5×/sec while AE hunts.
final class LiveExposureBus: ObservableObject {
    static let shared = LiveExposureBus()

    @Published private(set) var iso: Float = 0
    @Published private(set) var shutterLabel: String = "AUTO"

    func publish(iso: Float, shutterLabel: String) {
        if abs(self.iso - iso) > 2 {
            self.iso = iso
        }
        if self.shutterLabel != shutterLabel {
            self.shutterLabel = shutterLabel
        }
    }
}

/// STACK/HW long-exposure progress — leaf chrome only (Build 108).
/// Publishing through `@Published` on CameraManager rebuilt the whole Metal finder ~12Hz.
final class LongExposureProgressBus: ObservableObject {
    static let shared = LongExposureProgressBus()

    @Published private(set) var progress: Float = 0
    @Published private(set) var pathLabel: String = ""
    @Published private(set) var isCapturing: Bool = false

    func publish(progress: Float, pathLabel: String, capturing: Bool) {
        if capturing != isCapturing {
            isCapturing = capturing
        }
        if abs(progress - self.progress) >= 0.01 {
            self.progress = progress
        }
        if pathLabel != self.pathLabel {
            self.pathLabel = pathLabel
        }
        if !capturing, self.progress != 0 {
            self.progress = 0
        }
    }

    func reset() {
        progress = 0
        pathLabel = ""
        isCapturing = false
    }
}

/// One-shot finder toasts — leaf chrome only (Build 109).
/// Publishing through CameraManager.captureNote / ContentView @State rebuilt Metal.
final class ToastBus: ObservableObject {
    static let shared = ToastBus()

    @Published private(set) var message: String?
    private var clearWork: DispatchWorkItem?

    func show(_ text: String, duration: TimeInterval = 2.2) {
        clearWork?.cancel()
        message = text
        let work = DispatchWorkItem { [weak self] in
            self?.message = nil
        }
        clearWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    func clear() {
        clearWork?.cancel()
        clearWork = nil
        message = nil
    }
}
