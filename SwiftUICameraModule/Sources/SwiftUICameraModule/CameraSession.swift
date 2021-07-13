//
//  CameraSession.swift
//  SwiftUICameraModule
//
//  Created by apple on 13.07.21.
//

import Foundation
import AVFoundation
import UIKit

// MARK: - CameraSession

public class CameraSession {
    
    /// Output directory for a session.
    public var outputDirectory: String
    
    /// Output file type for a session, see AVMediaFormat.h for supported types.
    public var fileType: AVFileType = .mp4

    /// Output file extension for a session, see AVMediaFormat.h for supported extensions.
    public var fileExtension: String = "mp4"
    
    /// Unique identifier for a session.
    public var identifier: UUID {
        get {
            self._identifier
        }
    }

    /// Creation date for a session.
    public var date: Date {
        get {
            self._date
        }
    }
    
    public var isVideoSetup: Bool {
        get {
            self._videoInput != nil
        }
    }

    /// Checks if the session is setup for recording video
    public var isVideoReady: Bool {
        get {
            self._videoInput?.isReadyForMoreMediaData ?? false
        }
    }

    public var isAudioSetup: Bool {
        get {
            self._audioInput != nil
        }
    }

    /// Checks if the session is setup for recording audio
    public var isAudioReady: Bool {
        get {
            self._audioInput?.isReadyForMoreMediaData ?? false
        }
    }
    
    /// Recorded clips for the session.
    public var clips: [CameraClip] {
        get {
            self._clips
        }
    }

    /// Duration of a session, the sum of all recorded clips.
    public var totalDuration: CMTime {
        get {
            CMTimeAdd(self._totalDuration, self._currentClipDuration)
        }
    }
    
    /// Checks if the session's asset writer is ready for data.
    public var isReady: Bool {
        get {
            self._writer != nil
        }
    }
    
    /// True if the current clip recording has been started.
    public var currentClipHasStarted: Bool {
        get {
            self._currentClipHasStarted
        }
    }

    /// Duration of the current clip.
    public var currentClipDuration: CMTime {
        get {
            self._currentClipDuration
        }
    }

    /// Checks if the current clip has video.
    public var currentClipHasVideo: Bool {
        get {
            self._currentClipHasVideo
        }
    }

    /// Checks if the current clip has audio.
    public var currentClipHasAudio: Bool {
        get {
            self._currentClipHasAudio
        }
    }
    
    /// `AVAsset` of the session.
    public var asset: AVAsset? {
        get {
            var asset: AVAsset?
            self.executeClosureSyncOnSessionQueueIfNecessary {
                if self._clips.count == 1 {
                    asset = self._clips.first?.asset
                } else {
                    let composition: AVMutableComposition = AVMutableComposition()
                    self.appendClips(toComposition: composition)
                    asset = composition
                }
            }
            return asset
        }
    }

    /// Shared pool where by which all media is allocated.
    public var pixelBufferPool: CVPixelBufferPool? {
        get {
            self._pixelBufferAdapter?.pixelBufferPool
        }
    }

    public var customURL: URL? = nil
    
    // MARK: - private instance vars

    internal var _identifier: UUID
    internal var _date: Date
    
    internal var _totalDuration: CMTime = .zero
    internal var _clips: [CameraClip] = []
    internal var _clipFilenameCount: Int = 0
    
    internal var _audioQueue: DispatchQueue
    internal var _sessionQueue: DispatchQueue
    internal var _sessionQueueKey: DispatchSpecificKey<()>
    
    internal var _currentClipDuration: CMTime = .zero
    internal var _currentClipHasAudio: Bool = false
    internal var _currentClipHasVideo: Bool = false
    
    internal var _currentClipHasStarted: Bool = false
    internal var _timeOffset: CMTime = CMTime.invalid
    internal var _startTimestamp: CMTime = CMTime.invalid
    internal var _lastAudioTimestamp: CMTime = CMTime.invalid
    internal var _lastVideoTimestamp: CMTime = CMTime.invalid
    
