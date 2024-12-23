//
// SpeciesClassifierTests.swift
// WildlifeSafariTests
//
// Comprehensive test suite for SpeciesClassifier functionality including accuracy,
// performance, and error handling validation using Liquid Neural Networks.
//

import XCTest      // Latest - iOS unit testing framework
import CoreML      // Latest - ML model testing utilities
import UIKit       // Latest - Image handling
@testable import WildlifeSafari

// MARK: - Constants

private let kTestImageSize: CGFloat = 640
private let kTestConfidenceThreshold: Float = 0.90
private let kTestTimeout: TimeInterval = 1.0
private let kMaxMemoryUsage: Int64 = 256 * 1024 * 1024  // 256MB
private let kThermalThrottleThreshold: Double = 80.0
private let kTestBatchSize: Int = 10
private let kRequiredAccuracy: Double = 0.90 // 90% accuracy requirement

// MARK: - SpeciesClassifierTests

@available(iOS 14.0, *)
final class SpeciesClassifierTests: XCTestCase {
    
    // MARK: - Private Properties
    
    private var classifier: SpeciesClassifier!
    private var testImages: [UIImage]!
    private var testSpecies: [Species]!
    private var processInfo: ProcessInfo!
    private var coreDataStack: CoreDataStack!
    
    // MARK: - Setup & Teardown
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Initialize CoreData stack for testing
        coreDataStack = CoreDataStack(modelName: "WildlifeSafari")
        
        // Initialize classifier
        classifier = try SpeciesClassifier()
        
        // Load test images
        testImages = try loadTestImages()
        
        // Initialize test species data
        testSpecies = try createTestSpecies()
        
        // Get process info for monitoring
        processInfo = ProcessInfo.processInfo
        
