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

    func makeUIView(context: Context) -> FilteredPreviewView {
        let view = FilteredPreviewView()
        view.session = session
        view.backgroundColor = .black

        // Gestures
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tapGesture)

        let pinchGesture = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        view.addGestureRecognizer(pinchGesture)

        return view
    }

    func updateUIView(_ uiView: FilteredPreviewView, context: Context) {
        uiView.session = session
        uiView.updateFilteredImage(filteredImage)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap, onPinch: onPinch)
    }

    class Coordinator: NSObject {
        var onTap: ((CGPoint) -> Void)?
        var onPinch: ((CGFloat) -> Void)?
        var lastScale: CGFloat = 1.0

        init(onTap: ((CGPoint) -> Void)?, onPinch: ((CGFloat) -> Void)?) {
            self.onTap = onTap
            self.onPinch = onPinch
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            let location = gesture.location(in: gesture.view)
            guard let view = gesture.view else { return }

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
            metalView?.isHidden = false
            previewLayer?.isHidden = true
            metalView?.setNeedsDisplay()
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

        // Apply orientation correction for portrait mode
        // Video frames come in landscape orientation, rotate for portrait display
        let deviceOrientation = UIDevice.current.orientation
        if deviceOrientation.isPortrait || deviceOrientation == .unknown || deviceOrientation == .faceUp || deviceOrientation == .faceDown {
            ciImage = ciImage.oriented(.right)
        } else if deviceOrientation == .landscapeLeft {
            ciImage = ciImage.oriented(.down)
        }
        // landscapeRight is the native orientation, no transform needed

        let drawableSize = view.drawableSize
        let imageSize = ciImage.extent.size

        // Calculate scale to fill the view (aspect fill)
        let scaleX = drawableSize.width / imageSize.width
        let scaleY = drawableSize.height / imageSize.height
        let scale = max(scaleX, scaleY)

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