    internal var _skippedAudioBuffers: [CMSampleBuffer] = []
    
    private let sessionAudioQueueIdentifier = "camera.session.audioQueue"
    private let sessionQueueIdentifier = "camera.sessionQueue"
    private let sessionSpecificKey = DispatchSpecificKey<()>()
    
    internal var _writer: AVAssetWriter?
    internal var _videoInput: AVAssetWriterInput?
    internal var _audioInput: AVAssetWriterInput?
    internal var _pixelBufferAdapter: AVAssetWriterInputPixelBufferAdaptor?

    internal var _videoConfiguration: CameraVideoConfiguration?
    internal var _audioConfiguration: CameraAudioConfiguration?
    
    // MARK: - object lifecycle

    /// Initialize using a specific dispatch queue.
    ///
    /// - Parameters:
    ///   - queue: Queue for a session operations
    ///   - queueKey: Key for re-calling the session queue from the system
    public convenience init(queue: DispatchQueue, queueKey: DispatchSpecificKey<()>) {
        self.init()
        self._sessionQueue = queue
        self._sessionQueueKey = queueKey
    }

    /// Initializer.
    public init() {
        self._identifier = UUID()
        self._date = Date()
        self.outputDirectory = NSTemporaryDirectory()

        self._audioQueue = DispatchQueue(label: sessionAudioQueueIdentifier)

        // should always use init(queue:queueKey:), but this may be good for the future
        self._sessionQueue = DispatchQueue(label: sessionQueueIdentifier)
        self._sessionQueue.setSpecific(key: sessionSpecificKey, value: ())
        self._sessionQueueKey = sessionSpecificKey
    }

    deinit {
        self._writer = nil
        self._videoInput = nil
        self._audioInput = nil
        self._pixelBufferAdapter = nil

        self._videoConfiguration = nil
        self._audioConfiguration = nil
    }
    
    /// Starts a clip
    public func beginClip() {
        self.executeClosureSyncOnSessionQueueIfNecessary {
            if self._writer == nil {
                self.setupWriter()
                self._currentClipDuration = CMTime.zero
                self._currentClipHasAudio = false
                self._currentClipHasVideo = false
            } else {
                print("Camera, clip has already been created.")
            }
        }
    }
    
    /// Completion handler type for ending a clip
    public typealias CameraSessionEndClipCompletionHandler = (_: CameraClip?, _: Error?) -> Void
    
    /// Finalizes the recording of a clip.
    ///
    /// - Parameter completionHandler: Handler for when a clip is finalized or finalization fails
    public func endClip(completionHandler: CameraSessionEndClipCompletionHandler?) {
        self.executeClosureSyncOnSessionQueueIfNecessary {
            self._audioQueue.sync {
                if self._currentClipHasStarted {
                    self._currentClipHasStarted = false

                    if let writer = self._writer {
                        if !self.currentClipHasAudio && !self.currentClipHasVideo {
                            writer.cancelWriting()

                            self.removeFile(fileUrl: writer.outputURL)
                            self.destroyWriter()

                            if let completionHandler = completionHandler {
                                DispatchQueue.main.async {
                                    completionHandler(nil, nil)
                                }
                            }
                        } else {
                            // print("ending session \(CMTimeGetSeconds(self._currentClipDuration))")
                            writer.endSession(atSourceTime: CMTimeAdd(self._currentClipDuration, self._startTimestamp))
                            writer.finishWriting(completionHandler: {
                                self.executeClosureSyncOnSessionQueueIfNecessary {
                                    var clip: CameraClip?
                                    let url = writer.outputURL
                                    let error = writer.error

                                    if error == nil {
                                        clip = CameraClip(url: url, infoDict: nil)
                                        if let clip = clip {
                                            self.add(clip: clip)
                                        }
                                    }

                                    self.destroyWriter()

                                    if let completionHandler = completionHandler {
                                        DispatchQueue.main.async {
                                            completionHandler(clip, error)
                                        }
                                    }
                                }
                            })
                            return
                        }
                    }
                }

                if let completionHandler = completionHandler {
                    DispatchQueue.main.async {
                        completionHandler(nil, CameraError.notReadyToRecord)
                    }
                }
            }
        }
    }
    
}

