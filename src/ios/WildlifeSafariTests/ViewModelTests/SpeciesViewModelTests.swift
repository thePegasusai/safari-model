//
// SpeciesViewModelTests.swift
// WildlifeSafariTests
//
// Comprehensive test suite for SpeciesViewModel covering detection accuracy,
// performance, collection management, and error handling.
//

import XCTest // Latest - Core testing framework
import Combine // Latest - Testing asynchronous publishers
@testable import WildlifeSafari

@available(iOS 14.0, *)
final class SpeciesViewModelTests: XCTestCase {
    
    // MARK: - Properties
    
    private var sut: SpeciesViewModel!
    private var mockDetectionService: MockDetectionService!
    private var mockCollectionService: MockCollectionService!
    private var cancellables: Set<AnyCancellable>!
    private var detectionExpectation: XCTestExpectation!
    
    // Test constants
    private let testTimeout: TimeInterval = 5.0
    private let processingTimeThreshold: TimeInterval = 0.1 // 100ms requirement
    private let accuracyThreshold: Float = 0.9 // 90% accuracy requirement
    
    // MARK: - Test Lifecycle
    
    override func setUp() {
        super.setUp()
        
        // Initialize mock services
        mockDetectionService = MockDetectionService()
        mockCollectionService = MockCollectionService()
        
        // Initialize system under test
        sut = SpeciesViewModel(
            detectionService: mockDetectionService,
            collectionService: mockCollectionService
        )
        
        cancellables = Set<AnyCancellable>()
        detectionExpectation = expectation(description: "Detection completed")
    }
    
    override func tearDown() {
        cancellables.removeAll()
        sut = nil
        mockDetectionService = nil
        mockCollectionService = nil
        super.tearDown()
    }
    
    // MARK: - Detection Performance Tests
    
    func testDetectionPerformance() {
        // Configure mock service with known response time
        let startTime = Date()
        
        // Execute detection
        sut.startDetection()
            .sink(
                receiveCompletion: { _ in
                    let processingTime = Date().timeIntervalSince(startTime)
                    XCTAssertLessThanOrEqual(
                        processingTime,
                        self.processingTimeThreshold,
                        "Detection processing time exceeds 100ms requirement"
                    )
                    self.detectionExpectation.fulfill()
                },
                receiveValue: { state in
                    if case .detected = state {
                        XCTAssertNotNil(self.sut.currentSpecies)
                    }
                }
            )
            .store(in: &cancellables)
        
        wait(for: [detectionExpectation], timeout: testTimeout)
    }
    
    func testSpeciesDetectionAccuracy() {
        // Configure test data
        let testSpecies = createTestSpecies()
        var detectionResults: [Bool] = []
        let detectionCount = 100
        
        // Configure mock service
        mockDetectionService.mockSpecies = testSpecies
        mockDetectionService.mockConfidence = 0.95
        
        // Perform multiple detections
        let accuracyExpectation = expectation(description: "Accuracy test completed")
        accuracyExpectation.expectedFulfillmentCount = detectionCount
        
        for _ in 0..<detectionCount {
            sut.startDetection()
                .sink(
                    receiveCompletion: { _ in
                        accuracyExpectation.fulfill()
                    },
                    receiveValue: { state in
                        if case .detected(let species) = state {
                            detectionResults.append(species.scientificName == testSpecies.scientificName)
                        }
                    }
                )
                .store(in: &cancellables)
        }
        
        wait(for: [accuracyExpectation], timeout: testTimeout * 2)
        
        // Calculate accuracy
        let successfulDetections = detectionResults.filter { $0 }.count
        let accuracy = Float(successfulDetections) / Float(detectionCount)
        
        XCTAssertGreaterThanOrEqual(
            accuracy,
            accuracyThreshold,
            "Detection accuracy below 90% requirement"
        )
    }
    
    // MARK: - Collection Management Tests
    
