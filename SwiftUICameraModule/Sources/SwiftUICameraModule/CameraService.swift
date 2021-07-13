//
//  CameraService.swift
//  SwiftUICameraModule
//
//  Created by apple on 13.07.21.
//

import Foundation
import Combine
import AVFoundation
import Photos
import UIKit

public struct AlertError {
    public var title: String = ""
    public var message: String = ""
    public var primaryButtonTitle = "Accept"
    public var secondaryButtonTitle: String?
    public var primaryAction: (() -> ())?
    public var secondaryAction: (() -> ())?
    
    public init(title: String = "", message: String = "", primaryButtonTitle: String = "Accept", secondaryButtonTitle: String? = nil, primaryAction: (() -> ())? = nil, secondaryAction: (() -> ())? = nil) {
        self.title = title
        self.message = message
        self.primaryAction = primaryAction
        self.primaryButtonTitle = primaryButtonTitle
        self.secondaryAction = secondaryAction
    }
}

private let CameraCaptureSessionQueueIdentifier = "com.camera.capturesession"
private let CameraCaptureSessionQueueSpecificKey = DispatchSpecificKey<()>()

public enum Timer: Int {
    case fifteen = 15
    case thirty = 30
    
    var getCMTime: CMTime {
        return CMTime(seconds: Double(self.rawValue), preferredTimescale: 1)
    }
    
    mutating func toggle() {
        self = self == Timer.fifteen ? Timer.thirty : Timer.fifteen
    }
    
}

public class CameraService: NSObject {
    
    @Published public var flashMode: AVCaptureDevice.TorchMode = .off
    @Published public var shouldShowAlertView = false
    @Published public var isCameraButtonDisabled = true
    @Published public var isCameraUnavailable = true
    @Published public var timer: Timer = Timer.fifteen
    
    public weak var videoDelegate: CameraVideoDelegate?
    
    //    MARK: Alert properties
    public var alertError: AlertError = AlertError()
    
    public let session = AVCaptureSession()
    
    /// Configuration for video
    public var videoConfiguration: CameraVideoConfiguration

    /// Configuration for audio
    public var audioConfiguration: CameraAudioConfiguration
    
    public var customURL: URL? = nil {
        didSet {
            self._recordingSession?.customURL = customURL
        }
    }
    
    // MARK: Device Configuration Properties
    private let videoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .builtInDualCamera, .builtInTrueDepthCamera], mediaType: .video, position: .unspecified)
    
    @objc dynamic var videoDeviceInput: AVCaptureDeviceInput!
    @objc dynamic var audioDeviceInput: AVCaptureDeviceInput!
    
    @objc dynamic var videoOutput: AVCaptureVideoDataOutput!
    @objc dynamic var audioOutput: AVCaptureAudioDataOutput!
    
    var setupResult: SessionSetupResult = .authorized
    // Communicate with the session and other session objects on this queue.