// MARK: - setup

extension CameraSession {
    
    func removeVideoConfiguration() {
        
        self._videoInput = nil
        self._videoConfiguration = nil
        self._pixelBufferAdapter = nil
    }
    
    /// Prepares a session for recording video.
    ///
    /// - Parameters:
    ///   - settings: AVFoundation video settings dictionary
    ///   - configuration: Video configuration for video output
    ///   - formatDescription: sample buffer format description
    /// - Returns: True when setup completes successfully
    public func setupVideo(withSettings settings: [String: Any]?, configuration: CameraVideoConfiguration, formatDescription: CMFormatDescription? = nil) -> Bool {
        if let formatDescription = formatDescription {
            self._videoInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: settings, sourceFormatHint: formatDescription)
        } else {
            if let _ = settings?[AVVideoCodecKey],
                let _ = settings?[AVVideoWidthKey],
                let _ = settings?[AVVideoHeightKey] {
                self._videoInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: settings)
            } else {
                print("CameraSession, configuration failure for video output")
                self._videoInput = nil
                return false
            }
        }

        if let videoInput = self._videoInput {
            videoInput.expectsMediaDataInRealTime = true
            videoInput.transform = configuration.transform
            self._videoConfiguration = configuration

            var pixelBufferAttri: [String: Any] = [String(kCVPixelBufferPixelFormatTypeKey): Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)]

            if let formatDescription = formatDescription {
                let videoDimensions = CMVideoFormatDescriptionGetDimensions(formatDescription)
                pixelBufferAttri[String(kCVPixelBufferWidthKey)] = Float(videoDimensions.width)
                pixelBufferAttri[String(kCVPixelBufferHeightKey)] = Float(videoDimensions.height)
            } else if let width = settings?[AVVideoWidthKey],
                      let height = settings?[AVVideoHeightKey] {
                pixelBufferAttri[String(kCVPixelBufferWidthKey)] = width
                pixelBufferAttri[String(kCVPixelBufferHeightKey)] = height
            }

            self._pixelBufferAdapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: pixelBufferAttri)
        }
        return self.isVideoSetup
    }
    
    /// Prepares a session for recording audio.
    ///
    /// - Parameters:
    ///   - settings: AVFoundation audio settings dictionary
    ///   - configuration: Audio configuration for audio output
    ///   - formatDescription: sample buffer format description
    /// - Returns: True when setup completes successfully
    public func setupAudio(withSettings settings: [String: Any]?, configuration: CameraAudioConfiguration, formatDescription: CMFormatDescription) -> Bool {
        self._audioInput = AVAssetWriterInput(mediaType: AVMediaType.audio, outputSettings: settings, sourceFormatHint: formatDescription)
        if let audioInput = self._audioInput {
            audioInput.expectsMediaDataInRealTime = true
            self._audioConfiguration = configuration
        }
        return self.isAudioSetup
    }
    
    internal func setupWriter() {
        guard let url = self.nextFileURL() else {
            return
        }

        do {
            self._writer = try AVAssetWriter(url: url, fileType: self.fileType)
            if let writer = self._writer {
                writer.shouldOptimizeForNetworkUse = true
                writer.metadata = CameraSession.assetWriterMetadata

                if let videoInput = self._videoInput {
                    if writer.canAdd(videoInput) {
                        writer.add(videoInput)
                    } else {
                        print("Camera, could not add video input to session")
                    }
                }

                if let audioInput = self._audioInput {
                    if writer.canAdd(audioInput) {
                        writer.add(audioInput)
                    } else {
                        print("Camera, could not add audio input to session")
                    }
                }

                if writer.startWriting() {
                    self._timeOffset = CMTime.zero
                    self._startTimestamp = CMTime.invalid
                    self._currentClipHasStarted = true
                } else {
                    print("Camera, writer encountered an error \(String(describing: writer.error))")
                    self._writer = nil
                }
            }
        } catch {
            print("Camera could not create asset writer")
        }
    }
    
    internal func destroyWriter() {
        self._writer = nil
        self._currentClipHasStarted = false
        self._timeOffset = CMTime.zero
        self._startTimestamp = CMTime.invalid
        self._currentClipDuration = CMTime.zero
        self._currentClipHasVideo = false
        self._currentClipHasAudio = false
    }
    
}

