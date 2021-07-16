//
//  File.swift
//  
//
//  Created by apple on 13.07.21.
//

import Foundation

import Foundation
import Combine
import Photos
import UIKit

final public class CameraModel: ObservableObject {
    
    private let service = CameraService()
    
//    @Published var photo: Photo!
    @Published var isRecordingInternal: Bool = false
    
    @Published public var showAlertError = false
    
    @Published var isFlashOnInternal = false
    
    @Published var willCapturePhoto = false
    
    @Published var finalModelInternal: VideoPreviewModel? = nil
    
    @Published var timer: Timer = Timer.fifteen
    
    @Published public var progress: Float = 0.0
    
    lazy var hvTimer: HVTimer<Double> = {
        
        HVTimer(short: 0.25, data: 0.25, repeats: true) { [weak self] value in
            
            DispatchQueue.main.async {
                self?.hvTimer.data = (self?.hvTimer.data ?? 0) + 0.25
                self?.progress = Float(value ?? 1)/Float(self?.timer.rawValue ?? 1)
            }
        }
    }()
    
    public var alertError: AlertError!
    
    var sessionInternal: AVCaptureSession
    
    private var subscriptions = Set<AnyCancellable>()
    
    public var isRecording: Bool {
        return isRecordingInternal
    }
    
    public var currentTime: Timer {
        return timer
    }
    
    public var isFlashOn: Bool {
        return isFlashOnInternal
    }
    
    public var finalModel: VideoPreviewModel? {
        return finalModelInternal
    }
    
    public var session: AVCaptureSession {
        return sessionInternal
    }
    
    public init(maxTime timer: Timer = Timer.fifteen) {
        
        self.timer = timer
        self.sessionInternal = service.session
        self.service.videoDelegate = self
        
        service.$shouldShowAlertView.sink { [weak self] (val) in
            self?.alertError = self?.service.alertError
            self?.showAlertError = val
        }
        .store(in: &self.subscriptions)
        
        service.$flashMode.sink { [weak self] (mode) in
            self?.isFlashOnInternal = mode == .on
        }
        .store(in: &self.subscriptions)
        
        $timer.sink { [weak self] (value) in
            self?.service.timer = value
        }
        .store(in: &self.subscriptions)
        
        addApplicationObservers()
    }
    
    deinit {
        removeApplicationObservers()
    }
    
    internal func addApplicationObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(CameraModel.handleApplicationWillEnterForeground(_:)), name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(CameraModel.handleApplicationDidEnterBackground(_:)), name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    internal func removeApplicationObservers() {
        NotificationCenter.default.removeObserver(self, name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    @objc internal func handleApplicationWillEnterForeground(_ notification: Notification) {
        // self.sessionQueue.async {}
    }

    @objc internal func handleApplicationDidEnterBackground(_ notification: Notification) {
        
        self.service.executeClosureAsyncOnSessionQueueIfNecessary {
            if self.isRecordingInternal {
                self.service.pause()
            }
        }
    }
    
    // will start all camera services
    public func configure() {
        service.checkForPermissions()
        service.configure()
    }
    
    // will stop all camera services
    public func stop() {
        service.flashMode = .off
        self.isFlashOnInternal = service.flashMode == .on
        service.stop()
    }
    
    /// will toggle timer
    public func toggleTimer() {
        self.timer.toggle()
    }
    
    /// will start/strop recording according to last recording state
    public func handleCapture() {
        
        if self.isRecordingInternal {
            endCapture()
        } else {
            service.record()
            self.hvTimer.activate()
        }
        self.isRecordingInternal.toggle()
    }
    
    internal func endCapture() {
        
        DispatchQueue.main.async {
            self.hvTimer.cancel()
            self.progress = 0.0
        }
        
        if let session = service._recordingSession {

            if session.clips.count > 1 {
                session.mergeClips(usingPreset: AVAssetExportPresetHighestQuality, completionHandler: { (url: URL?, error: Error?) in
                    if let url = url {
                        
                        DispatchQueue.main.async { self.finalModelInternal = VideoPreviewModel(url: url) }
                        session.removeAllClips(removeFiles: false)

                    } else if let _ = error {
                        print("failed to merge clips at the end of capture \(String(describing: error))")
                    }
                })
            } else if let lastClipUrl = session.lastClipUrl {
                
                DispatchQueue.main.async { self.finalModelInternal = VideoPreviewModel(url: lastClipUrl) }
                session.removeAllClips(removeFiles: false)
                
            } else if session.currentClipHasStarted {
                session.endClip(completionHandler: { (clip, error) in
                    if error == nil, let url = clip?.url {
                        
                        DispatchQueue.main.async { self.finalModelInternal = VideoPreviewModel(url: url) }
                        session.removeAllClips(removeFiles: false)
                    } else {
                        print("Error saving video: \(error?.localizedDescription ?? "")")
                    }
                })
            } else {
                session.removeAllClips(removeFiles: false)
            }
        }
    }
    
    public func flipCamera() {
        service.changeCamera()
    }
    
    /// will remove last video if video recorded earlier
    public func removeLastVideo() {
        if let url = self.finalModelInternal?.url {
            try? FileManager.default.removeItem(at: url)
        }
        self.finalModelInternal = nil
    }
    
    /// will return URL if video recorded earlier
    public func getLastVideoLocalUrl() -> URL? {
        return self.finalModelInternal?.url
    }
    
    /// will save video if video recorded earlier
    public func saveLastVideo() {
        
        guard let url = self.finalModelInternal?.url else { return }
        
        self.saveVideo(withURL: url) { status in
//            guard status else { return }
        }
    }
    
    func zoom(with factor: CGFloat) {
//        service.set(zoom: factor)
    }
    
    public func toggleFlash() {
        service.flashMode = service.flashMode == .on ? .off : .on
        self.isFlashOnInternal = service.flashMode == .on
    }
    
    internal func saveVideo(withURL url: URL, onCompletion: ((_ success: Bool) -> ())? = nil) {
        
        PHPhotoLibrary.shared().performChanges({
            if let assetChangeRequest = PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url) {
                let assetCollectionChangeRequest = PHAssetCollectionChangeRequest()//PHAssetCollectionChangeRequest(for: albumAssetCollection)
                let enumeration: NSArray = [assetChangeRequest.placeholderForCreatedAsset!]
                assetCollectionChangeRequest.addAssets(enumeration)
            }
        }, completionHandler: { (success: Bool, error: Error?) in
            onCompletion?(success)
            if success == true {
                // prompt that the video has been saved
            } else {
                // prompt that the video has been saved
            }
        })
    }
}

extension CameraModel: CameraVideoDelegate {
    
    public func Camera(_ Camera: CameraService, didCompleteClip clip: CameraClip, inSession session: CameraSession) {
        DispatchQueue.main.async { self.isRecordingInternal.toggle() }
        self.endCapture()
    }
}

