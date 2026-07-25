import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

extension UIImage.Orientation {
    var cgImageOrientation: CGImagePropertyOrientation {
        switch self {
        case .up: return .up
        case .upMirrored: return .upMirrored
        case .down: return .down
        case .downMirrored: return .downMirrored
        case .left: return .left
        case .leftMirrored: return .leftMirrored
        case .right: return .right
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}

// MARK: - Lens FX Mode
// Live GPU shader effects applied to the camera feed (preview + captured photos).
// Classic film color grades live in FilmFilterMode / CameraManager.FilmFilter —
// Instant is kept here only so older raw values don't shift.
enum LensFXMode: Int, CaseIterable {
    case none = 0
    case liquid       // Animated liquid-glass distortion (touch-reactive)
    case chrome       // Liquid-metal chrome tone mapping (touch-reactive)
    case instant      // Deprecated: use FilmFilter.instant — hidden from picker
    case dream        // Orton-style glow blur
    case fisheye      // Bulging wide-angle lens distortion (touch-reactive)
    case thermal      // Thermal camera palette
    case xray         // X-ray inversion
    case vhs          // Chromatic aberration + scanline overlay
    case kaleido      // Six-way kaleidoscope (touch-reactive)
    case pixel8       // Chunky 8-bit pixellation
    case toon         // Comic-book ink and halftone
    case mirror       // Symmetry down the middle
    case negative     // Inverted film negative

    /// Shown in the Lens FX picker (excludes legacy Instant film look).
    static var pickerCases: [LensFXMode] {
        allCases.filter { $0 != .instant }
    }

    /// Warp / morph shaders that respond to viewfinder touch.
    var isTouchReactive: Bool {
        switch self {
        case .liquid, .chrome, .fisheye, .kaleido: return true
        default: return false
        }
    }

    /// Picker section: morphic warp vs stylistic look shaders.
    var pickerSection: LensFXSection {
        switch self {
        case .none: return .warp
        case .liquid, .chrome, .fisheye, .kaleido, .mirror: return .warp
        case .dream, .thermal, .xray, .vhs, .pixel8, .toon, .negative, .instant: return .look
        }
    }

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
        case .toon: return "Comic"
        case .mirror: return "Mirror"
        case .negative: return "Negative"
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
        case .toon: return "INK"
        case .mirror: return "SYM"
        case .negative: return "NEG"
        }
    }
}

enum LensFXSection: String, CaseIterable {
    case warp = "WARP"
    case look = "LOOK"
}

/// Viewfinder touch driving morphic Lens FX (normalized UIKit coords).
struct MorphTouchState {
    /// 0…1 left→right in the viewfinder
    var x: CGFloat = 0.5
    /// 0…1 top→bottom in the viewfinder
    var y: CGFloat = 0.5
    /// 0…1 contact strength (decays after release)
    var force: CGFloat = 0
    /// Normalized velocity (viewfinder widths/sec-ish)
    var velX: CGFloat = 0
    var velY: CGFloat = 0
    var isActive: Bool = false
}

/// How the live preview rotates the sensor buffer to upright UI.
/// Must stay in sync with `FilteredCameraPreview` orientation mapping.
enum PreviewBufferRotation: Equatable {
    case identity       // landscapeRight — sensor-native
    case rotate180      // landscapeLeft
    case rotateRight    // portrait
    case rotateLeft     // portraitUpsideDown

    static func from(interfaceOrientation: UIInterfaceOrientation) -> PreviewBufferRotation {
        switch interfaceOrientation {
        case .landscapeRight: return .identity
        case .landscapeLeft: return .rotate180
        case .portraitUpsideDown: return .rotateLeft
        default: return .rotateRight
        }
    }
}

// MARK: - Lens FX Engine
final class LensFXEngine {
    static let shared = LensFXEngine()

    // Serialize texture creation + effect graphs; preview + capture can hit this
    // from different queues when the user taps an FX.
    private let lock = NSLock()