    func testCollectionSync() {
        // Configure test data
        let testSpecies = createTestSpecies()
        let collectionId = UUID()
        let syncExpectation = expectation(description: "Collection sync completed")
        
        // Set current species
        mockDetectionService.mockSpecies = testSpecies
        
        // Perform detection and add to collection
        sut.startDetection()
            .flatMap { _ in
                self.sut.addToCollection(collectionId)
            }
            .sink(
                receiveCompletion: { completion in
                    if case .finished = completion {
                        syncExpectation.fulfill()
                    }
                },
                receiveValue: { _ in
                    XCTAssertTrue(self.mockCollectionService.syncCalled)
                }
            )
            .store(in: &cancellables)
        
        wait(for: [syncExpectation], timeout: testTimeout)
    }
    
    // MARK: - Error Handling Tests
    
    func testErrorHandling() {
        // Configure mock service to generate errors
        mockDetectionService.shouldFailDetection = true
        mockDetectionService.mockError = DetectionError.lowConfidence
        
        let errorExpectation = expectation(description: "Error handled")
        
        sut.startDetection()
            .sink(
                receiveCompletion: { completion in
                    if case .finished = completion {
                        errorExpectation.fulfill()
                    }
                },
                receiveValue: { state in
                    if case .failed(let error) = state {
                        XCTAssertEqual(error as? DetectionError, .lowConfidence)
                        XCTAssertNil(self.sut.currentSpecies)
                    }
                }
            )
            .store(in: &cancellables)
        
        wait(for: [errorExpectation], timeout: testTimeout)
    }
    
    func testThermalThrottling() {
        // Simulate thermal state change
        NotificationCenter.default.post(
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
        
        let throttleExpectation = expectation(description: "Thermal throttling handled")
        
        sut.startDetection()
            .sink(
                receiveCompletion: { _ in
                    throttleExpectation.fulfill()
                },
                receiveValue: { state in
                    if case .throttled = state {
                        XCTAssertFalse(self.mockDetectionService.isDetecting)
                    }
                }
            )
            .store(in: &cancellables)
        
        wait(for: [throttleExpectation], timeout: testTimeout)
    }
    
    // MARK: - Helper Methods
    
    private func createTestSpecies() -> Species {
        let context = mockCollectionService.coreDataStack.viewContext
        let species = Species(entity: Species.entity(), insertInto: context)
        species.scientificName = "Panthera leo"
        species.commonName = "Lion"
        species.taxonomy = "Mammalia||Carnivora||Felidae"
        species.conservationStatus = "Vulnerable"
        return species
    }
}

// MARK: - Mock Services

private class MockDetectionService: DetectionService {
    var mockSpecies: Species?
    var mockConfidence: Float = 0.95
    var mockError: Error?
    var shouldFailDetection = false
    var isDetecting = false
    
    func startDetection(mode: DetectionMode) -> AnyPublisher<DetectionResult, DetectionError> {
        isDetecting = true
        
        if shouldFailDetection {
            return Fail(error: mockError as? DetectionError ?? .invalidInput)
                .eraseToAnyPublisher()
        }
        
        guard let species = mockSpecies else {
            return Empty().eraseToAnyPublisher()
        }
        
        let prediction = SpeciesPrediction(species: species, confidence: mockConfidence)
        return Just(.species(prediction))
            .setFailureType(to: DetectionError.self)
            .eraseToAnyPublisher()
    }
    
    func stopDetection() {
        isDetecting = false
    }
    
    func detectSpecies(_ image: UIImage) -> AnyPublisher<Species, Error> {
        guard let species = mockSpecies else {
            return Fail(error: DetectionError.invalidInput).eraseToAnyPublisher()
        }
        return Just(species)
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }
}

private class MockCollectionService: CollectionService {
    var syncCalled = false
    let coreDataStack: CoreDataStack
    
    override init() {
        let config = NSPersistentStoreDescription()
        config.type = NSInMemoryStoreType
        
        let container = NSPersistentContainer(name: "WildlifeSafari")
        container.persistentStoreDescriptions = [config]
        
        container.loadPersistentStores { _, error in
            if let error = error {
                fatalError("Failed to load test store: \(error)")
            }
        }
        
        self.coreDataStack = CoreDataStack(container: container)
        super.init()
    }
    
    override func addDiscoveryToCollection(_ species: Species, collectionId: UUID) -> AnyPublisher<Void, Error> {
        syncCalled = true
        return Just(())
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }
}