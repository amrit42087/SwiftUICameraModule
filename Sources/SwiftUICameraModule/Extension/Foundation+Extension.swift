//
//  Foundation+Extension.swift
//  SwiftUICameraModule
//
//  Created by apple on 13.07.21.
//

import Foundation

import Foundation
import AVFoundation

// MARK: - FileManager

extension FileManager {

    /// Returns the available user designated storage space in bytes.
    ///
    /// - Returns: Number of available bytes in storage.
    public class func availableStorageSpaceInBytes() -> UInt64 {
        do {
            if let lastPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).last {
                let attributes = try FileManager.default.attributesOfFileSystem(forPath: lastPath)
                if let freeSize = attributes[FileAttributeKey.systemFreeSize] as? UInt64 {
                    return freeSize
                }
            }
        } catch {
            print("could not determine user attributes of file system")
            return 0
        }
        return 0
    }

}

// MARK: - Comparable

extension Comparable {

    public func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }

}

// MARK: - Data

extension Data {

    /// Outputs a `Data` object with the desired metadata dictionary
    ///
    /// - Parameter metadata: metadata dictionary to be added
    /// - Returns: JPEG formatted image data
    public func jpegData(withMetadataDictionary metadata: [String: Any]) -> Data? {
        var imageDataWithMetadata: Data?
        if let source = CGImageSourceCreateWithData(self as CFData, nil),
            let sourceType = CGImageSourceGetType(source) {
            let mutableData = NSMutableData()
            if let destination = CGImageDestinationCreateWithData(mutableData, sourceType, 1, nil) {
                CGImageDestinationAddImageFromSource(destination, source, 0, metadata as CFDictionary?)
                let success = CGImageDestinationFinalize(destination)
                if success == true {
                    imageDataWithMetadata = mutableData as Data
                } else {
                    print("could not finalize image with metadata")
                }
            }
        }
        return imageDataWithMetadata
    }

}

// MARK: - Date

extension Date {

    static let dateFormatter: DateFormatter = iso8601DateFormatter()
    fileprivate static func iso8601DateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .iso8601)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZZZZZ"
        return formatter
    }

    // http://nshipster.com/nsformatter/
    // http://unicode.org/reports/tr35/tr35-6.html#Date_Format_Patterns
    public func iso8601() -> String {
        Date.iso8601DateFormatter().string(from: self)
    }

}