    // Cached smooth-noise texture that drives the liquid glass distortion
    private var liquidTexture: CIImage?
    /// Throttled morph field — regenerating every preview frame was expensive.
    private var morphCache: CIImage?
    private var morphCacheKey: Int = .min
    private var morphCacheWidth: Int = 0
    private var morphCacheHeight: Int = 0

    // Epoch for animation: absolute timestamps are ~8e8 seconds, which loses
    // all sub-second precision once converted to Float for shader params
    private let startTime = CFAbsoluteTimeGetCurrent()

    // Shared Metal CIContext for still bakes (retries + software fallback)
    private let renderContext = ShutterRender.ciContext

    /// Latest viewfinder touch; read on the capture/preview queue.
    private let touchLock = NSLock()
    private var _touch = MorphTouchState()
    /// Last strong drag — shutter is outside the viewfinder, so force often
    /// decays to 0 before bake; sticky touch keeps the morph the user shaped.
    private var _stickyTouch = MorphTouchState()
    private var stickyTouchTime: CFAbsoluteTime = 0
    private var lastDecayTime: CFAbsoluteTime = 0

    /// Scoped overrides while applying an effect (still bake freezes these).
    private var applyTouchOverride: MorphTouchState?
    private var applyUprightTouch = false
    /// Live preview: skip bloom / twirl / wake so the finder stays fluid.
    private var applyPreviewCheap = false
    /// Live buffer→UI rotation; updated from the preview / ContentView.
    private var previewBufferRotation: PreviewBufferRotation = .rotateRight

    private init() {}

    func setPreviewBufferRotation(_ rotation: PreviewBufferRotation) {
        lock.lock()
        previewBufferRotation = rotation
        lock.unlock()
    }

    var touch: MorphTouchState {
        touchLock.lock()
        defer { touchLock.unlock() }
        return _touch
    }

    /// Snapshot morph uniforms for still bake (live or recent sticky drag).
    func snapshotForCapture() -> MorphTouchState {
        touchLock.lock()
        defer { touchLock.unlock() }
        if _touch.force > 0.15 {
            return _touch
        }
        if CFAbsoluteTimeGetCurrent() - stickyTouchTime < 1.6, _stickyTouch.force > 0.08 {
            var sticky = _stickyTouch
            // Keep the warp readable in the still after finger-up → shutter
            sticky.force = max(sticky.force, 0.55)
            sticky.isActive = false
            return sticky
        }
        return _touch
    }

    /// Update from the viewfinder (normalized UIKit top-left coords + velocity).
    func setTouch(x: CGFloat, y: CGFloat, force: CGFloat, velX: CGFloat, velY: CGFloat, active: Bool) {
        touchLock.lock()
        _touch.x = min(1, max(0, x))
        _touch.y = min(1, max(0, y))
        _touch.force = min(1, max(0, force))
        _touch.velX = velX
        _touch.velY = velY
        _touch.isActive = active
        if force > 0.2 {
            _stickyTouch = _touch
            stickyTouchTime = CFAbsoluteTimeGetCurrent()
        }
        touchLock.unlock()
    }

    /// Exponential settle after finger-up so the warp eases out naturally.
    func decayTouchIfNeeded(now: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()) {
        touchLock.lock()
        defer { touchLock.unlock() }
        guard !_touch.isActive, _touch.force > 0.001 else {
            if !_touch.isActive && _touch.force <= 0.001 {
                _touch.force = 0
                _touch.velX = 0
                _touch.velY = 0
            }
            lastDecayTime = now
            return
        }
        let dt = lastDecayTime > 0 ? min(0.05, now - lastDecayTime) : 1.0 / 30.0
        lastDecayTime = now
        // ~half-life 0.18s
        let k = pow(0.08, dt / 0.18)
        _touch.force *= CGFloat(k)
        _touch.velX *= CGFloat(k)
        _touch.velY *= CGFloat(k)
        if _touch.force < 0.001 {
            _touch.force = 0
            _touch.velX = 0
            _touch.velY = 0
        }
    }

