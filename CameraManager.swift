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
    @Published var selectedFilmFilter: FilmFilter = .none {
        didSet {
            syncPipelineSelection()
            refreshLivePreviewState()
        }
    }
    @Published var selectedLensFX: LensFXMode = .none {
        didSet {
            syncPipelineSelection()
            refreshLivePreviewState()
        }
    }
    @Published var isLongExposureCapturing: Bool = false
    @Published var longExposureProgress: Float = 0.0
    @Published var captureFormat: CaptureFormatType = .heic

    // Live preview filtering
    @Published var filteredPreviewImage: CIImage?
    private var lastPreviewFrameTime: CFAbsoluteTime = 0
    private let previewFrameInterval: CFAbsoluteTime = 1.0 / 30.0  // 30fps max
    /// While true, skip live FX so the GPU can finish baking the still.
    private var isBakingStill = false

    // Live histogram - real luminance bins computed from preview frames
    @Published var histogramBins: [Float] = []
    private var lastHistogramTime: CFAbsoluteTime = 0

    // Thread-safe copies for the video-data callback (don't read @Published off-main)
    private let pipelineLock = NSLock()
    private var pipelineFilmFilter: FilmFilter = .none
    private var pipelineLensFX: LensFXMode = .none

    // Remember the user's manual exposure so lens/format switches can re-apply it
    private var manualShutterIndex: Int?
    private var manualISOValue: Float?

    // Capture format types
    enum CaptureFormatType: Int, CaseIterable {
        case heic = 0
        case jpeg
        case raw

        var label: String {
            switch self {
            case .heic: return "HEIC"
            case .jpeg: return "JPG"
            case .raw: return "RAW"
            }
        }
    }

    // Long exposure support
    private var videoDataOutput: AVCaptureVideoDataOutput?
    private var longExposureAccumulator: CIImage?
    private var longExposureFrameCount: Int = 0
    private var longExposureTargetFrames: Int = 0
    private var longExposureCompletion: ((UIImage?) -> Void)?

    // Film filter types (color grades / stocks — not GPU morph shaders)
    enum FilmFilter: Int, CaseIterable {
        case none = 0
        case portra400      // Warm, natural skin tones
        case ektar100       // Vivid, saturated colors
        case kodakGold      // Golden warmth, gentle contrast
        case trix400        // Classic B&W
        case cinestill800   // Cinematic with halation
        case velvia50       // Ultra-vivid landscape
        case instant        // Faded Polaroid / SX-70 look

        var name: String {
            switch self {
            case .none: return "None"
            case .portra400: return "Portra"
            case .ektar100: return "Ektar"
            case .kodakGold: return "Gold"
            case .trix400: return "Tri-X"
            case .cinestill800: return "Cine"
            case .velvia50: return "Velvia"
            case .instant: return "Instant"
            }
        }
    }

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    override init() {
        super.init()
        syncPipelineSelection()
    }

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

        // Use wide angle camera directly - virtual multi-camera devices (triple/dual)
        // don't support .custom exposure mode needed for manual ISO/shutter control
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
            photoOutput.maxPhotoQualityPrioritization = .quality
        } else {
            DispatchQueue.main.async { self.error = .cannotAddOutput }
            session.commitConfiguration()
            return
        }

        // Add video data output for long exposure frame capture
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoDataOutput"))
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
            videoDataOutput = videoOutput
        }

        // Select format with longest exposure that still supports custom exposure mode
        selectBestFormatForLongExposure(device: videoDevice)

        // Request full-resolution stills for the final active format
        updateMaxPhotoDimensions(for: videoDevice)

        session.commitConfiguration()
        startSession()
    }

    // Modern replacement for isHighResolutionCaptureEnabled: pick the largest
    // photo dimensions the active format supports. Must be re-applied whenever
    // the device or its active format changes.
    private func updateMaxPhotoDimensions(for device: AVCaptureDevice) {
        let supported = device.activeFormat.supportedMaxPhotoDimensions
        if let best = supported.max(by: { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) }) {
            photoOutput.maxPhotoDimensions = best
        }
    }

    private func updateDeviceCapabilities(device: AVCaptureDevice) {
        let minISO = device.activeFormat.minISO
        let maxISO = device.activeFormat.maxISO
        let minBias = device.minExposureTargetBias
        let maxBias = device.maxExposureTargetBias
        let minDuration = device.activeFormat.minExposureDuration
        let maxDuration = device.activeFormat.maxExposureDuration
        DispatchQueue.main.async {
            self.minISO = minISO
            self.maxISO = maxISO
            self.minExposure = minBias
            self.maxExposure = maxBias
            self.minShutterDuration = minDuration
            self.maxShutterDuration = maxDuration
        }
    }

    private func syncPipelineSelection() {
        pipelineLock.lock()
        pipelineFilmFilter = selectedFilmFilter
        pipelineLensFX = selectedLensFX
        pipelineLock.unlock()
    }

    private func currentPipelineSelection() -> (FilmFilter, LensFXMode) {
        pipelineLock.lock()
        defer { pipelineLock.unlock() }
        return (pipelineFilmFilter, pipelineLensFX)
    }

    /// Re-apply stored manual ISO/shutter after a lens or format change.
    /// Switching devices/formats drops custom exposure; without this the UI
    /// still shows the old shutter/ISO while the sensor has gone back to auto.
    private func reapplyManualExposure(on device: AVCaptureDevice) {
        guard isManualExposure || manualISOValue != nil || manualShutterIndex != nil else { return }
        guard device.isExposureModeSupported(.custom) else { return }

        let duration: CMTime
        if let index = manualShutterIndex,
           index >= 0, index < CameraManager.shutterSpeedValues.count {
            duration = clampDuration(CameraManager.shutterSpeedValues[index], to: device)
        } else {
            duration = clampDuration(AVCaptureDevice.currentExposureDuration, to: device)
        }

        let isoSource = manualISOValue ?? isoValue
        let iso = max(device.activeFormat.minISO, min(isoSource, device.activeFormat.maxISO))

        do {
            try device.lockForConfiguration()
            device.setExposureModeCustom(duration: duration, iso: iso) { _ in }
            device.unlockForConfiguration()
            DispatchQueue.main.async {
                self.shutterSpeed = duration
                self.isoValue = iso
                self.isManualExposure = true
            }
        } catch {
            print("Error reapplying manual exposure: \(error)")
        }
    }

    private func clampDuration(_ duration: CMTime, to device: AVCaptureDevice) -> CMTime {
        let minDuration = device.activeFormat.minExposureDuration
        let maxDuration = device.activeFormat.maxExposureDuration
        if CMTimeCompare(duration, minDuration) < 0 { return minDuration }
        if CMTimeCompare(duration, maxDuration) > 0 { return maxDuration }
        return duration
    }

    // MARK: - Long Exposure Format Selection
    private func selectBestFormatForLongExposure(device: AVCaptureDevice) {
        // Find format with longest max exposure duration at >= 1080p resolution.
        // On builtInWideAngleCamera all standard formats support .custom exposure.
        var bestFormat: AVCaptureDevice.Format?
        var longestDuration: CMTime = CMTime.zero

        for format in device.formats {
            let maxDuration = format.maxExposureDuration
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)

            guard dimensions.width >= 1920 else { continue }

            if CMTimeCompare(maxDuration, longestDuration) > 0 {
                longestDuration = maxDuration
                bestFormat = format
            }
        }

        guard let format = bestFormat else { return }

        do {
            try device.lockForConfiguration()
            device.activeFormat = format
            device.unlockForConfiguration()

            // Verify custom exposure still works with this format; revert if not
            if !device.isExposureModeSupported(.custom) {
                print("Selected format does not support custom exposure, reverting")
                try device.lockForConfiguration()
                device.activeFormat = device.formats.first(where: {
                    CMVideoFormatDescriptionGetDimensions($0.formatDescription).width >= 1920
                }) ?? device.formats[0]
                device.unlockForConfiguration()
            }

            updateDeviceCapabilities(device: device)
        } catch {
            print("Error selecting format: \(error)")
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
                        self.capturePhoto { image in
                            // Restore auto exposure or the preview stays at
                            // seconds-per-frame and the camera looks frozen
                            self.resetToAutoExposure()
                            completion(image)
                        }
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

        longExposureAccumulator = nil
        longExposureFrameCount = 0
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

    private func normalizeAccumulator() -> UIImage? {
        guard let accumulator = longExposureAccumulator, longExposureFrameCount > 0 else { return nil }

        let count = Float(longExposureFrameCount)

        // Normalize by dividing by frame count
        let colorMatrix = CIFilter.colorMatrix()
        colorMatrix.inputImage = accumulator
        let scale = 1.0 / count
        colorMatrix.rVector = CIVector(x: CGFloat(scale), y: 0, z: 0, w: 0)
        colorMatrix.gVector = CIVector(x: 0, y: CGFloat(scale), z: 0, w: 0)
        colorMatrix.bVector = CIVector(x: 0, y: 0, z: CGFloat(scale), w: 0)
        colorMatrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        colorMatrix.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)

        guard let normalizedImage = colorMatrix.outputImage,
              let cgImage = ciContext.createCGImage(normalizedImage, from: normalizedImage.extent) else {
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

            // Use physical camera devices (not virtual) to maintain .custom exposure support
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
        guard device.isExposureModeSupported(.custom) else { return }

        manualISOValue = value

        sessionQueue.async {
            // Prefer the remembered shutter so ISO tweaks don't inherit a weird
            // auto duration after a lens switch
            let duration: CMTime
            if let index = self.manualShutterIndex,
               index >= 0, index < CameraManager.shutterSpeedValues.count {
                duration = self.clampDuration(CameraManager.shutterSpeedValues[index], to: device)
            } else {
                duration = self.clampDuration(AVCaptureDevice.currentExposureDuration, to: device)
            }
            let clampedISO = max(device.activeFormat.minISO, min(value, device.activeFormat.maxISO))

            do {
                try device.lockForConfiguration()
                device.setExposureModeCustom(duration: duration, iso: clampedISO) { _ in }
                device.unlockForConfiguration()
                DispatchQueue.main.async {
                    self.isoValue = clampedISO
                    self.shutterSpeed = duration
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
        guard device.isExposureModeSupported(.custom) else { return }

        manualShutterIndex = index
        let targetDuration = CameraManager.shutterSpeedValues[index]

        sessionQueue.async {
            let clampedDuration = self.clampDuration(targetDuration, to: device)
            let isoSource = self.manualISOValue ?? self.isoValue
            let clampedISO = max(device.activeFormat.minISO, min(isoSource, device.activeFormat.maxISO))

            do {
                try device.lockForConfiguration()
                device.setExposureModeCustom(duration: clampedDuration, iso: clampedISO) { _ in }
                device.unlockForConfiguration()
                DispatchQueue.main.async {
                    self.shutterSpeed = clampedDuration
                    self.isoValue = clampedISO
                    self.isManualExposure = true
                }
            } catch {
                print("Error setting shutter speed: \(error)")
            }
        }
    }

    func setAutoExposure() {
        guard let device = videoDeviceInput?.device else { return }

        manualISOValue = nil
        manualShutterIndex = nil

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

                if device.isExposurePointOfInterestSupported && !self.isManualExposure {
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
        guard device.isFocusModeSupported(.locked) else { return }

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

    /// Restrict AF to near range when macro is on. Only applies in auto/continuous AF.
    func setMacroEnabled(_ enabled: Bool) {
        guard let device = videoDeviceInput?.device else { return }

        sessionQueue.async {
            do {
                try device.lockForConfiguration()

                if device.isAutoFocusRangeRestrictionSupported {
                    device.autoFocusRangeRestriction = enabled ? .near : .none
                }

                // Macro only helps in auto AF — leave locked manual focus alone when disabling,
                // but when enabling, switch to continuous AF so the near restriction can engage.
                if enabled {
                    if device.isFocusModeSupported(.continuousAutoFocus) {
                        device.focusMode = .continuousAutoFocus
                    } else if device.isFocusModeSupported(.autoFocus) {
                        device.focusMode = .autoFocus
                    }
                    DispatchQueue.main.async {
                        self.isManualFocus = false
                    }
                }

                device.unlockForConfiguration()
            } catch {
                print("Error setting macro focus range: \(error)")
            }
        }
    }

    func setZoom(_ factor: CGFloat) {
        guard let device = videoDeviceInput?.device else { return }

        let maxZoom = min(device.activeFormat.videoMaxZoomFactor, 10.0)
        let minZoom = device.minAvailableVideoZoomFactor
        let clampedZoom = max(minZoom, min(factor, maxZoom))

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

    /// Switch to the physical camera lens matching the focal length.
    /// iPhone 15 Pro Max: 13mm ultra-wide, 24mm wide, 48mm (2x crop on wide), 120mm telephoto
    func switchToLens(focalLength: Int) {
        let deviceType: AVCaptureDevice.DeviceType
        let zoomWithinLens: CGFloat

        switch focalLength {
        case 13:
            deviceType = .builtInUltraWideCamera
            zoomWithinLens = 1.0
        case 24:
            deviceType = .builtInWideAngleCamera
            zoomWithinLens = 1.0
        case 48:
            // 48mm = 2x crop on the wide 24mm sensor
            deviceType = .builtInWideAngleCamera
            zoomWithinLens = 2.0
        case 120:
            deviceType = .builtInTelephotoCamera
            zoomWithinLens = 1.0
        default:
            deviceType = .builtInWideAngleCamera
            zoomWithinLens = CGFloat(focalLength) / 24.0
        }

        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            // If already on the right device, just adjust zoom — keep exposure as-is
            if let currentDevice = self.videoDeviceInput?.device,
               currentDevice.deviceType == deviceType {
                do {
                    try currentDevice.lockForConfiguration()
                    currentDevice.videoZoomFactor = max(currentDevice.minAvailableVideoZoomFactor,
                                                        min(zoomWithinLens, currentDevice.activeFormat.videoMaxZoomFactor))
                    currentDevice.unlockForConfiguration()
                    // Zoom-only changes can still perturb locked exposure on some
                    // formats; reassert the user's shutter/ISO if they set them.
                    self.reapplyManualExposure(on: currentDevice)
                    DispatchQueue.main.async { self.zoomFactor = zoomWithinLens }
                } catch {
                    print("Error setting zoom: \(error)")
                }
                return
            }

            // Need to switch to a different physical camera
            guard let newDevice = AVCaptureDevice.default(deviceType, for: .video, position: self.currentCamera) else {
                // Fallback: stay on current device and use digital zoom
                if let device = self.videoDeviceInput?.device {
                    let fallbackZoom: CGFloat
                    switch focalLength {
                    case 13: fallbackZoom = 0.5
                    case 48: fallbackZoom = 2.0
                    case 120: fallbackZoom = 5.0
                    default: fallbackZoom = CGFloat(focalLength) / 24.0
                    }
                    do {
                        try device.lockForConfiguration()
                        device.videoZoomFactor = max(device.minAvailableVideoZoomFactor,
                                                     min(fallbackZoom, device.activeFormat.videoMaxZoomFactor))
                        device.unlockForConfiguration()
                        self.reapplyManualExposure(on: device)
                        DispatchQueue.main.async { self.zoomFactor = fallbackZoom }
                    } catch {}
                }
                return
            }

            do {
                let newInput = try AVCaptureDeviceInput(device: newDevice)

                self.session.beginConfiguration()

                if let currentInput = self.videoDeviceInput {
                    self.session.removeInput(currentInput)
                }

                if self.session.canAddInput(newInput) {
                    self.session.addInput(newInput)
                    self.videoDeviceInput = newInput

                    // Select best format for this lens (changes activeFormat and
                    // clears custom exposure — must reapply afterwards)
                    self.selectBestFormatForLongExposure(device: newDevice)
                    self.updateDeviceCapabilities(device: newDevice)
                    self.updateMaxPhotoDimensions(for: newDevice)

                    // Apply zoom within this lens
                    try newDevice.lockForConfiguration()
                    newDevice.videoZoomFactor = max(newDevice.minAvailableVideoZoomFactor,
                                                    min(zoomWithinLens, newDevice.activeFormat.videoMaxZoomFactor))
                    newDevice.unlockForConfiguration()

                    // Restore the shutter/ISO the UI is still showing
                    self.reapplyManualExposure(on: newDevice)
                }

                self.session.commitConfiguration()

                DispatchQueue.main.async {
                    self.zoomFactor = zoomWithinLens
                }
            } catch {
                print("Error switching lens: \(error)")
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

    // Apply filter to CIImage (for live preview)
    func applyFilmFilter(to ciImage: CIImage, filter: FilmFilter? = nil) -> CIImage {
        let activeFilter = filter ?? selectedFilmFilter
        guard activeFilter != .none else { return ciImage }

        var outputImage = ciImage

        switch activeFilter {
        case .none:
            break

        case .portra400:
            let colorControls = CIFilter.colorControls()
            colorControls.inputImage = outputImage
            colorControls.saturation = 0.9
            colorControls.contrast = 0.95
            colorControls.brightness = 0.02
            if let result = colorControls.outputImage { outputImage = result }

            let tempTint = CIFilter.temperatureAndTint()
            tempTint.inputImage = outputImage
            tempTint.neutral = CIVector(x: 6500, y: 0)
            tempTint.targetNeutral = CIVector(x: 5800, y: 10)
            if let result = tempTint.outputImage { outputImage = result }

        case .ektar100:
            let colorControls = CIFilter.colorControls()
            colorControls.inputImage = outputImage
            colorControls.saturation = 1.3
            colorControls.contrast = 1.1
            colorControls.brightness = 0.0
            if let result = colorControls.outputImage { outputImage = result }

            let vibrance = CIFilter.vibrance()
            vibrance.inputImage = outputImage
            vibrance.amount = 0.3
            if let result = vibrance.outputImage { outputImage = result }

        case .kodakGold:
            // Golden hour in a canister: warm cast, gentle contrast, soft lift
            let colorControls = CIFilter.colorControls()
            colorControls.inputImage = outputImage
            colorControls.saturation = 1.08
            colorControls.contrast = 1.02
            colorControls.brightness = 0.03
            if let result = colorControls.outputImage { outputImage = result }

            let tempTint = CIFilter.temperatureAndTint()
            tempTint.inputImage = outputImage
            tempTint.neutral = CIVector(x: 6500, y: 0)
            tempTint.targetNeutral = CIVector(x: 5400, y: 12)
            if let result = tempTint.outputImage { outputImage = result }

            let vibrance = CIFilter.vibrance()
            vibrance.inputImage = outputImage
            vibrance.amount = 0.15
            if let result = vibrance.outputImage { outputImage = result }

        case .trix400:
            let noir = CIFilter.photoEffectNoir()
            noir.inputImage = outputImage
            if let result = noir.outputImage { outputImage = result }

            let colorControls = CIFilter.colorControls()
            colorControls.inputImage = outputImage
            colorControls.contrast = 1.15
            if let result = colorControls.outputImage { outputImage = result }

        case .cinestill800:
            let colorControls = CIFilter.colorControls()
            colorControls.inputImage = outputImage
            colorControls.saturation = 0.95
            colorControls.contrast = 1.05
            if let result = colorControls.outputImage { outputImage = result }

            let tempTint = CIFilter.temperatureAndTint()
            tempTint.inputImage = outputImage
            tempTint.neutral = CIVector(x: 6500, y: 0)
            tempTint.targetNeutral = CIVector(x: 5200, y: 15)
            if let result = tempTint.outputImage { outputImage = result }

            // Skip bloom for preview performance
            // let bloom = CIFilter.bloom()
            // bloom.inputImage = outputImage
            // bloom.radius = 5
            // bloom.intensity = 0.3
            // if let result = bloom.outputImage { outputImage = result }

        case .velvia50:
            let colorControls = CIFilter.colorControls()
            colorControls.inputImage = outputImage
            colorControls.saturation = 1.5
            colorControls.contrast = 1.15
            colorControls.brightness = -0.02
            if let result = colorControls.outputImage { outputImage = result }

            let vibrance = CIFilter.vibrance()
            vibrance.inputImage = outputImage
            vibrance.amount = 0.4
            if let result = vibrance.outputImage { outputImage = result }

        case .instant:
            outputImage = applyInstantFilmLook(to: outputImage, preview: true)
        }

        return outputImage
    }

    func applyFilmFilter(to image: UIImage) -> UIImage {

        applyFilmFilter(selectedFilmFilter, to: image)
    }

    /// Polaroid / SX-70 grade used by FilmFilter.instant (and legacy LensFX.instant).
    private func applyInstantFilmLook(to image: CIImage, preview: Bool) -> CIImage {
        let extent = image.extent
        var output = image

        let controls = CIFilter.colorControls()
        controls.inputImage = output
        controls.saturation = 0.82
        controls.brightness = 0.02
        controls.contrast = 0.92
        if let result = controls.outputImage { output = result }

        let tempTint = CIFilter.temperatureAndTint()
        tempTint.inputImage = output
        tempTint.neutral = CIVector(x: 6500, y: 0)
        tempTint.targetNeutral = CIVector(x: 5300, y: -8)
        if let result = tempTint.outputImage { output = result }

        let curve = CIFilter.toneCurve()
        curve.inputImage = output
        curve.point0 = CGPoint(x: 0.00, y: 0.10)
        curve.point1 = CGPoint(x: 0.25, y: 0.28)
        curve.point2 = CGPoint(x: 0.50, y: 0.52)
        curve.point3 = CGPoint(x: 0.75, y: 0.78)
        curve.point4 = CGPoint(x: 1.00, y: 0.93)
        if let result = curve.outputImage { output = result }

        let vignette = CIFilter.vignette()
        vignette.inputImage = output
        vignette.intensity = 0.8
        vignette.radius = 1.8
        if let result = vignette.outputImage { output = result }

        if !preview {
            let bloom = CIFilter.bloom()
            bloom.inputImage = output
            bloom.radius = 4
            bloom.intensity = 0.25
            if let result = bloom.outputImage { output = result }
        }

        return output.cropped(to: extent)
    }

    private func applyFilmFilter(_ filmFilter: FilmFilter, to image: UIImage) -> UIImage {
        guard filmFilter != .none else { return image }
        guard var ciImage = CIImage(image: image) else { return image }

        // Bake UIImage orientation into pixels; CIImage(image:) ignores it
        if image.imageOrientation != .up {
            ciImage = ciImage.oriented(image.imageOrientation.cgImageOrientation)
        }


        var outputImage = ciImage

        switch filmFilter {
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

        case .kodakGold:
            // Golden hour in a canister: warm cast, gentle contrast, soft lift
            let colorControls = CIFilter.colorControls()
            colorControls.inputImage = outputImage
            colorControls.saturation = 1.08
            colorControls.contrast = 1.02
            colorControls.brightness = 0.03
            if let result = colorControls.outputImage {
                outputImage = result
            }

            let tempTint = CIFilter.temperatureAndTint()
            tempTint.inputImage = outputImage
            tempTint.neutral = CIVector(x: 6500, y: 0)
            tempTint.targetNeutral = CIVector(x: 5400, y: 12)
            if let result = tempTint.outputImage {
                outputImage = result
            }

            let vibrance = CIFilter.vibrance()
            vibrance.inputImage = outputImage
            vibrance.amount = 0.15
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

        case .instant:
            outputImage = applyInstantFilmLook(to: outputImage, preview: false)
        }

        // Render the filtered image (use outputImage.extent in case filter changed bounds)
        guard let cgImage = ciContext.createCGImage(outputImage, from: outputImage.extent) else {
            return image
        }

        return UIImage(cgImage: cgImage, scale: image.scale, orientation: .up)
    }

    // Applies the new filter selection on the very next frame and drops any
    // stale filtered output, so toggling never appears stuck
    private func refreshLivePreviewState() {
        lastPreviewFrameTime = 0
        if selectedFilmFilter == .none && selectedLensFX == .none {
            filteredPreviewImage = nil
        }
    }

    private func downscaled(_ image: CIImage, longEdge target: CGFloat) -> CIImage {
        let maxDim = max(image.extent.width, image.extent.height)
        guard maxDim > target else { return image }
        let scale = target / maxDim
        return image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }

    // Cap live preview frames at ~1280px on the long edge; the viewfinder is
    // much smaller than sensor resolution and filters cost per-pixel
    private func downscaledForPreview(_ image: CIImage) -> CIImage {
        downscaled(image, longEdge: 1280)
    }

    // MARK: - Live Histogram

    // Computes 40 luminance bins from the current frame via CIAreaHistogram
    private func updateHistogram(from image: CIImage) {
        let binCount = 40

        // Histogram doesn't need resolution — sample a small version
        let small = downscaled(image, longEdge: 256)

        guard let filter = CIFilter(name: "CIAreaHistogram") else { return }
        filter.setValue(small, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: small.extent), forKey: "inputExtent")
        filter.setValue(binCount, forKey: "inputCount")
        filter.setValue(12.0, forKey: "inputScale")

        guard let output = filter.outputImage else { return }

        var bitmap = [UInt8](repeating: 0, count: binCount * 4)
        ciContext.render(
            output,
            toBitmap: &bitmap,
            rowBytes: binCount * 4,
            bounds: CGRect(x: 0, y: 0, width: binCount, height: 1),
            format: .RGBA8,
            colorSpace: nil
        )

        var bins = [Float](repeating: 0, count: binCount)
        for i in 0..<binCount {
            let r = Float(bitmap[i * 4])
            let g = Float(bitmap[i * 4 + 1])
            let b = Float(bitmap[i * 4 + 2])
            bins[i] = (r + g + b) / (3.0 * 255.0)
        }

        // Normalize so the tallest bin fills the display
        let peak = max(bins.max() ?? 1, 0.001)
        let normalized = bins.map { $0 / peak }

        DispatchQueue.main.async {
            self.histogramBins = normalized
        }
    }

    // MARK: - Lens FX Processing

    // Apply the selected lens FX to a captured still
    func applyLensFX(to image: UIImage) -> UIImage {
        applyLensFX(selectedLensFX, to: image)
    }

    private func applyLensFX(_ lensFX: LensFXMode, to image: UIImage) -> UIImage {
        guard lensFX != .none else { return image }
        if let rendered = LensFXEngine.shared.render(lensFX, on: image) {
            return rendered
        }
        // Last-ditch: never silently ship the unfiltered still when an FX was
        // requested — try a more aggressive downscale via the engine again.
        if let rendered = LensFXEngine.shared.render(lensFX, on: image, maxDimension: 1280) {
            print("LensFX: recovered bake at 1280px for \(lensFX.name)")
            return rendered
        }
        print("LensFX: BAKE FAILED for \(lensFX.name) — saving unfiltered still")
        return image
    }

    /// - Parameters:
    ///   - filmFilter: Optional override frozen from the UI at shutter time.
    ///   - lensFX: Optional override frozen from the UI at shutter time.
    ///     Prefer passing these from ContentView so bake cannot miss a stale
    ///     `selectedLensFX` if the SwiftUI binding lagged the viewfinder.
    func capturePhoto(
        filmFilter: FilmFilter? = nil,
        lensFX: LensFXMode? = nil,
        completion: @escaping (UIImage?) -> Void
    ) {
        // Freeze the selections at shutter time. The user can change controls
        // while AVFoundation is delivering the still.
        let captureFilmFilter = filmFilter ?? selectedFilmFilter
        let captureLensFX = lensFX ?? selectedLensFX
        let shouldProcess = captureFormat != .raw
        let needsFXBake = shouldProcess && (captureLensFX != .none || captureFilmFilter != .none)

        if needsFXBake {
            isBakingStill = true
        }

        print("LensFX capture: fx=\(captureLensFX.name) film=\(captureFilmFilter) format=\(captureFormat) process=\(shouldProcess)")


        photoCompletionHandler = { [weak self] image in
            guard let self = self, let image = image else {
                self?.isBakingStill = false
                DispatchQueue.main.async { completion(nil) }
                return
            }
            // Process off the AVFoundation delegate thread — filtering a full-res
            // still there blocks the capture pipeline and freezes the camera.
            // Deliver on main so SwiftUI state updates are safe.
            DispatchQueue.global(qos: .userInitiated).async {

                let filteredImage: UIImage
                if shouldProcess {
                    filteredImage = self.applyLensFX(
                        captureLensFX,
                        to: self.applyFilmFilter(captureFilmFilter, to: image)
                    )
                } else {
                    filteredImage = image
                }
                self.isBakingStill = false
                print("LensFX capture done: out=\(filteredImage.size) orient=\(filteredImage.imageOrientation.rawValue)")

                DispatchQueue.main.async { completion(filteredImage) }
            }
        }

        var settings: AVCapturePhotoSettings

        switch captureFormat {
        case .heic:
            if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
            } else {
                settings = AVCapturePhotoSettings()
            }
        case .jpeg:
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        case .raw:
            // Dual RAW+processed: DNG alone cannot decode via UIImage(data:),
            // which previously returned nil and dropped the capture silently.
            if let rawFormat = photoOutput.availableRawPhotoPixelFormatTypes.first {
                let processedFormat: [String: Any]
                if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                    processedFormat = [AVVideoCodecKey: AVVideoCodecType.hevc]
                } else {
                    processedFormat = [AVVideoCodecKey: AVVideoCodecType.jpeg]
                }
                settings = AVCapturePhotoSettings(
                    rawPixelFormatType: rawFormat,
                    processedFormat: processedFormat
                )
            } else {
                print("RAW not supported, falling back to HEIC")
                if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                    settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
                } else {
                    settings = AVCapturePhotoSettings()
                }
            }
        }

        settings.flashMode = flashMode
        settings.maxPhotoDimensions = photoOutput.maxPhotoDimensions

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

    private func saveRawDataToPhotoLibrary(_ data: Data) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else { return }

            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
            } completionHandler: { success, error in
                if let error = error {
                    print("Failed to save RAW: \(error)")
                } else if !success {
                    print("Failed to save RAW: unknown error")
                }
            }
        }
    }
}

extension CameraManager: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print("Photo capture error: \(error)")
            // RAW half of a dual capture can fail independently; still wait for processed
            if photo.isRawPhoto { return }
            let handler = photoCompletionHandler
            photoCompletionHandler = nil
            handler?(nil)
            return
        }

        // RAW half of a dual capture — persist DNG, wait for processed preview
        if photo.isRawPhoto {
            if let rawData = photo.fileDataRepresentation() {
                saveRawDataToPhotoLibrary(rawData)
            }
            return
        }

        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            let handler = photoCompletionHandler
            photoCompletionHandler = nil
            handler?(nil)
            return
        }

        let handler = photoCompletionHandler
        photoCompletionHandler = nil
        handler?(image)
    }
}

