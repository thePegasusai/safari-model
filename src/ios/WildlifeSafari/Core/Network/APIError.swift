//
// APIError.swift
// WildlifeSafari
//
// A comprehensive error type for handling API and network-related errors
// with localization support and detailed error recovery information.
//
// Foundation version: latest

import Foundation

/// A strongly-typed enumeration of all possible API and network-related errors
/// that can occur during network operations in the Wildlife Safari application.
@frozen
public enum APIError: Error, LocalizedError, Equatable {
    /// URL is malformed or invalid for the API request
    case invalidURL
    
    /// Underlying network or connectivity error with detailed system error information
    case networkError(Error)
    
    /// Request failed with specific HTTP status code for detailed error tracking
    case requestFailed(Int)
    
    /// Response data is invalid or unexpected format
    case invalidResponse
    
    /// Failed to decode response data with specific decoding error details
    case decodingError(Error)
    
    /// Authentication required or token invalid (401 errors)
    case unauthorized
    
    /// User lacks permission for requested resource (403 errors)
    case forbidden
    
    /// Requested resource not found (404 errors)
    case notFound
    
    /// API rate limit exceeded (429 errors)
    case rateLimitExceeded
    
    /// Server-side error occurred with specific error code (5xx errors)
    case serverError(Int)
    
    /// Device is offline or has no network connectivity
    case offline
    
    /// Human-readable error description with localized content for user display
    public var localizedDescription: String {
        switch self {
        case .invalidURL:
            return NSLocalizedString(
                "The URL for this request is invalid.",
                comment: "Invalid URL error description"
            )
            
        case .networkError(let error):
            return NSLocalizedString(
                "A network error occurred: \(error.localizedDescription)",
                comment: "Network error description"
            )
            
        case .requestFailed(let statusCode):
            return NSLocalizedString(
                "The request failed with status code: \(statusCode)",
                comment: "Request failed error description"
            )
            
        case .invalidResponse:
            return NSLocalizedString(
                "The server returned an invalid response.",
                comment: "Invalid response error description"
            )
            
        case .decodingError(let error):
            return NSLocalizedString(
                "Failed to process the server response: \(error.localizedDescription)",
                comment: "Decoding error description"
            )
            
        case .unauthorized:
            return NSLocalizedString(
                "Authentication is required to access this resource.",
                comment: "Unauthorized error description"
            )
            
        case .forbidden:
            return NSLocalizedString(
                "You don't have permission to access this resource.",
                comment: "Forbidden error description"
            )
            
        case .notFound:
            return NSLocalizedString(
                "The requested resource was not found.",
                comment: "Not found error description"
            )
            
        case .rateLimitExceeded:
            return NSLocalizedString(
                "You've exceeded the allowed number of requests. Please try again later.",
                comment: "Rate limit exceeded error description"
            )
            
        case .serverError(let code):
            return NSLocalizedString(
                "A server error occurred (Error \(code)). Please try again later.",
                comment: "Server error description"
            )
            
        case .offline:
            return NSLocalizedString(
                "No internet connection available.",
                comment: "Offline error description"
            )
        }
    }
    
    /// Optional localized error description conforming to LocalizedError protocol
    public var errorDescription: String? {
        return localizedDescription
    }
    
    /// Optional localized recovery suggestion for the error
    public var recoverySuggestion: String? {
        switch self {
        case .invalidURL:
            return NSLocalizedString(
                "Please check the URL and try again.",
                comment: "Invalid URL recovery suggestion"
            )
            
        case .networkError:
            return NSLocalizedString(
                "Please check your internet connection and try again.",
                comment: "Network error recovery suggestion"
            )
            
        case .requestFailed:
            return NSLocalizedString(
                "Please try again. If the problem persists, contact support.",
                comment: "Request failed recovery suggestion"
            )
            
        case .invalidResponse:
            return NSLocalizedString(
                "Please try again later. If the problem persists, update the app.",
                comment: "Invalid response recovery suggestion"
            )
            
        case .decodingError:
            return NSLocalizedString(
                "Please update to the latest version of the app.",
                comment: "Decoding error recovery suggestion"
            )
            
        case .unauthorized:
            return NSLocalizedString(
                "Please sign in again to continue.",
                comment: "Unauthorized recovery suggestion"
            )
            
        case .forbidden:
            return NSLocalizedString(
                "Please check your account permissions or contact support.",
                comment: "Forbidden recovery suggestion"
            )
            
        case .notFound:
            return NSLocalizedString(
                "Please check the resource identifier and try again.",
                comment: "Not found recovery suggestion"
            )
            
        case .rateLimitExceeded:
            return NSLocalizedString(
                "Please wait a few minutes before trying again.",
                comment: "Rate limit exceeded recovery suggestion"
            )
            
        case .serverError:
            return NSLocalizedString(
                "Our team has been notified. Please try again later.",
                comment: "Server error recovery suggestion"
            )
            
        case .offline:
            return NSLocalizedString(
                "Please check your internet connection. Some features may be available offline.",
                comment: "Offline recovery suggestion"
            )
        }
    }
    
    /// Equatable conformance implementation
    public static func == (lhs: APIError, rhs: APIError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidURL, .invalidURL),
             (.invalidResponse, .invalidResponse),
             (.unauthorized, .unauthorized),
             (.forbidden, .forbidden),
             (.notFound, .notFound),
             (.rateLimitExceeded, .rateLimitExceeded),
             (.offline, .offline):
            return true
            
        case (.networkError(let lhsError), .networkError(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
            
        case (.requestFailed(let lhsCode), .requestFailed(let rhsCode)):
            return lhsCode == rhsCode
            
        case (.decodingError(let lhsError), .decodingError(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
            
        case (.serverError(let lhsCode), .serverError(let rhsCode)):
            return lhsCode == rhsCode
            
        default:
            return false
        }
    }
}