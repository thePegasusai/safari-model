//
// FossilViewModelTests.swift
// WildlifeSafariTests
//
// Comprehensive test suite for FossilViewModel functionality including
// thermal and memory management, scanning performance, and visualization.
//

import XCTest      // Latest - Unit testing framework
import Combine     // Latest - Testing asynchronous publishers
@testable import WildlifeSafari

// MARK: - Mock Classes

private class MockDetectionService: DetectionService {
    var startDetectionCalled = false
    var stopDetectionCalled = false
    var detectionMode: DetectionMode?
    var detectionOptions: DetectionOptions?
    var detectionSubject = PassthroughSubject<DetectionResult, DetectionError>()
    
    override func startDetection(
        mode: DetectionMode,
        options: DetectionOptions?
    ) -> AnyPublisher<DetectionResult, DetectionError> {
        startDetectionCalled = true
        detectionMode = mode
        detectionOptions = options
        return detectionSubject.eraseToAnyPublisher()
    }
    
    override func stopDetection() {
        stopDetectionCalled = true
    }
}

private class MockFossilDetector: FossilDetector {
    var detectFossilCalled = false
    var lastInput: FossilInput?
    var mockResult: Result<FossilDetection, FossilDetectionError>?
    
    override func detectFossil(_ input: FossilInput) -> Result<FossilDetection, FossilDetectionError> {
        detectFossilCalled = true
        lastInput = input
        return mockResult ?? .failure(.processingError)
    }
}

private class MockThermalMonitor {
    var statePublisher = CurrentValueSubject<ProcessInfo.ThermalState, Never>(.nominal)
}

private class MockMemoryMonitor {
    var pressurePublisher = CurrentValueSubject<Bool, Never>(false)
}

private class MockPerformanceTracker {
    var lastInferenceTime: TimeInterval = 0
    var isMonitoring = false
    
    func startMonitoring() {
        isMonitoring = true
    }
    
    func stopMonitoring() {
        isMonitoring = false
    }
}

// MARK: - FossilViewModelTests

final class FossilViewModelTests: XCTestCase {
    
    // MARK: - Properties
    
    private var sut: FossilViewModel!
    private var mockDetectionService: MockDetectionService!
    private var mockFossilDetector: MockFossilDetector!
    private var mockThermalMonitor: MockThermalMonitor!
    private var mockMemoryMonitor: MockMemoryMonitor!
    private var mockPerformanceTracker: MockPerformanceTracker!
    private var cancellables: Set<AnyCancellable>!
    
    // MARK: - Setup & Teardown
    
    override func setUp() async throws {
        try await super.setUp()
        
        mockDetectionService = MockDetectionService()
        mockFossilDetector = MockFossilDetector()
        mockThermalMonitor = MockThermalMonitor()
        mockMemoryMonitor = MockMemoryMonitor()
        mockPerformanceTracker = MockPerformanceTracker()
        cancellables = []
        
        sut = FossilViewModel(
            detectionService: mockDetectionService,
            fossilDetector: mockFossilDetector,
            thermalStateMonitor: mockThermalMonitor.statePublisher,
            memoryPressureHandler: mockMemoryMonitor.pressurePublisher,
            performanceMonitor: mockPerformanceTracker
        )
    }
    
    override func tearDown() async throws {
        sut = nil
        mockDetectionService = nil
        mockFossilDetector = nil
        mockThermalMonitor = nil
        mockMemoryMonitor = nil
        mockPerformanceTracker = nil
        cancellables = nil
        
        try await super.tearDown()
    }
    
    // MARK: - Scanning Tests
    
    func testStartScanning_WithNormalConditions_StartsDetectionService() {
        // Given
        let expectation = expectation(description: "Detection service started")
        
        // When
        sut.startScanning()
        
        // Then
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertTrue(self.mockDetectionService.startDetectionCalled)
            XCTAssertEqual(self.mockDetectionService.detectionMode, .fossil)
            XCTAssertNotNil(self.mockDetectionService.detectionOptions)
            XCTAssertEqual(self.sut.scanningState, .preparing)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: kTestTimeout)
    }
    
    func testStopScanning_StopsDetectionAndCleanup() {
        // Given
        sut.startScanning()
        
        // When
        sut.stopScanning()
        
        // Then
        XCTAssertTrue(mockDetectionService.stopDetectionCalled)
        XCTAssertFalse(mockPerformanceTracker.isMonitoring)
        XCTAssertEqual(sut.scanningState, .idle)
    }
    
    // MARK: - Thermal Management Tests
    
    func testThermalStateChanges_AffectsScanningBehavior() {
        // Given
        let expectation = expectation(description: "Thermal state changes handled")
        
        // When
        sut.startScanning()
        mockThermalMonitor.statePublisher.send(.serious)
        
        // Then
        DispatchQueue.main.asyncAfter(deadline: .now() + kThermalStateChangeDelay) {
            XCTAssertEqual(self.sut.thermalState, .serious)
            
            // Test critical state
            self.mockThermalMonitor.statePublisher.send(.critical)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + kThermalStateChangeDelay) {
                XCTAssertEqual(self.sut.scanningState, .failed(.thermalLimitReached))
                XCTAssertTrue(self.mockDetectionService.stopDetectionCalled)
                expectation.fulfill()
            }
        }
        
        wait(for: [expectation], timeout: kTestTimeout)
    }
    
    // MARK: - Memory Management Tests
    
    func testMemoryWarning_TriggersOptimization() {
        // Given
        let expectation = expectation(description: "Memory warning handled")
        
        // When
        sut.startScanning()
        mockMemoryMonitor.pressurePublisher.send(true)
        
        // Then
        DispatchQueue.main.asyncAfter(deadline: .now() + kMemoryWarningDelay) {
            XCTAssertTrue(self.sut.memoryWarning)
            XCTAssertEqual(self.mockDetectionService.detectionOptions?.processingQuality, .low)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: kTestTimeout)
    }
    
    // MARK: - Performance Tests
    
    func testProcessingPerformance_MeetsRequirements() {
        // Given
        let expectation = expectation(description: "Performance requirements met")
        mockPerformanceTracker.lastInferenceTime = 0.05 // 50ms
        
        // When
        sut.startScanning()
        
        // Simulate successful detection
        let mockFossil = createMockFossil()
        let mockDetection = createMockDetection(confidence: 0.95)
        mockDetectionService.detectionSubject.send(.fossil(mockDetection))
        
        // Then
        DispatchQueue.main.asyncAfter(deadline: .now() + kTestScanDuration) {
            XCTAssertLessThan(self.mockPerformanceTracker.lastInferenceTime, kPerformanceThreshold / 1000.0)
            XCTAssertTrue(self.mockPerformanceTracker.isMonitoring)
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: kTestTimeout)
    }
    
    // MARK: - Helper Methods
    
    private func createMockFossil() -> Fossil {
        return Fossil(
            id: UUID(),
            scientificName: "Tyrannosaurus Rex",
            commonName: "T-Rex",
            period: "Late Cretaceous",
            estimatedAge: 66.0,
            discoveryLocation: CLLocation(latitude: 0, longitude: 0)
        )
    }
    
    private func createMockDetection(confidence: Float) -> FossilDetection {
        return FossilDetection(
            confidence: confidence,
            classification: "Tyrannosaurus Rex",
            boundingBox: .zero,
            depthMap: nil,
            threeDModel: nil,
            metadata: [:]
        )
    }
}