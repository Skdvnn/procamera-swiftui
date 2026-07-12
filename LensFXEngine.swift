import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

// MARK: - Lens FX Mode
// Live GPU effects applied to the camera feed (preview + captured photos).
// These run in the CIImage pipeline rendered by FilteredCameraPreview's MTKView,
// so they compose with the film simulation filters.
enum LensFXMode: Int, CaseIterable {
    case none = 0
    case liquid       // Animated liquid-glass distortion
    case chrome       // Liquid-metal chrome tone mapping
    case thermal      // Thermal camera palette
    case xray         // X-ray inversion
    case vhs          // Chromatic aberration + scanline overlay
    case kaleido      // Six-way kaleidoscope
    case pixel8       // Chunky 8-bit pixellation

    var name: String {
        switch self {
        case .none: return "None"
        case .liquid: return "Liquid"
        case .chrome: return "Chrome"
        case .thermal: return "Thermal"
        case .xray: return "X-Ray"
        case .vhs: return "VHS"
        case .kaleido: return "Kaleido"
        case .pixel8: return "8-Bit"
        }
    }

    var badge: String {
        switch self {
        case .none: return ""
        case .liquid: return "H2O"
        case .chrome: return "AG"
        case .thermal: return "IR"
        case .xray: return "XR"
        case .vhs: return "PAL"
        case .kaleido: return "x6"
        case .pixel8: return "8BIT"
        }
    }
}

// MARK: - Lens FX Engine
final class LensFXEngine {
    static let shared = LensFXEngine()

    // Cached smooth-noise texture that drives the liquid glass distortion
    private lazy var liquidTexture: CIImage = makeLiquidTexture()

    private init() {}

    /// Apply the selected effect to a camera frame.
    /// `time` animates time-varying effects in the live preview; pass 0 for stills.
    func apply(_ fx: LensFXMode, to image: CIImage, time: TimeInterval) -> CIImage {
        let extent = image.extent
        guard fx != .none, !extent.isInfinite, extent.width > 0 else { return image }

        switch fx {
        case .none:
            return image
        case .liquid:
            return applyLiquid(to: image, time: time)
        case .chrome:
            return applyChrome(to: image)
        case .thermal:
            return applySimpleFilter(name: "CIThermal", to: image)
        case .xray:
            return applySimpleFilter(name: "CIXRay", to: image)
        case .vhs:
            return applyVHS(to: image, time: time)
        case .kaleido:
            return applyKaleido(to: image, time: time)
        case .pixel8:
            return applyPixel8(to: image)
        }
    }

    // MARK: - Liquid glass distortion

    private func makeLiquidTexture() -> CIImage {
        // Blurred white noise gives smooth organic blobs; glass distortion
        // displaces pixels along the texture's luminance gradient.
        let textureRect = CGRect(x: 0, y: 0, width: 512, height: 512)
        guard let random = CIFilter.randomGenerator().outputImage else {
            return CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: textureRect)
        }

        let blur = CIFilter.gaussianBlur()
        blur.inputImage = random.cropped(to: textureRect).clampedToExtent()
        blur.radius = 14

