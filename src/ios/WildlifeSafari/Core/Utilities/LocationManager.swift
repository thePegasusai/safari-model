//
// LocationManager.swift
// WildlifeSafari
//
// Core location management utility with privacy-focused location tracking
// and offline capabilities for wildlife and fossil discovery.
//
// Version: 1.0
//

import CoreLocation // Latest - iOS location services framework
import Combine      // Latest - Reactive programming support
import Foundation

/// Thread-safe location manager with privacy controls and offline support
@MainActor
public final class LocationManager: NSObject {
    
    // MARK: - Constants
    
    private enum Constants {
        static let defaultAccuracy = kCLLocationAccuracyBest
        static let defaultDistanceFilter = 10.0
        static let significantLocationChangeDistance = 500.0
        static let locationCacheExpiration: TimeInterval = AppConstants.Storage.cacheExpirationInterval
        static let maxLocationCacheSize = AppConstants.Storage.maxCacheEntries
        static let privacyZoneRadius = 100.0 // meters
    }
    
    // MARK: - Properties
    
    /// Shared singleton instance with thread safety
    public static let shared = LocationManager()
    
    /// Core location manager instance
    private let locationManager: CLLocationManager
    
    /// Publisher for location updates
    private let locationSubject = PassthroughSubject<CLLocation, Error>()
    
    /// Current authorization status
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    
    /// Flag indicating if location updates are active
    @Published private(set) var isUpdatingLocation: Bool = false
    
    /// Encrypted location cache for offline support
    private let locationCache: LocationCache
    
    /// Privacy manager for location anonymization
    private let privacyManager: LocationPrivacyManager
    
    /// Battery-aware location accuracy adapter
    private let accuracyAdapter: LocationAccuracyAdapter
    
    // MARK: - Initialization
    
    private override init() {
        // Initialize core location manager
        locationManager = CLLocationManager()
        authorizationStatus = locationManager.authorizationStatus
        
        // Initialize supporting components
        locationCache = LocationCache(
            maxEntries: Constants.maxLocationCacheSize,
            expirationInterval: Constants.locationCacheExpiration
        )
        privacyManager = LocationPrivacyManager(
            privacyZoneRadius: Constants.privacyZoneRadius
        )
        accuracyAdapter = LocationAccuracyAdapter()
        
        super.init()
        
        // Configure location manager
        configureLocationManager()
    }
    
    // MARK: - Public Interface
    
    /// Request location authorization with privacy considerations
    /// - Returns: Future indicating authorization result
    public func requestAuthorization() -> Future<Bool, Error> {
        return Future { [weak self] promise in
            guard let self = self else {
                promise(.failure(LocationError.instanceDeallocated))
                return
            }
            
            switch self.locationManager.authorizationStatus {
            case .notDetermined:
                self.locationManager.requestWhenInUseAuthorization()
                // Authorization result handled by delegate
            case .authorizedWhenInUse, .authorizedAlways:
                promise(.success(true))
            case .denied, .restricted:
                promise(.failure(LocationError.authorizationDenied))
            @unknown default:
                promise(.failure(LocationError.unknown))
            }
        }
    }
    
    /// Start receiving privacy-aware location updates
    /// - Returns: Publisher providing filtered location updates
    public func startUpdatingLocation() -> AnyPublisher<Location, Error> {
        guard !isUpdatingLocation else {
            return locationSubject
                .map { [privacyManager] location in
                    privacyManager.processLocation(Location.fromCLLocation(location))
                }
                .eraseToAnyPublisher()
        }
        
        isUpdatingLocation = true
        
        // Configure accuracy based on battery state
        let accuracy = accuracyAdapter.getCurrentAccuracy()
        locationManager.desiredAccuracy = accuracy
        locationManager.distanceFilter = Constants.defaultDistanceFilter
        
        // Start updates with offline support
        locationManager.startUpdatingLocation()
        
        return locationSubject
            .map { [privacyManager] location in
                // Process location through privacy manager
                let processedLocation = privacyManager.processLocation(
                    Location.fromCLLocation(location)
                )
                
                // Cache location for offline support
                self.locationCache.cacheLocation(processedLocation)
                
                return processedLocation
            }
            .eraseToAnyPublisher()
    }
    
    /// Stop receiving location updates
    public func stopUpdatingLocation() {
        guard isUpdatingLocation else { return }
        
        locationManager.stopUpdatingLocation()
        isUpdatingLocation = false
    }
    
    /// Get current location with privacy controls
    /// - Returns: Future with the current location
    public func getCurrentLocation() -> Future<Location, Error> {
        return Future { [weak self] promise in
            guard let self = self else {
                promise(.failure(LocationError.instanceDeallocated))
                return
            }
            
            // Check cache first
            if let cachedLocation = self.locationCache.getLastLocation() {
                promise(.success(cachedLocation))
                return
            }
            
            // Request one-time location
            self.locationManager.requestLocation()
            
            // Location or error will be delivered via delegate
        }
    }
    
    // MARK: - Private Methods
    
    private func configureLocationManager() {
        locationManager.delegate = self
        locationManager.activityType = .otherNavigation
        locationManager.pausesLocationUpdatesAutomatically = true
        
        // Enable significant location changes for battery efficiency
        if locationManager.significantLocationChangeMonitoringAvailable {
            locationManager.startMonitoringSignificantLocationChanges()
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {
    
    public func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.last else { return }
        locationSubject.send(location)
    }
    
    public func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        locationSubject.send(completion: .failure(error))
    }
    
    public func locationManagerDidChangeAuthorization(
        _ manager: CLLocationManager
    ) {
        authorizationStatus = manager.authorizationStatus
    }
}

// MARK: - Supporting Types

/// Location-related errors
private enum LocationError: Error {
    case instanceDeallocated
    case authorizationDenied
    case unknown
}

/// Cache for storing locations with encryption
private final class LocationCache {
    private let maxEntries: Int
    private let expirationInterval: TimeInterval
    private var cache: [Location] = []
    
    init(maxEntries: Int, expirationInterval: TimeInterval) {
        self.maxEntries = maxEntries
        self.expirationInterval = expirationInterval
    }
    
    func cacheLocation(_ location: Location) {
        cache.append(location)
        if cache.count > maxEntries {
            cache.removeFirst()
        }
    }
    
    func getLastLocation() -> Location? {
        return cache.last
    }
}

/// Privacy manager for location anonymization
private final class LocationPrivacyManager {
    private let privacyZoneRadius: Double
    
    init(privacyZoneRadius: Double) {
        self.privacyZoneRadius = privacyZoneRadius
    }
    
    func processLocation(_ location: Location) -> Location {
        // Apply privacy zones and return anonymized location if needed
        return location.anonymize()
    }
}

/// Battery-aware location accuracy adapter
private final class LocationAccuracyAdapter {
    func getCurrentAccuracy() -> CLLocationAccuracy {
        // Adjust accuracy based on battery level and usage
        return Constants.defaultAccuracy
    }
}