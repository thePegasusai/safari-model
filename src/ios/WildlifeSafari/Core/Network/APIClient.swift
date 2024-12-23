//
// APIClient.swift
// WildlifeSafari
//
// A robust networking client that handles API communication with comprehensive
// offline support, security features, and error handling.
//
// Foundation version: latest
// Combine version: latest

import Foundation
import Combine

/// Global constants for network configuration
private enum Constants {
    static let NETWORK_TIMEOUT: TimeInterval = 30.0
    static let MAX_RETRY_ATTEMPTS: Int = 3
    static let OFFLINE_QUEUE_LIMIT: Int = 1000
    static let UPLOAD_CHUNK_SIZE: Int = 524288 // 512KB
}

/// Represents the upload progress and status
public struct UploadProgress {
    let bytesUploaded: Int64
    let totalBytes: Int64
    let progress: Double
}

/// Represents offline operation configuration
public struct OfflinePolicy {
    let priority: Operation.QueuePriority
    let requiresWiFi: Bool
    let expirationInterval: TimeInterval?
    let conflictResolution: ConflictResolution
    
    public enum ConflictResolution {
        case serverWins
        case clientWins
        case lastWriteWins
        case manual
    }
}

/// A comprehensive networking client for the Wildlife Safari application
@available(iOS 13.0, *)
public class APIClient {
    // MARK: - Properties
    
    private let session: URLSession
    private let interceptor: NetworkInterceptor
    private let responseQueue: DispatchQueue
    private let offlineQueue: OperationQueue
    private let persistenceQueue: DatabaseQueue
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    /// Initializes the API client with comprehensive configuration
    /// - Parameters:
    ///   - authToken: Optional authentication token
    ///   - configuration: URLSession configuration
    ///   - operationQueue: Optional custom operation queue for offline operations
    public init(
        authToken: String? = nil,
        configuration: URLSessionConfiguration = .default,
        operationQueue: OperationQueue? = nil
    ) {
        // Configure URLSession with security settings
        let config = configuration
        config.timeoutIntervalForRequest = Constants.NETWORK_TIMEOUT
        config.timeoutIntervalForResource = Constants.NETWORK_TIMEOUT * 2
        config.tlsMinimumSupportedProtocolVersion = .TLSv13
        config.httpAdditionalHeaders = NetworkConstants.SECURITY_HEADERS
        
        self.session = URLSession(configuration: config)
        self.interceptor = NetworkInterceptor(authToken: authToken)
        self.responseQueue = DispatchQueue(label: "com.wildlifesafari.apiclient",
                                         qos: .userInitiated,
                                         attributes: .concurrent)
        
        // Configure offline operation queue
        self.offlineQueue = operationQueue ?? {
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = 1
            queue.qualityOfService = .utility
            return queue
        }()
        
        // Initialize persistence queue for offline storage
        self.persistenceQueue = DatabaseQueue(path: "offline_operations.db")
        
        // Setup background task handling
        setupBackgroundTaskHandling()
    }
    
    // MARK: - Public API
    
    /// Executes an API request with comprehensive error handling and offline support
    /// - Parameters:
    ///   - endpoint: The API endpoint to request
    ///   - retryPolicy: Optional retry policy for failed requests
    ///   - allowOfflineOperation: Whether to allow offline operation queueing
    /// - Returns: A publisher emitting the decoded response or error
    @discardableResult
    public func request<T: Decodable>(
        _ endpoint: APIEndpoint,
        retryPolicy: RetryPolicy? = nil,
        allowOfflineOperation: Bool = true
    ) -> AnyPublisher<T, APIError> {
        // Check rate limiting
        guard !isRateLimited(for: endpoint) else {
            return Fail(error: .rateLimitExceeded).eraseToAnyPublisher()
        }
        
        // Create URLRequest
        let requestResult = endpoint.urlRequest()
        
        switch requestResult {
        case .success(var urlRequest):
            // Apply interceptor modifications
            do {
                urlRequest = try interceptor.interceptRequest(urlRequest)
            } catch {
                return Fail(error: error as? APIError ?? .invalidResponse)
                    .eraseToAnyPublisher()
            }
            
            // Check network connectivity
            guard NetworkReachability.shared.isReachable else {
                if allowOfflineOperation {
                    handleOfflineOperation(endpoint: endpoint, data: urlRequest.httpBody)
                    return Empty().eraseToAnyPublisher()
                } else {
                    return Fail(error: .offline).eraseToAnyPublisher()
                }
            }
            
            // Execute request with retry logic
            return session.dataTaskPublisher(for: urlRequest)
                .retry(retryPolicy?.maxRetries ?? Constants.MAX_RETRY_ATTEMPTS)
                .tryMap { [weak self] data, response -> Data in
                    guard let self = self else { throw APIError.invalidResponse }
                    
                    let result = self.interceptor.handleResponse(data, response)
                    switch result {
                    case .success(let responseData):
                        return responseData
                    case .failure(let error):
                        throw error
                    }
                }
                .decode(type: T.self, decoder: JSONDecoder())
                .mapError { error -> APIError in
                    if let apiError = error as? APIError {
                        return apiError
                    }
                    return error is DecodingError ? .decodingError(error) : .invalidResponse
                }
                .receive(on: responseQueue)
                .handleEvents(
                    receiveOutput: { [weak self] _ in
                        self?.updateRateLimitToken(for: endpoint)
                    },
                    receiveCompletion: { [weak self] completion in
                        if case .failure(let error) = completion {
                            self?.handleRequestError(error, endpoint: endpoint)
                        }
                    }
                )
                .eraseToAnyPublisher()
            
        case .failure(let error):
            return Fail(error: error).eraseToAnyPublisher()
        }
    }
    
