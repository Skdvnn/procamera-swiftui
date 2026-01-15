import AVFoundation
import UIKit
import Photos
import CoreImage
import CoreImage.CIFilterBuiltins

class CameraManager: NSObject, ObservableObject {
    @Published var session = AVCaptureSession()
    @Published var isSessionRunning = false
    @Published var error: CameraError?

    // Camera properties
    @Published var currentCamera: AVCaptureDevice.Position = .back
    @Published var flashMode: AVCaptureDevice.FlashMode = .off
    @Published var exposureValue: Float = 0.0
    @Published var isoValue: Float = 100
    @Published var shutterSpeed: CMTime = CMTime(value: 1, timescale: 125)
    @Published var focusPoint: CGPoint = CGPoint(x: 0.5, y: 0.5)
    @Published var isManualFocus: Bool = false
    @Published var lensPosition: Float = 0.5
    @Published var whiteBalance: AVCaptureDevice.WhiteBalanceGains?
    @Published var zoomFactor: CGFloat = 1.0
    @Published var isManualExposure: Bool = false
    @Published var selectedFilmFilter: FilmFilter = .none
    @Published var isLongExposureCapturing: Bool = false
    @Published var longExposureProgress: Float = 0.0

    // Long exposure support
    private var videoDataOutput: AVCaptureVideoDataOutput?
    private var longExposureFrames: [CIImage] = []
    private var longExposureTargetFrames: Int = 0
    private var longExposureCompletion: ((UIImage?) -> Void)?

    // Film filter types
    enum FilmFilter: Int, CaseIterable {
        case none = 0
        case portra400      // Warm, natural skin tones
        case ektar100       // Vivid, saturated colors
        case trix400        // Classic B&W
        case cinestill800   // Cinematic with halation
        case velvia50       // Ultra-vivid landscape

        var name: String {
            switch self {
            case .none: return "None"
            case .portra400: return "Portra"
            case .ektar100: return "Ektar"
            case .trix400: return "Tri-X"
            case .cinestill800: return "Cine"
            case .velvia50: return "Velvia"
            }
        }
    }

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    // Device capabilities
    @Published var minISO: Float = 50
    @Published var maxISO: Float = 1600
    @Published var minExposure: Float = -2.0
    @Published var maxExposure: Float = 2.0
    @Published var minShutterDuration: CMTime = CMTime(value: 1, timescale: 8000)
    @Published var maxShutterDuration: CMTime = CMTime(value: 1, timescale: 3)

    private var videoDeviceInput: AVCaptureDeviceInput?
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    private var photoCompletionHandler: ((UIImage?) -> Void)?

    // Shutter speed lookup table (index to CMTime)
    static let shutterSpeedValues: [CMTime] = [
        CMTime(value: 4, timescale: 1),      // 4" (4 seconds)
        CMTime(value: 2, timescale: 1),      // 2"
        CMTime(value: 1, timescale: 1),      // 1"
        CMTime(value: 1, timescale: 2),      // 1/2
        CMTime(value: 1, timescale: 4),      // 1/4
        CMTime(value: 1, timescale: 8),      // 1/8
        CMTime(value: 1, timescale: 15),     // 1/15
        CMTime(value: 1, timescale: 30),     // 1/30
        CMTime(value: 1, timescale: 60),     // 1/60
        CMTime(value: 1, timescale: 125),    // 1/125
        CMTime(value: 1, timescale: 250),    // 1/250
        CMTime(value: 1, timescale: 500),    // 1/500
        CMTime(value: 1, timescale: 1000),   // 1/1000
        CMTime(value: 1, timescale: 2000),   // 1/2000
        CMTime(value: 1, timescale: 4000),   // 1/4000
    ]

    enum CameraError: Error, LocalizedError {
        case cameraUnavailable
        case cannotAddInput
        case cannotAddOutput
        case permissionDenied

        var errorDescription: String? {
            switch self {
            case .cameraUnavailable: return "Camera unavailable"
            case .cannotAddInput: return "Cannot add camera input"
            case .cannotAddOutput: return "Cannot add photo output"
            case .permissionDenied: return "Camera permission denied"
            }
        }
    }

    override init() {
        super.init()
    }