    /// Map viewfinder-normalized UIKit point → CIImage point on the live buffer
    /// (or upright still). Inverts the same rotation `FilteredCameraPreview` applies.
    private func touchCenter(in extent: CGRect, touch: MorphTouchState) -> CGPoint {
        if applyUprightTouch {
            return CGPoint(
                x: extent.minX + touch.x * extent.width,
                y: extent.minY + (1.0 - touch.y) * extent.height
            )
        }
        let rotation = previewBufferRotation
        let nx: CGFloat
        let ny: CGFloat
        switch rotation {
        case .rotateRight:
            // Preview: buffer.oriented(.right). Existing mapping.
            nx = touch.y
            ny = touch.x
        case .rotateLeft:
            nx = 1.0 - touch.y
            ny = 1.0 - touch.x
        case .rotate180:
            nx = 1.0 - touch.x
            ny = 1.0 - touch.y
        case .identity:
            // Sensor-native landscape: UIKit top-left → CI bottom-left.
            nx = touch.x
            ny = 1.0 - touch.y
        }
        return CGPoint(
            x: extent.minX + nx * extent.width,
            y: extent.minY + ny * extent.height
        )
    }

    private func activeTouch() -> MorphTouchState {
        applyTouchOverride ?? touch
    }

    /// Apply the selected effect to a camera frame.
    /// - Parameters:
    ///   - time: Absolute clock for live preview (`CFAbsoluteTimeGetCurrent()`),
    ///     or a relative phase for stills when `stillBake` is true.
    ///   - touchOverride: Frozen morph uniforms for still capture.
    ///   - stillBake: Skip decay; treat `time` as relative phase; upright touch space.
    ///   - previewCheap: Lighter live graph (no chrome bloom / twirl / wake).
    func apply(
        _ fx: LensFXMode,
        to image: CIImage,
        time rawTime: TimeInterval,
        touchOverride: MorphTouchState? = nil,
        stillBake: Bool = false,
        previewCheap: Bool = false
    ) -> CIImage {
        let extent = image.extent
        guard fx != .none,
              !extent.isInfinite,
              extent.width > 1,
              extent.height > 1,
              extent.width.isFinite,
              extent.height.isFinite else {
            return image
        }

        let time: TimeInterval
        if stillBake {
            time = max(0, rawTime)
        } else {
            time = rawTime > 0 ? rawTime - startTime : 0
            if rawTime > 0 {
                decayTouchIfNeeded(now: rawTime)
            }
        }

        lock.lock()
        applyTouchOverride = touchOverride
        applyUprightTouch = stillBake
        applyPreviewCheap = previewCheap && !stillBake
        defer {
            applyTouchOverride = nil
            applyUprightTouch = false
            applyPreviewCheap = false
            lock.unlock()
        }

        // Keep the preview pipeline alive even if a single filter misbehaves
        let result: CIImage
        switch fx {
        case .none:
            result = image
        case .liquid:
            result = applyLiquid(to: image, time: time)
        case .chrome:
            result = applyChrome(to: image, time: time)
        case .instant:
            result = applyInstant(to: image)
        case .dream:
            result = applyDream(to: image)
        case .fisheye:
            result = applyFisheye(to: image)
        case .thermal:
            result = applyThermal(to: image)
        case .xray:
            result = applyXRay(to: image)
        case .vhs:
            result = applyVHS(to: image, time: time)
        case .kaleido:
            result = applyKaleido(to: image, time: time)
        case .pixel8:
            result = applyPixel8(to: image)
        case .toon:
            result = applyToon(to: image)
        case .mirror:
            result = applyMirror(to: image)
        case .negative:
            result = applyNegative(to: image)
        }

        let outExtent = result.extent
        guard !outExtent.isInfinite,
              outExtent.width > 1,
              outExtent.height > 1 else {
            return image
        }
        return result
    }