//    private let sessionQueue = DispatchQueue(label: "session queue")
    internal var _sessionQueue: DispatchQueue
    
    internal var _recording: Bool = false
    internal var _recordingSession: CameraSession?
    internal var _lastVideoFrameTimeInterval: TimeInterval = 0
    
    internal var _videoCustomContextRenderingEnabled: Bool = false
    internal var _sessionVideoCustomContextImageBuffer: CVPixelBuffer?
    
    internal var _lastVideoFrame: CMSampleBuffer?
    internal var _lastAudioFrame: CMSampleBuffer?
    
    var sessionQueue: DispatchQueue {
        get {
            self._sessionQueue
        }
    }
    
    var isSessionRunning = false
    
    var isConfigured = false
    
    /// The current recording session, a powerful means for modifying and editing previously recorded clips.
    /// The session provides features such as 'undo'.
    public var recordingSession: CameraSession? {
        get {
            self._recordingSession
        }
    }
    
    private var subscriptions = Set<AnyCancellable>()
    
    override public init() {
        
        self._sessionQueue = DispatchQueue(label: CameraCaptureSessionQueueIdentifier, qos: .userInteractive, target: DispatchQueue.global())
        self._sessionQueue.setSpecific(key: CameraCaptureSessionQueueSpecificKey, value: ())
        
        self.videoConfiguration = CameraVideoConfiguration()
        self.audioConfiguration = CameraAudioConfiguration()
        
        /*
         service.$shouldShowAlertView.sink { [weak self] (val) in
             self?.alertError = self?.service.alertError
             self?.showAlertError = val
         }
         .store(in: &self.subscriptions)
         */
        
        super.init()
        
        self.$flashMode.sink { [weak self] value in
            
            guard let unwrapSelf = self, let device = unwrapSelf.videoDeviceInput?.device else { return }
            
            unwrapSelf.setTorchMode(value, for: device)
        }.store(in: &self.subscriptions)
        
        self.$timer.sink { [weak self] (value) in
            self?.videoConfiguration.maximumCaptureDuration = value.getCMTime
            self?.recordingSession?.removeVideoConfiguration()
        }
        .store(in: &self.subscriptions)
        
    }
    
    func setTorchMode(_ torchMode: AVCaptureDevice.TorchMode, for device: AVCaptureDevice) {
        if device.isTorchModeSupported(torchMode) && device.torchMode != torchMode {
            do
            {
                try device.lockForConfiguration()
                    device.torchMode = torchMode
                    device.unlockForConfiguration()
            }
            catch {
                print("Error:-\(error)")
            }
        }
    }
    
    deinit {
        self._recordingSession = nil
    }
    
    public func configure() {
        /*
         Setup the capture session.
         In general, it's not safe to mutate an AVCaptureSession or any of its
         inputs, outputs, or connections from multiple threads at the same time.
         
         Don't perform these tasks on the main queue because
         AVCaptureSession.startRunning() is a blocking call, which can
         take a long time. Dispatch session setup to the sessionQueue, so
         that the main queue isn't blocked, which keeps the UI responsive.
         */
        self.executeClosureAsyncOnSessionQueueIfNecessary {
            self.configureSession()
        }
    }
    
    /// Stops the current recording session.
    public func stop() {
        
        let session = self.session
        
        self.executeClosureAsyncOnSessionQueueIfNecessary {
            
            if session.isRunning == true {
                session.stopRunning()
                self.isSessionRunning = false//session.isRunning
            }
            DispatchQueue.main.async {
                self.isCameraButtonDisabled = true
                self.isCameraUnavailable = true
            }
            
            session.beginConfiguration()
            
            self.removeInputs(session: session)
            self.removeOutputs(session: session)
            
            session.commitConfiguration()
            self.isConfigured = false
            
            self._recordingSession = nil
            
        }
        
    }
    
    internal func removeInputs(session: AVCaptureSession) {
        if let inputs = session.inputs as? [AVCaptureDeviceInput] {
            for input in inputs {
                session.removeInput(input)
            }
        }
    }
    
    internal func removeOutputs(session: AVCaptureSession) {
        
        for output in session.outputs {
            session.removeOutput(output)
        }
    }
    
    private func configureSession() {
        if setupResult != .authorized {
            return
        }
        
        session.beginConfiguration()
        
        session.sessionPreset = .high
        
        if let videoInput = addVideoDeviceInput(),
           let audioInput = addAudioDeviceInput(),
           let audioOutput = addAudioOutput(),
           let videoOutput = addVideoOutput() {
            self.videoDeviceInput = videoInput
            self.audioDeviceInput = audioInput
            self.audioOutput = audioOutput
            self.videoOutput = videoOutput
        } else {
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        session.commitConfiguration()
        self.isConfigured = true
        self.start()
    }
    
    /// - Tag: Start capture session
    
    public func start() {
//        We use our capture session queue to ensure our UI runs smoothly on the main thread.
        
        self.executeClosureAsyncOnSessionQueueIfNecessary {
            
            if !self.isSessionRunning && self.isConfigured {
                
                switch self.setupResult {
                case .authorized:
                    
                    self.session.startRunning()
                    self.isSessionRunning = self.session.isRunning
                    
                    self._recordingSession = CameraSession(queue: self._sessionQueue, queueKey: CameraCaptureSessionQueueSpecificKey)
                    self._recordingSession?.customURL = self.customURL
                    
                    if self.session.isRunning {
                        DispatchQueue.main.async {
                            self.isCameraButtonDisabled = false
                            self.isCameraUnavailable = false
                        }
                    }
                default:
                    print("Application not authorized to use camera")

                    DispatchQueue.main.async {
                        self.alertError = AlertError(title: "Camera Error", message: "Camera configuration failed. Either your device camera is not available or its missing permissions", primaryButtonTitle: "Accept", secondaryButtonTitle: nil, primaryAction: nil, secondaryAction: nil)
                        self.shouldShowAlertView = true
                        self.isCameraButtonDisabled = true
                        self.isCameraUnavailable = true
                    }
                }
            }
        }
    }
    
    /// Initiates video recording, managed as a clip within the 'CameraSession'
    public func record() {
        self.executeClosureSyncOnSessionQueueIfNecessary {
            self._recording = true
            if let _ = self._recordingSession {
                self.beginRecordingNewClipIfNecessary()
            }
        }
    }
    
    /// Pauses video recording, preparing 'Camera' to start a new clip with 'record()' with completion handler.
    ///
    /// - Parameter completionHandler: Completion handler for when pause completes
    public func pause(withCompletionHandler completionHandler: (() -> Void)? = nil) {
        self._recording = false

        self.executeClosureAsyncOnSessionQueueIfNecessary {
            if let session = self._recordingSession {
                if session.currentClipHasStarted {
                    session.endClip(completionHandler: { (sessionClip: CameraClip?, error: Error?) in
                        if let sessionClip = sessionClip {
                            DispatchQueue.main.async {
                                self.videoDelegate?.Camera(self, didCompleteClip: sessionClip, inSession: session)
                            }
                            if let completionHandler = completionHandler {
                                DispatchQueue.main.async(execute: completionHandler)
                            }
                        } else if let _ = error {
                            // TODO, report error
                            if let completionHandler = completionHandler {
                                DispatchQueue.main.async(execute: completionHandler)
                            }
                        }
                    })
                } else if let completionHandler = completionHandler {
                    DispatchQueue.main.async(execute: completionHandler)
                }
            } else if let completionHandler = completionHandler {
                DispatchQueue.main.async(execute: completionHandler)
            }
        }
    }
    
    internal func beginRecordingNewClipIfNecessary() {
        if let session = self._recordingSession,
            session.isReady == false {
            session.beginClip()
        }
    }
    
}