    func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    self?.setupSession()
                } else {
                    DispatchQueue.main.async {
                        self?.error = .permissionDenied
                    }
                }
            }
        default:
            error = .permissionDenied
        }
    }

    private func setupSession() {
        sessionQueue.async { [weak self] in
            self?.configureSession()
        }
    }

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        // Add video input
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: currentCamera) else {
            DispatchQueue.main.async { self.error = .cameraUnavailable }
            session.commitConfiguration()
            return
        }

        do {
            let videoInput = try AVCaptureDeviceInput(device: videoDevice)
            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
                videoDeviceInput = videoInput
                updateDeviceCapabilities(device: videoDevice)
            } else {
                DispatchQueue.main.async { self.error = .cannotAddInput }
                session.commitConfiguration()
                return
            }
        } catch {
            DispatchQueue.main.async { self.error = .cannotAddInput }
            session.commitConfiguration()
            return
        }

        // Add photo output
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            photoOutput.isHighResolutionCaptureEnabled = true
            photoOutput.maxPhotoQualityPrioritization = .quality
        } else {
            DispatchQueue.main.async { self.error = .cannotAddOutput }
            session.commitConfiguration()
            return
        }

        // Add video data output for long exposure frame capture
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoDataOutput"))
        videoOutput.alwaysDiscardsLateVideoFrames = false
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
            videoDataOutput = videoOutput
        }

        // Select best format for long exposure support
        selectBestFormatForLongExposure(device: videoDevice)

        session.commitConfiguration()
        startSession()
    }

    private func updateDeviceCapabilities(device: AVCaptureDevice) {
        DispatchQueue.main.async {
            self.minISO = device.activeFormat.minISO
            self.maxISO = device.activeFormat.maxISO
            self.minExposure = device.minExposureTargetBias
            self.maxExposure = device.maxExposureTargetBias
            self.minShutterDuration = device.activeFormat.minExposureDuration
            self.maxShutterDuration = device.activeFormat.maxExposureDuration
        }
    }

    // MARK: - Long Exposure Format Selection
    private func selectBestFormatForLongExposure(device: AVCaptureDevice) {
        // Find format with longest max exposure duration while maintaining good quality
        var bestFormat: AVCaptureDevice.Format?
        var longestDuration: CMTime = CMTime.zero

        for format in device.formats {
            let maxDuration = format.maxExposureDuration
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)

            // Prefer formats with at least 1080p resolution
            guard dimensions.width >= 1920 else { continue }

            // Check if this format supports longer exposure
            if CMTimeCompare(maxDuration, longestDuration) > 0 {
                longestDuration = maxDuration
                bestFormat = format
            }
        }

        // Apply the best format if found
        if let format = bestFormat {
            do {
                try device.lockForConfiguration()
                device.activeFormat = format
                device.unlockForConfiguration()

                // Update capabilities with new format
                updateDeviceCapabilities(device: device)

                let seconds = CMTimeGetSeconds(longestDuration)
                print("Selected format with max exposure: \(seconds)s")
            } catch {
                print("Error selecting format: \(error)")
            }
        }
    }

    // MARK: - Computational Long Exposure
    func captureLongExposure(durationSeconds: Double, completion: @escaping (UIImage?) -> Void) {
        guard let device = videoDeviceInput?.device else {
            completion(nil)
            return
        }

        // Get device's actual max exposure duration
        let maxHardwareDuration = CMTimeGetSeconds(device.activeFormat.maxExposureDuration)

        // If hardware can handle it directly, use single capture
        if durationSeconds <= maxHardwareDuration {
            captureSingleLongExposure(duration: durationSeconds, completion: completion)
        } else {
            // Use computational long exposure (frame averaging)
            captureComputationalLongExposure(targetDuration: durationSeconds, completion: completion)
        }
    }

    private func captureSingleLongExposure(duration: Double, completion: @escaping (UIImage?) -> Void) {
        guard let device = videoDeviceInput?.device else {
            completion(nil)
            return
        }

        let targetDuration = CMTime(seconds: duration, preferredTimescale: 1000000)

        sessionQueue.async {
            do {
                try device.lockForConfiguration()

                // Use user's selected ISO (clamped to device limits) for dark room support
                let targetISO = max(device.activeFormat.minISO, min(self.isoValue, device.activeFormat.maxISO))
                device.setExposureModeCustom(duration: targetDuration, iso: targetISO) { _ in
                    // Now capture the photo
                    DispatchQueue.main.async {
                        self.capturePhoto(completion: completion)
                    }
                }

                device.unlockForConfiguration()
            } catch {
                print("Error setting long exposure: \(error)")
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }

    private func captureComputationalLongExposure(targetDuration: Double, completion: @escaping (UIImage?) -> Void) {
        guard let device = videoDeviceInput?.device else {
            completion(nil)
            return
        }

        // Calculate how many frames we need at 30fps
        let fps: Double = 30.0
        let frameCount = Int(targetDuration * fps)

        DispatchQueue.main.async {
            self.isLongExposureCapturing = true
            self.longExposureProgress = 0.0
        }

        longExposureFrames = []
        longExposureTargetFrames = frameCount
        longExposureCompletion = completion

        // Set camera to max exposure per frame for best results
        sessionQueue.async {
            do {
                try device.lockForConfiguration()

                // Use hardware max exposure duration per frame for dark room support
                let maxDuration = device.activeFormat.maxExposureDuration
                let frameDuration = CMTime(seconds: 1.0/fps, preferredTimescale: 1000000)
                // In dark rooms, use max hardware exposure duration to capture more light
                let exposureDuration = CMTimeCompare(maxDuration, frameDuration) > 0 ? maxDuration : frameDuration

                // Use user's selected ISO (clamped to device limits) instead of forcing minISO
                // This allows proper exposure in dark rooms
                let targetISO = max(device.activeFormat.minISO, min(self.isoValue, device.activeFormat.maxISO))
                device.setExposureModeCustom(duration: exposureDuration, iso: targetISO) { _ in }

                device.unlockForConfiguration()
            } catch {
                print("Error setting up computational long exposure: \(error)")
                DispatchQueue.main.async {
                    self.isLongExposureCapturing = false
                    completion(nil)
                }
            }
        }
    }

    private func processLongExposureFrames() -> UIImage? {
        guard !longExposureFrames.isEmpty else { return nil }

        let count = Float(longExposureFrames.count)

        // Average all frames together
        var accumulatedImage = longExposureFrames[0]

        for i in 1..<longExposureFrames.count {
            let frame = longExposureFrames[i]

            // Blend frames using CIBlendWithAlphaMask or simple addition
            let blend = CIFilter.additionCompositing()
            blend.inputImage = frame
            blend.backgroundImage = accumulatedImage

            if let result = blend.outputImage {
                accumulatedImage = result
            }
        }

        // Normalize by dividing by frame count (multiply by 1/count)
        let colorMatrix = CIFilter.colorMatrix()
        colorMatrix.inputImage = accumulatedImage
        let scale = 1.0 / count
        colorMatrix.rVector = CIVector(x: CGFloat(scale), y: 0, z: 0, w: 0)
        colorMatrix.gVector = CIVector(x: 0, y: CGFloat(scale), z: 0, w: 0)
        colorMatrix.bVector = CIVector(x: 0, y: 0, z: CGFloat(scale), w: 0)
        colorMatrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        colorMatrix.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)

        guard let normalizedImage = colorMatrix.outputImage else { return nil }

        // Render to UIImage
        guard let cgImage = ciContext.createCGImage(normalizedImage, from: normalizedImage.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    func startSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if !self.session.isRunning {
                self.session.startRunning()
                DispatchQueue.main.async {
                    self.isSessionRunning = self.session.isRunning
                }
            }
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
                DispatchQueue.main.async {
                    self.isSessionRunning = false
                }
            }
        }
    }

    func switchCamera() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            let newPosition: AVCaptureDevice.Position = self.currentCamera == .back ? .front : .back

            guard let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition) else { return }

            do {
                let newInput = try AVCaptureDeviceInput(device: newDevice)

                self.session.beginConfiguration()

                if let currentInput = self.videoDeviceInput {
                    self.session.removeInput(currentInput)
                }

                if self.session.canAddInput(newInput) {
                    self.session.addInput(newInput)
                    self.videoDeviceInput = newInput
                    self.updateDeviceCapabilities(device: newDevice)
                    DispatchQueue.main.async {
                        self.currentCamera = newPosition
                        self.zoomFactor = 1.0
                    }
                }

                self.session.commitConfiguration()
            } catch {
                print("Error switching camera: \(error)")
            }
        }
    }

    func setExposure(_ value: Float) {
        guard let device = videoDeviceInput?.device else { return }

        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                device.setExposureTargetBias(value) { _ in }
                device.unlockForConfiguration()
                DispatchQueue.main.async {
                    self.exposureValue = value
                }
            } catch {
                print("Error setting exposure: \(error)")
            }
        }
    }

    func setISO(_ value: Float) {
        guard let device = videoDeviceInput?.device else { return }

        let clampedISO = max(device.activeFormat.minISO, min(value, device.activeFormat.maxISO))

        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                // Use custom exposure mode with current shutter speed and new ISO
                device.setExposureModeCustom(duration: self.shutterSpeed, iso: clampedISO) { _ in }
                device.unlockForConfiguration()
                DispatchQueue.main.async {
                    self.isoValue = clampedISO
                    self.isManualExposure = true
                }
            } catch {
                print("Error setting ISO: \(error)")
            }
        }
    }

    func setShutterSpeed(index: Int) {
        guard let device = videoDeviceInput?.device else { return }
        guard index >= 0 && index < CameraManager.shutterSpeedValues.count else { return }

        let targetDuration = CameraManager.shutterSpeedValues[index]

        // Clamp to device capabilities
        let minDuration = device.activeFormat.minExposureDuration
        let maxDuration = device.activeFormat.maxExposureDuration

        var clampedDuration = targetDuration
        if CMTimeCompare(targetDuration, minDuration) < 0 {
            clampedDuration = minDuration
        }
        if CMTimeCompare(targetDuration, maxDuration) > 0 {
            clampedDuration = maxDuration
        }

        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                // Set custom exposure with specific shutter speed
                let currentISO = max(device.activeFormat.minISO, min(self.isoValue, device.activeFormat.maxISO))
                device.setExposureModeCustom(duration: clampedDuration, iso: currentISO) { _ in }
                device.unlockForConfiguration()
                DispatchQueue.main.async {
                    self.shutterSpeed = clampedDuration
                    self.isManualExposure = true
                }
            } catch {
                print("Error setting shutter speed: \(error)")
            }
        }
    }

    func setAutoExposure() {
        guard let device = videoDeviceInput?.device else { return }

        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                device.unlockForConfiguration()
                DispatchQueue.main.async {
                    self.isManualExposure = false
                }
            } catch {
                print("Error setting auto exposure: \(error)")
            }
        }
    }

    func setFocus(at point: CGPoint) {
        guard let device = videoDeviceInput?.device else { return }

        sessionQueue.async {
            do {
                try device.lockForConfiguration()

                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = point
                    device.focusMode = .autoFocus
                }

                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = point
                    device.exposureMode = .autoExpose
                }

                device.unlockForConfiguration()

                DispatchQueue.main.async {
                    self.focusPoint = point
                }
            } catch {
                print("Error setting focus: \(error)")
            }
        }
    }

    func setManualFocus(_ position: Float) {
        guard let device = videoDeviceInput?.device else { return }

        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                device.setFocusModeLocked(lensPosition: position) { _ in }
                device.unlockForConfiguration()
                DispatchQueue.main.async {
                    self.lensPosition = position
                    self.isManualFocus = true
                }
            } catch {
                print("Error setting manual focus: \(error)")
            }
        }
    }

    func setZoom(_ factor: CGFloat) {
        guard let device = videoDeviceInput?.device else { return }

        let maxZoom = min(device.activeFormat.videoMaxZoomFactor, 10.0)
        let clampedZoom = max(1.0, min(factor, maxZoom))

        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                device.videoZoomFactor = clampedZoom
                device.unlockForConfiguration()
                DispatchQueue.main.async {
                    self.zoomFactor = clampedZoom
                }
            } catch {
                print("Error setting zoom: \(error)")
            }
        }
    }

    func cycleFlash() {
        switch flashMode {
        case .off:
            flashMode = .on
        case .on:
            flashMode = .auto
        case .auto:
            flashMode = .off
        @unknown default:
            flashMode = .off
        }
    }

    // White balance presets
    enum WhiteBalanceMode: Int, CaseIterable {
        case auto = 0
        case sunny = 1
        case cloudy = 2
        case shade = 3
        case incandescent = 4
        case fluorescent = 5

        var temperatureAndTint: (temperature: Float, tint: Float) {
            switch self {
            case .auto: return (0, 0) // Auto mode
            case .sunny: return (5500, 0)
            case .cloudy: return (6500, 0)
            case .shade: return (7500, 0)
            case .incandescent: return (3200, 0)
            case .fluorescent: return (4000, -10)
            }
        }
    }

    func setWhiteBalance(mode: Int) {
        guard let device = videoDeviceInput?.device else { return }

        sessionQueue.async {
            do {
                try device.lockForConfiguration()

                if mode == 0 {
                    // Auto white balance
                    if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                        device.whiteBalanceMode = .continuousAutoWhiteBalance
                    }
                } else {
                    // Manual white balance with temperature
                    if device.isWhiteBalanceModeSupported(.locked) {
                        let wbMode = WhiteBalanceMode(rawValue: mode) ?? .auto
                        let (temp, tint) = wbMode.temperatureAndTint
                        let temperatureAndTint = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(
                            temperature: temp,
                            tint: tint
                        )
                        var gains = device.deviceWhiteBalanceGains(for: temperatureAndTint)
                        // Clamp gains to valid range
                        let maxGain = device.maxWhiteBalanceGain
                        gains.redGain = min(max(1.0, gains.redGain), maxGain)
                        gains.greenGain = min(max(1.0, gains.greenGain), maxGain)
                        gains.blueGain = min(max(1.0, gains.blueGain), maxGain)
                        device.setWhiteBalanceModeLocked(with: gains) { _ in }
                    }
                }

                device.unlockForConfiguration()
            } catch {
                print("Error setting white balance: \(error)")
            }
        }
    }

    // MARK: - Film Filter Processing
    func applyFilmFilter(to image: UIImage) -> UIImage {
        guard selectedFilmFilter != .none else { return image }
        guard let ciImage = CIImage(image: image) else { return image }

        var outputImage = ciImage

        switch selectedFilmFilter {
        case .none:
            break

        case .portra400:
            // Warm, slightly desaturated, lifted shadows
            let colorControls = CIFilter.colorControls()
            colorControls.inputImage = outputImage
            colorControls.saturation = 0.9
            colorControls.contrast = 0.95
            colorControls.brightness = 0.02
            if let result = colorControls.outputImage {
                outputImage = result
            }

            // Add warmth
            let tempTint = CIFilter.temperatureAndTint()
            tempTint.inputImage = outputImage
            tempTint.neutral = CIVector(x: 6500, y: 0)
            tempTint.targetNeutral = CIVector(x: 5800, y: 10)
            if let result = tempTint.outputImage {
                outputImage = result
            }

        case .ektar100:
            // Vivid, saturated, punchy
            let colorControls = CIFilter.colorControls()
            colorControls.inputImage = outputImage
            colorControls.saturation = 1.3
            colorControls.contrast = 1.1
            colorControls.brightness = 0.0
            if let result = colorControls.outputImage {
                outputImage = result
            }

            // Add slight warmth
            let vibrance = CIFilter.vibrance()
            vibrance.inputImage = outputImage
            vibrance.amount = 0.3
            if let result = vibrance.outputImage {
                outputImage = result
            }

        case .trix400:
            // Classic black and white
            let noir = CIFilter.photoEffectNoir()
            noir.inputImage = outputImage
            if let result = noir.outputImage {
                outputImage = result
            }

            // Add contrast
            let colorControls = CIFilter.colorControls()
            colorControls.inputImage = outputImage
            colorControls.contrast = 1.15
            if let result = colorControls.outputImage {
                outputImage = result
            }

        case .cinestill800:
            // Cinematic look with warm highlights
            let colorControls = CIFilter.colorControls()
            colorControls.inputImage = outputImage
            colorControls.saturation = 0.95
            colorControls.contrast = 1.05
            if let result = colorControls.outputImage {
                outputImage = result
            }

            // Warm color cast
            let tempTint = CIFilter.temperatureAndTint()
            tempTint.inputImage = outputImage
            tempTint.neutral = CIVector(x: 6500, y: 0)
            tempTint.targetNeutral = CIVector(x: 5200, y: 15)
            if let result = tempTint.outputImage {
                outputImage = result
            }

            // Add halation-like bloom (subtle highlight glow)
            let bloom = CIFilter.bloom()
            bloom.inputImage = outputImage
            bloom.radius = 5
            bloom.intensity = 0.3
            if let result = bloom.outputImage {
                outputImage = result
            }

        case .velvia50:
            // Ultra vivid, high saturation
            let colorControls = CIFilter.colorControls()
            colorControls.inputImage = outputImage
            colorControls.saturation = 1.5
            colorControls.contrast = 1.15
            colorControls.brightness = -0.02
            if let result = colorControls.outputImage {
                outputImage = result
            }

            // Boost vibrance
            let vibrance = CIFilter.vibrance()
            vibrance.inputImage = outputImage
            vibrance.amount = 0.4
            if let result = vibrance.outputImage {
                outputImage = result
            }
        }

        // Render the filtered image (use outputImage.extent in case filter changed bounds)
        guard let cgImage = ciContext.createCGImage(outputImage, from: outputImage.extent) else {
            return image
        }

        return UIImage(cgImage: cgImage, scale: image.scale, orientation: image.imageOrientation)
    }

    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        photoCompletionHandler = { [weak self] image in
            guard let self = self, let image = image else {
                completion(nil)
                return
            }
            // Apply film filter before returning
            let filteredImage = self.applyFilmFilter(to: image)
            completion(filteredImage)
        }

        var settings = AVCapturePhotoSettings()

        if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        }

        settings.flashMode = flashMode
        settings.isHighResolutionPhotoEnabled = true

        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    // MARK: - Video Recording (stub for now)
    func startRecording() {
        print("Recording started")
        // TODO: Implement video recording
    }

    func stopRecording() {
        print("Recording stopped")
        // TODO: Implement video recording
    }

    func saveToPhotoLibrary(_ image: UIImage, completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized else {
                DispatchQueue.main.async { completion(false) }
                return
            }

            PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, error in
                DispatchQueue.main.async {
                    completion(success)
                }
            }
        }
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil,
              let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            photoCompletionHandler?(nil)
            return
        }
        photoCompletionHandler?(image)
    }
}

