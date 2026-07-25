import SwiftUI
import UIKit
import AVFoundation
import AVKit
import CoreImage
import MetalKit

// MARK: - Filtered Camera Preview (renders CIImage with film filters)
struct FilteredCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let filteredImage: CIImage?
    var onTap: ((CGPoint) -> Void)?
    var onPinch: ((CGFloat) -> Void)?
    /// Drag / press on the viewfinder for morphic Lens FX.
    /// point: normalized UIKit (0…1), velocity: normalized deltas, active: finger down.
    var onMorphTouch: ((CGPoint, CGPoint, Bool) -> Void)?
    /// When true, vertical pans scrub exposure (iOS Camera sun-drag) instead of morph.
    var exposureDragEnabled: Bool = false
    /// translation.height in points (finger down = positive), ended flag.
    var onExposureDrag: ((CGFloat, Bool) -> Void)?
    /// Long-press hold-to-compare (true while held).
    var onCompareHold: ((Bool) -> Void)? = nil

    func makeUIView(context: Context) -> FilteredPreviewView {
        let view = FilteredPreviewView()
        view.session = session
        view.backgroundColor = .black

        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tapGesture)

        let pinchGesture = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        view.addGestureRecognizer(pinchGesture)

        // Pan drives exposure scrub (after focus) or morph FX.
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        panGesture.maximumNumberOfTouches = 2
        panGesture.delegate = context.coordinator
        view.addGestureRecognizer(panGesture)

        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.45
        longPress.allowableMovement = 12
        longPress.delegate = context.coordinator
        view.addGestureRecognizer(longPress)

        context.coordinator.tapGesture = tapGesture
        context.coordinator.panGesture = panGesture

        return view
    }

    func updateUIView(_ uiView: FilteredPreviewView, context: Context) {
        uiView.session = session
        uiView.updateFilteredImage(filteredImage)
        context.coordinator.onTap = onTap
        context.coordinator.onPinch = onPinch
        context.coordinator.onMorphTouch = onMorphTouch
        context.coordinator.exposureDragEnabled = exposureDragEnabled
        context.coordinator.onExposureDrag = onExposureDrag
        context.coordinator.onCompareHold = onCompareHold
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onTap: onTap,
            onPinch: onPinch,
            onMorphTouch: onMorphTouch,
            exposureDragEnabled: exposureDragEnabled,
            onExposureDrag: onExposureDrag,
            onCompareHold: onCompareHold
        )
    }

    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onTap: ((CGPoint) -> Void)?
        var onPinch: ((CGFloat) -> Void)?
        var onMorphTouch: ((CGPoint, CGPoint, Bool) -> Void)?
        var exposureDragEnabled: Bool
        var onExposureDrag: ((CGFloat, Bool) -> Void)?
        var onCompareHold: ((Bool) -> Void)?
        var lastScale: CGFloat = 1.0
        weak var tapGesture: UITapGestureRecognizer?
        weak var panGesture: UIPanGestureRecognizer?
        private var lastPanTime: CFAbsoluteTime = 0
        private var lastPanPoint: CGPoint = .zero
        /// Once a pan chooses exposure vs morph, stick with it until lift.
        private var panMode: PanMode = .undecided
        private var compareActive = false

        private enum PanMode {
            case undecided
            case exposure
            case morph
        }

        init(
            onTap: ((CGPoint) -> Void)?,
            onPinch: ((CGFloat) -> Void)?,
            onMorphTouch: ((CGPoint, CGPoint, Bool) -> Void)?,
            exposureDragEnabled: Bool,
            onExposureDrag: ((CGFloat, Bool) -> Void)?,
            onCompareHold: ((Bool) -> Void)?
        ) {
            self.onTap = onTap
            self.onPinch = onPinch
            self.onMorphTouch = onMorphTouch
            self.exposureDragEnabled = exposureDragEnabled
            self.onExposureDrag = onExposureDrag
            self.onCompareHold = onCompareHold
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            let location = gesture.location(in: gesture.view)
            guard let view = gesture.view, view.bounds.width > 0, view.bounds.height > 0 else { return }

            let point = CGPoint(
                x: location.x / view.bounds.width,
                y: location.y / view.bounds.height
            )
            onTap?(point)
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            switch gesture.state {
            case .began:
                compareActive = true
                onCompareHold?(true)
            case .ended, .cancelled, .failed:
                if compareActive {
                    compareActive = false
                    onCompareHold?(false)
                }
            default:
                break
            }
        }

        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                lastScale = 1.0
            case .changed:
                let delta = gesture.scale / lastScale
                lastScale = gesture.scale
                onPinch?(delta)
            default:
                break
            }
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view, view.bounds.width > 0, view.bounds.height > 0 else { return }
            let location = gesture.location(in: view)
            let point = CGPoint(
                x: min(1, max(0, location.x / view.bounds.width)),
                y: min(1, max(0, location.y / view.bounds.height))
            )
            let translation = gesture.translation(in: view) // CGPoint (x/y), not CGSize

            let now = CFAbsoluteTimeGetCurrent()
            var velocity = CGPoint.zero

            switch gesture.state {
            case .began:
                lastPanTime = now
                lastPanPoint = point
                panMode = .undecided
                if exposureDragEnabled {
                    panMode = .exposure
                    onExposureDrag?(translation.y, false)
                } else {
                    panMode = .morph
                    onMorphTouch?(point, .zero, true)
                }

            case .changed:
                if panMode == .undecided {
                    // Prefer exposure when focus reticle is up; otherwise morph after a hint of movement
                    if exposureDragEnabled && abs(translation.y) >= abs(translation.x) {
                        panMode = .exposure
                    } else {
                        panMode = .morph
                        onMorphTouch?(point, .zero, true)
                    }
                }

                if panMode == .exposure {
                    onExposureDrag?(translation.y, false)
                } else {
                    let dt = max(1.0 / 120.0, now - lastPanTime)
                    velocity = CGPoint(
                        x: (point.x - lastPanPoint.x) / CGFloat(dt),
                        y: (point.y - lastPanPoint.y) / CGFloat(dt)
                    )
                    velocity.x = min(8, max(-8, velocity.x))
                    velocity.y = min(8, max(-8, velocity.y))
                    lastPanTime = now
                    lastPanPoint = point
                    onMorphTouch?(point, velocity, true)
                }

            case .ended, .cancelled, .failed:
                if panMode == .exposure {
                    onExposureDrag?(translation.y, true)
                } else {
                    let uiVel = gesture.velocity(in: view)
                    velocity = CGPoint(
                        x: min(8, max(-8, uiVel.x / view.bounds.width)),
                        y: min(8, max(-8, uiVel.y / view.bounds.height))
                    )
                    onMorphTouch?(point, velocity, false)
                }
                panMode = .undecided

            default:
                break
            }
        }
    }
}