// MARK: - queues

extension CameraService {

    internal func executeClosureAsyncOnSessionQueueIfNecessary(withClosure closure: @escaping () -> Void) {
        self._sessionQueue.async(execute: closure)
    }

    internal func executeClosureSyncOnSessionQueueIfNecessary(withClosure closure: @escaping () -> Void) {
        if DispatchQueue.getSpecific(key: CameraCaptureSessionQueueSpecificKey) != nil {
            closure()
        } else {
            self._sessionQueue.sync(execute: closure)
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate

extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    
    public func captureOutput(_ captureOutput: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        switch captureOutput {
        case videoOutput:
            self._lastVideoFrame = sampleBuffer
            if let session = self._recordingSession {
                self.handleVideoOutput(sampleBuffer: sampleBuffer, session: session)
            }
            break
        case audioOutput:
            self._lastAudioFrame = sampleBuffer
            if let session = self._recordingSession {
                self.handleAudioOutput(sampleBuffer: sampleBuffer, session: session)
            }
            break
        default:
            break
        }
        
    }
    
    // custom video rendering

    /// Enables delegate callbacks for rendering into a custom context.
    /// videoDelegate, func Camera(_ Camera: Camera, renderToCustomContextWithImageBuffer imageBuffer: CVPixelBuffer, onQueue queue: DispatchQueue)
    public var isVideoCustomContextRenderingEnabled: Bool {
        get {
            self._videoCustomContextRenderingEnabled
        }
        set {
            self.executeClosureSyncOnSessionQueueIfNecessary {
                self._videoCustomContextRenderingEnabled = newValue
                self._sessionVideoCustomContextImageBuffer = nil
            }
        }
    }
    
    // sample buffer processing

    internal func handleVideoOutput(sampleBuffer: CMSampleBuffer, session: CameraSession) {
        
        if session.isVideoSetup == false {
            
            if let settings = self.videoConfiguration.avcaptureSettingsDictionary(service: self, sampleBuffer: sampleBuffer),
                let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) {
                if !session.setupVideo(withSettings: settings, configuration: self.videoConfiguration, formatDescription: formatDescription) {
                    print("Camera, could not setup video session")
                }
            }
        }
        
        if self._recording && session.isAudioSetup && session.currentClipHasStarted {
            
            self.beginRecordingNewClipIfNecessary()
            
            let minTimeBetweenFrames = 0.004
            let sleepDuration = minTimeBetweenFrames - (CACurrentMediaTime() - self._lastVideoFrameTimeInterval)
            if sleepDuration > 0 {
                Thread.sleep(forTimeInterval: sleepDuration)
            }
            
            // check with the client to setup/maintain external render contexts
            let imageBuffer = self.isVideoCustomContextRenderingEnabled == true ? CMSampleBufferGetImageBuffer(sampleBuffer) : nil
            if let imageBuffer = imageBuffer {
                if CVPixelBufferLockBaseAddress(imageBuffer, CVPixelBufferLockFlags(rawValue: 0)) == kCVReturnSuccess {
                    // only called from captureQueue
//                    self.videoDelegate?.Camera(self, renderToCustomContextWithImageBuffer: imageBuffer, onQueue: self._sessionQueue)
                } else {
                    self._sessionVideoCustomContextImageBuffer = nil
                }
            }
            
            guard let device = self.videoDeviceInput?.device else {
                return
            }
            
            // when clients modify a frame using their rendering context, the resulting CVPixelBuffer is then passed in here with the original sampleBuffer for recording
            session.appendVideo(withSampleBuffer: sampleBuffer, customImageBuffer: self._sessionVideoCustomContextImageBuffer, minFrameDuration: device.activeVideoMinFrameDuration, completionHandler: { (success: Bool) -> Void in
                // cleanup client rendering context
                if self.isVideoCustomContextRenderingEnabled {
                    if let imageBuffer = imageBuffer {
                        CVPixelBufferUnlockBaseAddress(imageBuffer, CVPixelBufferLockFlags(rawValue: 0))
                    }
                }

                // process frame
                self._lastVideoFrameTimeInterval = CACurrentMediaTime()
                if success == true {
                    self.checkSessionDuration()
                }
            })
            
            if session.currentClipHasVideo == false && session.currentClipHasAudio {
                if let audioBuffer = self._lastAudioFrame {
                    let lastAudioEndTime = CMTimeAdd(CMSampleBufferGetPresentationTimeStamp(audioBuffer), CMSampleBufferGetDuration(audioBuffer))
                    let videoStartTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

                    if lastAudioEndTime > videoStartTime {
                        self.handleAudioOutput(sampleBuffer: audioBuffer, session: session)
                    }
                }
            }
        }
    }
    
    // Beta: handleVideoOutput(pixelBuffer:timestamp:session:) needs to be tested
    internal func handleVideoOutput(pixelBuffer: CVPixelBuffer, timestamp: TimeInterval, session: CameraSession) {
        
        if session.isVideoSetup == false {
            if let settings = self.videoConfiguration.avcaptureSettingsDictionary(service: self, pixelBuffer: pixelBuffer) {
                if !session.setupVideo(withSettings: settings, configuration: self.videoConfiguration) {
                    print("could not setup video session")
                }
            }
        }

        if self._recording && session.isAudioSetup && session.currentClipHasStarted {
            self.beginRecordingNewClipIfNecessary()

            let minTimeBetweenFrames = 0.004
            let sleepDuration = minTimeBetweenFrames - (CACurrentMediaTime() - self._lastVideoFrameTimeInterval)
            if sleepDuration > 0 {
                Thread.sleep(forTimeInterval: sleepDuration)
            }

            // check with the client to setup/maintain external render contexts
            let imageBuffer = self.isVideoCustomContextRenderingEnabled == true ? pixelBuffer : nil
            if let imageBuffer = imageBuffer {
                if CVPixelBufferLockBaseAddress(imageBuffer, CVPixelBufferLockFlags(rawValue: 0)) == kCVReturnSuccess {
                    // only called from captureQueue
//                    self.videoDelegate?.Camera(self, renderToCustomContextWithImageBuffer: imageBuffer, onQueue: self._sessionQueue)
                } else {
                    self._sessionVideoCustomContextImageBuffer = nil
                }
            }

            // when clients modify a frame using their rendering context, the resulting CVPixelBuffer is then passed in here with the original sampleBuffer for recording
            session.appendVideo(withPixelBuffer: pixelBuffer, customImageBuffer: self._sessionVideoCustomContextImageBuffer, timestamp: timestamp, minFrameDuration: CMTime(seconds: 1, preferredTimescale: 600), completionHandler: { (success: Bool) -> Void in
                // cleanup client rendering context
                if self.isVideoCustomContextRenderingEnabled {
                    if let imageBuffer = imageBuffer {
                        CVPixelBufferUnlockBaseAddress(imageBuffer, CVPixelBufferLockFlags(rawValue: 0))
                    }
                }

                // process frame
                self._lastVideoFrameTimeInterval = CACurrentMediaTime()
                if success {
//                    DispatchQueue.main.async {
//                        self.videoDelegate?.Camera(self, didAppendVideoPixelBuffer: pixelBuffer, timestamp: timestamp, inSession: session)
//                    }
                    self.checkSessionDuration()
                } else {
//                    DispatchQueue.main.async {
//                        self.videoDelegate?.Camera(self, didSkipVideoPixelBuffer: pixelBuffer, timestamp: timestamp, inSession: session)
//                    }
                }
            })

            if session.currentClipHasVideo == false && session.currentClipHasAudio {
                if let audioBuffer = self._lastAudioFrame {
                    let lastAudioEndTime = CMTimeAdd(CMSampleBufferGetPresentationTimeStamp(audioBuffer), CMSampleBufferGetDuration(audioBuffer))
                    let videoStartTime = CMTime(seconds: timestamp, preferredTimescale: 600)

                    if lastAudioEndTime > videoStartTime {
                        self.handleAudioOutput(sampleBuffer: audioBuffer, session: session)
                    }
                }
            }
        }
    }
    
    internal func handleAudioOutput(sampleBuffer: CMSampleBuffer, session: CameraSession) {
        if session.isAudioSetup == false {
            if let settings = self.audioConfiguration.avcaptureSettingsDictionary(service: self, sampleBuffer: sampleBuffer),
                let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) {
                if !session.setupAudio(withSettings: settings, configuration: self.audioConfiguration, formatDescription: formatDescription) {
                    print("Camera, could not setup audio session")
                }
            }

//            DispatchQueue.main.async {
//                self.videoDelegate?.Camera(self, didSetupAudioInSession: session)
//            }
        }

        if self._recording && session.isVideoSetup && session.currentClipHasStarted && session.currentClipHasVideo {
            self.beginRecordingNewClipIfNecessary()

            session.appendAudio(withSampleBuffer: sampleBuffer, completionHandler: { (success: Bool) -> Void in
                if success {
//                    DispatchQueue.main.async {
//                        self.videoDelegate?.Camera(self, didAppendAudioSampleBuffer: sampleBuffer, inSession: session)
//                    }
                    self.checkSessionDuration()
                } else {
//                    DispatchQueue.main.async {
//                        self.videoDelegate?.Camera(self, didSkipAudioSampleBuffer: sampleBuffer, inSession: session)
//                    }
                }
            })
        }
    }
    
