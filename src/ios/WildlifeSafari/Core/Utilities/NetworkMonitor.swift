//
// NetworkMonitor.swift
// WildlifeSafari
//
// A comprehensive network connectivity monitor that provides real-time network status tracking,
// connection quality monitoring, and intelligent offline mode management.
//
// Network version: latest
// Foundation version: latest
// Combine version: latest

import Network
import Foundation
import Combine

/// Global constants for network monitoring configuration
private enum Constants {
    static let NETWORK_CHECK_INTERVAL: TimeInterval = 5.0
    static let MAX_RETRY_ATTEMPTS: Int = 3
    static let CONNECTION_POOL_SIZE: Int = 5
    static let OFFLINE_THRESHOLD_MS: TimeInterval = 1500.0
}

/// Represents different types of network connections
public enum NetworkType: String {
    case wifi = "WiFi"
    case cellular = "Cellular"
    case ethernet = "Ethernet"
    case loopback = "Loopback"
    case unknown = "Unknown"
}

/// Represents network connection quality levels
public enum NetworkQuality: Int {
    case poor = 0
    case fair = 1
    case good = 2
    case excellent = 3
    
    var description: String {
        switch self {
        case .poor: return "Poor"
        case .fair: return "Fair"
        case .good: return "Good"
        case .excellent: return "Excellent"
        }
    }
}

/// Configuration for connection pooling
public struct ConnectionPoolConfig {
    let poolSize: Int
    let validateInterval: TimeInterval
    let timeoutInterval: TimeInterval
    
    public init(
        poolSize: Int = Constants.CONNECTION_POOL_SIZE,
        validateInterval: TimeInterval = Constants.NETWORK_CHECK_INTERVAL,
        timeoutInterval: TimeInterval = Constants.OFFLINE_THRESHOLD_MS
    ) {
        self.poolSize = poolSize
        self.validateInterval = validateInterval
        self.timeoutInterval = timeoutInterval
    }
}

/// Configuration for network security validation
public struct SecurityConfig {
    let validateCertificates: Bool
    let minimumTLSVersion: String
    let requiredSecurityLevel: NWParameters.TLSConfiguration.Level
    
    public init(
        validateCertificates: Bool = true,
        minimumTLSVersion: String = "TLSv1.3",
        requiredSecurityLevel: NWParameters.TLSConfiguration.Level = .negotiated
    ) {
        self.validateCertificates = validateCertificates
        self.minimumTLSVersion = minimumTLSVersion
        self.requiredSecurityLevel = requiredSecurityLevel
    }
}

/// A comprehensive network connectivity monitor
@available(iOS 13.0, *)
public class NetworkMonitor {
    // MARK: - Properties
    
    private let monitor: NWPathMonitor
    private let monitorQueue: DispatchQueue
    private var cancellables = Set<AnyCancellable>()
    
    // Publishers for network status
    public let isConnected = CurrentValueSubject<Bool, Never>(false)
    public let connectionType = CurrentValueSubject<NetworkType, Never>(.unknown)
    public let connectionQuality = CurrentValueSubject<NetworkQuality, Never>(.poor)
    
    // Connection management
    private var connectionPool: [NWConnection] = []
    private let poolConfig: ConnectionPoolConfig
    private let securityConfig: SecurityConfig
    
    // Metrics tracking
    private var metrics = NetworkMetrics()
    private var lastPathUpdate = Date()
    
    // MARK: - Initialization
    
    /// Initializes the network monitor with enhanced configuration
    /// - Parameters:
    ///   - poolConfig: Configuration for connection pooling
    ///   - securityConfig: Configuration for security validation
    public init(
        poolConfig: ConnectionPoolConfig = ConnectionPoolConfig(),
        securityConfig: SecurityConfig = SecurityConfig()
    ) {
        self.poolConfig = poolConfig
        self.securityConfig = securityConfig
        
        self.monitor = NWPathMonitor()
        self.monitorQueue = DispatchQueue(label: "com.wildlifesafari.networkmonitor",
                                        qos: .userInitiated)
        
        setupMonitoring()
    }
    
    // MARK: - Public Methods
    
    /// Starts network monitoring with enhanced features
    public func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            
            // Update connection status
            let isConnected = path.status == .satisfied
            self.isConnected.send(isConnected)
            
            // Update connection type
            let networkType = self.determineNetworkType(from: path)
            self.connectionType.send(networkType)
            
            // Monitor connection quality
            self.monitorConnectionQuality(path: path)
            
            // Handle network transition
            self.handleNetworkTransition(
                previousState: self.isConnected.value,
                newState: isConnected
            )
            
