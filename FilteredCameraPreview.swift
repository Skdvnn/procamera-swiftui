import SwiftUI
import UIKit
import AVFoundation
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
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onTap: onTap,
            onPinch: onPinch,
            onMorphTouch: onMorphTouch,
            exposureDragEnabled: exposureDragEnabled,
            onExposureDrag: onExposureDrag
        )
    }

    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onTap: ((CGPoint) -> Void)?
        var onPinch: ((CGFloat) -> Void)?
        var onMorphTouch: ((CGPoint, CGPoint, Bool) -> Void)?
        var exposureDragEnabled: Bool
        var onExposureDrag: ((CGFloat, Bool) -> Void)?
        var lastScale: CGFloat = 1.0
        weak var tapGesture: UITapGestureRecognizer?
        weak var panGesture: UIPanGestureRecognizer?
        private var lastPanTime: CFAbsoluteTime = 0
        private var lastPanPoint: CGPoint = .zero
        /// Once a pan chooses exposure vs morph, stick with it until lift.
        private var panMode: PanMode = .undecided

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
            onExposureDrag: ((CGFloat, Bool) -> Void)?
        ) {
            self.onTap = onTap
            self.onPinch = onPinch
            self.onMorphTouch = onMorphTouch
            self.exposureDragEnabled = exposureDragEnabled
            self.onExposureDrag = onExposureDrag
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
            let translation = gesture.translation(in: view)

            let now = CFAbsoluteTimeGetCurrent()
            var velocity = CGPoint.zero

            switch gesture.state {
            case .began:
                lastPanTime = now
                lastPanPoint = point
                panMode = .undecided
                if exposureDragEnabled {
                    panMode = .exposure
                    onExposureDrag?(translation.height, false)
                } else {
                    panMode = .morph
                    onMorphTouch?(point, .zero, true)
                }

            case .changed:
                if panMode == .undecided {
                    // Prefer exposure when focus reticle is up; otherwise morph after a hint of movement
                    if exposureDragEnabled && abs(translation.height) >= abs(translation.width) {
                        panMode = .exposure
                    } else {
                        panMode = .morph
                        onMorphTouch?(point, .zero, true)
                    }
                }

                if panMode == .exposure {
                    onExposureDrag?(translation.height, false)
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
                    onExposureDrag?(translation.height, true)
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
        metalView?.frame = bounds
    }

    func updateFilteredImage(_ image: CIImage?) {
        currentCIImage = image

        if image != nil {
            // Show Metal view, hide preview layer
            let wasHidden = metalView?.isHidden ?? true
            metalView?.isHidden = false
            previewLayer?.isHidden = true
            // Defer the first draw until after layout so drawableSize is non-zero
            if wasHidden {
                DispatchQueue.main.async { [weak self] in
                    self?.metalView?.setNeedsDisplay()
                }
            } else {
                metalView?.setNeedsDisplay()
            }
        } else {
            // Show preview layer, hide Metal view
            metalView?.isHidden = true
            previewLayer?.isHidden = false
        }
    }
}

// MARK: - MTKViewDelegate for Metal rendering
extension FilteredPreviewView: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Handle size changes if needed
    }

    func draw(in view: MTKView) {
        guard var ciImage = currentCIImage,
              let commandBuffer = commandQueue?.makeCommandBuffer(),
              let drawable = view.currentDrawable else {
            return
        }

        // First frame after un-hiding the MTKView often has a 0×0 drawable —
        // rendering into that crashes Metal when Lens FX/film filters turn on.
        let drawableSize = view.drawableSize
        guard drawableSize.width > 1, drawableSize.height > 1 else { return }

        // Apply orientation correction for portrait mode
        // Video frames come in landscape orientation, rotate for portrait display
        let deviceOrientation = UIDevice.current.orientation
        if deviceOrientation.isPortrait || deviceOrientation == .unknown || deviceOrientation == .faceUp || deviceOrientation == .faceDown {
            ciImage = ciImage.oriented(.right)
        } else if deviceOrientation == .landscapeLeft {
            ciImage = ciImage.oriented(.down)
        }
        // landscapeRight is the native orientation, no transform needed

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
