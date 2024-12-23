//
// NetworkInterceptor.swift
// WildlifeSafari
//
// An advanced network interceptor that handles request modification, authentication,
// rate limiting, and response processing with comprehensive security features.
//
// Foundation version: latest

import Foundation

/// Constants for network configuration
private enum NetworkConstants {
    static let REQUEST_TIMEOUT: TimeInterval = 30.0
    static let MAX_RETRIES: Int = 3
    static let RATE_LIMIT_WINDOW: TimeInterval = 60.0
    static let MAX_REQUESTS_PER_WINDOW: Int = 60
    
    // Security-related constants
    static let MIN_TLS_VERSION = "TLSv1.3"
    static let SECURITY_HEADERS = [
        "X-Content-Type-Options": "nosniff",
        "X-Frame-Options": "DENY",
        "X-XSS-Protection": "1; mode=block",
        "Strict-Transport-Security": "max-age=31536000; includeSubDomains"
    ]
}

/// Advanced network interceptor for handling API requests with comprehensive security features
@available(iOS 13.0, *)
public class NetworkInterceptor {
    // MARK: - Properties
    
    private var authToken: String?
    private let session: URLSession
    private var retryCount: Int
    private var lastRequestTime: Date
    private var requestCount: Int
    private let requestQueue: DispatchQueue
    
    // MARK: - Rate Limiting
    
    private var rateLimitBucket: [(Date, Int)] = []
    private let rateLimitSemaphore = DispatchSemaphore(value: 1)
    
    // MARK: - Initialization
    
    /// Initializes the interceptor with authentication token and secure networking settings
    /// - Parameter authToken: Optional authentication token for API requests
    public init(authToken: String? = nil) {
        self.authToken = authToken
        self.retryCount = 0
        self.lastRequestTime = Date()
        self.requestCount = 0
        self.requestQueue = DispatchQueue(label: "com.wildlifesafari.networkinterceptor",
                                        qos: .userInitiated)
        
        // Configure secure URLSession
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = NetworkConstants.REQUEST_TIMEOUT
        configuration.timeoutIntervalForResource = NetworkConstants.REQUEST_TIMEOUT * 2
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv13
        configuration.httpAdditionalHeaders = NetworkConstants.SECURITY_HEADERS
        
        self.session = URLSession(configuration: configuration)
    }
    
    // MARK: - Request Interception
    
    /// Modifies and secures the request with authentication, headers, and security measures
    /// - Parameter request: Original URLRequest to be modified
    /// - Returns: Modified and secured URLRequest
    /// - Throws: APIError if request modification fails
    public func interceptRequest(_ request: URLRequest) throws -> URLRequest {
        var modifiedRequest = request
        
        // Validate request URL
        guard let url = request.url else {
            throw APIError.invalidURL
        }
        
        // Add authentication header if token exists
        if let token = authToken {
            modifiedRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        // Add security headers
        NetworkConstants.SECURITY_HEADERS.forEach { key, value in
            modifiedRequest.setValue(value, forHTTPHeaderField: key)
        }
        
        // Add rate limiting headers
        modifiedRequest.setValue(String(requestCount), forHTTPHeaderField: "X-Request-Count")
        modifiedRequest.setValue(ISO8601DateFormatter().string(from: lastRequestTime),
                               forHTTPHeaderField: "X-Last-Request-Time")
        
        // Add device identification
        modifiedRequest.setValue(UIDevice.current.identifierForVendor?.uuidString,
                               forHTTPHeaderField: "X-Device-ID")
        
        // Add request signing
        if let signature = generateRequestSignature(for: modifiedRequest) {
            modifiedRequest.setValue(signature, forHTTPHeaderField: "X-Request-Signature")
        }
        
        return modifiedRequest
    }
    
    // MARK: - Response Handling
    
    /// Processes API response with comprehensive error handling and security validation
    /// - Parameters:
    ///   - data: Response data
    ///   - response: URLResponse object
    /// - Returns: Result containing processed data or detailed error
    public func handleResponse(_ data: Data, _ response: URLResponse) -> Result<Data, APIError> {
        guard let httpResponse = response as? HTTPURLResponse else {
            return .failure(.invalidResponse)
        }
        
        // Update rate limiting state
        updateRateLimitState()
        
        // Process response based on status code
        switch httpResponse.statusCode {
        case 200...299:
            return validateAndProcessResponse(data, httpResponse)
            
        case 401:
            return .failure(.unauthorized)
            
        case 403:
            return .failure(.forbidden)
            
        case 404:
            return .failure(.notFound)
            
        case 429:
            return .failure(.rateLimitExceeded)
            
        case 500...599:
            return .failure(.serverError(httpResponse.statusCode))
            
        default:
            return .failure(.requestFailed(httpResponse.statusCode))
        }
    }
    
    // MARK: - Retry Logic
    
    /// Determines retry eligibility with sophisticated backoff strategy
    /// - Parameter error: The APIError that occurred
    /// - Returns: Boolean indicating whether to retry the request
    public func shouldRetry(for error: APIError) -> Bool {
        guard retryCount < NetworkConstants.MAX_RETRIES else {
            return false
        }
        
        // Determine if error is retryable
        let isRetryableError = isRetryableError(error)
        
        if isRetryableError {
            retryCount += 1
            
            // Calculate exponential backoff delay
            let delay = calculateBackoffDelay()
            Thread.sleep(forTimeInterval: delay)
            
            return true
        }
        
        return false
    }
    
    // MARK: - Private Helper Methods
    
    private func generateRequestSignature(for request: URLRequest) -> String? {
        // Implementation of request signing using HMAC-SHA256
        // This is a placeholder - actual implementation would use secure cryptographic functions
        return nil
    }
    
    private func validateAndProcessResponse(_ data: Data, _ response: HTTPURLResponse) -> Result<Data, APIError> {
        // Verify response signature if present
        if let signature = response.value(forHTTPHeaderField: "X-Response-Signature") {
            guard validateResponseSignature(signature, for: data) else {
                return .failure(.invalidResponse)
            }
        }
        
        return .success(data)
    }
    
    private func validateResponseSignature(_ signature: String, for data: Data) -> Bool {
        // Implementation of response signature validation
        // This is a placeholder - actual implementation would use secure cryptographic functions
        return true
    }
    
    private func updateRateLimitState() {
        rateLimitSemaphore.wait()
        defer { rateLimitSemaphore.signal() }
        
        let now = Date()
        
        // Remove expired entries
        rateLimitBucket = rateLimitBucket.filter {
            now.timeIntervalSince($0.0) < NetworkConstants.RATE_LIMIT_WINDOW
        }
        
        // Add new request
        rateLimitBucket.append((now, 1))
        
        // Update tracking properties
        lastRequestTime = now
        requestCount = rateLimitBucket.reduce(0) { $0 + $1.1 }
    }
    
    private func isRetryableError(_ error: APIError) -> Bool {
        switch error {
        case .networkError, .serverError, .requestFailed:
            return true
        case .rateLimitExceeded:
            return false
        default:
            return false
        }
    }
    
    private func calculateBackoffDelay() -> TimeInterval {
        // Exponential backoff with jitter
        let baseDelay = 0.1 // 100ms
        let maxDelay = 10.0 // 10 seconds
        let exponentialDelay = baseDelay * pow(2.0, Double(retryCount - 1))
        let jitter = Double.random(in: 0...0.1)
        return min(maxDelay, exponentialDelay + jitter)
    }
}