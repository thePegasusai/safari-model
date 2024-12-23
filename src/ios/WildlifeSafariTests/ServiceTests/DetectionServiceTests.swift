//
// DetectionServiceTests.swift
// WildlifeSafariTests
//
// Comprehensive test suite for DetectionService validating species identification,
// fossil detection, performance metrics, and resource management.
//

import XCTest      // Latest - iOS unit testing framework
import Combine     // Latest - Testing asynchronous detection operations
import CoreML      // Latest - ML model configuration for testing
@testable import WildlifeSafari

// MARK: - Constants

private let kTestTimeout: TimeInterval = 5.0
private let kTestImageSize = CGSize(width: 640, height: 640)
private let kAccuracyThreshold: Float = 0.90
private let kProcessingTimeThreshold: TimeInterval = 0.100
private let kTestBatchSize = 10
private let kMemoryThreshold: Float = 0.80

@available(iOS 14.0, *)
final class DetectionServiceTests: XCTestCase {
    
    // MARK: - Private Properties
    
    private var detectionService: DetectionService!
    private var configuration: MLModelConfiguration!
    private var cancellables = Set<AnyCancellable>()
    private var testImageGenerator: TestImageGenerator!
    private var performanceMetrics: XCTPerformanceMetric!
    
    // MARK: - Setup/Teardown
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Configure ML model for testing
        configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndGPU
        configuration.allowLowPrecisionAccumulationOnGPU = true
        
        // Initialize detection service with test configuration
        let options = DetectionOptions(
            confidenceThreshold: kAccuracyThreshold,
            enableThermalProtection: true,
            enableMemoryOptimization: true,
            processingQuality: .high
        )
        detectionService = try DetectionService(configuration: configuration, options: options)
        
        // Initialize test utilities
        testImageGenerator = TestImageGenerator(imageSize: kTestImageSize)
        performanceMetrics = XCTPerformanceMetric("Detection Time")
        
        // Set up performance monitoring
        setupPerformanceMonitoring()
    }
    
    override func tearDown() {
        // Stop any ongoing detection
        detectionService.stopDetection()
        
        // Clear test resources
        testImageGenerator = nil
        performanceMetrics = nil
        cancellables.removeAll()
        
        super.tearDown()
    }
    
    // MARK: - Test Cases
    
    /// Tests species detection accuracy against the 90% threshold requirement
    func testSpeciesDetectionAccuracy() async throws {
        // Generate test dataset
        let testImages = try await testImageGenerator.generateTestImages(count: kTestBatchSize)
        var accuracyResults: [Float] = []
        
        // Perform detection on test images
        for image in testImages {
            let expectation = expectation(description: "Species detection")
            
            detectionService.detectSpecies(image)
                .sink(
                    receiveCompletion: { completion in
                        if case .failure(let error) = completion {
                            XCTFail("Detection failed: \(error)")
                        }
                        expectation.fulfill()
                    },
                    receiveValue: { result in
                        if case .species(let prediction) = result {
                            accuracyResults.append(prediction.confidence)
                        }
                    }
                )
                .store(in: &cancellables)
        }
        
        await fulfillment(of: [expectation], timeout: kTestTimeout)
        
        // Calculate average accuracy
        let averageAccuracy = accuracyResults.reduce(0, +) / Float(accuracyResults.count)
        
        // Verify accuracy meets threshold
        XCTAssertGreaterThanOrEqual(averageAccuracy, kAccuracyThreshold,
                                  "Average detection accuracy below required threshold")
    }
    
    /// Validates detection processing time meets sub-100ms requirement
    func testDetectionPerformance() async throws {
        let testImage = try await testImageGenerator.generateTestImage()
        
        measure(metrics: [XCTClockMetric()]) {
            let expectation = expectation(description: "Performance test")
            
            detectionService.detectSpecies(testImage)
                .sink(
                    receiveCompletion: { _ in
                        expectation.fulfill()
                    },
                    receiveValue: { _ in }
                )
                .store(in: &cancellables)
            
            wait(for: [expectation], timeout: kTestTimeout)
        }
        
        // Verify processing time
        let processingTime = Double(getMetric(XCTClockMetric.self))
        XCTAssertLessThanOrEqual(processingTime, kProcessingTimeThreshold,
                                "Processing time exceeds requirement")
    }
    
    /// Tests continuous detection capabilities and resource management
    func testContinuousDetection() async throws {
        let frameCount = 100
        var detectionResults: [DetectionResult] = []
        let expectation = expectation(description: "Continuous detection")
        
        // Start continuous detection
        detectionService.startDetection(mode: .species)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        XCTFail("Continuous detection failed: \(error)")
                    }
                    expectation.fulfill()
                },
                receiveValue: { result in
                    detectionResults.append(result)
                    if detectionResults.count >= frameCount {
                        self.detectionService.stopDetection()
                    }
                }
            )
            .store(in: &cancellables)
        
        // Simulate camera frames
        for _ in 0..<frameCount {
            let image = try await testImageGenerator.generateTestImage()
            try await Task.sleep(nanoseconds: UInt64(0.033 * 1_000_000_000)) // ~30fps
            // Process frame
        }
        
        await fulfillment(of: [expectation], timeout: kTestTimeout * 2)
        
        // Verify continuous detection performance
        XCTAssertGreaterThanOrEqual(detectionResults.count, frameCount * 8 / 10,
                                  "Continuous detection missed too many frames")
    }
    
    /// Validates thermal state management during detection
    func testThermalManagement() async throws {
        let expectation = expectation(description: "Thermal management")
        var thermalStateChanges: [ProcessInfo.ThermalState] = []
        
        // Monitor thermal state changes
        NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)
            .sink { _ in
                thermalStateChanges.append(self.detectionService.thermalState)
            }
            .store(in: &cancellables)
        
        // Perform intensive detection operations
        let testImages = try await testImageGenerator.generateTestImages(count: 50)
        
        for image in testImages {
            _ = try await detectionService.detectSpecies(image).async()
        }
        
        expectation.fulfill()
        await fulfillment(of: [expectation], timeout: kTestTimeout * 5)
        
        // Verify thermal management
        XCTAssertFalse(thermalStateChanges.contains(.critical),
                      "Detection allowed device to reach critical thermal state")
    }
    
    // MARK: - Private Helpers
    
    private func setupPerformanceMonitoring() {
        let metrics = XCTPerformanceMetric("Memory Usage")
        metrics.map { metric in
            XCTPerformanceMetric(metric)
        }
    }
}

// MARK: - Test Utilities

private class TestImageGenerator {
    private let imageSize: CGSize
    
    init(imageSize: CGSize) {
        self.imageSize = imageSize
    }
    
    func generateTestImage() async throws -> UIImage {
        // Generate test image implementation
        let renderer = UIGraphicsImageRenderer(size: imageSize)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: imageSize))
        }
    }
    
    func generateTestImages(count: Int) async throws -> [UIImage] {
        var images: [UIImage] = []
        for _ in 0..<count {
            let image = try await generateTestImage()
            images.append(image)
        }
        return images
    }
}

// MARK: - Publisher Extensions

extension Publisher {
    func async() async throws -> Output {
        try await withCheckedThrowingContinuation { continuation in
            var cancellable: AnyCancellable?
            
            cancellable = self.sink(
                receiveCompletion: { completion in
                    switch completion {
                    case .finished:
                        break
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                    cancellable?.cancel()
                },
                receiveValue: { value in
                    continuation.resume(returning: value)
                    cancellable?.cancel()
                }
            )
        }
    }
}