    private func checkSessionDuration() {
        if let session = self._recordingSession,
            let maximumCaptureDuration = self.videoConfiguration.maximumCaptureDuration {
            if maximumCaptureDuration.isValid && session.totalDuration >= maximumCaptureDuration {
                self._recording = false

                // already on session queue, adding to next cycle
                self.executeClosureAsyncOnSessionQueueIfNecessary {
                    session.endClip(completionHandler: { (sessionClip: CameraClip?, error: Error?) in
                        if let clip = sessionClip {
                            DispatchQueue.main.async {
                                self.videoDelegate?.Camera(self, didCompleteClip: clip, inSession: session)
                            }
                        } else if let _ = error {
                            // TODO report error
                        }
//                        DispatchQueue.main.async {
//                            self.videoDelegate?.Camera(self, didCompleteSession: session)
//                        }
                    })
                }
            }
        }
    }
    
}

// MARK: - authorization

extension CameraService {
    
    public func checkForPermissions() {
        
        CameraService.requestAuthorizationForAudioVideo { status in
            
            self.setupResult = status
            
            switch status {
            case .authorized, .notDetermined, .configurationFailed:
                break
            case .notAuthorized:
                
                DispatchQueue.main.async {
                    self.alertError = AlertError(title: "Camera Access", message: "SwiftCamera doesn't have access to use your camera, please update your privacy settings.", primaryButtonTitle: "Settings", secondaryButtonTitle: nil, primaryAction: {
                            UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!,
                                                      options: [:], completionHandler: nil)
                    }, secondaryAction: nil)
                    self.shouldShowAlertView = true
                    self.isCameraUnavailable = true
                    self.isCameraButtonDisabled = true
                }
            }
        }
    }
    
    /// Checks the audio and video authorization status
    ///
    /// - Returns: Authorization status for the desired media type.
    public static func requestAuthorizationForAudioVideo(completionHandler: @escaping ((CameraServiceAuthorizationStatus) -> Void) ) {
        
        var audioStatus: CameraServiceAuthorizationStatus?
        var videoStatus: CameraServiceAuthorizationStatus?
        
        self.requestAuthorization(forMediaType: AVMediaType.video) { (mediaType, status) in
            videoStatus = status
            guard audioStatus == .authorized else { return }
            completionHandler(status)
        }
        self.requestAuthorization(forMediaType: AVMediaType.audio) { (mediaType, status) in
            audioStatus = status
            guard videoStatus == .authorized else { return }
            completionHandler(status)
        }
    }
    
    /// Checks the current authorization status for the desired media type.
    ///
    /// - Parameter mediaType: Specified media type (i.e. AVMediaTypeVideo, AVMediaTypeAudio, etc.)
    /// - Returns: Authorization status for the desired media type.
    public static func authorizationStatus(forMediaType mediaType: AVMediaType) -> CameraServiceAuthorizationStatus {
        let status = AVCaptureDevice.authorizationStatus(for: mediaType)
        var CameraStatus: CameraServiceAuthorizationStatus = .notDetermined
        switch status {
        case .denied, .restricted:
            CameraStatus = .notAuthorized
            break
        case .authorized:
            CameraStatus = .authorized
            break
        case .notDetermined:
            break
        @unknown default:
            debugPrint("unknown authorization type")
            break
        }
        return CameraStatus
    }
    
    /// Requests authorization permission.
    ///
    /// - Parameters:
    ///   - mediaType: Specified media type (i.e. AVMediaTypeVideo, AVMediaTypeAudio, etc.)
    ///   - completionHandler: A block called with the responding access request result
    public static func requestAuthorization(forMediaType mediaType: AVMediaType, completionHandler: @escaping ((AVMediaType, CameraServiceAuthorizationStatus) -> Void) ) {
        AVCaptureDevice.requestAccess(for: mediaType) { (granted: Bool) in
            // According to documentation, requestAccess runs on an arbitary queue
            DispatchQueue.main.async {
                completionHandler(mediaType, (granted ? .authorized : .notAuthorized))
            }
        }
    }
    
}

