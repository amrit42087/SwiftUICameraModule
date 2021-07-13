//
//  CameraServiceAuthorizationStatus.swift
//  SwiftUICameraModule
//
//  Created by apple on 13.07.21.
//

import Foundation

// MARK: - types

typealias SessionSetupResult = CameraServiceAuthorizationStatus
public enum CameraServiceAuthorizationStatus: Int, CustomStringConvertible {
    case notDetermined = 0
    case notAuthorized
    case authorized
    case configurationFailed

    public var description: String {
        get {
            switch self {
            case .notDetermined:
                return "Not Determined"
            case .notAuthorized:
                return "Not Authorized"
            case .authorized:
                return "Authorized"
            case .configurationFailed:
                return "Configuration Failed!"
            }
        }
    }
}

// MARK: - error types

/// Error domain for all Next Level errors.
public let CameraErrorDomain = "CameraErrorDomain"

/// Error types.
public enum CameraError: Error, CustomStringConvertible {
    case unknown
    case started
    case deviceNotAvailable
    case authorization
    case fileExists
    case nothingRecorded
    case notReadyToRecord

    public var description: String {
        get {
            switch self {
            case .unknown:
                return "Unknown"
            case .started:
                return "Camera already started"
            case .fileExists:
                return "File exists"
            case .authorization:
                return "Authorization has not been requested"
            case .deviceNotAvailable:
                return "Device Not Available"
            case .nothingRecorded:
                return "Nothing recorded"
            case .notReadyToRecord:
                return "Camera is not ready to record"
            }
        }
    }
}
