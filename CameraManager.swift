import AVFoundation
import ImageIO
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
    /// Live sensor ISO while AUTO (0 when unknown / manual owns the dial).
    /// Mirrored to `LiveExposureBus` so ContentView does not rebuild every probe.
    var liveISO: Float = 0
    /// Live shutter readout while AUTO (e.g. "1/125").
    var liveShutterLabel: String = "AUTO"
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
    /// Throttle STACK progress publishes so ContentView isn't rebuilt every frame.
    private var lastLEProgressPublish: CFAbsoluteTime = 0
    private var lastLEProgressValue: Float = -1
    /// "HW" single-shot hardware duration vs "STACK" computational average.
    @Published var longExposurePathLabel: String = ""
    /// One-shot toast when film/FX bake falls back to a clean still.
    @Published var captureNote: String?
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
    /// createCGImage failures while filtered — fall back to clean AV preview.
    private var livePreviewFailStreak = 0
    /// Cap live FX preview — heavy FX go slower (build 42: slightly lower for headroom).
    private let previewFrameInterval: CFAbsoluteTime = 1.0 / 12.0

    // Live histogram — published on HistogramBus (not here) so bin updates
    // don't invalidate the whole finder. Sampled on a utility queue.
    private var lastHistogramTime: CFAbsoluteTime = 0
    private let histogramQueue = DispatchQueue(label: "camera.histogram", qos: .utility)

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
    /// User-facing completion kept alive across GPU bake so timeout can still unblock UI.
    private var bakeTimeoutCompletion: ((UIImage?) -> Void)?
    /// Invalidates late bake / HW photo completions after cancel or timeout.
    private var bakeGeneration = UUID()
    private let photoStateLock = NSLock()
    /// Invalidates late HW-LE exposure callbacks after timeout/cancel.
    private var hwLongExposureToken: UUID?
    /// Tracks the current LE operation; bumped on every new start and cancel to abort stale completions.
    private var leOpID = UUID()
    /// STACK watchdog: fires targetDuration+10 s after arm; finalizes or cancels if still running.
    private var stackWatchdogWork: DispatchWorkItem?
    /// HW LE timeout work item — stored so cancelLongExposure can suppress it.
    private var hwTimeoutWork: DispatchWorkItem?
    /// Held after RAW half arrives; saved only when processed half succeeds; discarded on failure.
    private var pendingRawData: Data?
    /// `AVCapturePhotoSettings.uniqueID` for the in-flight still — ignore late callbacks.
    private var activeCaptureUniqueID: Int64?
    /// Remembered WB / macro so lens+flip can reapply.
    private var lockedWhiteBalanceMode: Int = 0
    private var macroEnabledFlag = false
    /// Orientation snapshotted when STACK LE starts (main-thread UIKit).
    private var longExposureInterfaceOrientation: UIInterfaceOrientation = .portrait
    private var longExposureWasFront = false
    /// Owns video-data + STACK accumulation (single-owner for LE flags).
    private let videoDataQueue = DispatchQueue(label: "shutter.videoData")
    private var sessionObservers: [NSObjectProtocol] = []

    // Film stocks — same enum as UI (`FilmFilterMode`).
    typealias FilmFilter = FilmFilterMode

    private let ciContext = ShutterRender.ciContext

    override init() {
        super.init()
        syncPipelineSelection()
        installSessionObservers()
    }

    deinit {
        for obs in sessionObservers {
            NotificationCenter.default.removeObserver(obs)
        }
    }

    /// True while still bake / photo handler / HW or STACK LE owns the pipeline.
    private func capturePipelineBusy(includeUILongExposure: Bool = false) -> Bool {
        let (_, _, _, _, _, baking) = currentPipelineSelection()
        photoStateLock.lock()
        let busy = photoCompletionHandler != nil
            || baking
            || bakeTimeoutCompletion != nil
            || isAccumulatingLongExposure
            || isFinalizingLongExposure
            || hwLongExposureToken != nil
            || longExposureCompletion != nil
            || activeCaptureUniqueID != nil
        photoStateLock.unlock()
        if includeUILongExposure, isLongExposureCapturing { return true }
        return busy
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
    /// Samples device.iso / exposureDuration for AUTO readouts.
    private var exposureProbe: DispatchSourceTimer?

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
        videoOutput.setSampleBufferDelegate(self, queue: videoDataQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
            videoDataOutput = videoOutput
            applyVideoMirroring()
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
            let (_, _, _, _, _, baking) = self.currentPipelineSelection()
            self.photoStateLock.lock()
            let hasBakeTarget = self.bakeTimeoutCompletion != nil
            let hasPhoto = self.photoCompletionHandler != nil
            let hasCapture = self.activeCaptureUniqueID != nil
            // Clear stuck still OR stack-LE bake even after photo handler was taken.
            guard hasBakeTarget || hasPhoto || baking || hasCapture else {
                self.photoStateLock.unlock()
                return
            }
            print("Capture timeout — clearing stuck bake gate")
            self.bakeGeneration = UUID()
            let done = self.bakeTimeoutCompletion
            self.bakeTimeoutCompletion = nil
            self.longExposureCompletion = nil
            self.photoCompletionHandler = nil
            self.activeCaptureUniqueID = nil
            self.pendingRawData = nil
            self.isFinalizingLongExposure = false
            self.photoStateLock.unlock()
            self.setBakingStill(false)
            DispatchQueue.main.async {
                self.isLongExposureCapturing = false
                self.longExposureProgress = 0
                self.longExposurePathLabel = ""
                done?(nil)
            }
        }
        bakeTimeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: work)
    }

    private func peekPhotoHandler() -> Bool {
        photoStateLock.lock()
        defer { photoStateLock.unlock() }
        return photoCompletionHandler != nil
    }

    private func takePhotoHandler() -> ((UIImage?) -> Void)? {
        photoStateLock.lock()
        defer { photoStateLock.unlock() }
        let handler = photoCompletionHandler
        photoCompletionHandler = nil
        return handler
    }

    private func setPhotoHandler(_ handler: ((UIImage?) -> Void)?) {
        photoStateLock.lock()
        defer { photoStateLock.unlock() }
        photoCompletionHandler = handler
    }

    /// Deliver a bake result once. Generation mismatch means cancel/timeout won.
    private func finishUserBake(_ image: UIImage?, generation: UUID) {
        photoStateLock.lock()
        guard bakeGeneration == generation else {
            photoStateLock.unlock()
            return
        }
        let done = bakeTimeoutCompletion
        bakeTimeoutCompletion = nil
        // Invalidate so a second finish/timeout cannot deliver twice.
        bakeGeneration = UUID()
        photoStateLock.unlock()

        cancelBakeTimeout()
        setBakingStill(false)
        isFinalizingLongExposure = false

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isLongExposureCapturing = false
            self.longExposureProgress = 0
            self.longExposurePathLabel = ""
            done?(image)
        }
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
            // currentExposureDuration is a keep-current sentinel — never clamp it.
            duration = AVCaptureDevice.currentExposureDuration
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

    // MARK: - Preview Format Selection
    /// Prefer a smooth finder (≥30 fps near 1080p) over maximizing exposure duration.
    /// Night/LE still work within the format's max exposure; we no longer pick
    /// slow high-res formats that starve the live preview.
    private func selectBestFormatForLongExposure(device: AVCaptureDevice) {
        struct Candidate {
            let format: AVCaptureDevice.Format
            let width: Int32
            let maxFps: Float
            let maxExp: CMTime
        }

        var candidates: [Candidate] = []
        for format in device.formats {
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let maxFps = Float(
                format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
            )
            // Keep preview-sized streams; skip 4K/photo-only formats that crush fps.
            guard dimensions.width >= 1280, dimensions.width <= 1920 else { continue }
            candidates.append(
                Candidate(
                    format: format,
                    width: dimensions.width,
                    maxFps: maxFps,
                    maxExp: format.maxExposureDuration
                )
            )
        }

        // Fallback: any ≥1280 wide format if the 1080p band is empty.
        if candidates.isEmpty {
            for format in device.formats {
                let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                guard dimensions.width >= 1280 else { continue }
                let maxFps = Float(
                    format.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0
                )
                candidates.append(
                    Candidate(
                        format: format,
                        width: dimensions.width,
                        maxFps: maxFps,
                        maxExp: format.maxExposureDuration
                    )
                )
            }
        }

        let ranked = candidates.sorted { a, b in
            let a30 = a.maxFps >= 29
            let b30 = b.maxFps >= 29
            if a30 != b30 { return a30 && !b30 }
            let aDist = abs(Int(a.width) - 1920)
            let bDist = abs(Int(b.width) - 1920)
            if aDist != bDist { return aDist < bDist }
            if a.maxFps != b.maxFps { return a.maxFps > b.maxFps }
            return CMTimeCompare(a.maxExp, b.maxExp) > 0
        }

        guard let best = ranked.first else { return }
        let format = best.format

        do {
            try device.lockForConfiguration()
            device.activeFormat = format

            // Cap peak stream rate at 30 fps for thermal/GPU headroom. Leave
            // maxFrameDuration alone so custom long exposures can still lengthen frames.
            let thirty = CMTime(value: 1, timescale: 30)
            if format.videoSupportedFrameRateRanges.contains(where: {
                CMTimeCompare($0.minFrameDuration, thirty) <= 0
                    && CMTimeCompare($0.maxFrameDuration, thirty) >= 0
            }) {
                device.activeVideoMinFrameDuration = thirty
            }

            device.unlockForConfiguration()

            // Verify custom exposure still works with this format; revert if not
            if !device.isExposureModeSupported(.custom) {
                print("Selected format does not support custom exposure, reverting")
                try device.lockForConfiguration()
                if let fallback = device.formats.first(where: {
                    CMVideoFormatDescriptionGetDimensions($0.formatDescription).width >= 1920
                }) ?? device.formats.first {
                    device.activeFormat = fallback
                }
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
    ///   - morphTouch: Pre-frozen touch state (e.g. from timer arm). Falls back to a live snapshot when nil.
    func captureLongExposure(
        durationSeconds: Double,
        filmFilter: FilmFilter? = nil,
        lensFX: LensFXMode? = nil,
        morphTouch: MorphTouchState? = nil,
        completion: @escaping (UIImage?) -> Void
    ) {
        // Same serialization as capturePhoto — overlapping LE overwrites completion
        // and leaves ContentView isCapturing stuck true.
        if capturePipelineBusy(includeUILongExposure: true) {
            DispatchQueue.main.async { completion(nil) }
            return
        }
        guard let device = videoDeviceInput?.device else {
            DispatchQueue.main.async { completion(nil) }
            return
        }

        longExposureFilmFilter = filmFilter ?? selectedFilmFilter
        longExposureLensFX = lensFX ?? selectedLensFX
        let fx = longExposureLensFX
        longExposureMorphTouch = morphTouch ?? (fx.isTouchReactive
            ? LensFXEngine.shared.snapshotForCapture()
            : nil)
        // Remember manuals so thawing the LE custom exposure doesn't wipe Night/Street.
        exposureSnapshotBeforeLE = (manualShutterIndex, manualISOValue)
        // Snapshot orientation on the calling thread (main) for STACK upright stills.
        longExposureInterfaceOrientation = Self.currentInterfaceOrientation()
        longExposureWasFront = (currentCamera == .front)

        // Set synchronously before returning — ContentView reads this flag immediately.
        isLongExposureCapturing = true
        longExposureProgress = 0.0

        // Get device's actual max exposure duration
        let maxHardwareDuration = CMTimeGetSeconds(device.activeFormat.maxExposureDuration)

        // If hardware can handle it directly, use single capture
        if durationSeconds <= maxHardwareDuration {
            longExposurePathLabel = "HW"
            captureSingleLongExposure(duration: durationSeconds, completion: completion)
        } else {
            // Use computational long exposure (frame averaging)
            longExposurePathLabel = "STACK"
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

        // Token so a late exposure callback can't double-complete after timeout/cancel.
        // Assign leOpID and all lock-protected LE state atomically.
        let hwToken = UUID()
        let op = UUID()
        photoStateLock.lock()
        leOpID = op
        hwLongExposureToken = hwToken
        longExposureCompletion = completion
        photoStateLock.unlock()

        // isLongExposureCapturing / progress already set synchronously in captureLongExposure.

        // If the custom-exposure callback never fires, don't leave the shutter stuck.
        let hwTimeout = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.photoStateLock.lock()
            guard self.hwLongExposureToken == hwToken else {
                self.photoStateLock.unlock()
                return
            }
            self.hwLongExposureToken = nil
            self.longExposureCompletion = nil
            self.photoStateLock.unlock()
            print("HW long-exposure timeout — aborting")
            self.hwTimeoutWork = nil
            self.restoreExposureAfterLongExposure()
            self.isLongExposureCapturing = false
            self.longExposureProgress = 0.0
            self.longExposurePathLabel = ""
            completion(nil)
        }
        hwTimeoutWork = hwTimeout
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 8, execute: hwTimeout)

        sessionQueue.async {
            do {
                try device.lockForConfiguration()

                // Use user's selected ISO (clamped to device limits) for dark room support
                let targetISO = max(device.activeFormat.minISO, min(self.isoValue, device.activeFormat.maxISO))
                device.setExposureModeCustom(duration: targetDuration, iso: targetISO) { _ in
                    // Now capture the photo
                    DispatchQueue.main.async {
                        self.photoStateLock.lock()
                        guard self.hwLongExposureToken == hwToken else {
                            self.photoStateLock.unlock()
                            return
                        }
                        self.hwLongExposureToken = nil
                        self.longExposureCompletion = nil
                        self.photoStateLock.unlock()
                        hwTimeout.cancel()
                        self.hwTimeoutWork = nil
                        self.longExposureProgress = 1.0
                        self.capturePhoto(
                            filmFilter: captureFilm,
                            lensFX: captureFX,
                            morphTouch: self.longExposureMorphTouch
                        ) { image in
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
                    hwTimeout.cancel()
                    self.hwTimeoutWork = nil
                    self.photoStateLock.lock()
                    self.hwLongExposureToken = nil
                    self.longExposureCompletion = nil
                    self.photoStateLock.unlock()
                    self.isLongExposureCapturing = false
                    self.longExposureProgress = 0.0
                    self.longExposurePathLabel = ""
                    // Don't leave the finder locked on a multi-second custom exposure.
                    self.restoreExposureAfterLongExposure()
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
        // isLongExposureCapturing / progress already set synchronously in captureLongExposure.

        // Assign leOpID + STACK gates atomically with completion.
        let op = UUID()
        photoStateLock.lock()
        leOpID = op
        longExposureCompletion = completion
        isFinalizingLongExposure = false
        isAccumulatingLongExposure = true
        photoStateLock.unlock()

        longExposureAccumulator = nil
        longExposureFrameCount = 0
        longExposureStartTime = CFAbsoluteTimeGetCurrent()
        longExposureTargetDuration = max(targetDuration, 0.1)
        lastLEProgressPublish = 0
        lastLEProgressValue = -1

        // STACK watchdog: hop off main — finalize path may syncCI.
        stackWatchdogWork?.cancel()
        let watchdog = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.videoDataQueue.async {
                self.photoStateLock.lock()
                guard self.leOpID == op else {
                    self.photoStateLock.unlock()
                    return
                }
                let accumulating = self.isAccumulatingLongExposure
                let finalizing = self.isFinalizingLongExposure
                self.photoStateLock.unlock()
                print("STACK watchdog fired — finalizing or cancelling")
                if accumulating {
                    self.finalizeLongExposure()
                } else if !finalizing {
                    self.cancelLongExposure()
                }
            }
        }
        stackWatchdogWork = watchdog
        DispatchQueue.main.asyncAfter(deadline: .now() + longExposureTargetDuration + 10, execute: watchdog)

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
                self.photoStateLock.lock()
                self.isAccumulatingLongExposure = false
                self.longExposureCompletion = nil
                self.photoStateLock.unlock()
                self.stackWatchdogWork?.cancel()
                self.stackWatchdogWork = nil
                self.restoreExposureAfterLongExposure()
                DispatchQueue.main.async {
                    self.isLongExposureCapturing = false
                    self.longExposureProgress = 0.0
                    self.longExposurePathLabel = ""
                    completion(nil)
                }
            }
        }
    }

    /// Abort in-flight HW or STACK long exposure and restore manuals.
    func cancelLongExposure() {
        let (_, _, _, _, _, baking) = currentPipelineSelection()
        photoStateLock.lock()
        let hadHW = hwLongExposureToken != nil
        let hadStack = isAccumulatingLongExposure || isFinalizingLongExposure
        let hadBake = baking || bakeTimeoutCompletion != nil || photoCompletionHandler != nil
            || activeCaptureUniqueID != nil
        let shouldCancel = hadHW || hadStack || hadBake
        guard shouldCancel || isLongExposureCapturing else {
            photoStateLock.unlock()
            return
        }

        // Atomically bump leOpID and bakeGeneration; drain lock-protected state.
        leOpID = UUID()
        bakeGeneration = UUID()
        let bakeDone = bakeTimeoutCompletion
        bakeTimeoutCompletion = nil
        let completion = longExposureCompletion
        longExposureCompletion = nil
        hwLongExposureToken = nil
        photoCompletionHandler = nil
        activeCaptureUniqueID = nil
        pendingRawData = nil
        isAccumulatingLongExposure = false
        isFinalizingLongExposure = false
        photoStateLock.unlock()

        // Suppress pending timeout / watchdog work items.
        cancelBakeTimeout()
        stackWatchdogWork?.cancel()
        stackWatchdogWork = nil
        hwTimeoutWork?.cancel()
        hwTimeoutWork = nil

        longExposureAccumulator = nil
        longExposureFrameCount = 0
        longExposureTargetDuration = 0

        setBakingStill(false)

        restoreExposureAfterLongExposure()

        DispatchQueue.main.async {
            self.isLongExposureCapturing = false
            self.longExposureProgress = 0.0
            self.longExposurePathLabel = ""
            if let bakeDone {
                bakeDone(nil)
            } else {
                completion?(nil)
            }
        }
    }

    /// Running-average accumulator already stays in display range — just render it.
    private func normalizeAccumulator() -> UIImage? {
        guard var accumulator = longExposureAccumulator, longExposureFrameCount > 0 else { return nil }

        // Video buffers are sensor-native; match Metal preview upright mapping.
        switch longExposureInterfaceOrientation {
        case .portrait, .unknown:
            accumulator = accumulator.oriented(.right)
        case .portraitUpsideDown:
            accumulator = accumulator.oriented(.left)
        case .landscapeLeft:
            accumulator = accumulator.oriented(.down)
        case .landscapeRight:
            break
        @unknown default:
            accumulator = accumulator.oriented(.right)
        }
        if longExposureWasFront {
            accumulator = accumulator.oriented(.upMirrored)
        }

        guard let cgImage = ShutterRender.syncCI({
            ciContext.createCGImage(accumulator, from: accumulator.extent)
        }) else {
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
            self.startExposureProbe()
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.stopExposureProbe()
            if self.session.isRunning {
                self.session.stopRunning()
                DispatchQueue.main.async {
                    self.isSessionRunning = false
                }
            }
        }
    }

    private func startExposureProbe() {
        stopExposureProbe()
        let timer = DispatchSource.makeTimerSource(queue: sessionQueue)
        timer.schedule(deadline: .now() + 0.35, repeating: 0.4)
        timer.setEventHandler { [weak self] in
            self?.sampleLiveExposure()
        }
        timer.resume()
        exposureProbe = timer
    }

    private func stopExposureProbe() {
        exposureProbe?.cancel()
        exposureProbe = nil
    }

    private func sampleLiveExposure() {
        guard let device = videoDeviceInput?.device else { return }
        let iso = device.iso
        let label = Self.formatShutterDuration(device.exposureDuration)
        DispatchQueue.main.async {
            // Manual dials own the UI numbers — don't fight them with sensor samples.
            guard !self.isManualExposure else { return }
            if abs(self.liveISO - iso) > 2 {
                self.liveISO = iso
            }
            if self.liveShutterLabel != label {
                self.liveShutterLabel = label
            }
            LiveExposureBus.shared.publish(iso: self.liveISO, shutterLabel: self.liveShutterLabel)
        }
    }

    /// Compact shutter string for AUTO readout / metadata.
    static func formatShutterDuration(_ time: CMTime) -> String {
        let seconds = CMTimeGetSeconds(time)
        guard seconds.isFinite, seconds > 0 else { return "AUTO" }
        if seconds >= 1 {
            if abs(seconds - seconds.rounded()) < 0.05 {
                return "\(Int(seconds.rounded()))\""
            }
            return String(format: "%.1f\"", seconds)
        }
        let denom = max(1, Int((1.0 / seconds).rounded()))
        return "1/\(denom)"
    }

    func switchCamera() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            // Never tear down inputs mid-still / mid-LE — black finder + stuck bake.
            if self.capturePipelineBusy(includeUILongExposure: true) { return }

            let newPosition: AVCaptureDevice.Position = self.currentCamera == .back ? .front : .back

            // Use physical camera devices (not virtual) to maintain .custom exposure support
            guard let newDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition) else { return }

            do {
                let newInput = try AVCaptureDeviceInput(device: newDevice)
                let oldInput = self.videoDeviceInput

                self.session.beginConfiguration()
                defer { self.session.commitConfiguration() }

                if let oldInput {
                    self.session.removeInput(oldInput)
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
                        // Front usually has no flash.
                        if newPosition == .front {
                            self.flashMode = .off
                        }
                    }
                    // Flip drops custom exposure / lock / WB — restore.
                    self.reapplyManualExposure(on: newDevice)
                    self.reapplyLockWhiteBalanceMacro(on: newDevice)
                    self.applyVideoMirroring(front: newPosition == .front)
                } else if let oldInput, self.session.canAddInput(oldInput) {
                    // Never leave the session without a video input.
                    self.session.addInput(oldInput)
                    print("switchCamera: new input rejected — restored previous camera")
                }
            } catch {
                print("Error switching camera: \(error)")
            }
        }
    }

    /// Re-apply AE/AF lock, WB, and macro after a device swap.
    private func reapplyLockWhiteBalanceMacro(on device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            if isAEAFLocked {
                if device.isFocusModeSupported(.locked) { device.focusMode = .locked }
                if device.isExposureModeSupported(.locked), !isManualExposure {
                    device.exposureMode = .locked
                }
            }
            if device.isAutoFocusRangeRestrictionSupported {
                device.autoFocusRangeRestriction = macroEnabledFlag ? .near : .none
            }
            device.unlockForConfiguration()
        } catch {
            print("Error reapplying lock/macro: \(error)")
        }
        // WB needs its own lock cycle (gains API).
        let mode = lockedWhiteBalanceMode
        setWhiteBalance(mode: mode)
    }

    private func applyVideoMirroring(front: Bool? = nil) {
        let useFront = front ?? (currentCamera == .front)
        if let conn = videoDataOutput?.connection(with: .video),
           conn.isVideoMirroringSupported {
            conn.automaticallyAdjustsVideoMirroring = false
            conn.isVideoMirrored = useFront
        }
    }

    func setExposure(_ value: Float) {
        guard let device = videoDeviceInput?.device else { return }
        // Target bias is ignored in .custom — don't pretend EV works over manuals.
        // Bias is a no-op in .custom — don't update UI as if it applied.
        guard !isManualExposure else { return }

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
                // currentExposureDuration is a keep-current sentinel — never clamp it.
                duration = AVCaptureDevice.currentExposureDuration
            }
            let clampedISO = max(device.activeFormat.minISO, min(value, device.activeFormat.maxISO))

            do {
                try device.lockForConfiguration()
                device.setExposureModeCustom(duration: duration, iso: clampedISO) { _ in }
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

    /// - Parameter iso: UI ISO to lock with shutter (avoids CameraManager default 100 desync).
    func setShutterSpeed(index: Int, iso: Float? = nil) {
        guard let device = videoDeviceInput?.device else { return }
        guard index >= 0 && index < CameraManager.shutterSpeedValues.count else { return }
        guard device.isExposureModeSupported(.custom) else { return }

        if let iso { manualISOValue = iso }
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
                self.sampleLiveExposure()
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
        macroEnabledFlag = enabled
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

    @discardableResult
    func setZoom(_ factor: CGFloat) -> CGFloat {
        guard let device = videoDeviceInput?.device else { return factor }

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
        return clampedZoom
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

            // Never tear down inputs mid-still / mid-LE — same gate as switchCamera.
            if self.capturePipelineBusy(includeUILongExposure: true) { return }

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
                let oldInput = self.videoDeviceInput

                self.session.beginConfiguration()
                if let oldInput {
                    self.session.removeInput(oldInput)
                }

                var switched = false
                if self.session.canAddInput(newInput) {
                    self.session.addInput(newInput)
                    self.videoDeviceInput = newInput
                    switched = true

                    // Select best format for this lens (changes activeFormat and
                    // clears custom exposure — must reapply afterwards)
                    self.selectBestFormatForLongExposure(device: newDevice)
                    self.updateDeviceCapabilities(device: newDevice)
                    self.updateMaxPhotoDimensions(for: newDevice)
                } else if let oldInput, self.session.canAddInput(oldInput) {
                    self.session.addInput(oldInput)
                    print("switchToLens: new input rejected — restored previous lens")
                }
                self.session.commitConfiguration()

                // Device lock OUTSIDE beginConfiguration — a throw mid-config
                // previously left the graph half-mutated.
                if switched {
                    do {
                        try newDevice.lockForConfiguration()
                        newDevice.videoZoomFactor = max(newDevice.minAvailableVideoZoomFactor,
                                                        min(zoomWithinLens, newDevice.activeFormat.videoMaxZoomFactor))
                        newDevice.unlockForConfiguration()
                    } catch {
                        print("Error setting lens zoom: \(error)")
                    }
                    self.reapplyManualExposure(on: newDevice)
                    self.reapplyLockWhiteBalanceMacro(on: newDevice)
                    self.applyVideoMirroring()
                    let appliedZoom = newDevice.videoZoomFactor
                    DispatchQueue.main.async {
                        self.zoomFactor = appliedZoom
                    }
                }
            } catch {
                print("Error switching lens: \(error)")
            }
        }
    }

    func cycleFlash() {
        let supported = Set(photoOutput.supportedFlashModes)
        let order: [AVCaptureDevice.FlashMode] = [.off, .on, .auto]
        let start = order.firstIndex(of: flashMode) ?? 0
        for offset in 1...order.count {
            let next = order[(start + offset) % order.count]
            if supported.contains(next) {
                flashMode = next
                return
            }
        }
        flashMode = .off
    }

    /// Flash mode safe for the current photo output (front often supports only off).
    private func resolvedFlashMode() -> AVCaptureDevice.FlashMode {
        let supported = photoOutput.supportedFlashModes
        if supported.contains(flashMode) { return flashMode }
        if supported.contains(.off) { return .off }
        return supported.first ?? .off
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
        lockedWhiteBalanceMode = mode
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
        bakeFilmFilter(filmFilter, onto: image).image
    }

    private func bakeFilmFilter(_ filmFilter: FilmFilter, onto image: UIImage) -> (image: UIImage, ok: Bool) {
        guard filmFilter != .none else { return (image, true) }
        guard var ciImage = CIImage(image: image) else { return (image, false) }

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
            return (rendered, true)
        }
        print("FilmFilter: bake failed for \(filmFilter) — saving unfiltered still")
        return (image, false)
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
                let cgImage: CGImage? = {
                    if context === ciContext {
                        return ShutterRender.syncCI({
                            context.createCGImage(candidate, from: candidate.extent)
                                ?? context.createCGImage(
                                    candidate,
                                    from: candidate.extent,
                                    format: .RGBA8,
                                    colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
                                )
                        })
                    }
                    return context.createCGImage(candidate, from: candidate.extent)
                        ?? context.createCGImage(
                            candidate,
                            from: candidate.extent,
                            format: .RGBA8,
                            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
                        )
                }()
                if let cgImage {
                    return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
                }
            }
        }
        return nil
    }

    // Applies the new filter selection on the very next frame and drops any
    // stale filtered output, so toggling never appears stuck
    private func refreshLivePreviewState() {
        pipelineLock.lock()
        lastPreviewFrameTime = 0
        let shouldClear = previewLooksBypassed
            || (selectedFilmFilter == .none && selectedLensFX == .none
                && !focusPeakingEnabled && !zebraEnabled)
        if shouldClear {
            livePreviewActive = false
            livePreviewFailStreak = 0
            pipelineLock.unlock()
            livePreview.push(nil)
        } else {
            pipelineLock.unlock()
        }
    }

    /// Session interruption / media-services reset recovery.
    private func installSessionObservers() {
        let center = NotificationCenter.default
        let interrupted = center.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification,
            object: session,
            queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.videoDataQueue.async {
                self.pipelineLock.lock()
                self.livePreviewActive = false
                self.livePreviewFailStreak = 0
                self.pipelineLock.unlock()
                self.livePreview.push(nil)
            }
        }
        let ended = center.addObserver(
            forName: AVCaptureSession.interruptionEndedNotification,
            object: session,
            queue: nil
        ) { [weak self] _ in
            self?.startSession()
        }
        let runtime = center.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification,
            object: session,
            queue: nil
        ) { [weak self] note in
            guard let self else { return }
            let err = note.userInfo?[AVCaptureSessionErrorKey] as? AVError
            print("AVCaptureSession runtime error: \(String(describing: err))")
            self.sessionQueue.async {
                self.livePreview.push(nil)
                // Soft recover — do not surface a blocking cameraUnavailable toast.
                if err?.code == .mediaServicesWereReset || !self.session.isRunning {
                    if self.session.isRunning { self.session.stopRunning() }
                    self.session.startRunning()
                }
                DispatchQueue.main.async {
                    self.isSessionRunning = self.session.isRunning
                }
            }
        }
        sessionObservers = [interrupted, ended, runtime]
    }

    private func downscaled(_ image: CIImage, longEdge target: CGFloat) -> CIImage {
        let maxDim = max(image.extent.width, image.extent.height)
        guard maxDim > target else { return image }
        let scale = target / maxDim
        return image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }

    // Cap live preview frames; heavy FX use a smaller buffer.
    private func downscaledForPreview(_ image: CIImage, heavyFX: Bool) -> CIImage {
        downscaled(image, longEdge: heavyFX ? 640 : 720)
    }

    private func isHeavyPreviewFX(_ fx: LensFXMode) -> Bool {
        switch fx {
        case .liquid, .chrome, .dream, .kaleido, .toon: return true
        default: return false
        }
    }

    private func previewInterval(for fx: LensFXMode, film: FilmFilter) -> CFAbsoluteTime {
        if isHeavyPreviewFX(fx) { return 1.0 / 8.0 }
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
        // Dedicated histogram context — never races Metal preview/bake.
        ShutterRender.histogramContext.render(
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
            HistogramBus.shared.publish(normalized)
        }
    }

    // MARK: - Lens FX Processing

    // Apply the selected lens FX to a captured still
    func applyLensFX(to image: UIImage) -> UIImage {
        bakeLensFX(selectedLensFX, onto: image, touch: nil).image
    }

    private func applyLensFX(
        _ lensFX: LensFXMode,
        to image: UIImage,
        touch: MorphTouchState? = nil
    ) -> UIImage {
        bakeLensFX(lensFX, onto: image, touch: touch).image
    }

    private func bakeLensFX(
        _ lensFX: LensFXMode,
        onto image: UIImage,
        touch: MorphTouchState? = nil
    ) -> (image: UIImage, ok: Bool) {
        guard lensFX != .none else { return (image, true) }
        if let rendered = LensFXEngine.shared.render(lensFX, on: image, touch: touch) {
            return (rendered, true)
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
            return (rendered, true)
        }
        print("LensFX: BAKE FAILED for \(lensFX.name) — saving unfiltered still")
        return (image, false)
    }

    /// Bake film then FX; surface a toast note when either look fails.
    private func bakeLooksForCapture(
        film: FilmFilter,
        fx: LensFXMode,
        touch: MorphTouchState?,
        onto image: UIImage
    ) -> UIImage {
        var working = image
        var notes: [String] = []
        if film != .none {
            let baked = bakeFilmFilter(film, onto: working)
            working = baked.image
            if !baked.ok { notes.append("Film bake failed") }
        }
        if fx != .none {
            let baked = bakeLensFX(fx, onto: working, touch: touch)
            working = baked.image
            if !baked.ok { notes.append("FX bake failed") }
        }
        if !notes.isEmpty {
            let message = notes.joined(separator: " · ") + " — saved clean look"
            DispatchQueue.main.async { self.captureNote = message }
        }
        return working
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
        // Serialize: block mid-bake, STACK accumulation, and any in-flight LE.
        // Do NOT use isLongExposureCapturing — HW LE sets that before calling us.
        if capturePipelineBusy() {
            DispatchQueue.main.async { completion(nil) }
            return
        }

        // Freeze the selections at shutter time. The user can change controls
        // while AVFoundation is delivering the still.
        let captureFilmFilter = filmFilter ?? selectedFilmFilter
        let captureLensFX = lensFX ?? selectedLensFX
        let captureTouch: MorphTouchState? = {
            guard captureLensFX.isTouchReactive else { return nil }
            if let morphTouch { return morphTouch }
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

        let gen = UUID()
        // Atomically record bakeGeneration and bakeTimeoutCompletion so cancel/timeout
        // cannot race the bake registration.
        photoStateLock.lock()
        bakeGeneration = gen
        bakeTimeoutCompletion = { img in
            DispatchQueue.main.async { completion(img) }
        }
        photoStateLock.unlock()
        setPhotoHandler { [weak self] image in
            guard let self else { return }
            self.photoStateLock.lock()
            let genCurrent = self.bakeGeneration == gen
            self.photoStateLock.unlock()
            guard genCurrent else { return }
            guard let image else {
                self.finishUserBake(nil, generation: gen)
                return
            }
            // Keep bake timeout armed across the GPU bake — cancelling it when the
            // still arrives left pipelineBakingStill stuck forever if createCGImage hung.
            DispatchQueue.global(qos: .userInitiated).async {
                self.photoStateLock.lock()
                let stillCurrent = self.bakeGeneration == gen
                self.photoStateLock.unlock()
                guard stillCurrent else { return }
                let filteredImage: UIImage
                if needsFXBake {
                    filteredImage = self.bakeLooksForCapture(
                        film: captureFilmFilter,
                        fx: captureLensFX,
                        touch: captureTouch,
                        onto: image
                    )
                } else {
                    filteredImage = image
                }
                print("LensFX capture done: out=\(filteredImage.size) orient=\(filteredImage.imageOrientation.rawValue)")
                self.finishUserBake(filteredImage, generation: gen)
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

        settings.flashMode = resolvedFlashMode()
        applyMinimalProcessing(to: &settings)

        // Snapshot UIKit orientation on main — never from sessionQueue.
        let fire: (CGFloat) -> Void = { [weak self] angle in
            guard let self else { return }
            self.sessionQueue.async {
                guard self.session.isRunning else {
                    DispatchQueue.main.async {
                        self.photoStateLock.lock()
                        self.bakeGeneration = UUID()
                        let done = self.bakeTimeoutCompletion
                        self.bakeTimeoutCompletion = nil
                        self.photoCompletionHandler = nil
                        self.activeCaptureUniqueID = nil
                        self.pendingRawData = nil
                        self.photoStateLock.unlock()
                        self.cancelBakeTimeout()
                        self.setBakingStill(false)
                        done?(nil)
                    }
                    return
                }
                if let device = self.videoDeviceInput?.device {
                    self.updateMaxPhotoDimensions(for: device)
                }
                settings.maxPhotoDimensions = self.photoOutput.maxPhotoDimensions
                self.applyCaptureOrientation(rotationAngle: angle)
                // Bind this request's uniqueID so a late prior callback cannot
                // steal the next capture's handler.
                self.photoStateLock.lock()
                self.activeCaptureUniqueID = settings.uniqueID
                self.photoStateLock.unlock()
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
        let uid = photo.resolvedSettings.uniqueID
        photoStateLock.lock()
        let isCurrent = activeCaptureUniqueID == uid
        if !isCurrent {
            photoStateLock.unlock()
            print("Ignoring stale photo callback uid=\(uid)")
            return
        }

        if let error = error {
            print("Photo capture error: \(error)")
            if photo.isRawPhoto {
                // RAW half failed: discard any staged raw so we don't save a stale DNG
                // if the processed half later succeeds.
                pendingRawData = nil
                photoStateLock.unlock()
                return
            }
            // Processed half failed: also discard any pending RAW + handler.
            pendingRawData = nil
            activeCaptureUniqueID = nil
            let handler = photoCompletionHandler
            photoCompletionHandler = nil
            photoStateLock.unlock()
            handler?(nil)
            return
        }

        // RAW half of a dual capture — stage DNG; save only when processed succeeds.
        if photo.isRawPhoto {
            pendingRawData = photo.fileDataRepresentation()
            photoStateLock.unlock()
            return
        }

        // Processed half arrived — try to decode.
        let handler = photoCompletionHandler
        photoCompletionHandler = nil
        let rawToSave = pendingRawData
        pendingRawData = nil
        activeCaptureUniqueID = nil
        photoStateLock.unlock()

        let image = decodedProcessedPhoto(photo)
        guard let image else {
            handler?(nil)
            return
        }

        // Success — save any staged RAW DNG now that we know the capture is good.
        if let rawToSave {
            saveRawDataToPhotoLibrary(rawToSave)
        }
        handler?(image)
    }

    /// Prefer UIImage(data:); fall back to CGImageSource when HEIC decode flakes.
    private func decodedProcessedPhoto(_ photo: AVCapturePhoto) -> UIImage? {
        guard let data = photo.fileDataRepresentation() else { return nil }
        if let ui = UIImage(data: data) { return ui }
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let src = CGImageSourceCreateWithData(data as CFData, options as CFDictionary),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, options as CFDictionary) else {
            return nil
        }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let raw = props?[kCGImagePropertyOrientation] as? UInt32 ?? 1
        let orient: UIImage.Orientation
        switch raw {
        case 2: orient = .upMirrored
        case 3: orient = .down
        case 4: orient = .downMirrored
        case 5: orient = .leftMirrored
        case 6: orient = .right
        case 7: orient = .rightMirrored
        case 8: orient = .left
        default: orient = .up
        }
        return UIImage(cgImage: cg, scale: 1, orientation: orient)
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
        error: Error?
    ) {
        let uid = resolvedSettings.uniqueID
        photoStateLock.lock()
        // Ignore finishes for a superseded capture; ignore if already drained.
        guard activeCaptureUniqueID == uid else {
            photoStateLock.unlock()
            return
        }
        let handler = photoCompletionHandler
        photoCompletionHandler = nil
        pendingRawData = nil
        activeCaptureUniqueID = nil
        photoStateLock.unlock()

        // Last-chance clear if processed never arrived (stuck bake / RAW-only fail).
        guard let handler else { return }
        if let error {
            print("didFinishCaptureFor error: \(error)")
        } else {
            print("didFinishCaptureFor with handler still armed — clearing")
        }
        handler(nil)
    }
}

// MARK: - Video Data Output Delegate (for computational long exposure + live preview)
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let (filmFilter, lensFX, peaking, zebra, bypass, bakingStill) = currentPipelineSelection()
        photoStateLock.lock()
        let accumulating = isAccumulatingLongExposure
        photoStateLock.unlock()
        let wantsLiveProcessing = !bypass
            && (filmFilter != .none || lensFX != .none || peaking || zebra)
            && !accumulating
            && !bakingStill

        let now = CFAbsoluteTimeGetCurrent()
        let wantsHistogram = !accumulating && (now - lastHistogramTime >= 0.5)

        // Idle frames: no CIImage wrap, no GPU work — AVCaptureVideoPreviewLayer paints.
        if !wantsLiveProcessing && !accumulating && !wantsHistogram {
            pipelineLock.lock()
            let active = livePreviewActive
            if bypass || active {
                if active {
                    livePreviewActive = false
                    livePreviewFailStreak = 0
                    pipelineLock.unlock()
                    livePreview.push(nil)
                } else {
                    pipelineLock.unlock()
                }
            } else {
                pipelineLock.unlock()
            }
            return
        }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        if wantsHistogram {
            lastHistogramTime = now
            // Copy a tiny bitmap NOW — the CVPixelBuffer is recycled after this callback.
            // Use the serialized Metal context here; keep histogramContext exclusive
            // to histogramQueue inside updateHistogram.
            let tiny = downscaled(ciImage, longEdge: 160)
            var owned: CIImage = tiny
            if let cg = ShutterRender.syncCI({
                ciContext.createCGImage(tiny, from: tiny.extent)
            }) {
                owned = CIImage(cgImage: cg)
            }
            histogramQueue.async { [weak self] in
                self?.updateHistogram(from: owned)
            }
        }

        if bypass {
            pipelineLock.lock()
            if livePreviewActive {
                livePreviewActive = false
                livePreviewFailStreak = 0
                pipelineLock.unlock()
                livePreview.push(nil)
            } else {
                pipelineLock.unlock()
            }
        } else if wantsLiveProcessing {
            pipelineLock.lock()
            let due = now - lastPreviewFrameTime >= previewInterval(for: lensFX, film: filmFilter)
            if due { lastPreviewFrameTime = now }
            pipelineLock.unlock()
            if due {
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
                            time: now,
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
                    // Materialize now — CVPixelBuffer is recycled when this callback returns.
                    guard let cg = ShutterRender.syncCI({
                        ciContext.createCGImage(frame, from: out)
                    }) else {
                        return nil
                    }
                    return CIImage(cgImage: cg)
                }

                pipelineLock.lock()
                if let processed {
                    livePreviewFailStreak = 0
                    livePreviewActive = true
                    pipelineLock.unlock()
                    livePreview.push(processed)
                } else {
                    // GPU/CI miss after a successful push left Metal stuck black
                    // (esp. collapsed resize). Restore AV preview and retry later.
                    livePreviewFailStreak += 1
                    let shouldClear = livePreviewActive && livePreviewFailStreak >= 3
                    if shouldClear {
                        livePreviewActive = false
                        livePreviewFailStreak = 0
                    }
                    pipelineLock.unlock()
                    if shouldClear { livePreview.push(nil) }
                }
            }
        } else {
            pipelineLock.lock()
            if livePreviewActive {
                // Clear once — do not hop to main on every idle camera frame.
                livePreviewActive = false
                livePreviewFailStreak = 0
                pipelineLock.unlock()
                livePreview.push(nil)
            } else {
                pipelineLock.unlock()
            }
        }

        // Handle long exposure frame capture (wall-clock stop + running average)
        guard accumulating else { return }

        let elapsed = now - longExposureStartTime
        // Prefer at least one frame before stopping; bail if the sensor never delivers.
        if elapsed >= longExposureTargetDuration {
            if longExposureFrameCount > 0 || elapsed >= longExposureTargetDuration + 8 {
                finalizeLongExposure()
            }
            return
        }

        // Materialize every frame — CVPixelBuffer is recycled when this callback returns.
        // Autoreleasepool keeps intermediate CIImage / CGImage allocations from piling up
        // across dozens of frames (GPU textures and CF objects are autorelease-heavy).
        autoreleasepool {
            let accumulationFrame = downscaled(ciImage, longEdge: 1280)
            guard let ownedCG = ShutterRender.syncCI({
                ciContext.createCGImage(accumulationFrame, from: accumulationFrame.extent)
            }) else {
                return
            }
            let ownedFrame = CIImage(cgImage: ownedCG)
            longExposureFrameCount += 1
            let n = Float(longExposureFrameCount)
            if let acc = longExposureAccumulator, n > 1 {
                let scaledOld = scaledCIImage(acc, scale: (n - 1) / n)
                let scaledNew = scaledCIImage(ownedFrame, scale: 1 / n)
                let blend = CIFilter.additionCompositing()
                blend.inputImage = scaledNew
                blend.backgroundImage = scaledOld
                if let blended = blend.outputImage,
                   let flat = ShutterRender.syncCI({
                       ciContext.createCGImage(blended, from: blended.extent)
                   }) {
                    longExposureAccumulator = CIImage(cgImage: flat)
                } else {
                    longExposureAccumulator = ownedFrame
                }
            } else {
                longExposureAccumulator = ownedFrame
            }
        }

        let progress = min(1.0, Float(elapsed / longExposureTargetDuration))
        // ~12 Hz / 4% steps — enough for the ring, cheap for SwiftUI.
        if progress - lastLEProgressValue >= 0.04 || now - lastLEProgressPublish >= 0.08 {
            lastLEProgressPublish = now
            lastLEProgressValue = progress
            DispatchQueue.main.async {
                self.longExposureProgress = progress
            }
        }
    }

    private func finalizeLongExposure() {
        // Atomic gate — video callback and watchdog both call this.
        photoStateLock.lock()
        let op = leOpID
        guard isAccumulatingLongExposure, !isFinalizingLongExposure else {
            photoStateLock.unlock()
            return
        }
        isFinalizingLongExposure = true
        isAccumulatingLongExposure = false
        let completion = longExposureCompletion
        longExposureCompletion = nil
        let gen = UUID()
        bakeGeneration = gen
        bakeTimeoutCompletion = { img in
            DispatchQueue.main.async { completion?(img) }
        }
        photoStateLock.unlock()

        // Watchdog no longer needed — we are now finalizing.
        stackWatchdogWork?.cancel()
        stackWatchdogWork = nil

        // Keep isLongExposureCapturing true through bake so Cancel still works
        // and sessionBusy blocks competing captures until JPEG lands.
        DispatchQueue.main.async {
            self.longExposureProgress = 1.0
        }

        // Snapshot + bake BEFORE restoring exposure. resetToAutoExposure used to
        // nil the accumulator first, so normalize always returned nil.
        let captureFilmFilter = longExposureFilmFilter
        let captureLensFX = longExposureLensFX
        // Capture + clear morphTouch before touching longExposureCompletion under lock.
        let captureTouch = longExposureMorphTouch
        longExposureMorphTouch = nil

        setBakingStill(true)
        armBakeTimeout()

        // normalizeAccumulator may syncCI — never run that on the main queue
        // (STACK watchdog used to call finalize on main and freeze the UI).
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let resultImage = self.normalizeAccumulator()

            self.longExposureAccumulator = nil
            self.longExposureFrameCount = 0
            self.longExposureTargetDuration = 0

            self.restoreExposureAfterLongExposure()

            // Abort if bakeGeneration was superseded (cancel/timeout won).
            self.photoStateLock.lock()
            let genStillCurrent = self.bakeGeneration == gen
            let opStillCurrent = self.leOpID == op
            self.photoStateLock.unlock()
            guard genStillCurrent, opStillCurrent else { return }

            let finalImage: UIImage?
            if let img = resultImage {
                // Same WYSIWYG bake policy as normal capture.
                finalImage = self.bakeLooksForCapture(
                    film: captureFilmFilter,
                    fx: captureLensFX,
                    touch: captureTouch,
                    onto: img
                )
            } else {
                finalImage = nil
            }

            self.finishUserBake(finalImage, generation: gen)
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