    /// Renders a still-image variant of an effect. Orientation metadata is
    /// flattened before processing so the saved JPEG is not rotated twice.
    ///
    /// Under live-camera GPU load, a single `createCGImage` can fail and used
    /// to silently return nil (callers then saved the unfiltered still). This
    /// path retries with plain createCGImage, a software CIContext, and a
    /// smaller max dimension before giving up.
    func render(
        _ fx: LensFXMode,
        on image: UIImage,
        touch: MorphTouchState? = nil,
        maxDimension: CGFloat = 3072
    ) -> UIImage? {
        guard fx != .none else { return image }

        // Prefer CGImage → CIImage so we control orientation ourselves.
        let base: CIImage?
        if let cg = image.cgImage {
            base = CIImage(cgImage: cg)
        } else {
            base = CIImage(image: image)
        }
        guard var input = base else {
            print("LensFX render: could not build CIImage for \(fx.name)")
            return nil
        }

        // Bake the UIImage orientation into the pixels explicitly.
        // CIImage(cgImage:) / CIImage(image:) ignore UIImage.imageOrientation.
        if image.imageOrientation != .up {
            input = input.oriented(image.imageOrientation.cgImageOrientation)
        }

        let attemptDims: [CGFloat] = maxDimension > 2048
            ? [maxDimension, 2048, 1536]
            : [maxDimension, 1536]

        for dim in attemptDims {
            if let rendered = renderAttempt(
                fx,
                input: input,
                maxDimension: dim,
                scale: image.scale,
                touch: touch
            ) {
                return rendered
            }
        }

        print("LensFX render: all attempts failed for \(fx.name) size=\(image.size)")
        return nil
    }

    private func renderAttempt(
        _ fx: LensFXMode,
        input source: CIImage,
        maxDimension: CGFloat,
        scale: CGFloat,
        touch: MorphTouchState?
    ) -> UIImage? {
        var input = source

        let longestEdge = max(input.extent.width, input.extent.height)
        if longestEdge > maxDimension {
            let s = maxDimension / longestEdge
            input = input.transformed(by: CGAffineTransform(scaleX: s, y: s))
        }
        // Normalize origin so filters that use extent.mid as their center behave
        input = input.transformed(by: CGAffineTransform(
            translationX: -input.extent.minX,
            y: -input.extent.minY
        ))

        // Relative phase only — do not pass an absolute clock (that used to
        // smash sticky touch via decayTouchIfNeeded).
        var output = apply(
            fx,
            to: input,
            time: 0.35,
            touchOverride: touch,
            stillBake: true
        ).cropped(to: input.extent)

        // Bake scanlines into VHS stills — live preview draws them via a
        // SwiftUI overlay that never reaches the capture pipeline.
        if fx == .vhs {
            output = applyVHSScanlines(to: output)
        }

        guard output.extent.width > 1, output.extent.height > 1 else { return nil }

        let contexts: [CIContext] = [
            renderContext,
            CIContext(options: [.useSoftwareRenderer: true])
        ]

        for context in contexts {
            // Prefer plain createCGImage — RGBA8+forced sRGB has failed under
            // device GPU contention even when the filter graph is valid.
            if let cgImage = context.createCGImage(output, from: output.extent)
                ?? context.createCGImage(
                    output,
                    from: output.extent,
                    format: .RGBA8,
                    colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
                ) {
                return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
            }
        }
        return nil
    }

    /// Static scanline overlay matching the live VHS viewfinder treatment.
    private func applyVHSScanlines(to image: CIImage) -> CIImage {
        let extent = image.extent
        guard extent.width > 1, extent.height > 1 else { return image }

        // Horizontal stripe mask via striped generator + crop
        let stripes = CIFilter.stripesGenerator()
        stripes.center = CGPoint(x: 0, y: 0)
        stripes.color0 = CIColor(red: 0, green: 0, blue: 0, alpha: 0.35)
        stripes.color1 = CIColor(red: 0, green: 0, blue: 0, alpha: 0)
        stripes.width = Float(max(1.5, extent.height / 280))
        stripes.sharpness = 1

        guard var stripeImage = stripes.outputImage?.transformed(
            by: CGAffineTransform(rotationAngle: .pi / 2)
        ) else { return image }

        stripeImage = stripeImage
            .transformed(by: CGAffineTransform(
                translationX: -stripeImage.extent.minX,
                y: -stripeImage.extent.minY
            ))
            .cropped(to: extent)

        let over = CIFilter.sourceOverCompositing()
        over.inputImage = stripeImage
        over.backgroundImage = image
        return (over.outputImage ?? image).cropped(to: extent)

    }