// MARK: - file management

extension CameraSession {

    internal func nextFileURL() -> URL? {
        
        if let url = customURL {
            return url
        }
        
        let filename = "\(self.identifier.uuidString)-Camera-clip.\(self._clipFilenameCount).\(self.fileExtension)"
        if let url =  CameraClip.clipURL(withFilename: filename, directoryPath: self.outputDirectory) {
            self.removeFile(fileUrl: url)
            self._clipFilenameCount += 1
            return url
        }
        return nil
    }

    internal func removeFile(fileUrl: URL) {
        if FileManager.default.fileExists(atPath: fileUrl.path) {
            do {
                try FileManager.default.removeItem(atPath: fileUrl.path)
            } catch {
                print("Camera, could not remove file at path")
            }
        }
    }
}

// MARK: - clip editing

extension CameraSession {

    /// Helper function that provides the location of the last recorded clip.
    /// This is helpful when merging multiple segments isn't desired.
    ///
    /// - Returns: URL path to the last recorded clip.
    public var lastClipUrl: URL? {
        get {
            var lastClipUrl: URL?
            if !self._clips.isEmpty,
                let lastClip = self.clips.last,
                let clipURL = lastClip.url {
                lastClipUrl = clipURL
            }
            return lastClipUrl
        }
    }

    /// Adds a specific clip to a session.
    ///
    /// - Parameter clip: Clip to be added
    public func add(clip: CameraClip) {
        self.executeClosureSyncOnSessionQueueIfNecessary {
            self._clips.append(clip)
            self._totalDuration = CMTimeAdd(self._totalDuration, clip.duration)
        }
    }

    /// Adds a specific clip to a session at the desired index.
    ///
    /// - Parameters:
    ///   - clip: Clip to be added
    ///   - idx: Index at which to add the clip
    public func add(clip: CameraClip, at idx: Int) {
        self.executeClosureSyncOnSessionQueueIfNecessary {
            self._clips.insert(clip, at: idx)
            self._totalDuration = CMTimeAdd(self._totalDuration, clip.duration)
        }
    }

    /// Removes a specific clip from a session.
    ///
    /// - Parameter clip: Clip to be removed
    public func remove(clip: CameraClip) {
        self.executeClosureSyncOnSessionQueueIfNecessary {
            if let idx = self._clips.firstIndex(where: { clipToEvaluate -> Bool in
                clip.uuid == clipToEvaluate.uuid
            }) {
                self._clips.remove(at: idx)
                self._totalDuration = CMTimeSubtract(self._totalDuration, clip.duration)
            }
        }
    }

    /// Removes a clip from a session at the desired index.
    ///
    /// - Parameters:
    ///   - idx: Index of the clip to remove
    ///   - removeFile: True to remove the associated file with the clip
    public func remove(clipAt idx: Int, removeFile: Bool) {
        self.executeClosureSyncOnSessionQueueIfNecessary {
            if self._clips.indices.contains(idx) {
                let clip = self._clips.remove(at: idx)
                self._totalDuration = CMTimeSubtract(self._totalDuration, clip.duration)

                if removeFile {
                    clip.removeFile()
                }
            }
        }
    }