// MARK: - Video Data Output Delegate (for computational long exposure + live preview)
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Convert sample buffer to CIImage
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        // Update the real histogram a few times a second
        if !isLongExposureCapturing {
            let now = CFAbsoluteTimeGetCurrent()
            if now - lastHistogramTime >= 0.25 {
                lastHistogramTime = now
                updateHistogram(from: ciImage)
            }
        }

        // Handle live preview processing (film filter and/or lens FX, not during long exposure)
        let (filmFilter, lensFX) = currentPipelineSelection()
        let wantsLiveProcessing = filmFilter != .none || lensFX != .none
        if wantsLiveProcessing && !isLongExposureCapturing && !isBakingStill {

            let currentTime = CFAbsoluteTimeGetCurrent()
            if currentTime - lastPreviewFrameTime >= previewFrameInterval {
                lastPreviewFrameTime = currentTime

                // Downscale first: full-res sensor frames are far too heavy
                // to run distortion filters on at preview frame rates
                var processed = downscaledForPreview(ciImage)
                processed = applyFilmFilter(to: processed, filter: filmFilter)
                if lensFX != .none {
                    processed = LensFXEngine.shared.apply(lensFX, to: processed, time: currentTime)
                }

                DispatchQueue.main.async {
                    self.filteredPreviewImage = processed
                }
            }
        } else if !wantsLiveProcessing {
            // Clear filtered preview when no filter selected
            DispatchQueue.main.async {
                if self.filteredPreviewImage != nil {
                    self.filteredPreviewImage = nil
                }
            }
        }

        // Handle long exposure frame capture
        guard isLongExposureCapturing,
              longExposureFrameCount < longExposureTargetFrames else {
            if isLongExposureCapturing && longExposureFrameCount >= longExposureTargetFrames {
                finalizeLongExposure()
            }
            return
        }

        // Running accumulation — add frame to accumulator.
        // Accumulate at reduced resolution: adding full-res frames at 30fps
        // saturates the GPU and freezes the app during the exposure.
        let accumulationFrame = downscaled(ciImage, longEdge: 2048)
        if let acc = longExposureAccumulator {
            let blend = CIFilter.additionCompositing()
            blend.inputImage = accumulationFrame
            blend.backgroundImage = acc
            longExposureAccumulator = blend.outputImage
        } else {
            longExposureAccumulator = accumulationFrame
        }
        longExposureFrameCount += 1

        // Render intermediate result every 30 frames to keep CIFilter chain shallow
        if longExposureFrameCount % 30 == 0, let acc = longExposureAccumulator {
            if let rendered = ciContext.createCGImage(acc, from: acc.extent) {
                longExposureAccumulator = CIImage(cgImage: rendered)
            }
        }

        let progress = Float(longExposureFrameCount) / Float(longExposureTargetFrames)
        DispatchQueue.main.async {
            self.longExposureProgress = progress
        }
    }

    private func finalizeLongExposure() {
        guard isLongExposureCapturing else { return }

        DispatchQueue.main.async {
            self.isLongExposureCapturing = false
        }

        resetToAutoExposure()

        let captureFilmFilter = selectedFilmFilter
        let captureLensFX = selectedLensFX
        isBakingStill = true

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let resultImage = self.normalizeAccumulator()

            let finalImage: UIImage?
            if let img = resultImage {
                finalImage = self.applyLensFX(
                    captureLensFX,
                    to: self.applyFilmFilter(captureFilmFilter, to: img)
                )
            } else {
                finalImage = nil
            }

            self.longExposureAccumulator = nil
            self.longExposureFrameCount = 0
            self.isBakingStill = false

            DispatchQueue.main.async {
                self.longExposureCompletion?(finalImage)
                self.longExposureCompletion = nil
                self.longExposureProgress = 0.0
            }
        }
    }

    private func resetToAutoExposure() {
        guard let device = videoDeviceInput?.device else { return }

        longExposureAccumulator = nil
        longExposureFrameCount = 0
        longExposureTargetFrames = 0

        sessionQueue.async {
            do {
                try device.lockForConfiguration()

                // Reset to auto exposure
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }

                // Reset exposure duration to auto
                if device.isExposureModeSupported(.autoExpose) {
                    device.exposureMode = .autoExpose
                }

                device.unlockForConfiguration()

                DispatchQueue.main.async {
                    self.isManualExposure = false
                    self.longExposureProgress = 0.0
                }
            } catch {
                print("Error resetting to auto exposure: \(error)")
            }
        }
    }
}