// MARK: - Custom Preview View with Metal rendering
class FilteredPreviewView: UIView {
    private var metalView: MTKView?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let ciContext: CIContext
    private var commandQueue: MTLCommandQueue?
    private var device: MTLDevice?
    private var currentCIImage: CIImage?

    var session: AVCaptureSession? {
        didSet {
            previewLayer?.session = session
        }
    }

    override init(frame: CGRect) {
        // Create CIContext with Metal for GPU-accelerated rendering
        if let device = MTLCreateSystemDefaultDevice() {
            self.device = device
            self.commandQueue = device.makeCommandQueue()
            self.ciContext = CIContext(mtlDevice: device, options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()])
        } else {
            self.ciContext = CIContext(options: [.useSoftwareRenderer: false])
        }

        super.init(frame: frame)
        setupViews()
        setupHardwareShutterEvents()
    }

    required init?(coder: NSCoder) {
        if let device = MTLCreateSystemDefaultDevice() {
            self.device = device
            self.commandQueue = device.makeCommandQueue()
            self.ciContext = CIContext(mtlDevice: device, options: [.workingColorSpace: CGColorSpaceCreateDeviceRGB()])
        } else {
            self.ciContext = CIContext(options: [.useSoftwareRenderer: false])
        }

        super.init(coder: coder)
        setupViews()
        setupHardwareShutterEvents()
    }

    /// Camera Control / volume hardware shutter events (iOS 17.2+).
    private var captureEventInteraction: AnyObject?

    private func setupHardwareShutterEvents() {
        if #available(iOS 17.2, *) {
            let interaction = AVCaptureEventInteraction(
                primary: { event in
                    guard event.phase == .ended else { return }
                    NotificationCenter.default.post(name: .shutterHardwareShutter, object: nil)
                },
                secondary: { event in
                    guard event.phase == .ended else { return }
                    NotificationCenter.default.post(name: .shutterHardwareShutter, object: nil)
                }
            )
            interaction.isEnabled = true
            addInteraction(interaction)
            captureEventInteraction = interaction
        }
    }

    private func setupViews() {
        // Setup preview layer (shows raw camera when no filter)
        let preview = AVCaptureVideoPreviewLayer()
        preview.videoGravity = .resizeAspectFill
        layer.addSublayer(preview)
        self.previewLayer = preview

        // Setup Metal view for filtered preview
        if let device = self.device {
            let mtkView = MTKView(frame: bounds, device: device)
            mtkView.delegate = self
            mtkView.framebufferOnly = false
            mtkView.enableSetNeedsDisplay = true
            mtkView.isPaused = true
            mtkView.backgroundColor = .clear
            mtkView.isOpaque = false
            mtkView.isHidden = true  // Hidden when no filter
            // Gestures live on the parent; keep Metal view from eating touches
            mtkView.isUserInteractionEnabled = false
            addSubview(mtkView)
            self.metalView = mtkView
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer?.frame = bounds
        guard let metalView else { return }
        metalView.frame = bounds
        // Explicit drawable size — first FX toggle used to hit a 0×0 layer.
        if bounds.width > 1, bounds.height > 1 {
            let scale = window?.screen.scale ?? UIScreen.main.scale
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            if metalView.drawableSize != size {
                metalView.drawableSize = size
            }
        }
    }

    func updateFilteredImage(_ image: CIImage?) {
        currentCIImage = image

        if image != nil {
            let wasHidden = metalView?.isHidden ?? true
            metalView?.isHidden = false
            previewLayer?.isHidden = true
            // First enable after FX/film toggle: wait for a real drawable.
            if wasHidden {
                setNeedsLayout()
                layoutIfNeeded()
                metalView?.setNeedsLayout()
                metalView?.layoutIfNeeded()
                scheduleMetalDraw(attemptsLeft: 10)
            } else {
                metalView?.setNeedsDisplay()
            }
        } else {
            metalView?.isHidden = true
            previewLayer?.isHidden = false
        }
    }

    /// Retries until MTKView has a non-zero drawable (avoids Metal crash on FX enable).
    private func scheduleMetalDraw(attemptsLeft: Int) {
        guard attemptsLeft > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.016) { [weak self] in
            guard let self, let metalView = self.metalView, !metalView.isHidden else { return }
            self.layoutIfNeeded()
            metalView.layoutIfNeeded()
            if metalView.drawableSize.width > 1, metalView.drawableSize.height > 1,
               metalView.bounds.width > 1, metalView.bounds.height > 1 {
                metalView.setNeedsDisplay()
            } else {
                self.scheduleMetalDraw(attemptsLeft: attemptsLeft - 1)
            }
        }
    }
}

