import AVFoundation
import UIKit
import Photos
import CoreImage
import CoreImage.CIFilterBuiltins
import Combine

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
    @Published var isAEAFLocked: Bool = false
    /// Hardware lens aperture (read-only; phones don't stop down).
    @Published var lensAperture: Float = 0
    @Published var focusPeakingEnabled: Bool = false {
        didSet {
            syncPipelineSelection()
            refreshLivePreviewState()
        }
    }
    @Published var zebraEnabled: Bool = false {
        didSet {
            syncPipelineSelection()
            refreshLivePreviewState()
        }
    }
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
    /// "HW" single-shot hardware duration vs "STACK" computational average.
    @Published var longExposurePathLabel: String = ""
    /// Hold-to-compare: temporarily show clean preview (no film/FX bake).
    @Published var previewLooksBypassed: Bool = false {
        didSet {
            syncPipelineSelection()
            refreshLivePreviewState()
        }
    }
    @Published var captureFormat: CaptureFormatType = .heic
    /// Minimal Apple computational photography — prefer speed + Bayer RAW.
    /// Default ON: less Smart HDR / Deep Fusion fusion, more sensor-honest stills.
    @Published var naturalCaptureEnabled: Bool = true {
        didSet {
            guard oldValue != naturalCaptureEnabled else { return }
            sessionQueue.async { [weak self] in
                self?.applyNaturalCapturePhotoOutputConfig()
            }
        }
    }
    // Live preview filtering — Metal sink, NOT @Published (avoids 15Hz SwiftUI thrash).
    let livePreview = LivePreviewBridge()
    private var lastPreviewFrameTime: CFAbsoluteTime = 0
    /// True while Metal is showing a filtered frame (video-queue flag).
    private var livePreviewActive = false
    /// Cap live FX preview — heavy FX go slower.
    private let previewFrameInterval: CFAbsoluteTime = 1.0 / 15.0

    // Live histogram - real luminance bins computed from preview frames
    @Published var histogramBins: [Float] = []
    private var lastHistogramTime: CFAbsoluteTime = 0

    // Thread-safe copies for the video-data callback (don't read @Published off-main)
    private let pipelineLock = NSLock()
    private var pipelineFilmFilter: FilmFilter = .none
    private var pipelineLensFX: LensFXMode = .none
    private var pipelinePeaking = false
    private var pipelineZebra = false
    private var pipelineBypassLooks = false
    /// Skip live FX while a still bake owns the GPU (main / video / bake queues).
    private var pipelineBakingStill = false

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
    private var longExposureStartTime: CFAbsoluteTime = 0
    private var longExposureTargetDuration: TimeInterval = 0
    private var longExposureCompletion: ((UIImage?) -> Void)?
    /// Frame-accumulation gate (video queue). Separate from the published UI flag.
    private var isAccumulatingLongExposure = false
    private var isFinalizingLongExposure = false
    private var longExposureFilmFilter: FilmFilter = .none
    private var longExposureLensFX: LensFXMode = .none
    private var longExposureMorphTouch: MorphTouchState?
    /// Manual shutter/ISO to restore after LE thaws the multi-second preview lock.
    private var exposureSnapshotBeforeLE: (shutter: Int?, iso: Float?)?
    private var bakeTimeoutWork: DispatchWorkItem?

    // Film stocks — same enum as UI (`FilmFilterMode`).
    typealias FilmFilter = FilmFilterMode

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
    /// Prevents re-adding inputs/outputs when SwiftUI re-fires onAppear.
    private var isSessionConfigured = false

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
        // SwiftUI can re-call onAppear; never re-add the same photoOutput.
        guard !isSessionConfigured else {
            startSession()
            return
        }

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
            applyNaturalCapturePhotoOutputConfig()
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
        isSessionConfigured = true
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

    // MARK: - Natural / rude capture (minimize Apple computational photography)

    /// Configure photo output for natural (speed + Bayer) vs polished (quality + ProRAW allowed).
    /// Must run on `sessionQueue`. There is no public "disable Deep Fusion" switch —
    /// `.speed` + Bayer RAW + ProRAW off are the real levers (WWDC / AVFoundation).
    private func applyNaturalCapturePhotoOutputConfig() {
        let natural = naturalCaptureEnabled
        // Per-capture prioritization cannot exceed this max.
        photoOutput.maxPhotoQualityPrioritization = natural ? .speed : .quality

        // ProRAW is Apple's fused linear DNG — more processing, not less.
        // Keep it off in natural mode so Bayer formats stay available.
        if photoOutput.isAppleProRAWSupported {
            photoOutput.isAppleProRAWEnabled = !natural
        }

        print("NaturalCapture: natural=\(natural) maxQ=\(photoOutput.maxPhotoQualityPrioritization.rawValue) proRAW=\(photoOutput.isAppleProRAWEnabled) rawFormats=\(photoOutput.availableRawPhotoPixelFormatTypes.count)")
    }

    /// Prefer pure Bayer sensor RAW over Apple ProRAW (fused / more processed).
    private func preferredRawPixelFormat() -> OSType? {
        let available = photoOutput.availableRawPhotoPixelFormatTypes
        if let bayer = available.first(where: { AVCapturePhotoOutput.isBayerRAWPixelFormat($0) }) {
            return bayer
        }
        // Fallback: any non-ProRAW format, then first available.
        if let nonPro = available.first(where: { !AVCapturePhotoOutput.isAppleProRAWPixelFormat($0) }) {
            return nonPro
        }
        return available.first
    }

    private func applyMinimalProcessing(to settings: inout AVCapturePhotoSettings) {
        let natural = naturalCaptureEnabled
        // `.speed` skips the heavy multi-frame fusion path that `.quality` invites.
        settings.photoQualityPrioritization = natural ? .speed : .quality
        // Red-eye is an extra face-rewrite pass — never for natural stills.
        settings.isAutoRedEyeReductionEnabled = false
        // Per-capture fusion knob lives on settings (not photoOutput).
        if photoOutput.isVirtualDeviceFusionSupported {
            settings.isAutoVirtualDeviceFusionEnabled = false
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
            self.lensAperture = device.lensAperture
        }
    }

    private func syncPipelineSelection() {
        pipelineLock.lock()
        pipelineFilmFilter = selectedFilmFilter
        pipelineLensFX = selectedLensFX
        pipelinePeaking = focusPeakingEnabled
        pipelineZebra = zebraEnabled
        pipelineBypassLooks = previewLooksBypassed
        pipelineLock.unlock()
    }

    private func setBakingStill(_ baking: Bool) {
        pipelineLock.lock()
        pipelineBakingStill = baking
        pipelineLock.unlock()
    }

    private func armBakeTimeout() {
        bakeTimeoutWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.photoCompletionHandler != nil else { return }
            print("Capture timeout — clearing stuck bake gate")
            let handler = self.photoCompletionHandler
            self.photoCompletionHandler = nil
            self.setBakingStill(false)
            handler?(nil)
        }
        bakeTimeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: work)
    }

    private func cancelBakeTimeout() {
        bakeTimeoutWork?.cancel()
        bakeTimeoutWork = nil
    }

    private func currentPipelineSelection() -> (FilmFilter, LensFXMode, Bool, Bool, Bool, Bool) {
        pipelineLock.lock()
        defer { pipelineLock.unlock() }
        return (
            pipelineFilmFilter,
            pipelineLensFX,
            pipelinePeaking,
            pipelineZebra,
            pipelineBypassLooks,
            pipelineBakingStill
        )
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
    /// - Parameters:
    ///   - filmFilter / lensFX: Optional overrides frozen at shutter time (same as `capturePhoto`).
    func captureLongExposure(
        durationSeconds: Double,
        filmFilter: FilmFilter? = nil,
        lensFX: LensFXMode? = nil,
        completion: @escaping (UIImage?) -> Void
    ) {
        guard let device = videoDeviceInput?.device else {
            completion(nil)
            return
        }

        longExposureFilmFilter = filmFilter ?? selectedFilmFilter
        longExposureLensFX = lensFX ?? selectedLensFX
        let fx = longExposureLensFX
        longExposureMorphTouch = fx.isTouchReactive
            ? LensFXEngine.shared.snapshotForCapture()
            : nil
        // Remember manuals so thawing the LE custom exposure doesn't wipe Night/Street.
        exposureSnapshotBeforeLE = (manualShutterIndex, manualISOValue)

        // Get device's actual max exposure duration
        let maxHardwareDuration = CMTimeGetSeconds(device.activeFormat.maxExposureDuration)

        // If hardware can handle it directly, use single capture
        if durationSeconds <= maxHardwareDuration {
            DispatchQueue.main.async { self.longExposurePathLabel = "HW" }
            captureSingleLongExposure(duration: durationSeconds, completion: completion)
        } else {
            // Use computational long exposure (frame averaging)
            DispatchQueue.main.async { self.longExposurePathLabel = "STACK" }
            captureComputationalLongExposure(targetDuration: durationSeconds, completion: completion)
        }
    }

    private func captureSingleLongExposure(duration: Double, completion: @escaping (UIImage?) -> Void) {
        guard let device = videoDeviceInput?.device else {
            completion(nil)
            return
        }

        let targetDuration = CMTime(seconds: duration, preferredTimescale: 1000000)
        let captureFilm = longExposureFilmFilter
        let captureFX = longExposureLensFX

        DispatchQueue.main.async {
            self.isLongExposureCapturing = true
            self.longExposureProgress = 0.0
        }

        sessionQueue.async {
            do {
                try device.lockForConfiguration()

                // Use user's selected ISO (clamped to device limits) for dark room support
                let targetISO = max(device.activeFormat.minISO, min(self.isoValue, device.activeFormat.maxISO))
                device.setExposureModeCustom(duration: targetDuration, iso: targetISO) { _ in
                    // Now capture the photo
                    DispatchQueue.main.async {
                        self.longExposureProgress = 1.0
                        self.capturePhoto(filmFilter: captureFilm, lensFX: captureFX) { image in
                            // Thaw multi-second preview lock, then restore manuals.
                            self.restoreExposureAfterLongExposure()
                            self.isLongExposureCapturing = false
                            self.longExposureProgress = 0.0
                            self.longExposurePathLabel = ""
                            completion(image)
                        }
                    }
                }

                device.unlockForConfiguration()
            } catch {
                print("Error setting long exposure: \(error)")
                DispatchQueue.main.async {
                    self.isLongExposureCapturing = false
                    completion(nil)
                }
            }
        }
    }

    private func captureComputationalLongExposure(targetDuration: Double, completion: @escaping (UIImage?) -> Void) {
        guard let device = videoDeviceInput?.device else {
            completion(nil)
            return
        }

        // Wall-clock target: stop when real time elapses, not after N frames at 30fps.
        // Per-frame exposure often uses hardware max (~1s), so a frame-count budget
        // made "4s" LE take minutes and feel stuck.
        DispatchQueue.main.async {
            self.isLongExposureCapturing = true
            self.longExposureProgress = 0.0
        }

        isFinalizingLongExposure = false
        isAccumulatingLongExposure = true
        longExposureAccumulator = nil
        longExposureFrameCount = 0
        longExposureStartTime = CFAbsoluteTimeGetCurrent()
        longExposureTargetDuration = max(targetDuration, 0.1)
        longExposureCompletion = completion

        // Set camera to max exposure per frame for best light gathering
        sessionQueue.async {
            do {
                try device.lockForConfiguration()

                let maxDuration = device.activeFormat.maxExposureDuration
                let frameDuration = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 1000000)
                // In dark rooms, use max hardware exposure duration to capture more light
                let exposureDuration = CMTimeCompare(maxDuration, frameDuration) > 0 ? maxDuration : frameDuration

                let targetISO = max(device.activeFormat.minISO, min(self.isoValue, device.activeFormat.maxISO))
                device.setExposureModeCustom(duration: exposureDuration, iso: targetISO) { _ in }

                device.unlockForConfiguration()
            } catch {
                print("Error setting up computational long exposure: \(error)")
                self.isAccumulatingLongExposure = false
                self.longExposureCompletion = nil
                DispatchQueue.main.async {
                    self.isLongExposureCapturing = false
                    completion(nil)
                }
            }
        }
    }

    /// Running-average accumulator already stays in display range — just render it.
    private func normalizeAccumulator() -> UIImage? {
        guard let accumulator = longExposureAccumulator, longExposureFrameCount > 0 else { return nil }

        guard let cgImage = ciContext.createCGImage(accumulator, from: accumulator.extent) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    private func scaledCIImage(_ image: CIImage, scale: Float) -> CIImage {
        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = image
        let s = CGFloat(scale)
        matrix.rVector = CIVector(x: s, y: 0, z: 0, w: 0)
        matrix.gVector = CIVector(x: 0, y: s, z: 0, w: 0)
        matrix.bVector = CIVector(x: 0, y: 0, z: s, w: 0)
        matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        matrix.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        return matrix.outputImage ?? image
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
                    self.selectBestFormatForLongExposure(device: newDevice)
                    self.updateMaxPhotoDimensions(for: newDevice)
                    self.updateDeviceCapabilities(device: newDevice)
                    self.applyNaturalCapturePhotoOutputConfig()
                    DispatchQueue.main.async {
                        self.currentCamera = newPosition
                        self.zoomFactor = 1.0
                    }
                    // Flip drops custom exposure on the new device — restore manuals.
                    self.reapplyManualExposure(on: newDevice)
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
                    self.isAEAFLocked = false
                }
            } catch {
                print("Error setting auto exposure: \(error)")
            }
        }
    }

    /// Lock both AF and AE at the current values (pro half-press analogue).
    func setAEAFLocked(_ locked: Bool) {
        guard let device = videoDeviceInput?.device else { return }

        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                if locked {
                    if device.isFocusModeSupported(.locked) {
                        device.focusMode = .locked
                    }
                    // Don't clobber custom ISO/shutter; only lock auto-exposure modes.
                    if !self.isManualExposure, device.isExposureModeSupported(.locked) {
                        device.exposureMode = .locked
                    }
                } else {
                    if device.isFocusModeSupported(.continuousAutoFocus) {
                        device.focusMode = .continuousAutoFocus
                    }
                    if !self.isManualExposure, device.isExposureModeSupported(.continuousAutoExposure) {
                        device.exposureMode = .continuousAutoExposure
                    }
                }
                device.unlockForConfiguration()
                DispatchQueue.main.async {
                    self.isAEAFLocked = locked
                    if !locked {
                        self.isManualFocus = false
                    }
                }
            } catch {
                print("Error setting AE/AF lock: \(error)")
            }
        }
    }

    /// Continuous AF + auto exposure — one-tap exit from manual / lock.
    func returnToAuto() {
        setAutoExposure()
        guard let device = videoDeviceInput?.device else { return }
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                if device.isFocusModeSupported(.continuousAutoFocus) {
                    device.focusMode = .continuousAutoFocus
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = CGPoint(x: 0.5, y: 0.5)
                }
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
                }
                device.setExposureTargetBias(0) { _ in }
                device.unlockForConfiguration()
                DispatchQueue.main.async {
                    self.isManualFocus = false
                    self.isAEAFLocked = false
                    self.exposureValue = 0
                    self.lensPosition = device.lensPosition
                }
            } catch {
                print("Error returning to auto: \(error)")
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

            // Preview skips bloom — CIBloom every frame freezes the finder.
            // Still bake keeps the full CineStill halation.

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

        // Live grain stays a Canvas overlay (cheap, stable). Still bake adds CI grain.
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

        // Bake grain into film stills so the finder overlay isn't preview-only.
        if filmFilter != .none {
            outputImage = applyFilmGrain(to: outputImage, amount: 0.06)
        }

        // Same retry / software-fallback path as Lens FX — a single createCGImage
        // can fail under live-camera GPU load and used to drop the film look silently.
        if let rendered = renderCIImageSafely(outputImage, scale: image.scale) {
            return rendered
        }
        print("FilmFilter: bake failed for \(filmFilter) — saving unfiltered still")
        return image
    }

    /// Soft luminance grain (shared by live preview + still bake).
    private func applyFilmGrain(to image: CIImage, amount: Float) -> CIImage {
        let extent = image.extent
        guard !extent.isInfinite, extent.width > 1, extent.height > 1, amount > 0 else {
            return image
        }
        let noise = CIFilter.randomGenerator()
        guard var noiseImage = noise.outputImage?.cropped(to: extent) else { return image }

        let mono = CIFilter.colorControls()
        mono.inputImage = noiseImage
        mono.saturation = 0
        mono.contrast = 1.4
        if let result = mono.outputImage { noiseImage = result }

        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = noiseImage
        let a = CGFloat(amount)
        matrix.rVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        matrix.gVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        matrix.bVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        matrix.aVector = CIVector(x: a, y: a, z: a, w: 0)
        matrix.biasVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        guard let grainAlpha = matrix.outputImage else { return image }

        let softLight = CIFilter.softLightBlendMode()
        softLight.inputImage = grainAlpha
        softLight.backgroundImage = image
        return (softLight.outputImage ?? image).cropped(to: extent)
    }

    /// Finite-extent + downscale + software CIContext retries for still bakes.
    private func renderCIImageSafely(_ image: CIImage, scale: CGFloat) -> UIImage? {
        var working = image
        let extent = working.extent
        guard !extent.isInfinite,
              extent.width > 1,
              extent.height > 1,
              extent.width.isFinite,
              extent.height.isFinite else {
            return nil
        }
        working = working.transformed(by: CGAffineTransform(
            translationX: -working.extent.minX,
            y: -working.extent.minY
        ))

        let dims: [CGFloat] = [4096, 3072, 2048, 1536]
        let contexts: [CIContext] = [
            ciContext,
            CIContext(options: [.useSoftwareRenderer: true])
        ]

        for dim in dims {
            var candidate = working
            let longest = max(candidate.extent.width, candidate.extent.height)
            if longest > dim {
                let s = dim / longest
                candidate = candidate.transformed(by: CGAffineTransform(scaleX: s, y: s))
            }
            for context in contexts {
                if let cgImage = context.createCGImage(candidate, from: candidate.extent)
                    ?? context.createCGImage(
                        candidate,
                        from: candidate.extent,
                        format: .RGBA8,
                        colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
                    ) {
                    return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
                }
            }
        }
        return nil
    }

    // Applies the new filter selection on the very next frame and drops any
    // stale filtered output, so toggling never appears stuck
    private func refreshLivePreviewState() {
        lastPreviewFrameTime = 0
        if previewLooksBypassed
            || (selectedFilmFilter == .none && selectedLensFX == .none
                && !focusPeakingEnabled && !zebraEnabled) {
            livePreviewActive = false
            livePreview.push(nil)
        }
    }

    private func downscaled(_ image: CIImage, longEdge target: CGFloat) -> CIImage {
        let maxDim = max(image.extent.width, image.extent.height)
        guard maxDim > target else { return image }
        let scale = target / maxDim
        return image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }

    // Cap live preview frames; heavy FX use a smaller buffer.
    private func downscaledForPreview(_ image: CIImage, heavyFX: Bool) -> CIImage {
        downscaled(image, longEdge: heavyFX ? 720 : 840)
    }

    private func isHeavyPreviewFX(_ fx: LensFXMode) -> Bool {
        switch fx {
        case .liquid, .chrome, .dream, .kaleido, .toon: return true
        default: return false
        }
    }

    private func previewInterval(for fx: LensFXMode, film: FilmFilter) -> CFAbsoluteTime {
        if isHeavyPreviewFX(fx) { return 1.0 / 11.0 }
        if film != .none || fx != .none { return previewFrameInterval }
        return previewFrameInterval
    }

    // MARK: - Live Histogram

    // Computes 40 luminance bins from the current frame via CIAreaHistogram
    private func updateHistogram(from image: CIImage) {
        let binCount = 40

        // Histogram doesn't need resolution — sample a small version
        let small = downscaled(image, longEdge: 160)

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
            // Skip no-op publishes — each assignment redraws ContentView.
            if Self.histogramNearlyEqual(normalized, self.histogramBins) { return }
            self.histogramBins = normalized
        }
    }

    private static func histogramNearlyEqual(_ a: [Float], _ b: [Float]) -> Bool {
        guard a.count == b.count, !a.isEmpty else { return false }
        var err: Float = 0
        for i in a.indices {
            err += abs(a[i] - b[i])
        }
        return err < 0.4
    }

    // MARK: - Lens FX Processing

    // Apply the selected lens FX to a captured still
    func applyLensFX(to image: UIImage) -> UIImage {
        applyLensFX(selectedLensFX, to: image)
    }

    private func applyLensFX(
        _ lensFX: LensFXMode,
        to image: UIImage,
        touch: MorphTouchState? = nil
    ) -> UIImage {
        guard lensFX != .none else { return image }
        if let rendered = LensFXEngine.shared.render(lensFX, on: image, touch: touch) {
            return rendered
        }
        // Last-ditch: never silently ship the unfiltered still when an FX was
        // requested — try a more aggressive downscale via the engine again.
        if let rendered = LensFXEngine.shared.render(
            lensFX,
            on: image,
            touch: touch,
            maxDimension: 1280
        ) {
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
    ///   - morphTouch: Frozen drag-to-morph uniforms (Liquid/Chrome/Fisheye/Kaleido).
    func capturePhoto(
        filmFilter: FilmFilter? = nil,
        lensFX: LensFXMode? = nil,
        morphTouch: MorphTouchState? = nil,
        completion: @escaping (UIImage?) -> Void
    ) {
        // Serialize — a second shutter while bake is in-flight used to overwrite
        // photoCompletionHandler and drop / mis-route the first still.
        if photoCompletionHandler != nil {
            DispatchQueue.main.async { completion(nil) }
            return
        }

        // Freeze the selections at shutter time. The user can change controls
        // while AVFoundation is delivering the still.
        let captureFilmFilter = filmFilter ?? selectedFilmFilter
        let captureLensFX = lensFX ?? selectedLensFX
        let captureTouch: MorphTouchState? = {
            if let morphTouch { return morphTouch }
            guard captureLensFX.isTouchReactive else { return nil }
            return LensFXEngine.shared.snapshotForCapture()
        }()
        // Selected film/FX always bake into the processed companion (WYSIWYG).
        // Natural capture only reduces Apple ISP fusion — it does not strip looks.
        // RAW DNG stays clean via the separate raw callback.
        let needsFXBake = captureLensFX != .none || captureFilmFilter != .none

        if needsFXBake {
            setBakingStill(true)
        }

        print("LensFX capture: fx=\(captureLensFX.name) film=\(captureFilmFilter) format=\(captureFormat) bake=\(needsFXBake) natural=\(naturalCaptureEnabled) touchForce=\(captureTouch?.force ?? 0)")

        photoCompletionHandler = { [weak self] image in
            self?.cancelBakeTimeout()
            guard let self = self, let image = image else {
                self?.setBakingStill(false)
                DispatchQueue.main.async { completion(nil) }
                return
            }
            // Process off the AVFoundation delegate thread — filtering a full-res
            // still there blocks the capture pipeline and freezes the camera.
            // Deliver on main so SwiftUI state updates are safe.
            DispatchQueue.global(qos: .userInitiated).async {

                let filteredImage: UIImage
                if needsFXBake {
                    filteredImage = self.applyLensFX(
                        captureLensFX,
                        to: self.applyFilmFilter(captureFilmFilter, to: image),
                        touch: captureTouch
                    )
                } else {
                    filteredImage = image
                }
                self.setBakingStill(false)
                print("LensFX capture done: out=\(filteredImage.size) orient=\(filteredImage.imageOrientation.rawValue)")

                DispatchQueue.main.async { completion(filteredImage) }
            }
        }
        armBakeTimeout()

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
            // Prefer Bayer over ProRAW so the DNG stays closer to the sensor.
            if let rawFormat = preferredRawPixelFormat() {
                let isBayer = AVCapturePhotoOutput.isBayerRAWPixelFormat(rawFormat)
                let isPro = AVCapturePhotoOutput.isAppleProRAWPixelFormat(rawFormat)
                print("NaturalCapture RAW: format=\(rawFormat) bayer=\(isBayer) proRAW=\(isPro)")
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
        applyMinimalProcessing(to: &settings)

        // Snapshot UIKit orientation on main — never from sessionQueue.
        let fire: (CGFloat) -> Void = { [weak self] angle in
            guard let self else { return }
            self.sessionQueue.async {
                guard self.session.isRunning else {
                    DispatchQueue.main.async {
                        self.cancelBakeTimeout()
                        self.photoCompletionHandler = nil
                        self.setBakingStill(false)
                        completion(nil)
                    }
                    return
                }
                if let device = self.videoDeviceInput?.device {
                    self.updateMaxPhotoDimensions(for: device)
                }
                settings.maxPhotoDimensions = self.photoOutput.maxPhotoDimensions
                self.applyCaptureOrientation(rotationAngle: angle)
                self.photoOutput.capturePhoto(with: settings, delegate: self)
            }
        }
        if Thread.isMainThread {
            fire(Self.videoRotationAngle(for: Self.currentInterfaceOrientation()))
        } else {
            DispatchQueue.main.async {
                fire(Self.videoRotationAngle(for: Self.currentInterfaceOrientation()))
            }
        }
    }

    // MARK: - Capture / preview orientation

    /// Match still orientation to what the finder shows (portrait + landscape).
    private func applyCaptureOrientation(rotationAngle: CGFloat) {
        guard let connection = photoOutput.connection(with: .video) else { return }
        if connection.isVideoRotationAngleSupported(rotationAngle) {
            connection.videoRotationAngle = rotationAngle
        }
        // Front camera: mirror so selfies match the finder (preview layer mirrors).
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = (currentCamera == .front)
        }
    }

    static func currentInterfaceOrientation() -> UIInterfaceOrientation {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let orient = scenes.first(where: { $0.activationState == .foregroundActive })?.interfaceOrientation {
            return orient
        }
        return scenes.first?.interfaceOrientation ?? .portrait
    }

    /// Degrees clockwise for `AVCaptureConnection.videoRotationAngle`.
    static func videoRotationAngle(for orient: UIInterfaceOrientation) -> CGFloat {
        switch orient {
        case .portrait: return 90
        case .portraitUpsideDown: return 270
        case .landscapeRight: return 0
        case .landscapeLeft: return 180
        default: return 90
        }
    }


    func saveToPhotoLibrary(_ image: UIImage, completion: @escaping (String?) -> Void) {
        PhotosLibraryService.saveImage(image, completion: completion)
    }

    private func saveRawDataToPhotoLibrary(_ data: Data) {
        PhotosLibraryService.requestReadWrite { status in
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
            cancelBakeTimeout()
            let handler = photoCompletionHandler
            photoCompletionHandler = nil
            setBakingStill(false)
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
            cancelBakeTimeout()
            let handler = photoCompletionHandler
            photoCompletionHandler = nil
            setBakingStill(false)
            handler?(nil)
            return
        }

        let handler = photoCompletionHandler
        photoCompletionHandler = nil
        handler?(image)
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: Error?
    ) {
        // Last-chance clear if processed never arrived (stuck bake / RAW-only fail).
        guard photoCompletionHandler != nil else { return }
        if let error {
            print("didFinishCaptureFor error: \(error)")
        } else {
            print("didFinishCaptureFor with handler still armed — clearing")
        }
        cancelBakeTimeout()
        let handler = photoCompletionHandler
        photoCompletionHandler = nil
        setBakingStill(false)
        handler?(nil)
    }
}

// MARK: - Video Data Output Delegate (for computational long exposure + live preview)
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Convert sample buffer to CIImage
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        // Update the real histogram ~2×/sec (was 4× and republished every time).
        if !isLongExposureCapturing {
            let now = CFAbsoluteTimeGetCurrent()
            if now - lastHistogramTime >= 0.5 {
                lastHistogramTime = now
                updateHistogram(from: ciImage)
            }
        }

        // Handle live preview processing (film filter and/or lens FX, not during long exposure)
        let (filmFilter, lensFX, peaking, zebra, bypass, bakingStill) = currentPipelineSelection()
        if bypass {
            if livePreviewActive {
                livePreviewActive = false
                livePreview.push(nil)
            }
        } else {
        let wantsLiveProcessing = filmFilter != .none || lensFX != .none || peaking || zebra
        if wantsLiveProcessing && !isLongExposureCapturing && !bakingStill {

            let currentTime = CFAbsoluteTimeGetCurrent()
            let interval = previewInterval(for: lensFX, film: filmFilter)
            if currentTime - lastPreviewFrameTime >= interval {
                lastPreviewFrameTime = currentTime
                let heavy = isHeavyPreviewFX(lensFX)

                // Downscale + autoreleasepool: keep FX cheap and crash-resistant
                // under GPU contention when toggling looks rapidly.
                let processed: CIImage? = autoreleasepool {
                    var frame = downscaledForPreview(ciImage, heavyFX: heavy)
                    let extent = frame.extent
                    guard !extent.isInfinite,
                          extent.width > 1,
                          extent.height > 1 else {
                        return nil
                    }
                    frame = applyFilmFilter(to: frame, filter: filmFilter)
                    if lensFX != .none {
                        // previewCheap skips bloom/twirl that stills still get.
                        frame = LensFXEngine.shared.apply(
                            lensFX,
                            to: frame,
                            time: currentTime,
                            previewCheap: true
                        )
                    }
                    if peaking {
                        frame = ViewfinderMonitor.applyFocusPeaking(to: frame)
                    }
                    if zebra {
                        frame = ViewfinderMonitor.applyZebra(to: frame)
                    }
                    let out = frame.extent
                    guard !out.isInfinite, out.width > 1, out.height > 1 else {
                        return nil
                    }
                    return frame
                }

                if let processed {
                    livePreviewActive = true
                    livePreview.push(processed)
                }
            }
        } else if !wantsLiveProcessing {
            // Clear once — do not hop to main on every idle camera frame.
            if livePreviewActive {
                livePreviewActive = false
                livePreview.push(nil)
            }
        }
        }

        // Handle long exposure frame capture (wall-clock stop + running average)
        guard isAccumulatingLongExposure else { return }

        let elapsed = CFAbsoluteTimeGetCurrent() - longExposureStartTime
        // Prefer at least one frame before stopping; bail if the sensor never delivers.
        if elapsed >= longExposureTargetDuration {
            if longExposureFrameCount > 0 || elapsed >= longExposureTargetDuration + 8 {
                finalizeLongExposure()
            }
            return
        }

        // Running average keeps values in 0…1 so periodic 8-bit flatten is safe.
        // (Old path summed then divided — flatten crushed highlights → near-black.)
        let accumulationFrame = downscaled(ciImage, longEdge: 2048)
        longExposureFrameCount += 1
        let n = Float(longExposureFrameCount)
        if let acc = longExposureAccumulator, n > 1 {
            let scaledOld = scaledCIImage(acc, scale: (n - 1) / n)
            let scaledNew = scaledCIImage(accumulationFrame, scale: 1 / n)
            let blend = CIFilter.additionCompositing()
            blend.inputImage = scaledNew
            blend.backgroundImage = scaledOld
            longExposureAccumulator = blend.outputImage
        } else {
            longExposureAccumulator = accumulationFrame
        }

        // Keep the CIFilter graph shallow
        if longExposureFrameCount % 30 == 0, let acc = longExposureAccumulator {
            if let rendered = ciContext.createCGImage(acc, from: acc.extent) {
                longExposureAccumulator = CIImage(cgImage: rendered)
            }
        }

        let progress = min(1.0, Float(elapsed / longExposureTargetDuration))
        DispatchQueue.main.async {
            self.longExposureProgress = progress
        }
    }

    private func finalizeLongExposure() {
        // Gate against repeated calls while the video queue is still delivering frames
        guard isAccumulatingLongExposure, !isFinalizingLongExposure else { return }
        isFinalizingLongExposure = true
        isAccumulatingLongExposure = false

        DispatchQueue.main.async {
            self.isLongExposureCapturing = false
            self.longExposureProgress = 1.0
        }

        // Snapshot + bake BEFORE restoring exposure. resetToAutoExposure used to
        // nil the accumulator first, so normalize always returned nil.
        let captureFilmFilter = longExposureFilmFilter
        let captureLensFX = longExposureLensFX
        let captureTouch = longExposureMorphTouch
        let completion = longExposureCompletion
        longExposureCompletion = nil
        longExposureMorphTouch = nil
        setBakingStill(true)

        let resultImage = normalizeAccumulator()

        longExposureAccumulator = nil
        longExposureFrameCount = 0
        longExposureTargetDuration = 0

        restoreExposureAfterLongExposure()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let finalImage: UIImage?
            if let img = resultImage {
                // Same WYSIWYG bake policy as normal capture.
                finalImage = self.applyLensFX(
                    captureLensFX,
                    to: self.applyFilmFilter(captureFilmFilter, to: img),
                    touch: captureTouch
                )
            } else {
                finalImage = nil
            }

            self.setBakingStill(false)
            self.cancelBakeTimeout()
            self.isFinalizingLongExposure = false

            DispatchQueue.main.async {
                completion?(finalImage)
                self.longExposureProgress = 0.0
                self.longExposurePathLabel = ""
            }
        }
    }

    /// Drop the multi-second custom exposure that freezes the finder, then
    /// put back the user's Night/Street manuals (do not wipe them).
    private func restoreExposureAfterLongExposure() {
        let snap = exposureSnapshotBeforeLE
        exposureSnapshotBeforeLE = nil
        guard let device = videoDeviceInput?.device else { return }

        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                if device.isExposureModeSupported(.continuousAutoExposure) {
                    device.exposureMode = .continuousAutoExposure
                }
                device.unlockForConfiguration()
            } catch {
                print("Error thawing exposure after LE: \(error)")
            }

            DispatchQueue.main.async {
                if let shutter = snap?.shutter {
                    self.setShutterSpeed(index: shutter)
                }
                if let iso = snap?.iso {
                    self.setISO(iso)
                }
                if snap?.shutter == nil, snap?.iso == nil {
                    self.manualShutterIndex = nil
                    self.manualISOValue = nil
                    self.isManualExposure = false
                }
            }
        }
    }

    private func resetToAutoExposure() {
        guard let device = videoDeviceInput?.device else { return }

        // Clear remembered manual shutter/ISO so lens/format switches cannot
        // re-lock a multi-second exposure and freeze the live preview.
        manualShutterIndex = nil
        manualISOValue = nil

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