// MARK: - Handle Camera input and output

extension CameraService {
    
    func addVideoDeviceInput() -> AVCaptureDeviceInput? {
        
        // Add video input.
        do {
            var defaultVideoDevice: AVCaptureDevice?
            
            if let backCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
                // If a rear dual camera is not available, default to the rear wide angle camera.
                defaultVideoDevice = backCameraDevice
            } else if let frontCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
                // If the rear wide angle camera isn't available, default to the front wide angle camera.
                defaultVideoDevice = frontCameraDevice
            }
            
            guard let videoDevice = defaultVideoDevice else {
                print("Default video device is unavailable.")
                return nil
            }
            
            let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
            
            if session.canAddInput(videoDeviceInput) {
                session.addInput(videoDeviceInput)
                return videoDeviceInput
            } else {
                print("Couldn't add video device input to the session.")
                return nil
            }
        } catch {
            print("Couldn't create video device input: \(error)")
            return nil
        }
    }
    
    func addAudioDeviceInput() -> AVCaptureDeviceInput? {
        
        do {
            if let audioDevice = AVCaptureDevice.default(for: AVMediaType.audio) {
                
                let audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice)
                
                if session.canAddInput(audioDeviceInput) {
                    session.addInput(audioDeviceInput)
                    return audioDeviceInput
                } else {
                    print("Couldn't add audio device input to the session.")
                    return nil
                }
            } else {
                return nil
            }
        } catch {
            print("Couldn't create audio device input: \(error)")
            return nil
        }
    }
    
    func addVideoOutput() -> AVCaptureVideoDataOutput? {
        
        let videoOutput = AVCaptureVideoDataOutput()
        
        videoOutput.alwaysDiscardsLateVideoFrames = false
        var videoSettings = [String(kCVPixelBufferPixelFormatTypeKey): Int(kCVPixelFormatType_32BGRA)]
        #if !( targetEnvironment(simulator) )
        let formatTypes = videoOutput.availableVideoPixelFormatTypes
        var supportsFullRange = false
        var supportsVideoRange = false
        for format in formatTypes {
            if format == Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) {
                supportsFullRange = true
            }
            if format == Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange) {
                supportsVideoRange = true
            }
        }
        if supportsFullRange {
            videoSettings[String(kCVPixelBufferPixelFormatTypeKey)] = Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
        } else if supportsVideoRange {
            videoSettings[String(kCVPixelBufferPixelFormatTypeKey)] = Int(kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
        }
        #endif
        videoOutput.videoSettings = videoSettings
        
        if self.session.canAddOutput(videoOutput) {
            self.session.addOutput(videoOutput)
            videoOutput.setSampleBufferDelegate(self, queue: self.sessionQueue)
            return videoOutput
        } else {
            return nil
        }
    }
    
    func addAudioOutput() -> AVCaptureAudioDataOutput? {
        
        let audioOutput = AVCaptureAudioDataOutput()
        
        if self.session.canAddOutput(audioOutput) {
            self.session.addOutput(audioOutput)
            audioOutput.setSampleBufferDelegate(self, queue: self.sessionQueue)
            return audioOutput
        } else {
            print("Couldn't add audio device output to the session.")
            return nil
        }
    }
    
    /// - Tag: ChangeCamera
    public func changeCamera() {
        //        MARK: Here disable all camera operation related buttons due to configuration is due upon and must not be interrupted
        DispatchQueue.main.async {
            self.isCameraButtonDisabled = true
        }
        
        self.executeClosureAsyncOnSessionQueueIfNecessary {
            let currentVideoDevice = self.videoDeviceInput.device
            let currentPosition = currentVideoDevice.position
            
            let preferredPosition: AVCaptureDevice.Position
            let preferredDeviceType: AVCaptureDevice.DeviceType
            
            switch currentPosition {
            case .unspecified, .front:
                preferredPosition = .back
                preferredDeviceType = .builtInWideAngleCamera
                
            case .back:
                preferredPosition = .front
                preferredDeviceType = .builtInWideAngleCamera
                
            @unknown default:
                print("Unknown capture position. Defaulting to back, dual-camera.")
                preferredPosition = .back
                preferredDeviceType = .builtInWideAngleCamera
            }
            let devices = self.videoDeviceDiscoverySession.devices
            var newVideoDevice: AVCaptureDevice? = nil
            
            // First, seek a device with both the preferred position and device type. Otherwise, seek a device with only the preferred position.
            if let device = devices.first(where: { $0.position == preferredPosition && $0.deviceType == preferredDeviceType }) {
                newVideoDevice = device
            } else if let device = devices.first(where: { $0.position == preferredPosition }) {
                newVideoDevice = device
            }
            
            if let videoDevice = newVideoDevice {
                do {
                    let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
                    
                    self.session.beginConfiguration()
                    
                    // Remove the existing device input first, because AVCaptureSession doesn't support
                    // simultaneous use of the rear and front cameras.
                    self.session.removeInput(self.videoDeviceInput)
                    
                    if self.session.canAddInput(videoDeviceInput) {
                        self.session.addInput(videoDeviceInput)
                        self.videoDeviceInput = videoDeviceInput
                    } else {
                        self.session.addInput(self.videoDeviceInput)
                    }
                    
                    if let connection = self.videoOutput.connection(with: .video) {
                        if connection.isVideoStabilizationSupported {
                            connection.preferredVideoStabilizationMode = .auto
                        }
                    }
                    self.session.commitConfiguration()
                } catch {
                    print("Error occurred while creating video device input: \(error)")
                }
            }
            DispatchQueue.main.async {
//                MARK: Here enable capture button due to successfull setup
                self.isCameraButtonDisabled = false
            }
        }
    }
    
}