// MARK: - MTKViewDelegate for Metal rendering
extension FilteredPreviewView: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Handle size changes if needed
    }

    /// Prefer the window scene's interface orientation over UIDevice (more reliable
    /// while rotating, and correct when device orientation is faceUp/unknown).
    private static func interfaceOrientation() -> UIInterfaceOrientation {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let orient = scenes.first(where: { $0.activationState == .foregroundActive })?.interfaceOrientation {
            return orient
        }
        return scenes.first?.interfaceOrientation ?? .portrait
    }

    func draw(in view: MTKView) {
        // Size-guard BEFORE currentDrawable — acquiring a 0×0 drawable has
        // crashed Metal on the first film/FX toggle.
        let drawableSize = view.drawableSize
        guard drawableSize.width > 1, drawableSize.height > 1,
              view.bounds.width > 1, view.bounds.height > 1 else {
            return
        }

        guard var ciImage = currentCIImage,
              let commandBuffer = commandQueue?.makeCommandBuffer(),
              let drawable = view.currentDrawable,
              drawable.texture.width > 1,
              drawable.texture.height > 1 else {
            return
        }

        // Video buffers are sensor-native (landscape). Map to the *interface*
        // orientation so portrait + landscape left/right all read upright.
        switch Self.interfaceOrientation() {
        case .portrait, .unknown:
            ciImage = ciImage.oriented(.right)
        case .portraitUpsideDown:
            ciImage = ciImage.oriented(.left)
        case .landscapeLeft:
            // Home button / indicator on the right → buffer needs 180°
            ciImage = ciImage.oriented(.down)
        case .landscapeRight:
            break // sensor-native
        @unknown default:
            ciImage = ciImage.oriented(.right)
        }

        let extent = ciImage.extent
        let imageSize = extent.size
        guard !extent.isInfinite,
              imageSize.width > 1,
              imageSize.height > 1,
              imageSize.width.isFinite,
              imageSize.height.isFinite else {
            return
        }

        // Calculate scale to fill the view (aspect fill)
        let scaleX = drawableSize.width / imageSize.width
        let scaleY = drawableSize.height / imageSize.height
        let scale = max(scaleX, scaleY)
        guard scale.isFinite, scale > 0 else { return }

        // Center the scaled image
        let scaledWidth = imageSize.width * scale
        let scaledHeight = imageSize.height * scale
        let offsetX = (drawableSize.width - scaledWidth) / 2
        let offsetY = (drawableSize.height - scaledHeight) / 2

        // Transform image to fit drawable
        var transformedImage = ciImage
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(by: CGAffineTransform(translationX: offsetX, y: offsetY))

        // Crop to drawable bounds
        let drawableRect = CGRect(origin: .zero, size: drawableSize)
        transformedImage = transformedImage.cropped(to: drawableRect)

        // Render to Metal texture
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        ciContext.render(
            transformedImage,
            to: drawable.texture,
            commandBuffer: commandBuffer,
            bounds: drawableRect,
            colorSpace: colorSpace
        )

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
