//
//  CameraClip.swift
//  SwiftUICameraModule
//
//  Created by apple on 13.07.21.
//

import UIKit
import Foundation
import AVFoundation

// CameraClip dictionary representation keys

public let CameraClipFilenameKey = "CameraClipFilenameKey"
public let CameraClipInfoDictKey = "CameraClipInfoDictKey"

/// CameraClip, an object for managing a single media clip
public class CameraClip {

    /// Unique identifier for a clip
    public var uuid: UUID {
        get {
            self._uuid
        }
    }

    /// URL of the clip
    public var url: URL? {
        didSet {
            self._asset = nil
        }
    }

    /// True, if the clip's file exists
    public var fileExists: Bool {
        get {
            if let url = self.url {
                return FileManager.default.fileExists(atPath: url.path)
            }
            return false
        }
    }

    /// `AVAsset` of the clip
    public var asset: AVAsset? {
        get {
            if let url = self.url {
                if self._asset == nil {
                    self._asset = AVAsset(url: url)
                }
            }
            return self._asset
        }
    }

    /// Duration of the clip, otherwise invalid.
    public var duration: CMTime {
        get {
            self.asset?.duration ?? CMTime.zero
        }
    }

    /// Set to true if the clip's audio should be muted in the merged file
    public var isMutedOnMerge = false

    /// If it doesn't already exist, generates a thumbnail image of the clip.
    public var thumbnailImage: UIImage? {
        get {
            guard self._thumbnailImage == nil else {
                return self._thumbnailImage
            }

            if let asset = self.asset {
                let imageGenerator: AVAssetImageGenerator = AVAssetImageGenerator(asset: asset)
                imageGenerator.appliesPreferredTrackTransform = true

                do {
                    let cgimage: CGImage = try imageGenerator.copyCGImage(at: CMTime.zero, actualTime: nil)
                    let uiimage: UIImage = UIImage(cgImage: cgimage)
                    self._thumbnailImage = uiimage
                } catch {
                    print("Camera, unable to generate lastFrameImage for \(String(describing: self.url?.absoluteString)))")
                    self._thumbnailImage = nil
                }
            }
            return self._thumbnailImage
        }
    }

    /// If it doesn't already exist, generates an image for the last frame of the clip.
    public var lastFrameImage: UIImage? {
        get {
            guard self._lastFrameImage == nil,
                  let asset = self.asset
            else {
                return self._lastFrameImage
            }

            let imageGenerator: AVAssetImageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true

            do {
                let cgimage: CGImage = try imageGenerator.copyCGImage(at: self.duration, actualTime: nil)
                let uiimage: UIImage = UIImage(cgImage: cgimage)
                self._lastFrameImage = uiimage
            } catch {
                print("Camera, unable to generate lastFrameImage for \(String(describing: self.url?.absoluteString))")
                self._lastFrameImage = nil
            }

            return self._lastFrameImage
        }
    }

    /// Frame rate at which the asset was recorded.
    public var frameRate: Float {
        get {
            if let tracks = self.asset?.tracks(withMediaType: AVMediaType.video),
                tracks.isEmpty == false {
                if let videoTrack = tracks.first {
                    return videoTrack.nominalFrameRate
                }
            }
            return 0
        }
    }

    /// Dictionary containing metadata about the clip.
    public var infoDict: [String: Any]? {
        get {
            self._infoDict
        }
    }

    /// Dictionary containing data for re-initialization of the clip.
    public var representationDict: [String: Any]? {
        get {
            if let infoDict = self.infoDict,
               let url = self.url {
                return [CameraClipFilenameKey: url.lastPathComponent,
                        CameraClipInfoDictKey: infoDict]
            } else if let url = self.url {
                return [CameraClipFilenameKey: url.lastPathComponent]
            } else {
                return nil
            }
        }
    }

    // MARK: - class functions

    /// Class method initializer for a clip URL
    ///
    /// - Parameters:
    ///   - filename: Filename for the media asset
    ///   - directoryPath: Directory path for the media asset
    /// - Returns: Returns a URL for the designated clip, otherwise nil
    public class func clipURL(withFilename filename: String, directoryPath: String) -> URL? {
        var clipURL = URL(fileURLWithPath: directoryPath)
        clipURL.appendPathComponent(filename)
        return clipURL
    }

    /// Class method initializer for a CameraClip
    ///
    /// - Parameters:
    ///   - url: URL of the media asset
    ///   - infoDict: Dictionary containing metadata about the clip
    /// - Returns: Returns a CameraClip
    public class func clip(withUrl url: URL?, infoDict: [String: Any]?) -> CameraClip {
        CameraClip(url: url, infoDict: infoDict)
    }

    // MARK: - private instance vars

    internal var _uuid: UUID = UUID()
    internal var _asset: AVAsset?
    internal var _infoDict: [String: Any]?
    internal var _thumbnailImage: UIImage?
    internal var _lastFrameImage: UIImage?

    // MARK: - object lifecycle

    /// Initialize a clip from a URL and dictionary.
    ///
    /// - Parameters:
    ///   - url: URL and filename of the specified media asset
    ///   - infoDict: Dictionary with CameraClip metadata information
    public convenience init(url: URL?, infoDict: [String: Any]?) {
        self.init()
        self.url = url
        self._infoDict = infoDict
    }

    /// Initialize a clip from a dictionary representation and directory name
    ///
    /// - Parameters:
    ///   - directoryPath: Directory where the media asset is located
    ///   - representationDict: Dictionary containing defining metadata about the clip
    public convenience init(directoryPath: String, representationDict: [String: Any]?) {
        if let clipDict = representationDict,
           let filename = clipDict[CameraClipFilenameKey] as? String,
           let url: URL = CameraClip.clipURL(withFilename: filename, directoryPath: directoryPath) {
            let infoDict = clipDict[CameraClipInfoDictKey] as? [String: Any]
            self.init(url: url, infoDict: infoDict)
        } else {
            self.init()
        }
    }

    deinit {
        self._asset = nil
        self._infoDict = nil
        self._thumbnailImage = nil
        self._lastFrameImage = nil
    }

    // MARK: - functions

    /// Removes the associated file representation on disk.
    public func removeFile() {
        do {
            if let url = self.url {
                try FileManager.default.removeItem(at: url)
                self.url = nil
            }
        } catch {
            print("Camera, error deleting a clip's file \(String(describing: self.url?.absoluteString))")
        }
    }

}