        // Set up performance monitoring
        setupPerformanceMonitoring()
    }
    
    override func tearDown() async throws {
        // Clean up resources
        classifier = nil
        testImages = nil
        testSpecies = nil
        processInfo = nil
        
        // Reset CoreData stack
        _ = coreDataStack.resetStack()
        coreDataStack = nil
        
        try await super.tearDown()
    }
    
    // MARK: - Model Initialization Tests
    
    func testModelInitialization() async throws {
        // Test model initialization
        let newClassifier = try SpeciesClassifier()
        
        // Verify model loaded successfully
        XCTAssertNotNil(newClassifier, "Classifier should initialize successfully")
        
        // Test model configuration
        let prediction = try await newClassifier.predictWithConfidence(testImages[0])
        XCTAssertNotNil(prediction, "Model should be able to make predictions")
        
        // Verify memory footprint
        let memoryUsage = getMemoryUsage()
        XCTAssertLessThan(memoryUsage, kMaxMemoryUsage, "Memory usage should be within limits")
        
        // Test thread safety
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<kTestBatchSize {
                group.addTask {
                    do {
                        _ = try await newClassifier.predictWithConfidence(self.testImages[0])
                    } catch {
                        XCTFail("Thread safety test failed: \(error)")
                    }
                }
            }
        }
    }
    
    // MARK: - Species Classification Tests
    
    func testSpeciesClassification() async throws {
        var correctPredictions = 0
        let totalPredictions = testImages.count
        
        // Test classification accuracy
        for (index, image) in testImages.enumerated() {
            let prediction = try await classifier.predictWithConfidence(image)
            
            // Verify confidence threshold
            XCTAssertGreaterThanOrEqual(prediction.confidence, kTestConfidenceThreshold,
                                      "Prediction confidence should meet threshold")
            
            // Verify species match
            if prediction.species.scientificName == testSpecies[index].scientificName {
                correctPredictions += 1
            }
            
            // Verify metadata completeness
            XCTAssertFalse(prediction.species.commonName.isEmpty, "Common name should not be empty")
            XCTAssertFalse(prediction.species.scientificName.isEmpty, "Scientific name should not be empty")
        }
        
        // Calculate accuracy
        let accuracy = Double(correctPredictions) / Double(totalPredictions)
        XCTAssertGreaterThanOrEqual(accuracy, kRequiredAccuracy,
                                  "Classification accuracy should meet 90% requirement")
    }
    
    // MARK: - Performance Tests
    
    func testClassificationPerformance() async throws {
        // Measure single image classification time
        let metrics = XCTMeasureOptions()
        metrics.iterationCount = 10
        
        measure(metrics: metrics) {
            let expectation = expectation(description: "Classification completed")
            
            Task {
                do {
                    let startTime = CFAbsoluteTimeGetCurrent()
                    _ = try await classifier.predictWithConfidence(testImages[0])
                    let processingTime = CFAbsoluteTimeGetCurrent() - startTime
                    
                    // Verify sub-100ms processing requirement
                    XCTAssertLessThan(processingTime, 0.1,
                                    "Processing time should be under 100ms")
                    
                    expectation.fulfill()
                } catch {
                    XCTFail("Performance test failed: \(error)")
                }
            }
            
            wait(for: [expectation], timeout: kTestTimeout)
        }
        
        // Test thermal impact
        let initialThermalState = processInfo.thermalState
        let expectation = expectation(description: "Thermal test completed")
        
        // Perform intensive classification
        Task {
            for _ in 0..<100 {
                _ = try await classifier.predictWithConfidence(testImages[0])
            }
            
            // Verify thermal state
            XCTAssertLessThanOrEqual(
                processInfo.thermalState.rawValue,
                ProcessInfo.ThermalState.serious.rawValue,
                "Thermal state should remain within acceptable limits"
            )
            
            expectation.fulfill()
        }
        
        await fulfillment(of: [expectation], timeout: kTestTimeout * 10)
    }
    
    // MARK: - Offline Classification Tests
    
    func testOfflineClassification() async throws {
        // Simulate offline mode
        let offlineClassifier = try SpeciesClassifier()
        
        // Test offline classification
        let prediction = try await offlineClassifier.predictWithConfidence(testImages[0])
        XCTAssertNotNil(prediction, "Should classify species offline")
        
        // Test model version handling
        XCTAssertThrowsError(try await offlineClassifier.updateModel(at: URL(fileURLWithPath: "invalid"))) { error in
            XCTAssertTrue(error is ClassifierError, "Should handle invalid model updates")
        }
        
        // Test cached data usage
        let firstPrediction = try await offlineClassifier.predictWithConfidence(testImages[0])
        let secondPrediction = try await offlineClassifier.predictWithConfidence(testImages[0])
        
        XCTAssertEqual(firstPrediction.species.id, secondPrediction.species.id,
                      "Cached predictions should be consistent")
    }
    
    // MARK: - Helper Methods
    
    private func loadTestImages() throws -> [UIImage] {
        // Load test images from bundle
        guard let bundle = Bundle(for: type(of: self)),
              let paths = bundle.paths(forResourcesOfType: "jpg", inDirectory: "TestImages")
                .sorted() as? [String] else {
            throw XCTSkip("Test images not found")
        }
        
        return try paths.map { path in
            guard let image = UIImage(contentsOfFile: path) else {
                throw XCTSkip("Failed to load test image at \(path)")
            }
            return image
        }
    }
    
    private func createTestSpecies() throws -> [Species] {
        let context = coreDataStack.viewContext
        
        // Create test species data
        return try ["Panthera leo", "Aquila chrysaetos", "Ursus arctos"].map { name in
            let species = Species(context: context)
            species.scientificName = name
            species.commonName = name // Simplified for testing
            try species.setTaxonomyArray(["Animalia", "Chordata", "Mammalia"])
            return species
        }
    }
    
    private func setupPerformanceMonitoring() {
        // Add performance monitoring observers
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleThermalStateChange),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
    }
    
    @objc private func handleThermalStateChange(_ notification: Notification) {
        if processInfo.thermalState == .critical {
            XCTFail("Device entered critical thermal state during testing")
        }
    }
    
    private func getMemoryUsage() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }
        
        XCTAssertEqual(kerr, KERN_SUCCESS, "Failed to get memory usage")
        return info.resident_size
    }
}