    // MARK: - Liquid glass distortion

    private func liquidTextureImage() -> CIImage {
        if let liquidTexture { return liquidTexture }
        let made = makeLiquidTexture()
        liquidTexture = made
        return made
    }

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
        if let cgImage = ShutterRender.ciContext.createCGImage(blurred, from: textureRect) {
            return CIImage(cgImage: cgImage)
        }
        return blurred
    }

    // Two noise layers flowing in different directions, blended 50/50.
    // Their interference makes the distortion field genuinely morph over time
    // instead of just sliding past. Cached ~8 Hz — motion still reads continuous.
    private func morphingTexture(covering extent: CGRect, time: TimeInterval) -> CIImage {
        let w = Int(extent.width.rounded())
        let h = Int(extent.height.rounded())
        // Quantize time so Liquid/Chrome don't rebuild the tile field every frame.
        let key = Int((time * 8.0).rounded(.down))
        if let morphCache,
           morphCacheKey == key,
           morphCacheWidth == w,
           morphCacheHeight == h {
            return morphCache
        }

        let t = CGFloat(time)

        let driftA = CGAffineTransform(translationX: t * 46, y: t * 18)
        // Second layer: larger blobs, moving against the first
        let driftB = CGAffineTransform(translationX: -t * 28, y: t * 36)
            .scaledBy(x: 1.8, y: 1.8)

        let base = liquidTextureImage()
        let layerA = base
            .transformed(by: driftA)
            .applyingFilter("CIAffineTile")
            .cropped(to: extent)
        let layerB = base
            .transformed(by: driftB)
            .applyingFilter("CIAffineTile")
            .cropped(to: extent)

        let mix = CIFilter.dissolveTransition()
        mix.inputImage = layerA
        mix.targetImage = layerB
        mix.time = 0.5

        let result = (mix.outputImage ?? layerA).cropped(to: extent)
        morphCache = result
        morphCacheKey = key
        morphCacheWidth = w
        morphCacheHeight = h
        return result
    }

    // Heavy glass warp driven by the morphing texture, plus a slow breathing
    // twirl — reads as flowing liquid rather than static shimmer.
    // When touch force > 0, the warp centers on the finger with a localized
    // refraction bulge and a trailing wake from drag velocity.
    private func morphDistort(_ image: CIImage, extent: CGRect, time: TimeInterval, strength: CGFloat) -> CIImage {
        let t = activeTouch()
        let force = t.force
        let center: CGPoint = force > 0.01
            ? touchCenter(in: extent, touch: t)
            : CGPoint(x: extent.midX, y: extent.midY)

        // Velocity pulls the noise field (molten flow toward drag direction)
        let velBoost = min(1.2, hypot(t.velX, t.velY) * 0.35)
        let textureTime = time
            + TimeInterval(t.velX) * 0.4
            + TimeInterval(t.velY) * 0.25
        let texture = morphingTexture(covering: extent, time: textureTime)

        let forceGain: CGFloat = applyPreviewCheap ? (1.0 + force * 1.1) : (1.0 + force * 1.8 + velBoost * 0.6)
        let glassScale = extent.width * strength * forceGain

        guard let glass = CIFilter(name: "CIGlassDistortion") else { return image }
        glass.setValue(image.clampedToExtent(), forKey: kCIInputImageKey)
        glass.setValue(texture, forKey: "inputTexture")
        glass.setValue(CIVector(x: center.x, y: center.y), forKey: kCIInputCenterKey)
        glass.setValue(glassScale, forKey: kCIInputScaleKey)

        var output = (glass.outputImage ?? image).cropped(to: extent)

        // Localized refraction bulge under the finger
        if force > 0.02 {
            let bump = CIFilter.bumpDistortion()
            bump.inputImage = output.clampedToExtent()
            bump.center = center
            bump.radius = Float(min(extent.width, extent.height) * (0.18 + force * 0.28))
            bump.scale = Float(0.35 + force * 0.85 + velBoost * 0.25)
            output = (bump.outputImage ?? output).cropped(to: extent)

            // Trailing wake opposite drag velocity (skip on cheap live preview)
            let speed = hypot(t.velX, t.velY)
            if !applyPreviewCheap, speed > 0.15 {
                let wake = CIFilter.bumpDistortion()
                // UIKit +y is down; CI +y is up when baking upright stills
                let wakeYSign: CGFloat = applyUprightTouch ? 1 : -1
                let wakeCenter = CGPoint(
                    x: center.x - t.velX * extent.width * 0.12,
                    y: center.y + wakeYSign * t.velY * extent.height * 0.12
                )
                wake.inputImage = output.clampedToExtent()
                wake.center = wakeCenter
                wake.radius = Float(min(extent.width, extent.height) * 0.14)
                wake.scale = Float(min(0.7, speed * 0.35) * force)
                output = (wake.outputImage ?? output).cropped(to: extent)
            }
        }

        // Twirl is expensive — stills keep it; live preview skips.
        if !applyPreviewCheap {
            let twirl = CIFilter.twirlDistortion()
            twirl.inputImage = output.clampedToExtent()
            twirl.center = center
            let baseRadius = min(extent.width, extent.height) * (force > 0.02 ? 0.45 : 0.75)
            twirl.radius = Float(baseRadius * (1.0 + force * 0.35))
            let breath = Float(sin(time * 0.45)) * 0.9
            let dragSpin = Float((t.velX - t.velY) * force * 0.8)
            twirl.angle = breath + dragSpin
            output = (twirl.outputImage ?? output).cropped(to: extent)
        }
        return output
    }

    private func applyLiquid(to image: CIImage, time: TimeInterval) -> CIImage {
        let extent = image.extent
        let strength: CGFloat = applyPreviewCheap ? 0.038 : 0.055
        return morphDistort(image, extent: extent, time: time, strength: strength)
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

        // Specular sheen — stills only; live bloom is a GPU sink.
        if !applyPreviewCheap {
            let bloom = CIFilter.bloom()
            bloom.inputImage = output
            bloom.radius = 6
            bloom.intensity = 0.4
            if let result = bloom.outputImage { output = result }
        }

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
        blur.radius = Float(extent.width * (applyPreviewCheap ? 0.006 : 0.012))
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
        let t = activeTouch()
        let center: CGPoint = t.force > 0.02
            ? touchCenter(in: extent, touch: t)
            : CGPoint(x: extent.midX, y: extent.midY)
        let scaleBoost = Float(t.force * 0.45 + min(0.35, hypot(t.velX, t.velY) * 0.2))

        let bump = CIFilter.bumpDistortion()
        bump.inputImage = image.clampedToExtent()
        bump.center = center
        bump.radius = Float(max(extent.width, extent.height) * (0.62 - t.force * 0.12))
        bump.scale = 0.55 + scaleBoost

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
        let t = activeTouch()
        let center: CGPoint = t.force > 0.02
            ? touchCenter(in: extent, touch: t)
            : CGPoint(x: extent.midX, y: extent.midY)

        let kaleido = CIFilter.kaleidoscope()
        kaleido.inputImage = image.clampedToExtent()
        kaleido.count = 6
        kaleido.center = center
        let baseAngle = Float(time * 0.15)
        let touchSpin = Float((t.velX - t.velY) * t.force * 0.6)
        kaleido.angle = baseAngle + touchSpin

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

    // MARK: - Mirror symmetry

    private func applyMirror(to image: CIImage) -> CIImage {
        let extent = image.extent

        // Flip horizontally in place: x' = (maxX + minX) - x
        let flip = CGAffineTransform(a: -1, b: 0, c: 0, d: 1,
                                     tx: extent.maxX + extent.minX, ty: 0)
        let flipped = image.transformed(by: flip)

        // Right half becomes the reflection of the left half
        let rightHalf = CGRect(x: extent.midX, y: extent.minY,
                               width: extent.width / 2, height: extent.height)

        let composite = CIFilter.sourceOverCompositing()
        composite.inputImage = flipped.cropped(to: rightHalf)
        composite.backgroundImage = image

        return (composite.outputImage ?? image).cropped(to: extent)
    }

    // MARK: - Film negative

    private func applyNegative(to image: CIImage) -> CIImage {
        let extent = image.extent
        var output = image

        let invert = CIFilter.colorInvert()
        invert.inputImage = output
        if let result = invert.outputImage { output = result }

        // Slight orange bias like a real color negative base
        let tint = CIFilter.colorMatrix()
        tint.inputImage = output
        tint.rVector = CIVector(x: 1.0, y: 0, z: 0, w: 0)
        tint.gVector = CIVector(x: 0, y: 0.92, z: 0, w: 0)
        tint.bVector = CIVector(x: 0, y: 0, z: 0.82, w: 0)
        tint.biasVector = CIVector(x: 0.06, y: 0.03, z: 0, w: 0)
        if let result = tint.outputImage { output = result }

        return output.cropped(to: extent)
    }

    // MARK: - Thermal / X-Ray (safe fallbacks)

    private func applyThermal(to image: CIImage) -> CIImage {
        if let filter = CIFilter(name: "CIThermal") {
            filter.setValue(image, forKey: kCIInputImageKey)
            if let output = filter.outputImage {
                return output.cropped(to: image.extent)
            }
        }
        // Fallback: false-color heat map if CIThermal isn't available
        return applyFalseColorHeat(to: image)
    }

    private func applyXRay(to image: CIImage) -> CIImage {
        if let filter = CIFilter(name: "CIXRay") {
            filter.setValue(image, forKey: kCIInputImageKey)
            if let output = filter.outputImage {
                return output.cropped(to: image.extent)
            }
        }
        // Fallback: invert + cool tint
        return applyNegative(to: image)
    }

    private func applyFalseColorHeat(to image: CIImage) -> CIImage {
        let extent = image.extent
        let mono = CIFilter.photoEffectMono()
        mono.inputImage = image
        let base = mono.outputImage ?? image

        let falseColor = CIFilter.falseColor()
        falseColor.inputImage = base
        falseColor.color0 = CIColor(red: 0.05, green: 0.0, blue: 0.35, alpha: 1)
        falseColor.color1 = CIColor(red: 1.0, green: 0.85, blue: 0.1, alpha: 1)
        return (falseColor.outputImage ?? image).cropped(to: extent)
    }

    // MARK: - Helpers

    private func applySimpleFilter(name: String, to image: CIImage) -> CIImage {
        let extent = image.extent
        guard let filter = CIFilter(name: name) else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        guard let output = filter.outputImage else { return image }
        let outExtent = output.extent
        if outExtent.isInfinite || outExtent.width < 1 || outExtent.height < 1 {
            return image
        }
        return output.cropped(to: extent)
    }

    /// Comic look with a real fallback when `CIComicEffect` is unavailable.
    private func applyToon(to image: CIImage) -> CIImage {
        let extent = image.extent
        if let filter = CIFilter(name: "CIComicEffect") {
            filter.setValue(image, forKey: kCIInputImageKey)
            if let output = filter.outputImage {
                let out = output.extent
                if !out.isInfinite, out.width > 1, out.height > 1 {
                    return output.cropped(to: extent)
                }
            }
        }

        // Fallback: posterize + ink edges so Comic never silently no-ops.
        var output = image
        let posterize = CIFilter.colorPosterize()
        posterize.inputImage = output
        posterize.levels = 6
        if let result = posterize.outputImage { output = result }

        let edges = CIFilter.edges()
        edges.inputImage = image
        edges.intensity = 1.4
        if let edgeImage = edges.outputImage {
            let mono = CIFilter.colorControls()
            mono.inputImage = edgeImage
            mono.saturation = 0
            mono.contrast = 1.8
            if let ink = mono.outputImage {
                let multiply = CIFilter.multiplyCompositing()
                multiply.inputImage = ink
                multiply.backgroundImage = output
                if let result = multiply.outputImage {
                    output = result
                }
            }
        }
        return output.cropped(to: extent)
    }
}
