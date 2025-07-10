//
//  WLEDAPIError.swift
//  Aesdetic-Control
//
//  Created by Aesdetic Control Team on 1/27/25.
//

import Foundation

// MARK: - WLED API Error Handling

/// Comprehensive error handling for WLED API operations
enum WLEDAPIError: LocalizedError {
    case networkError(Error)
    case invalidResponse
    case httpError(Int)
    case decodingError(Error)
    case encodingError(Error)
    case deviceOffline(String)
    case deviceUnreachable(String)
    case timeout
    case invalidURL
    case maxRetriesExceeded
    case unsupportedOperation(String)
    case deviceBusy(String)
    case invalidConfiguration
    
    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from device"
        case .httpError(let statusCode):
            return httpErrorMessage(for: statusCode)
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .encodingError(let error):
            return "Failed to encode request: \(error.localizedDescription)"
        case .deviceOffline(let deviceName):
            return "Device '\(deviceName)' is offline or unreachable"
        case .deviceUnreachable(let deviceName):
            return "Unable to reach device '\(deviceName)'. Check network connection."
        case .timeout:
            return "Request timed out. Device may be busy or network is slow."
        case .invalidURL:
            return "Invalid device URL configuration"
        case .maxRetriesExceeded:
            return "Maximum retry attempts exceeded. Device may be temporarily unavailable."
        case .unsupportedOperation(let operation):
            return "Operation '\(operation)' is not supported by this device"
        case .deviceBusy(let deviceName):
            return "Device '\(deviceName)' is busy processing another request"
        case .invalidConfiguration:
            return "Invalid API configuration. Check your settings."
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .deviceOffline, .deviceUnreachable:
            return "Ensure the device is powered on and connected to the same WiFi network."
        case .timeout:
            return "Check your network connection or try again in a moment."
        case .httpError(let statusCode) where statusCode >= 500:
            return "The device may be experiencing issues. Try restarting the device."
        case .maxRetriesExceeded, .deviceBusy:
            return "Wait a moment and try again. The device may be temporarily busy."
        case .invalidURL, .invalidConfiguration:
            return "Check your device settings and network configuration."
        case .unsupportedOperation:
            return "This feature may require a newer version of WLED firmware."
        default:
            return nil
        }
    }
    
    var errorCode: Int {
        switch self {
        case .networkError: return 1001
        case .invalidResponse: return 1002
        case .httpError(let statusCode): return statusCode
        case .decodingError: return 1003
        case .encodingError: return 1004
        case .deviceOffline: return 1005
        case .deviceUnreachable: return 1006
        case .timeout: return 1007
        case .invalidURL: return 1008
        case .maxRetriesExceeded: return 1009
        case .unsupportedOperation: return 1010
        case .deviceBusy: return 1011
        case .invalidConfiguration: return 1012
        }
    }
    
    /// Determines if this error type is retryable
    var isRetryable: Bool {
        switch self {
        case .networkError, .timeout, .deviceBusy:
            return true
        case .httpError(let statusCode):
            return statusCode >= 500 // Only retry server errors
        case .maxRetriesExceeded:
            return false // Already exhausted retries
        case .invalidURL, .invalidResponse, .decodingError, .encodingError, .invalidConfiguration, .unsupportedOperation:
            return false // Configuration or format issues won't be fixed by retrying
        case .deviceOffline, .deviceUnreachable:
            return true // May come back online
        }
    }
    
    private func httpErrorMessage(for statusCode: Int) -> String {
        switch statusCode {
        case 400:
            return "Bad request (HTTP 400). Check the request format."
        case 401:
            return "Unauthorized (HTTP 401). Device may require authentication."
        case 403:
            return "Forbidden (HTTP 403). Access denied to device."
        case 404:
            return "Not found (HTTP 404). Endpoint may not be supported."
        case 405:
            return "Method not allowed (HTTP 405). Check request method."
        case 408:
            return "Request timeout (HTTP 408). Device took too long to respond."
        case 409:
            return "Conflict (HTTP 409). Device may be in an invalid state."
        case 429:
            return "Too many requests (HTTP 429). Device is rate limiting."
        case 500:
            return "Internal server error (HTTP 500). Device firmware issue."
        case 502:
            return "Bad gateway (HTTP 502). Network routing issue."
        case 503:
            return "Service unavailable (HTTP 503). Device is temporarily unavailable."
        case 504:
            return "Gateway timeout (HTTP 504). Network timeout occurred."
        default:
            if statusCode >= 400 && statusCode < 500 {
                return "Client error (HTTP \(statusCode)). Check device compatibility."
            } else if statusCode >= 500 {
                return "Server error (HTTP \(statusCode)). Device may be experiencing issues."
            } else {
                return "HTTP error: \(statusCode)"
            }
        }
    }
    
    /// Create WLEDAPIError from generic Error with device context
    static func from(_ error: Error, device: WLEDDevice) -> WLEDAPIError {
        if let apiError = error as? WLEDAPIError {
            return apiError
        }
        
        if error is DecodingError {
            return .decodingError(error)
        }
        
        if error is EncodingError {
            return .encodingError(error)
        }
        
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return .timeout
            case .notConnectedToInternet, .networkConnectionLost:
                return .deviceOffline(device.name)
            case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                return .deviceUnreachable(device.name)
            case .badURL, .unsupportedURL:
                return .invalidURL
            case .resourceUnavailable:
                return .deviceBusy(device.name)
            default:
                return .networkError(urlError)
            }
        }
        
        return .networkError(error)
    }
}

// MARK: - Error Retry Strategy

/// Strategy for determining retry behavior
struct WLEDRetryStrategy {
    let maxRetries: Int
    let baseDelay: TimeInterval
    let maxDelay: TimeInterval
    let backoffMultiplier: Double
    
    static let `default` = WLEDRetryStrategy(
        maxRetries: 3,
        baseDelay: 1.0,
        maxDelay: 10.0,
        backoffMultiplier: 2.0
    )
    
    static let aggressive = WLEDRetryStrategy(
        maxRetries: 5,
        baseDelay: 0.5,
        maxDelay: 8.0,
        backoffMultiplier: 1.5
    )
    
    static let conservative = WLEDRetryStrategy(
        maxRetries: 2,
        baseDelay: 2.0,
        maxDelay: 15.0,
        backoffMultiplier: 3.0
    )
    
    /// Calculate delay for a specific retry attempt
    func delayForAttempt(_ attempt: Int) -> TimeInterval {
        let exponentialDelay = baseDelay * pow(backoffMultiplier, Double(attempt - 1))
        return min(exponentialDelay, maxDelay)
    }
    
    /// Determine if error should be retried for given attempt number
    func shouldRetry(error: WLEDAPIError, attempt: Int) -> Bool {
        return attempt <= maxRetries && error.isRetryable
    }
} 