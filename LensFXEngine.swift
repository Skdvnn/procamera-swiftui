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
    case instant      // Faded instant-film look with vignette
    case dream        // Orton-style glow blur
    case fisheye      // Bulging wide-angle lens distortion
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
        case .instant: return "Instant"
        case .dream: return "Dream"
        case .fisheye: return "Fisheye"
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
        case .instant: return "SX70"
        case .dream: return "GLOW"
        case .fisheye: return "180"
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

    // Epoch for animation: absolute timestamps are ~8e8 seconds, which loses
    // all sub-second precision once converted to Float for shader params
    private let startTime = CFAbsoluteTimeGetCurrent()

    private init() {}

    /// Apply the selected effect to a camera frame.
    /// `time` animates time-varying effects in the live preview; pass 0 for stills.
    func apply(_ fx: LensFXMode, to image: CIImage, time rawTime: TimeInterval) -> CIImage {
        let extent = image.extent
        guard fx != .none, !extent.isInfinite, extent.width > 0 else { return image }

        let time = rawTime > 0 ? rawTime - startTime : 0

        switch fx {
        case .none:
            return image
        case .liquid:
            return applyLiquid(to: image, time: time)
        case .chrome:
            return applyChrome(to: image, time: time)
        case .instant:
            return applyInstant(to: image)
        case .dream:
            return applyDream(to: image)
        case .fisheye:
            return applyFisheye(to: image)
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

        let blurred = (blur.outputImage ?? random).cropped(to: textureRect)

        // Render once to a bitmap — otherwise the noise+blur chain would be
        // lazily re-executed on the GPU for every preview frame
        let context = CIContext(options: [.useSoftwareRenderer: false])
        if let cgImage = context.createCGImage(blurred, from: textureRect) {
            return CIImage(cgImage: cgImage)
        }
        return blurred
    }

    // Two noise layers flowing in different directions, blended 50/50.
    // Their interference makes the distortion field genuinely morph over time
    // instead of just sliding past.
    private func morphingTexture(covering extent: CGRect, time: TimeInterval) -> CIImage {
        let t = CGFloat(time)

        let driftA = CGAffineTransform(translationX: t * 46, y: t * 18)
        // Second layer: larger blobs, moving against the first
        let driftB = CGAffineTransform(translationX: -t * 28, y: t * 36)
            .scaledBy(x: 1.8, y: 1.8)

        let layerA = liquidTexture
            .transformed(by: driftA)
            .applyingFilter("CIAffineTile")
            .cropped(to: extent)
        let layerB = liquidTexture
            .transformed(by: driftB)
            .applyingFilter("CIAffineTile")
            .cropped(to: extent)

        let mix = CIFilter.dissolveTransition()
        mix.inputImage = layerA
        mix.targetImage = layerB
        mix.time = 0.5

        return (mix.outputImage ?? layerA).cropped(to: extent)
    }

    // Heavy glass warp driven by the morphing texture, plus a slow breathing
    // twirl — reads as flowing liquid rather than static shimmer.
    private func morphDistort(_ image: CIImage, extent: CGRect, time: TimeInterval, strength: CGFloat) -> CIImage {
        let texture = morphingTexture(covering: extent, time: time)

        guard let glass = CIFilter(name: "CIGlassDistortion") else { return image }
        glass.setValue(image.clampedToExtent(), forKey: kCIInputImageKey)
        glass.setValue(texture, forKey: "inputTexture")
        glass.setValue(CIVector(x: extent.midX, y: extent.midY), forKey: kCIInputCenterKey)
        glass.setValue(extent.width * strength, forKey: kCIInputScaleKey)

        var output = (glass.outputImage ?? image).cropped(to: extent)

        let twirl = CIFilter.twirlDistortion()
        twirl.inputImage = output.clampedToExtent()
        twirl.center = CGPoint(x: extent.midX, y: extent.midY)
        twirl.radius = Float(min(extent.width, extent.height) * 0.75)
        twirl.angle = Float(sin(time * 0.45)) * 0.9

        output = (twirl.outputImage ?? output).cropped(to: extent)
        return output
    }

    private func applyLiquid(to image: CIImage, time: TimeInterval) -> CIImage {
        let extent = image.extent
        return morphDistort(image, extent: extent, time: time, strength: 0.055)
    }

    // MARK: - Chrome (liquid metal)

    private func applyChrome(to image: CIImage, time: TimeInterval) -> CIImage {
        let extent = image.extent

        // Morphing warp first, then the metal tone map — the moving highlights
        // over warped geometry give the molten T-1000 look
        var output = morphDistort(image, extent: extent, time: time, strength: 0.035)

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

    // MARK: - Instant film (Polaroid look)

    private func applyInstant(to image: CIImage) -> CIImage {
        let extent = image.extent
        var output = image

        // Soft and slightly washed out
        let controls = CIFilter.colorControls()
        controls.inputImage = output
        controls.saturation = 0.82
        controls.brightness = 0.02
        controls.contrast = 0.92
        if let result = controls.outputImage { output = result }

        // Warm cast with the slight green shadow shift of aged instant film
        let tempTint = CIFilter.temperatureAndTint()
        tempTint.inputImage = output
        tempTint.neutral = CIVector(x: 6500, y: 0)
        tempTint.targetNeutral = CIVector(x: 5300, y: -8)
        if let result = tempTint.outputImage { output = result }

        // Lifted blacks, rolled-off highlights — the faded print curve
        let curve = CIFilter.toneCurve()
        curve.inputImage = output
        curve.point0 = CGPoint(x: 0.00, y: 0.10)
        curve.point1 = CGPoint(x: 0.25, y: 0.28)
        curve.point2 = CGPoint(x: 0.50, y: 0.52)
        curve.point3 = CGPoint(x: 0.75, y: 0.78)
        curve.point4 = CGPoint(x: 1.00, y: 0.93)
        if let result = curve.outputImage { output = result }

        // Heavy corner falloff like a cheap plastic lens
        let vignette = CIFilter.vignette()
        vignette.inputImage = output
        vignette.intensity = 0.8
        vignette.radius = 1.8
        if let result = vignette.outputImage { output = result }

        // Gentle halation glow on highlights
        let bloom = CIFilter.bloom()
        bloom.inputImage = output
        bloom.radius = 4
        bloom.intensity = 0.25
        if let result = bloom.outputImage { output = result }

        return output.cropped(to: extent)
    }

    // MARK: - Dream (Orton-style glow blur)

    private func applyDream(to image: CIImage) -> CIImage {
        let extent = image.extent

        // Wide soft blur of the frame...
        let blur = CIFilter.gaussianBlur()
        blur.inputImage = image.clampedToExtent()
        blur.radius = Float(extent.width * 0.012)
        let blurred = (blur.outputImage ?? image).cropped(to: extent)

        // ...dimmed, then screened over the sharp original: highlights bloom
        // and halo while detail stays visible underneath
        let dim = CIFilter.colorMatrix()
        dim.inputImage = blurred
        dim.rVector = CIVector(x: 0.65, y: 0, z: 0, w: 0)
        dim.gVector = CIVector(x: 0, y: 0.65, z: 0, w: 0)
        dim.bVector = CIVector(x: 0, y: 0, z: 0.65, w: 0)
        dim.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)

        let screen = CIFilter.screenBlendMode()
        screen.inputImage = dim.outputImage
        screen.backgroundImage = image

        var output = (screen.outputImage ?? image).cropped(to: extent)

        // Dreamy color push
        let vibrance = CIFilter.vibrance()
        vibrance.inputImage = output
        vibrance.amount = 0.25
        if let result = vibrance.outputImage { output = result }

        return output.cropped(to: extent)
    }

    // MARK: - Fisheye lens distortion

    private func applyFisheye(to image: CIImage) -> CIImage {
        let extent = image.extent

        let bump = CIFilter.bumpDistortion()
        bump.inputImage = image.clampedToExtent()
        bump.center = CGPoint(x: extent.midX, y: extent.midY)
        bump.radius = Float(max(extent.width, extent.height) * 0.62)
        bump.scale = 0.55

        var output = (bump.outputImage ?? image).cropped(to: extent)

        // Dark corners sell the ultra-wide lens
        let vignette = CIFilter.vignette()
        vignette.inputImage = output
        vignette.intensity = 0.6
        vignette.radius = 2.0
        if let result = vignette.outputImage { output = result }

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
