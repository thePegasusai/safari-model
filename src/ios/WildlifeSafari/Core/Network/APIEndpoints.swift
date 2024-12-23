//
// APIEndpoints.swift
// WildlifeSafari
//
// Defines type-safe API endpoints with comprehensive security, rate limiting,
// and error handling for the Wildlife Safari iOS application.
//
// Foundation version: latest

import Foundation

/// Base URL for the Wildlife Safari API
private let BASE_URL = "https://api.wildlifesafari.com/v1"

/// Current API version
private let API_VERSION = "v1"

/// Default headers included in all API requests
private let DEFAULT_HEADERS: [String: String] = [
    "Content-Type": "application/json",
    "Accept": "application/json",
    "X-Client-Version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
    "X-API-Version": API_VERSION
]

/// Rate limits for different endpoint types (requests per minute)
private let RATE_LIMITS: [String: Int] = [
    "detection": 60,
    "collections": 120,
    "sync": 30
]

/// Type-safe HTTP methods supported by the API
@frozen
public enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case patch = "PATCH"
}

/// Request configuration options
public struct RequestOptions {
    let timeout: TimeInterval
    let cachePolicy: URLRequest.CachePolicy
    let retryCount: Int
    
    public init(
        timeout: TimeInterval = 30.0,
        cachePolicy: URLRequest.CachePolicy = .useProtocolCachePolicy,
        retryCount: Int = 3
    ) {
        self.timeout = timeout
        self.cachePolicy = cachePolicy
        self.retryCount = retryCount
    }
}

/// Type-safe API endpoint configurations
@frozen
public enum APIEndpoint {
    // Authentication
    case login(credentials: LoginCredentials)
    
    // Species Detection
    case detectSpecies(imageData: Data, location: LocationData?)
    case detectFossil(scanData: Data, metadata: ScanMetadata)
    
    // Collections Management
    case getCollections(page: Int, limit: Int)
    case createCollection(name: String, description: String?)
    case addDiscovery(discovery: DiscoveryData, collectionId: String)
    
    // Data Synchronization
    case syncData(changes: [SyncData], lastSyncTimestamp: Date)
    
    /// HTTP method for the endpoint
    private var method: HTTPMethod {
        switch self {
        case .login, .detectSpecies, .detectFossil, .createCollection, .addDiscovery:
            return .post
        case .getCollections:
            return .get
        case .syncData:
            return .put
        }
    }
    
    /// Endpoint-specific path
    private var path: String {
        switch self {
        case .login:
            return "/auth/login"
        case .detectSpecies:
            return "/detect/species"
        case .detectFossil:
            return "/detect/fossil"
        case .getCollections:
            return "/collections"
        case .createCollection:
            return "/collections"
        case .addDiscovery(_, let collectionId):
            return "/collections/\(collectionId)/discoveries"
        case .syncData:
            return "/sync"
        }
    }
    
    /// Rate limit category for the endpoint
    private var rateLimitCategory: String {
        switch self {
        case .detectSpecies, .detectFossil:
            return "detection"
        case .getCollections, .createCollection, .addDiscovery:
            return "collections"
        case .syncData:
            return "sync"
        case .login:
            return "auth"
        }
    }
    
    /// Constructs a URLRequest for the endpoint with proper configuration
    /// - Parameters:
    ///   - authToken: Optional authentication token
    ///   - options: Request configuration options
    /// - Returns: Configured URLRequest or error
    public func urlRequest(
        authToken: String? = nil,
        options: RequestOptions = RequestOptions()
    ) -> Result<URLRequest, APIError> {
        // Construct and validate base URL
        guard let baseURL = URL(string: BASE_URL),
              let url = URL(string: path, relativeTo: baseURL) else {
            return .failure(.invalidURL)
        }
        
        // Create request with URL
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.timeoutInterval = options.timeout
        request.cachePolicy = options.cachePolicy
        
        // Add default headers
        DEFAULT_HEADERS.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        
        // Add authorization if provided
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        // Add rate limiting headers
        if let rateLimit = RATE_LIMITS[rateLimitCategory] {
            request.setValue("\(rateLimit)", forHTTPHeaderField: "X-RateLimit-Limit")
        }
        
        // Configure request body
        do {
            switch self {
            case .login(let credentials):
                request.httpBody = try JSONEncoder().encode(credentials)
                
            case .detectSpecies(let imageData, let location):
                var body: [String: Any] = ["image": imageData.base64EncodedString()]
                if let location = location {
                    body["location"] = try JSONEncoder().encode(location)
                }
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                
            case .detectFossil(let scanData, let metadata):
                let body: [String: Any] = [
                    "scan_data": scanData.base64EncodedString(),
                    "metadata": try JSONEncoder().encode(metadata)
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                
            case .getCollections(let page, let limit):
                var components = URLComponents(url: url, resolvingAgainstBaseURL: true)
                components?.queryItems = [
                    URLQueryItem(name: "page", value: "\(page)"),
                    URLQueryItem(name: "limit", value: "\(limit)")
                ]
                request.url = components?.url
                
            case .createCollection(let name, let description):
                var body: [String: String] = ["name": name]
                if let description = description {
                    body["description"] = description
                }
                request.httpBody = try JSONEncoder().encode(body)
                
            case .addDiscovery(let discovery, _):
                request.httpBody = try JSONEncoder().encode(discovery)
                
            case .syncData(let changes, let timestamp):
                let body: [String: Any] = [
                    "changes": try JSONEncoder().encode(changes),
                    "last_sync": ISO8601DateFormatter().string(from: timestamp)
                ]
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
            }
        } catch {
            return .failure(.invalidResponse)
        }
        
        // Configure SSL pinning
        if let pinnedCertificates = SSLPinningManager.shared.certificates {
            request.setValue(pinnedCertificates, forHTTPHeaderField: "X-SSL-Pin")
        }
        
        // Add request signature for sensitive endpoints
        if method != .get {
            request.setValue(
                RequestSigner.sign(request: request),
                forHTTPHeaderField: "X-Request-Signature"
            )
        }
        
        return .success(request)
    }
}

// MARK: - Custom Debug Description
extension APIEndpoint: CustomDebugStringConvertible {
    public var debugDescription: String {
        return """
        APIEndpoint:
          - Method: \(method.rawValue)
          - Path: \(path)
          - Rate Limit Category: \(rateLimitCategory)
        """
    }
}

// MARK: - Request Validation
extension APIEndpoint {
    /// Validates request parameters
    private func validateParameters() -> Result<Void, APIError> {
        switch self {
        case .getCollections(let page, let limit):
            guard page > 0, limit > 0, limit <= 100 else {
                return .failure(.invalidResponse)
            }
            
        case .createCollection(let name, _):
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .failure(.invalidResponse)
            }
            
        case .detectSpecies(let imageData, _):
            guard !imageData.isEmpty, imageData.count <= 10_000_000 else {
                return .failure(.invalidResponse)
            }
            
        case .detectFossil(let scanData, _):
            guard !scanData.isEmpty, scanData.count <= 50_000_000 else {
                return .failure(.invalidResponse)
            }
            
        default:
            break
        }
        
        return .success(())
    }
}