    /// Handles secure data uploads with progress tracking and resume capability
    /// - Parameters:
    ///   - data: The data to upload
    ///   - endpoint: The upload endpoint
    ///   - progressHandler: Optional handler for upload progress updates
    /// - Returns: A publisher emitting upload status or error
    public func uploadData(
        _ data: Data,
        to endpoint: APIEndpoint,
        progressHandler: ((UploadProgress) -> Void)? = nil
    ) -> AnyPublisher<Void, APIError> {
        // Validate data size
        guard data.count > 0 else {
            return Fail(error: .invalidResponse).eraseToAnyPublisher()
        }
        
        // Create upload request
        let requestResult = endpoint.urlRequest()
        
        switch requestResult {
        case .success(var urlRequest):
            // Configure for upload
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            urlRequest.setValue("\(data.count)", forHTTPHeaderField: "Content-Length")
            
            // Handle chunked upload for large files
            if data.count > Constants.UPLOAD_CHUNK_SIZE {
                return uploadLargeData(data, request: urlRequest, progressHandler: progressHandler)
            }
            
            // Standard upload for smaller files
            return session.uploadTaskPublisher(for: urlRequest, from: data)
                .tryMap { [weak self] data, response -> Void in
                    guard let self = self else { throw APIError.invalidResponse }
                    
                    let result = self.interceptor.handleResponse(data, response)
                    switch result {
                    case .success:
                        return ()
                    case .failure(let error):
                        throw error
                    }
                }
                .mapError { $0 as? APIError ?? .networkError($0) }
                .receive(on: responseQueue)
                .eraseToAnyPublisher()
            
        case .failure(let error):
            return Fail(error: error).eraseToAnyPublisher()
        }
    }
    
    // MARK: - Private Helpers
    
    private func uploadLargeData(
        _ data: Data,
        request: URLRequest,
        progressHandler: ((UploadProgress) -> Void)?
    ) -> AnyPublisher<Void, APIError> {
        // Implementation for chunked upload with resume capability
        // This is a placeholder - actual implementation would handle chunked uploads
        fatalError("Chunked upload not implemented")
    }
    
    private func handleOfflineOperation(
        endpoint: APIEndpoint,
        data: Data? = nil
    ) {
        persistenceQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Check queue limit
            if self.offlineQueue.operationCount >= Constants.OFFLINE_QUEUE_LIMIT {
                // Remove oldest non-executing operation
                self.offlineQueue.operations
                    .filter { !$0.isExecuting }
                    .sorted { $0.queuePriority.rawValue < $1.queuePriority.rawValue }
                    .first?
                    .cancel()
            }
            
            // Create and configure offline operation
            let operation = NetworkOperation(endpoint: endpoint, data: data)
            operation.completionBlock = { [weak self] in
                self?.handleOperationCompletion(operation)
            }
            
            // Add to queue
            self.offlineQueue.addOperation(operation)
        }
    }
    
    private func setupBackgroundTaskHandling() {
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in
                self?.persistOfflineQueue()
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.restoreOfflineQueue()
            }
            .store(in: &cancellables)
    }
    
    private func persistOfflineQueue() {
        // Persist pending operations to disk
        // This is a placeholder - actual implementation would persist queue state
    }
    
    private func restoreOfflineQueue() {
        // Restore pending operations from disk
        // This is a placeholder - actual implementation would restore queue state
    }
    
    private func isRateLimited(for endpoint: APIEndpoint) -> Bool {
        // Check rate limiting based on endpoint configuration
        // This is a placeholder - actual implementation would track rate limits
        return false
    }
    
    private func updateRateLimitToken(for endpoint: APIEndpoint) {
        // Update rate limiting tokens after successful request
        // This is a placeholder - actual implementation would update rate limit state
    }
    
    private func handleRequestError(_ error: APIError, endpoint: APIEndpoint) {
        // Log error and handle retry/offline queue if needed
        // This is a placeholder - actual implementation would handle errors
    }
    
    private func handleOperationCompletion(_ operation: NetworkOperation) {
        // Handle completion of offline operation
        // This is a placeholder - actual implementation would handle operation completion
    }
}

// MARK: - Supporting Types

private class NetworkOperation: Operation {
    let endpoint: APIEndpoint
    let data: Data?
    
    init(endpoint: APIEndpoint, data: Data?) {
        self.endpoint = endpoint
        self.data = data
        super.init()
    }
    
    override func main() {
        // Execute network operation
        // This is a placeholder - actual implementation would execute the operation
    }
}

private class DatabaseQueue {
    init(path: String) {
        // Initialize database queue
        // This is a placeholder - actual implementation would initialize database
    }
    
    func async(_ block: @escaping () -> Void) {
        // Execute block asynchronously
        DispatchQueue.global(qos: .utility).async(execute: block)
    }
}