    /// Removes and destroys all clips for a session.
    ///
    /// - Parameter removeFiles: When true, associated files are also removed.
    public func removeAllClips(removeFiles: Bool = true) {
        self.executeClosureAsyncOnSessionQueueIfNecessary {
            while !self._clips.isEmpty {
                if let clipToRemove = self._clips.first {
                    if removeFiles {
                        clipToRemove.removeFile()
                    }
                    self._clips.removeFirst()
                }
            }
            self._totalDuration = CMTime.zero
        }
    }

    /// Removes the last recorded clip for a session, "Undo".
    public func removeLastClip() {
        self.executeClosureSyncOnSessionQueueIfNecessary {
            if !self._clips.isEmpty,
               let clipToRemove = self.clips.last {
                self.remove(clip: clipToRemove)
            }
        }
    }

    /// Completion handler type for merging clips, optionals indicate success or failure when nil
    public typealias CameraSessionMergeClipsCompletionHandler = (_: URL?, _: Error?) -> Void

    /// Merges all existing recorded clips in the session and exports to a file.
    ///
    /// - Parameters:
    ///   - preset: AVAssetExportSession preset name for export
    ///   - completionHandler: Handler for when the merging process completes
    public func mergeClips(usingPreset preset: String, completionHandler: @escaping CameraSessionMergeClipsCompletionHandler) {
        self.executeClosureAsyncOnSessionQueueIfNecessary {
            let filename = "\(self.identifier.uuidString)-NL-merged.\(self.fileExtension)"

            let outputURL = CameraClip.clipURL(withFilename: filename, directoryPath: self.outputDirectory)
            var asset: AVAsset?

            if !self._clips.isEmpty {

                if self._clips.count == 1 {
                    debugPrint("Camera, warning, a merge was requested for a single clip, use lastClipUrl instead")
                }

                asset = self.asset

                if let exportAsset = asset, let exportURL = outputURL {
                    self.removeFile(fileUrl: exportURL)

                    if let exportSession = AVAssetExportSession(asset: exportAsset, presetName: preset) {
                        exportSession.shouldOptimizeForNetworkUse = true
                        exportSession.outputURL = exportURL
                        exportSession.outputFileType = self.fileType
                        exportSession.exportAsynchronously {
                            DispatchQueue.main.async {
                                completionHandler(exportURL, exportSession.error)
                            }
                        }
                        return
                    }
                }
            }

            DispatchQueue.main.async {
                completionHandler(nil, CameraError.unknown)
            }
        }
    }
}

// MARK: - composition

extension CameraSession {

    internal func appendClips(toComposition composition: AVMutableComposition, audioMix: AVMutableAudioMix? = nil) {
        self.executeClosureSyncOnSessionQueueIfNecessary {
            var videoTrack: AVMutableCompositionTrack?
            var audioTrack: AVMutableCompositionTrack?

            var currentTime = composition.duration

            for clip: CameraClip in self._clips {
                if let asset = clip.asset {
                    let videoAssetTracks = asset.tracks(withMediaType: AVMediaType.video)
                    let audioAssetTracks = asset.tracks(withMediaType: AVMediaType.audio)

                    var maxRange = CMTime.invalid

                    var videoTime = currentTime
                    for videoAssetTrack in videoAssetTracks {
                        if videoTrack == nil {
                            let videoTracks = composition.tracks(withMediaType: AVMediaType.video)
                            if videoTracks.count > 0 {
                                videoTrack = videoTracks.first
                            } else {
                                videoTrack = composition.addMutableTrack(withMediaType: AVMediaType.video, preferredTrackID: kCMPersistentTrackID_Invalid)
                                videoTrack?.preferredTransform = videoAssetTrack.preferredTransform
                            }
                        }

                        if let foundTrack = videoTrack {
                            videoTime = self.appendTrack(track: videoAssetTrack, toCompositionTrack: foundTrack, withStartTime: videoTime, range: maxRange)
                            maxRange = videoTime
                        }
                    }

                    if !clip.isMutedOnMerge {
                        var audioTime = currentTime
                        for audioAssetTrack in audioAssetTracks {
                        if audioTrack == nil {
                            let audioTracks = composition.tracks(withMediaType: AVMediaType.audio)

                            if audioTracks.count > 0 {
                                audioTrack = audioTracks.first
                            } else {
                                audioTrack = composition.addMutableTrack(withMediaType: AVMediaType.audio, preferredTrackID: kCMPersistentTrackID_Invalid)
                            }
                        }
                        if let foundTrack = audioTrack {
                            audioTime = self.appendTrack(track: audioAssetTrack, toCompositionTrack: foundTrack, withStartTime: audioTime, range: maxRange)
                        }
                      }
                    }

                    currentTime = composition.duration
                }
            }
        }
    }

