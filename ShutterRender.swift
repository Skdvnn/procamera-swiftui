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
