//
// MapViewModelTests.swift
// WildlifeSafariTests
//
// Comprehensive test suite for MapViewModel functionality including location tracking,
// region management, and discovery annotations.
//

import XCTest
import Combine
import MapKit
import CoreLocation
@testable import WildlifeSafari

@MainActor
final class MapViewModelTests: XCTestCase {
    // MARK: - Properties
    
    private var sut: MapViewModel!
    private var locationManager: LocationManager!
    private var collectionService: CollectionService!
    private var cancellables: Set<AnyCancellable>!
    private var locationUpdateExpectation: XCTestExpectation!
    private var regionUpdateExpectation: XCTestExpectation!
    
    // MARK: - Test Lifecycle
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Initialize dependencies
        locationManager = LocationManager.shared
        collectionService = CollectionService(
            apiClient: APIClient(),
            coreDataStack: CoreDataStack(modelName: "WildlifeSafari"),
            syncService: SyncService(
                apiClient: APIClient(),
                coreDataStack: CoreDataStack(modelName: "WildlifeSafari")
            )
        )
        
        // Initialize view model
        sut = MapViewModel(
            locationManager: locationManager,
            collectionService: collectionService
        )
        
        // Initialize test properties
        cancellables = Set<AnyCancellable>()
        locationUpdateExpectation = expectation(description: "Location update received")
        regionUpdateExpectation = expectation(description: "Region update received")
    }
    
    override func tearDown() {
        // Clean up subscriptions
        cancellables.removeAll()
        
        // Reset location manager state
        sut.stopLocationTracking()
        locationManager = nil
        
        // Clear expectations
        locationUpdateExpectation = nil
        regionUpdateExpectation = nil
        
        // Clean up view model
        sut = nil
        
        super.tearDown()
    }
    
    // MARK: - Location Tracking Tests
    
    func testStartLocationTracking() async throws {
        // Given
        let testLocation = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        let testRegion = MKCoordinateRegion(
            center: testLocation,
            span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
        )
        
        // When
        sut.startLocationTracking()
        
        // Observe region updates
        sut.$region
            .dropFirst()
            .sink { [weak self] region in
                XCTAssertEqual(region.center.latitude, testRegion.center.latitude, accuracy: 0.001)
                XCTAssertEqual(region.center.longitude, testRegion.center.longitude, accuracy: 0.001)
                self?.regionUpdateExpectation.fulfill()
            }
            .store(in: &cancellables)
        
        // Simulate location update
        let location = Location(coordinate: testLocation)
        NotificationCenter.default.post(
            name: .init("locationUpdate"),
            object: location
        )
        
        // Then
        XCTAssertTrue(sut.isTrackingLocation)
        await fulfillment(of: [regionUpdateExpectation], timeout: 5.0)
    }
    
    func testStopLocationTracking() async throws {
        // Given
        sut.startLocationTracking()
        XCTAssertTrue(sut.isTrackingLocation)
        
        // When
        sut.stopLocationTracking()
        
        // Then
        XCTAssertFalse(sut.isTrackingLocation)
        
        // Verify location updates stopped
        let locationUpdateReceived = expectation(description: "Location update should not be received")
        locationUpdateReceived.isInverted = true
        
        sut.$region
            .dropFirst()
            .sink { _ in
                locationUpdateReceived.fulfill()
            }
            .store(in: &cancellables)
        
        await fulfillment(of: [locationUpdateReceived], timeout: 2.0)
    }
    
    // MARK: - Annotation Tests
    
    func testUpdateAnnotations() async throws {
        // Given
        let testLocation = CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        let testDiscovery = Discovery(entity: Discovery.entity(), insertInto: nil)
        try testDiscovery.setLocation(Location(coordinate: testLocation))
        
        let testCollection = Collection(entity: Collection.entity(), insertInto: nil)
        _ = testCollection.addDiscovery(testDiscovery)
        
        // When
        sut.$annotations
            .dropFirst()
            .sink { annotations in
                XCTAssertEqual(annotations.count, 1)
                XCTAssertEqual(annotations.first?.coordinate.latitude, testLocation.latitude)
                XCTAssertEqual(annotations.first?.coordinate.longitude, testLocation.longitude)
                self.locationUpdateExpectation.fulfill()
            }
            .store(in: &cancellables)
        
        // Simulate collection update
        NotificationCenter.default.post(
            name: .NSManagedObjectContextDidSave,
            object: testCollection
        )
        
        // Then
        await fulfillment(of: [locationUpdateExpectation], timeout: 5.0)
    }
    
    // MARK: - Error Handling Tests
    
    func testLocationTrackingError() async throws {
        // Given
        let errorExpectation = expectation(description: "Error received")
        
        // When
        sut.$error
            .compactMap { $0 }
            .sink { error in
                XCTAssertNotNil(error)
                errorExpectation.fulfill()
            }
            .store(in: &cancellables)
        
        // Simulate location error
        NotificationCenter.default.post(
            name: .init("locationError"),
            object: NSError(domain: "Location", code: -1)
        )
        
        // Then
        await fulfillment(of: [errorExpectation], timeout: 5.0)
    }
}