    private func appendTrack(track: AVAssetTrack, toCompositionTrack compositionTrack: AVMutableCompositionTrack, withStartTime time: CMTime, range: CMTime) -> CMTime {
        var timeRange = track.timeRange
        let startTime = time + timeRange.start

        if range.isValid {
            let currentRange = startTime + timeRange.duration

            if currentRange > range {
                timeRange = CMTimeRange(start: timeRange.start, duration: (timeRange.duration - (currentRange - range)))
            }
        }

        if timeRange.duration > CMTime.zero {
            do {
                try compositionTrack.insertTimeRange(timeRange, of: track, at: startTime)
            } catch {
                print("Camera, failed to insert composition track")
            }
            return (startTime + timeRange.duration)
        }

        return startTime
    }

}

// MARK: - recording

extension CameraSession {
    
    /// Completion handler type for appending a sample buffer
    public typealias CameraSessionAppendSampleBufferCompletionHandler = (_: Bool) -> Void
    
    /// Append video sample buffer frames to a session for recording.
    ///
    /// - Parameters:
    ///   - sampleBuffer: Sample buffer input to be appended, unless an image buffer is also provided
    ///   - imageBuffer: Optional image buffer input for writing a custom buffer
    ///   - minFrameDuration: Current active minimum frame duration
    ///   - completionHandler: Handler when a frame appending operation completes or fails
    public func appendVideo(withSampleBuffer sampleBuffer: CMSampleBuffer, customImageBuffer: CVPixelBuffer?, minFrameDuration: CMTime, completionHandler: CameraSessionAppendSampleBufferCompletionHandler) {
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        self.startSessionIfNecessary(timestamp: timestamp)

        var frameDuration = minFrameDuration
        let offsetBufferTimestamp = CMTimeSubtract(timestamp, self._timeOffset)

        if let timeScale = self._videoConfiguration?.timescale,
            timeScale != 1.0 {
            let scaledDuration = CMTimeMultiplyByFloat64(minFrameDuration, multiplier: timeScale)
            if self._currentClipDuration.value > 0 {
                self._timeOffset = CMTimeAdd(self._timeOffset, CMTimeSubtract(minFrameDuration, scaledDuration))
            }
            frameDuration = scaledDuration
        }

        if let videoInput = self._videoInput,
            let pixelBufferAdapter = self._pixelBufferAdapter,
            videoInput.isReadyForMoreMediaData {

            var bufferToProcess: CVPixelBuffer?
            if let customImageBuffer = customImageBuffer {
                bufferToProcess = customImageBuffer
            } else {
                bufferToProcess = CMSampleBufferGetImageBuffer(sampleBuffer)
            }

            if let bufferToProcess = bufferToProcess,
                pixelBufferAdapter.append(bufferToProcess, withPresentationTime: offsetBufferTimestamp) {
                self._currentClipDuration = CMTimeSubtract(CMTimeAdd(offsetBufferTimestamp, frameDuration), self._startTimestamp)
                self._lastVideoTimestamp = timestamp
                self._currentClipHasVideo = true
                completionHandler(true)
                return
            }
        }
        completionHandler(false)
    }
    