        let blurred = blur.outputImage ?? random
        return blurred.cropped(to: textureRect)
    }

    private func applyLiquid(to image: CIImage, time: TimeInterval) -> CIImage {
        let extent = image.extent

        // Drift the texture so the preview shimmers like water
        let drift = CGAffineTransform(
            translationX: CGFloat(time.truncatingRemainder(dividingBy: 512)) * 24,
            y: CGFloat(sin(time * 0.7)) * 40
        )
        // Tile the texture so it covers the whole frame at any offset
        let tiled = liquidTexture
            .transformed(by: drift)
            .applyingFilter("CIAffineTile")
            .cropped(to: extent)

        let glass = CIFilter.glassDistortion()
        glass.inputImage = image.clampedToExtent()
        glass.texture = tiled
        glass.center = CGPoint(x: extent.midX, y: extent.midY)
        glass.scale = Float(extent.width * 0.02)

        return (glass.outputImage ?? image).cropped(to: extent)
    }

    // MARK: - Chrome (liquid metal)

    private func applyChrome(to image: CIImage) -> CIImage {
        let extent = image.extent
        var output = image

        let mono = CIFilter.photoEffectMono()
        mono.inputImage = output
        if let result = mono.outputImage { output = result }

        // Hard S-curve: crushed shadows, hot speculars — reads as polished metal
        let curve = CIFilter.toneCurve()
        curve.inputImage = output
        curve.point0 = CGPoint(x: 0.00, y: 0.02)
        curve.point1 = CGPoint(x: 0.25, y: 0.10)
        curve.point2 = CGPoint(x: 0.50, y: 0.50)
        curve.point3 = CGPoint(x: 0.75, y: 0.90)
        curve.point4 = CGPoint(x: 1.00, y: 0.98)
        if let result = curve.outputImage { output = result }

        // Cool silver-blue cast
        let tint = CIFilter.colorMatrix()
        tint.inputImage = output
        tint.rVector = CIVector(x: 0.92, y: 0, z: 0, w: 0)
        tint.gVector = CIVector(x: 0, y: 0.97, z: 0, w: 0)
        tint.bVector = CIVector(x: 0, y: 0, z: 1.10, w: 0)
        if let result = tint.outputImage { output = result }

        // Specular sheen
        let bloom = CIFilter.bloom()
        bloom.inputImage = output
        bloom.radius = 6
        bloom.intensity = 0.4
        if let result = bloom.outputImage { output = result }

        return output.cropped(to: extent)
    }

    // MARK: - VHS chromatic aberration

    private func applyVHS(to image: CIImage, time: TimeInterval) -> CIImage {
        let extent = image.extent
        let clamped = image.clampedToExtent()

        // Fringe amount wobbles slightly over time like bad tracking
        let wobble = time > 0 ? (1.0 + 0.3 * sin(time * 2.3)) : 1.0
        let dx = extent.width * 0.0035 * CGFloat(wobble)

        func channel(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, shiftX: CGFloat) -> CIImage? {
            let matrix = CIFilter.colorMatrix()
            matrix.inputImage = clamped
            matrix.rVector = CIVector(x: r, y: 0, z: 0, w: 0)
            matrix.gVector = CIVector(x: 0, y: g, z: 0, w: 0)
            matrix.bVector = CIVector(x: 0, y: 0, z: b, w: 0)
            matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
            return matrix.outputImage?.transformed(by: CGAffineTransform(translationX: shiftX, y: 0))
        }

        guard let red = channel(1, 0, 0, shiftX: dx),
              let green = channel(0, 1, 0, shiftX: 0),
              let blue = channel(0, 0, 1, shiftX: -dx) else {
            return image
        }

        let addRG = CIFilter.additionCompositing()
        addRG.inputImage = red
        addRG.backgroundImage = green

        let addB = CIFilter.additionCompositing()
        addB.inputImage = addRG.outputImage
        addB.backgroundImage = blue

        var output = addB.outputImage ?? image

        // Slightly hot saturation and lifted blacks, like tape playback
        let controls = CIFilter.colorControls()
        controls.inputImage = output
        controls.saturation = 1.15
        controls.brightness = 0.02
        controls.contrast = 0.98
        if let result = controls.outputImage { output = result }

        return output.cropped(to: extent)
    }

    // MARK: - Kaleidoscope

    private func applyKaleido(to image: CIImage, time: TimeInterval) -> CIImage {
        let extent = image.extent

        let kaleido = CIFilter.kaleidoscope()
        kaleido.inputImage = image.clampedToExtent()
        kaleido.count = 6
        kaleido.center = CGPoint(x: extent.midX, y: extent.midY)
        kaleido.angle = Float(time * 0.15)

        return (kaleido.outputImage ?? image).cropped(to: extent)
    }

    // MARK: - 8-bit pixellation

    private func applyPixel8(to image: CIImage) -> CIImage {
        let extent = image.extent
        var output = image

        let pixellate = CIFilter.pixellate()
        pixellate.inputImage = output.clampedToExtent()
        pixellate.center = CGPoint(x: extent.midX, y: extent.midY)
        pixellate.scale = Float(max(8, extent.width / 96))
        if let result = pixellate.outputImage { output = result }

        // Quantize colors for the retro palette feel
        let posterize = CIFilter.colorPosterize()
        posterize.inputImage = output
        posterize.levels = 5
        if let result = posterize.outputImage { output = result }

        return output.cropped(to: extent)
    }

    // MARK: - Helpers

    private func applySimpleFilter(name: String, to image: CIImage) -> CIImage {
        let extent = image.extent
        guard let filter = CIFilter(name: name) else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        return (filter.outputImage ?? image).cropped(to: extent)
    }
}
