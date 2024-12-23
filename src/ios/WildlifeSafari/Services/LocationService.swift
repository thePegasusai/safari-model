//
// LocationService.swift
// WildlifeSafari
//
// Service layer handling location-related operations with enhanced security,
// privacy controls, and offline capabilities.
//
// Version: 1.0
//

import CoreLocation // Latest - iOS location services framework
import Combine      // Latest - Reactive programming support
import Foundation

/// Constants used throughout the LocationService
private enum Constants {
    static let locationHistoryLimit = 100
    static let locationCacheKey = "cached_locations"
    static let locationRetentionDays = 30
    static let maxCacheSizeMB = 50
    static let privacyZoneRadius = 100
}

/// Represents the synchronization status of location data
private enum SyncStatus {
    case synced
    case pending
    case error(Error)
}

/// Enhanced service class managing location operations with advanced security and offline capabilities
@MainActor
public final class LocationService {
    
    // MARK: - Properties
    
    private let locationManager: LocationManager
    private var locationHistory: CurrentValueSubject<[Location], Never>
    private let locationUpdates: PassthroughSubject<Location, Error>
    private var cancellables: Set<AnyCancellable>
    private let syncStatus: CurrentValueSubject<SyncStatus, Never>
    private var retentionTimer: Timer?
    
    // MARK: - Initialization
    
    public init() {
        // Initialize properties
        locationManager = LocationManager.shared
        locationHistory = CurrentValueSubject<[Location], Never>([])
        locationUpdates = PassthroughSubject<Location, Error>()
        cancellables = Set<AnyCancellable>()
        syncStatus = CurrentValueSubject<SyncStatus, Never>(.synced)
        
        // Setup location history management
        setupLocationHistoryManagement()
        
        // Load cached locations
        loadCachedLocations()
        
        // Initialize retention timer
        setupRetentionTimer()
    }
    
    // MARK: - Public Interface
    
    /// Begin secure location tracking with privacy controls
    /// - Parameters:
    ///   - accuracy: Desired location accuracy
    ///   - enablePrivacyZones: Whether to enable privacy zones
    /// - Returns: Publisher providing privacy-aware location updates
    @MainActor
    public func startTracking(
        accuracy: CLLocationAccuracy = kCLLocationAccuracyBest,
        enablePrivacyZones: Bool = true
    ) -> AnyPublisher<Location, Error> {
        // Configure privacy zones if enabled
        if enablePrivacyZones {
            locationManager.configurePrivacyZones()
        }
        
        // Start location updates
        return locationManager.startUpdatingLocation()
            .handleEvents(receiveOutput: { [weak self] location in
                self?.handleLocationUpdate(location)
            })
            .eraseToAnyPublisher()
    }
    
    /// Stop location tracking and secure cache
    @MainActor
    public func stopTracking() {
        locationManager.stopUpdatingLocation()
        
        // Cache current location history
        cacheLocations()
        
        // Update sync status
        syncStatus.send(.synced)
    }
    
    /// Get current device location with privacy controls
    /// - Parameter applyPrivacyFilter: Whether to apply privacy filtering
    /// - Returns: Future with the current location
    @MainActor
    public func getCurrentLocation(applyPrivacyFilter: Bool = true) -> Future<Location, Error> {
        return locationManager.getCurrentLocation()
            .map { location -> Location in
                if applyPrivacyFilter {
                    return location.anonymize()
                }
                return location
            }
            .eraseToAnyPublisher()
            .future()
    }
    
    /// Manage location data retention and cache size
    @MainActor
    public func manageRetention() {
        // Remove expired locations
        let cutoffDate = Date().addingTimeInterval(-TimeInterval(Constants.locationRetentionDays * 24 * 60 * 60))
        locationHistory.value = locationHistory.value.filter { $0.timestamp > cutoffDate }
        
        // Manage cache size
        enforceMaxCacheSize()
        
        // Update storage
        cacheLocations()
    }
    
    // MARK: - Private Methods
    
    private func setupLocationHistoryManagement() {
        locationUpdates
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.syncStatus.send(.error(error))
                    }
                },
                receiveValue: { [weak self] location in
                    self?.addLocationToHistory(location)
                }
            )
            .store(in: &cancellables)
    }
    
    private func setupRetentionTimer() {
        retentionTimer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(24 * 60 * 60),
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.manageRetention()
            }
        }
    }
    
    private func handleLocationUpdate(_ location: Location) {
        locationUpdates.send(location)
        syncStatus.send(.pending)
    }
    
    private func addLocationToHistory(_ location: Location) {
        var currentHistory = locationHistory.value
        currentHistory.append(location)
        
        // Enforce history limit
        if currentHistory.count > Constants.locationHistoryLimit {
            currentHistory.removeFirst()
        }
        
        locationHistory.send(currentHistory)
    }
    
    private func loadCachedLocations() {
        guard let data = UserDefaults.standard.data(forKey: Constants.locationCacheKey),
              let locations = try? JSONDecoder().decode([Location].self, from: data) else {
            return
        }
        locationHistory.send(locations)
    }
    
    private func cacheLocations() {
        guard let data = try? JSONEncoder().encode(locationHistory.value) else {
            return
        }
        UserDefaults.standard.set(data, forKey: Constants.locationCacheKey)
    }
    
    private func enforceMaxCacheSize() {
        let maxBytes = Constants.maxCacheSizeMB * 1024 * 1024
        guard let data = try? JSONEncoder().encode(locationHistory.value),
              data.count > maxBytes else {
            return
        }
        
        // Remove oldest entries until under size limit
        var currentHistory = locationHistory.value
        while let encodedData = try? JSONEncoder().encode(currentHistory),
              encodedData.count > maxBytes,
              !currentHistory.isEmpty {
            currentHistory.removeFirst()
        }
        
        locationHistory.send(currentHistory)
    }
}

// MARK: - Publisher Extensions

private extension Publisher {
    func future() -> Future<Output, Failure> {
        return Future { promise in
            var cancellable: AnyCancellable?
            cancellable = self.sink(
                receiveCompletion: { completion in
                    switch completion {
                    case .finished:
                        break
                    case .failure(let error):
                        promise(.failure(error))
                    }
                    cancellable?.cancel()
                },
                receiveValue: { value in
                    promise(.success(value))
                    cancellable?.cancel()
                }
            )
        }
    }
}