// MARK: - Video Data Output Delegate (for computational long exposure)
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Only capture frames when doing long exposure
        guard isLongExposureCapturing,
              longExposureFrames.count < longExposureTargetFrames else {
            // Check if we've collected enough frames
            if isLongExposureCapturing && longExposureFrames.count >= longExposureTargetFrames {
                finalizeLongExposure()
            }
            return
        }

        // Convert sample buffer to CIImage
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        longExposureFrames.append(ciImage)

        // Update progress
        let progress = Float(longExposureFrames.count) / Float(longExposureTargetFrames)
        DispatchQueue.main.async {
            self.longExposureProgress = progress
        }
    }

    private func finalizeLongExposure() {
        guard isLongExposureCapturing else { return }

        DispatchQueue.main.async {
            self.isLongExposureCapturing = false
        }

        // Reset camera to auto exposure to prevent lag
        resetToAutoExposure()

        // Process frames on background queue
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let resultImage = self.processLongExposureFrames()

            // Apply film filter if selected
            let finalImage: UIImage?
            if let img = resultImage {
                finalImage = self.applyFilmFilter(to: img)
            } else {
                finalImage = nil
            }

            // Clear frames
            self.longExposureFrames = []

            // Call completion
            DispatchQueue.main.async {
                self.longExposureCompletion?(finalImage)
                self.longExposureCompletion = nil
                self.longExposureProgress = 0.0
            }
        }
    }

    private func resetToAutoExposure() {
        guard let device = videoDeviceInput?.device else { return }

        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                device.unlockForConfiguration()
                DispatchQueue.main.async {
                    self.isManualExposure = false
                }
            } catch {
                print("Error resetting to auto exposure: \(error)")
            }
        }
    }
}
