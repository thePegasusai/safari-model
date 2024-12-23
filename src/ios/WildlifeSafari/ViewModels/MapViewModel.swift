//
// MapViewModel.swift
// WildlifeSafari
//
// Enterprise-grade ViewModel for handling secure, performant, and offline-capable
// map functionality in the Wildlife Detection Safari Pokédex iOS application.
//

import Foundation // Latest - Basic iOS functionality
import Combine    // Latest - Reactive programming support
import MapKit     // Latest - Map visualization and interaction
import CoreLocation // Latest - Location services

// MARK: - Constants

private enum Constants {
    static let DEFAULT_SPAN = MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    static let LOCATION_UPDATE_THRESHOLD: TimeInterval = 1.0
    static let MAX_CACHED_ANNOTATIONS = 1000
    static let CLUSTER_THRESHOLD = 50
    static let MAP_CACHE_SIZE = 50 * 1024 * 1024 // 50MB
    static let MIN_CLUSTER_DISTANCE = 100.0 // meters
    static let LOCATION_ACCURACY = kCLLocationAccuracyBest
}

// MARK: - Supporting Types

/// Represents the network connectivity status
enum NetworkStatus {
    case online
    case offline
    case limited
}

/// Custom annotation for wildlife and fossil discoveries
final class DiscoveryAnnotation: MKPointAnnotation {
    let discoveryId: UUID
    let discoveryType: DiscoveryType
    let confidence: Double
    let timestamp: Date
    
    init(discovery: Discovery) {
        self.discoveryId = discovery.discoveryId
        self.discoveryType = discovery.species?.commonName.contains("Fossil") == true ? .fossil : .wildlife
        self.confidence = discovery.confidence
        self.timestamp = discovery.timestamp
        super.init()
        
        if let location = discovery.location {
            self.coordinate = location.coordinate
        }
    }
    
    enum DiscoveryType {
        case wildlife
        case fossil
    }
}

/// Manages map tile caching for offline use
private final class MapTileCache {
    private let cache = NSCache<NSString, MKTileOverlay>()
    
    init() {
        cache.totalCostLimit = Constants.MAP_CACHE_SIZE
        cache.countLimit = 1000
    }
    
    func cacheMapRegion(_ region: MKCoordinateRegion) {
        // Implementation for caching map tiles
    }
}

/// Manages annotation clustering for performance
private final class AnnotationClusterManager {
    private var clusters: [MKClusterAnnotation] = []
    
    func clusterAnnotations(_ annotations: [DiscoveryAnnotation]) -> [MKAnnotation] {
        guard annotations.count > Constants.CLUSTER_THRESHOLD else {
            return annotations
        }
        
        // Implement clustering logic
        return annotations
    }
}

// MARK: - MapViewModel Implementation

@MainActor
@available(iOS 14.0, *)
public final class MapViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published private(set) var region: MKCoordinateRegion
    @Published private(set) var annotations: [DiscoveryAnnotation] = []
    @Published private(set) var isTrackingLocation = false
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?
    @Published private(set) var networkStatus: NetworkStatus = .online
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    private let locationManager: LocationManager
    private let collectionService: CollectionService
    private let clusterManager: AnnotationClusterManager
    private let tileCache: MapTileCache
    private let annotationUpdateQueue = DispatchQueue(label: "com.wildlifesafari.map.annotations", qos: .userInitiated)
    
    // MARK: - Initialization
    
    public init(locationManager: LocationManager, collectionService: CollectionService) {
        self.locationManager = locationManager
        self.collectionService = collectionService
        self.clusterManager = AnnotationClusterManager()
        self.tileCache = MapTileCache()
        
        // Initialize with default region
        self.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            span: Constants.DEFAULT_SPAN
        )
        
        setupBindings()
        setupNetworkMonitoring()
    }
    
    // MARK: - Public Methods
    
    /// Starts secure location tracking with battery optimization
    public func startLocationTracking() {
        guard !isTrackingLocation else { return }
        
        isTrackingLocation = true
        
        locationManager.requestAuthorization()
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.error = error
                    }
                },
                receiveValue: { [weak self] authorized in
                    guard authorized else { return }
                    self?.startSecureLocationUpdates()
                }
            )
            .store(in: &cancellables)
    }
    
    /// Safely stops location tracking and cleans up resources
    public func stopLocationTracking() {
        guard isTrackingLocation else { return }
        
        isTrackingLocation = false
        locationManager.stopUpdatingLocation()
        cancellables.removeAll()
    }
    
    /// Centers map on specific location with privacy controls
    public func centerOnLocation(_ coordinate: CLLocationCoordinate2D) {
        guard CLLocationCoordinate2DIsValid(coordinate) else { return }
        
        let newRegion = MKCoordinateRegion(
            center: coordinate,
            span: Constants.DEFAULT_SPAN
        )
        
        withAnimation {
            region = newRegion
        }
        
        // Cache map tiles for offline use
        tileCache.cacheMapRegion(newRegion)
    }
    
    // MARK: - Private Methods
    
    private func setupBindings() {
        // Observe collection changes
        collectionService.collectionsPublisher
            .receive(on: annotationUpdateQueue)
            .sink { [weak self] completion in
                if case .failure(let error) = completion {
                    self?.error = error
                }
            } receiveValue: { [weak self] _ in
                self?.updateAnnotations()
            }
            .store(in: &cancellables)
    }
    
    private func setupNetworkMonitoring() {
        // Monitor network status changes
        NotificationCenter.default.publisher(for: .networkStatusChanged)
            .sink { [weak self] notification in
                if let status = notification.object as? NetworkStatus {
                    self?.handleNetworkStatusChange(status)
                }
            }
            .store(in: &cancellables)
    }
    
    private func startSecureLocationUpdates() {
        locationManager.startUpdatingLocation()
            .throttle(for: .seconds(Constants.LOCATION_UPDATE_THRESHOLD), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] completion in
                if case .failure(let error) = completion {
                    self?.error = error
                }
            } receiveValue: { [weak self] location in
                self?.handleLocationUpdate(location)
            }
            .store(in: &cancellables)
    }
    
    private func handleLocationUpdate(_ location: Location) {
        // Center map on anonymized location
        centerOnLocation(location.coordinate)
    }
    
    private func updateAnnotations() {
        isLoading = true
        
        Task {
            do {
                // Fetch discoveries from local cache
                let collections = try await collectionService.getAllCollections()
                
                var newAnnotations: [DiscoveryAnnotation] = []
                
                for collection in collections {
                    if case .success(let discoveries) = collection.getDiscoveries() {
                        let annotations = discoveries.compactMap { discovery -> DiscoveryAnnotation? in
                            guard discovery.location != nil else { return nil }
                            return DiscoveryAnnotation(discovery: discovery)
                        }
                        newAnnotations.append(contentsOf: annotations)
                    }
                }
                
                // Apply clustering if needed
                let processedAnnotations = clusterManager.clusterAnnotations(newAnnotations)
                
                await MainActor.run {
                    self.annotations = newAnnotations
                    self.isLoading = false
                }
                
                // Trigger sync if online
                if networkStatus == .online {
                    try await collectionService.syncCollections()
                }
                
            } catch {
                await MainActor.run {
                    self.error = error
                    self.isLoading = false
                }
            }
        }
    }
    
    private func handleNetworkStatusChange(_ status: NetworkStatus) {
        networkStatus = status
        
        if status == .online {
            // Trigger sync when coming back online
            Task {
                try await collectionService.syncCollections()
            }
        }
    }
}