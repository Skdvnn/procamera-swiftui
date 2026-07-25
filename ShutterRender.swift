import Combine
import CoreImage
import Metal

/// Shared GPU resources for preview, FX, and histogram — one Metal device / CIContext
/// instead of three separate contexts fighting for memory and compile caches.
enum ShutterRender {
    static let device: MTLDevice? = MTLCreateSystemDefaultDevice()

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