    // Beta: appendVideo(withPixelBuffer:customImageBuffer:timestamp:minFrameDuration:completionHandler:) needs to be tested

    /// Append video pixel buffer frames to a session for recording.
    ///
    /// - Parameters:
    ///   - sampleBuffer: Sample buffer input to be appended, unless an image buffer is also provided
    ///   - customImageBuffer: Optional image buffer input for writing a custom buffer
    ///   - minFrameDuration: Current active minimum frame duration
    ///   - completionHandler: Handler when a frame appending operation completes or fails
    public func appendVideo(withPixelBuffer pixelBuffer: CVPixelBuffer, customImageBuffer: CVPixelBuffer?, timestamp: TimeInterval, minFrameDuration: CMTime, completionHandler: CameraSessionAppendSampleBufferCompletionHandler) {
        let timestamp = CMTime(seconds: timestamp, preferredTimescale: minFrameDuration.timescale)
        self.startSessionIfNecessary(timestamp: timestamp)

        var frameDuration = minFrameDuration
        let offsetBufferTimestamp = CMTimeSubtract(timestamp, self._timeOffset)

        if let timeScale = self._videoConfiguration?.timescale,
            timeScale != 1.0 {
            let scaledDuration = CMTimeMultiplyByFloat64(minFrameDuration, multiplier: timeScale)
            if self._currentClipDuration.value > 0 {
                self._timeOffset = CMTimeAdd(self._timeOffset, CMTimeSubtract(minFrameDuration, scaledDuration))
            }
            frameDuration = scaledDuration
        }

        if let videoInput = self._videoInput,
            let pixelBufferAdapter = self._pixelBufferAdapter,
            videoInput.isReadyForMoreMediaData {

            var bufferToProcess: CVPixelBuffer?
            if let customImageBuffer = customImageBuffer {
                bufferToProcess = customImageBuffer
            } else {
                bufferToProcess = pixelBuffer
            }

            if let bufferToProcess = bufferToProcess,
                pixelBufferAdapter.append(bufferToProcess, withPresentationTime: offsetBufferTimestamp) {
                self._currentClipDuration = CMTimeSubtract(CMTimeAdd(offsetBufferTimestamp, frameDuration), self._startTimestamp)
                self._lastVideoTimestamp = timestamp
                self._currentClipHasVideo = true
                completionHandler(true)
                return
            }
        }
        completionHandler(false)
    }