            // Update metrics
            self.updateMetrics(path: path)
        }
        
        // Start monitoring on dedicated queue
        monitor.start(queue: monitorQueue)
        
        // Initialize connection pool
        initializeConnectionPool()
        
        // Start periodic validation
        startPeriodicValidation()
    }
    
    /// Stops network monitoring and cleans up resources
    public func stopMonitoring() {
        monitor.cancel()
        connectionPool.forEach { $0.cancel() }
        connectionPool.removeAll()
        cancellables.removeAll()
    }
    
    // MARK: - Private Methods
    
    private func setupMonitoring() {
        // Configure security parameters
        let parameters = NWParameters()
        parameters.tls = .init(configuration: .init())
        parameters.tls?.minimumTLSVersion = .TLSv13
        parameters.tls?.maximumTLSVersion = .TLSv13
        
        // Setup automatic retry mechanism
        setupRetryMechanism()
    }
    
    private func determineNetworkType(from path: NWPath) -> NetworkType {
        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            return .ethernet
        } else if path.usesInterfaceType(.loopback) {
            return .loopback
        }
        return .unknown
    }
    
    private func monitorConnectionQuality(path: NWPath) {
        let quality: NetworkQuality
        
        switch path.quality {
        case .poor:
            quality = .poor
        case .good:
            quality = .good
        case .excellent:
            quality = .excellent
        default:
            quality = .fair
        }
        
        connectionQuality.send(quality)
    }
    
    private func handleNetworkTransition(previousState: Bool, newState: Bool) {
        if !previousState && newState {
            // Network became available
            APIClient.retryOperation()
            validateConnections()
        } else if previousState && !newState {
            // Network became unavailable
            handleOfflineMode()
        }
    }
    
    private func initializeConnectionPool() {
        guard connectionPool.isEmpty else { return }
        
        for _ in 0..<poolConfig.poolSize {
            let connection = createSecureConnection()
            connectionPool.append(connection)
        }
    }
    
    private func createSecureConnection() -> NWConnection {
        let parameters = NWParameters.tls
        parameters.tls?.minimumTLSVersion = .TLSv13
        parameters.tls?.maximumTLSVersion = .TLSv13
        
        let connection = NWConnection(
            host: "api.wildlifesafari.com",
            port: 443,
            using: parameters
        )
        
        connection.stateUpdateHandler = { [weak self] state in
            self?.handleConnectionStateUpdate(connection: connection, state: state)
        }
        
        return connection
    }
    
    private func handleConnectionStateUpdate(connection: NWConnection, state: NWConnection.State) {
        switch state {
        case .ready:
            metrics.successfulConnections += 1
        case .failed(let error):
            metrics.failedConnections += 1
            handleConnectionError(error)
        case .waiting(let error):
            metrics.waitingConnections += 1
            handleConnectionError(error)
        default:
            break
        }
    }
    
    private func validateConnections() {
        connectionPool.forEach { connection in
            APIClient.validateConnection(connection) { [weak self] result in
                switch result {
                case .success:
                    self?.metrics.validConnections += 1
                case .failure(let error):
                    self?.handleConnectionError(error)
                }
            }
        }
    }
    
    private func handleOfflineMode() {
        // Notify system of offline mode
        APIClient.handleOfflineOperation(endpoint: .syncData(changes: [], lastSyncTimestamp: Date()))
        
        // Update metrics
        metrics.offlineTransitions += 1
        
        // Schedule periodic connectivity checks
        startPeriodicValidation()
    }
    
    private func startPeriodicValidation() {
        Timer.publish(every: poolConfig.validateInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.validateConnections()
            }
            .store(in: &cancellables)
    }
    
    private func setupRetryMechanism() {
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                self?.validateConnections()
            }
            .store(in: &cancellables)
    }
    
    private func handleConnectionError(_ error: Error) {
        metrics.errors.append(NetworkError(timestamp: Date(), error: error))
        if metrics.errors.count > Constants.MAX_RETRY_ATTEMPTS {
            connectionQuality.send(.poor)
        }
    }
    
    private func updateMetrics(path: NWPath) {
        metrics.lastPathUpdate = Date()
        metrics.pathUpdates += 1
        
        // Clean up old errors
        let oldestAllowedTimestamp = Date().addingTimeInterval(-3600) // 1 hour
        metrics.errors.removeAll { $0.timestamp < oldestAllowedTimestamp }
    }
}

// MARK: - Supporting Types

private struct NetworkMetrics {
    var successfulConnections: Int = 0
    var failedConnections: Int = 0
    var waitingConnections: Int = 0
    var validConnections: Int = 0
    var offlineTransitions: Int = 0
    var pathUpdates: Int = 0
    var lastPathUpdate: Date = Date()
    var errors: [NetworkError] = []
}

private struct NetworkError {
    let timestamp: Date
    let error: Error
}