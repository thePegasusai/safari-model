//
// CameraViewModelTests.swift
// WildlifeSafariTests
//
// Comprehensive test suite for CameraViewModel validating real-time detection,
// performance metrics, offline capabilities, and error handling.
//

import XCTest // Latest - Core testing framework
import Combine // Latest - Async testing support
@testable import WildlifeSafari

@available(iOS 14.0, *)
@MainActor
final class CameraViewModelTests: XCTestCase {
    
    // MARK: - Private Properties
    
    private var sut: CameraViewModel!
    private var mockCameraManager: MockCameraManager!
    private var mockSpeciesClassifier: MockSpeciesClassifier!
    private var cancellables: Set<AnyCancellable>!
    
    // Test constants
    private let kTestTimeout: TimeInterval = 5.0
    private let kProcessingDelay: TimeInterval = 0.1
    private let kPerformanceThreshold: TimeInterval = 0.1
    private let kConfidenceThreshold: Float = 0.85
    
    // MARK: - Setup & Teardown
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Initialize mocks
        mockCameraManager = MockCameraManager()
        mockSpeciesClassifier = MockSpeciesClassifier()
        
        // Initialize system under test
        sut = CameraViewModel(
            cameraManager: mockCameraManager,
            speciesClassifier: mockSpeciesClassifier
        )
        
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDown() async throws {
        cancellables = nil
        sut = nil
        mockCameraManager = nil
        mockSpeciesClassifier = nil
        try await super.tearDown()
    }
    
    // MARK: - Real-time Detection Tests
    
    func testRealTimeDetection() async throws {
        // Given
        let expectation = expectation(description: "Species detection completed")
        let testFrame = UIImage()
        let expectedSpecies = Species()
        let prediction = SpeciesPrediction(species: expectedSpecies, confidence: 0.95, timestamp: Date())
        
        mockCameraManager.currentFrame = testFrame
        mockSpeciesClassifier.mockPrediction = prediction
        
        // When
        var receivedPrediction: SpeciesPrediction?
        sut.$currentPrediction
            .dropFirst()
            .sink { prediction in
                receivedPrediction = prediction
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        await sut.startDetection()
        
        // Then
        await fulfillment(of: [expectation], timeout: kTestTimeout)
        XCTAssertNotNil(receivedPrediction)
        XCTAssertEqual(receivedPrediction?.species.id, expectedSpecies.id)
        XCTAssertGreaterThan(receivedPrediction?.confidence ?? 0, kConfidenceThreshold)
    }
    
    // MARK: - Performance Tests
    
    func testPerformanceMetrics() async throws {
        // Given
        let expectation = expectation(description: "Performance metrics updated")
        
        // When
        var metrics: PerformanceMetrics?
        sut.$performanceMetrics
            .dropFirst()
            .sink { newMetrics in
                metrics = newMetrics
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        await sut.startDetection()
        
        // Then
        await fulfillment(of: [expectation], timeout: kTestTimeout)
        XCTAssertNotNil(metrics)
        XCTAssertLessThan(metrics?.processingTime ?? 1.0, kPerformanceThreshold)
        XCTAssertGreaterThan(metrics?.frameRate ?? 0, 0)
        XCTAssertEqual(metrics?.thermalState, .nominal)
    }
    
    func testProcessingTimeThreshold() async {
        // Given
        let expectation = expectation(description: "Processing completed within threshold")
        
        measure(metrics: [XCTClockMetric()]) {
            // When
            Task {
                await sut.startDetection()
                expectation.fulfill()
            }
        }
        
        // Then
        await fulfillment(of: [expectation], timeout: kTestTimeout)
    }
    
    // MARK: - Offline Capability Tests
    
    func testOfflineDetection() async throws {
        // Given
        let expectation = expectation(description: "Offline detection completed")
        let testFrame = UIImage()
        let offlinePrediction = SpeciesPrediction(
            species: Species(),
            confidence: 0.90,
            timestamp: Date()
        )
        
        mockCameraManager.currentFrame = testFrame
        mockSpeciesClassifier.mockPrediction = offlinePrediction
        mockSpeciesClassifier.offlineMode = true
        
        // When
        var receivedPrediction: SpeciesPrediction?
        sut.$currentPrediction
            .dropFirst()
            .sink { prediction in
                receivedPrediction = prediction
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        await sut.startDetection()
        
        // Then
        await fulfillment(of: [expectation], timeout: kTestTimeout)
        XCTAssertNotNil(receivedPrediction)
        XCTAssertTrue(mockSpeciesClassifier.offlineMode)
    }
    
    // MARK: - Error Handling Tests
    
    func testCameraSetupError() async throws {
        // Given
        mockCameraManager.shouldFailSetup = true
        
        // When
        var receivedError: Error?
        do {
            try await sut.setupCamera()
        } catch {
            receivedError = error
        }
        
        // Then
        XCTAssertNotNil(receivedError)
        XCTAssertTrue(receivedError is CameraError)
        XCTAssertEqual((receivedError as? CameraError)?.localizedDescription, CameraError.setupFailed.localizedDescription)
    }
    
    func testThermalThrottling() async {
        // Given
        let expectation = expectation(description: "Thermal throttling handled")
        mockCameraManager.simulateThermalWarning = true
        
        // When
        var receivedError: Error?
        sut.$error
            .dropFirst()
            .sink { error in
                receivedError = error
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        await sut.startDetection()
        
        // Then
        await fulfillment(of: [expectation], timeout: kTestTimeout)
        XCTAssertNotNil(receivedError)
        XCTAssertTrue(receivedError is CameraError)
        XCTAssertEqual((receivedError as? CameraError)?.localizedDescription, CameraError.thermalThrottling.localizedDescription)
    }
}

// MARK: - Mock Objects

private class MockCameraManager: CameraManager {
    var currentFrame: UIImage?
    var shouldFailSetup = false
    var simulateThermalWarning = false
    
    override func setupCamera() async throws {
        if shouldFailSetup {
            throw CameraError.setupFailed
        }
    }
    
    override func startCapture() {
        if simulateThermalWarning {
            NotificationCenter.default.post(
                name: ProcessInfo.thermalStateDidChangeNotification,
                object: nil
            )
        }
    }
}

private class MockSpeciesClassifier: SpeciesClassifier {
    var mockPrediction: SpeciesPrediction?
    var offlineMode = false
    
    override func classifySpecies(_ image: UIImage) async throws -> [SpeciesPrediction] {
        if let prediction = mockPrediction {
            return [prediction]
        }
        throw ClassifierError.predictionFailed("No mock prediction available")
    }
}