    /// Append audio sample buffer to a session for recording.
    ///
    /// - Parameters:
    ///   - sampleBuffer: Sample buffer input to be appended
    ///   - completionHandler: Handler when a frame appending operation completes or fails
    public func appendAudio(withSampleBuffer sampleBuffer: CMSampleBuffer, completionHandler: @escaping CameraSessionAppendSampleBufferCompletionHandler) {
        self.startSessionIfNecessary(timestamp: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        self._audioQueue.async {

            var hasFailed = false

            let buffers = self._skippedAudioBuffers + [sampleBuffer]
            self._skippedAudioBuffers = []
            var failedBuffers: [CMSampleBuffer] = []

            buffers.forEach { buffer in
                let duration = CMSampleBufferGetDuration(buffer)
                if let adjustedBuffer = CMSampleBuffer.createSampleBuffer(fromSampleBuffer: buffer, withTimeOffset: self._timeOffset, duration: duration) {
                    let presentationTimestamp = CMSampleBufferGetPresentationTimeStamp(adjustedBuffer)
                    let lastTimestamp = CMTimeAdd(presentationTimestamp, duration)

                    if let audioInput = self._audioInput,
                        audioInput.isReadyForMoreMediaData,
                        audioInput.append(adjustedBuffer) {
                        self._lastAudioTimestamp = lastTimestamp

                        if !self.currentClipHasVideo {
                            self._currentClipDuration = CMTimeSubtract(lastTimestamp, self._startTimestamp)
                        }

                        self._currentClipHasAudio = true

                    } else {
                        failedBuffers.append(buffer)
                        hasFailed = true
                    }
                }
            }

            self._skippedAudioBuffers = failedBuffers
            completionHandler(!hasFailed)
        }
    }

    /// Resets a session to the initial state.
    public func reset() {
        self.executeClosureSyncOnSessionQueueIfNecessary {
            self.endClip(completionHandler: nil)
            self._videoInput = nil
            self._audioInput = nil
            self._pixelBufferAdapter = nil
            self._skippedAudioBuffers = []
            self._videoConfiguration = nil
            self._audioConfiguration = nil
        }
    }
    
    private func startSessionIfNecessary(timestamp: CMTime) {
        if !self._startTimestamp.isValid {
            self._startTimestamp = timestamp
            self._writer?.startSession(atSourceTime: timestamp)
        }
    }
    
}

// MARK: - queues

extension CameraSession {

    internal func executeClosureAsyncOnSessionQueueIfNecessary(withClosure closure: @escaping () -> Void) {
        self._sessionQueue.async(execute: closure)
    }

    internal func executeClosureSyncOnSessionQueueIfNecessary(withClosure closure: @escaping () -> Void) {
        if DispatchQueue.getSpecific(key: self._sessionQueueKey) != nil {
            closure()
        } else {
            self._sessionQueue.sync(execute: closure)
        }
    }

}

private let CameraMetadataTitle = "CameraSwiftUIModule"
private let CameraMetadataArtist = "CameraSwiftUIModule"

extension CameraSession {

    internal class var tiffMetadata: [String: Any] {
        [ kCGImagePropertyTIFFSoftware as String: CameraMetadataTitle,
                 kCGImagePropertyTIFFArtist as String: CameraMetadataArtist,
                 kCGImagePropertyTIFFDateTime as String: Date().iso8601() ]
    }

    internal class var assetWriterMetadata: [AVMutableMetadataItem] {
        let currentDevice = UIDevice.current

        let modelItem = AVMutableMetadataItem()
        modelItem.keySpace = AVMetadataKeySpace.common
        modelItem.key = AVMetadataKey.commonKeyModel as (NSCopying & NSObjectProtocol)
        modelItem.value = currentDevice.localizedModel as (NSCopying & NSObjectProtocol)

        let softwareItem = AVMutableMetadataItem()
        softwareItem.keySpace = AVMetadataKeySpace.common
        softwareItem.key = AVMetadataKey.commonKeySoftware as (NSCopying & NSObjectProtocol)
        softwareItem.value = CameraMetadataTitle as (NSCopying & NSObjectProtocol)

        let artistItem = AVMutableMetadataItem()
        artistItem.keySpace = AVMetadataKeySpace.common
        artistItem.key = AVMetadataKey.commonKeyArtist as (NSCopying & NSObjectProtocol)
        artistItem.value = CameraMetadataArtist as (NSCopying & NSObjectProtocol)

        let creationDateItem = AVMutableMetadataItem()
        creationDateItem.keySpace = .common

        if #available(iOS 13.0, *) {
            creationDateItem.key = AVMetadataKey.commonKeyCreationDate as NSString
            creationDateItem.value = Date() as NSDate
        } else {
            creationDateItem.key = AVMetadataKey.commonKeyCreationDate as (NSCopying & NSObjectProtocol)
            creationDateItem.value = Date().iso8601() as (NSCopying & NSObjectProtocol)
        }

        return [modelItem, softwareItem, artistItem, creationDateItem]
    }

}