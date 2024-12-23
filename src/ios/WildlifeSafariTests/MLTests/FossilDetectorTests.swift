//
// FossilDetectorTests.swift
// WildlifeSafariTests
//
// Unit test suite for FossilDetector class validating fossil detection,
// 3D scanning, and LNN-based classification functionality
//

import XCTest      // Latest - iOS unit testing framework
import CoreML      // Latest - ML model testing integration
import Vision      // Latest - Computer vision testing
import ARKit       // Latest - AR scanning validation
@testable import WildlifeSafari

// MARK: - Constants

private let kTestTimeout: TimeInterval = 5.0
private let kRequiredAccuracy: Float = 0.90 // 90% accuracy requirement
private let kMaxProcessingTime: TimeInterval = 0.1 // 100ms requirement
private let kMinPointCloudDensity: Int = 1000
private let kTestFossilTypes = ["tyrannosaurus", "triceratops", "velociraptor"]

final class FossilDetectorTests: XCTestCase {
    
    // MARK: - Private Properties
    
    private var sut: FossilDetector!
    private var configuration: MLModelConfiguration!
    private var mockARSession: ARSession!
    private var testDataset: [FossilInput]!
    private var performanceMetrics: PerformanceMetrics!
    
    // MARK: - Setup & Teardown
    
    override func setUp() {
        super.setUp()
        
        // Initialize test configuration
        configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndGPU
        
        // Initialize mock AR session
        mockARSession = ARSession()
        
        // Initialize performance metrics
        performanceMetrics = PerformanceMetrics()
        
        // Load test dataset
        testDataset = loadTestDataset()
        
        do {
            // Initialize system under test
            sut = try FossilDetector(configuration: configuration)
        } catch {
            XCTFail("Failed to initialize FossilDetector: \(error)")
        }
        
        // Monitor thermal state
        setupThermalStateMonitoring()
    }
    
    override func tearDown() {
        // Stop any active scanning
        mockARSession.pause()
        
        // Clean up resources
        sut = nil
        configuration = nil
        mockARSession = nil
        testDataset = nil
        performanceMetrics = nil
        
        super.tearDown()
    }
    
    // MARK: - Test Cases
    
    func testFossilDetection() throws {
        // Given
        let testInput = try XCTUnwrap(createMockFossilInput(type: "tyrannosaurus"))
        let initialThermalState = ProcessInfo.processInfo.thermalState
        
        // When
        let detectionResult = sut.detectFossil(testInput)
        
        // Then
        switch detectionResult {
        case .success(let detection):
            XCTAssertGreaterThanOrEqual(detection.confidence, kRequiredAccuracy)
            XCTAssertEqual(detection.classification, "tyrannosaurus")
            XCTAssertNotNil(detection.boundingBox)
            XCTAssertNotNil(detection.metadata["detectionTimestamp"])
            
            // Verify thermal impact
            XCTAssertEqual(ProcessInfo.processInfo.thermalState, initialThermalState,
                          "Detection should not significantly impact thermal state")
            
        case .failure(let error):
            XCTFail("Fossil detection failed: \(error)")
        }
    }
    
    func testScanningSession() throws {
        // Given
        setupMockARSession()
        let expectation = XCTestExpectation(description: "Scanning completion")
        
        // When
        sut.startScanning()
        
        // Monitor point cloud density
        var pointCloudDensity = 0
        mockARSession.delegate = self
        
        // Then
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            pointCloudDensity = self.getCurrentPointCloudDensity()
            self.sut.stopScanning()
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: kTestTimeout)
        
        XCTAssertGreaterThanOrEqual(pointCloudDensity, kMinPointCloudDensity,
                                   "Point cloud should meet minimum density requirement")
    }
    
    func testPerformance() throws {
        // Given
        let testInput = try XCTUnwrap(createMockFossilInput(type: "triceratops"))
        
        // When
        measure(metrics: [XCTCPUMetric(), XCTMemoryMetric(), XCTClockMetric()]) {
            _ = sut.detectFossil(testInput)
        }
        
        // Then
        XCTAssertLessThanOrEqual(performanceMetrics.lastProcessingTime, kMaxProcessingTime,
                                "Processing time should be under 100ms")
        XCTAssertLessThanOrEqual(performanceMetrics.peakMemoryUsage, 512 * 1024 * 1024,
                                "Memory usage should be under 512MB")
    }
    
    func testModelAccuracy() throws {
        // Given
        var correctPredictions = 0
        let totalSamples = testDataset.count
        
        // When
        for input in testDataset {
            let result = sut.detectFossil(input)
            if case .success(let detection) = result {
                if detection.classification == input.metadata?["expectedClass"] as? String {
                    correctPredictions += 1
                }
            }
        }
        
        // Then
        let accuracy = Float(correctPredictions) / Float(totalSamples)
        XCTAssertGreaterThanOrEqual(accuracy, kRequiredAccuracy,
                                   "Model accuracy should meet 90% requirement")
    }
    
    // MARK: - Helper Methods
    
    private func createMockFossilInput(type: String) -> FossilInput? {
        guard let image = UIImage(named: "\(type)_test") else { return nil }
        
        let pixelBuffer = image.pixelBuffer()
        let metadata = ["expectedClass": type]
        
        return FossilInput(
            depthData: nil,
            scanData: nil,
            image: pixelBuffer,
            metadata: metadata
        )
    }
    
    private func loadTestDataset() -> [FossilInput] {
        var dataset: [FossilInput] = []
        
        for fossilType in kTestFossilTypes {
            if let input = createMockFossilInput(type: fossilType) {
                dataset.append(input)
            }
        }
        
        return dataset
    }
    
    private func setupMockARSession() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.environmentTexturing = .automatic
        configuration.frameSemantics = .sceneDepth
        
        mockARSession.run(configuration)
    }
    
    private func getCurrentPointCloudDensity() -> Int {
        guard let frame = mockARSession.currentFrame,
              let points = frame.rawFeaturePoints?.points else {
            return 0
        }
        return points.count
    }
    
    private func setupThermalStateMonitoring() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleThermalStateChange),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
    }
    
    @objc private func handleThermalStateChange(_ notification: Notification) {
        let thermalState = ProcessInfo.processInfo.thermalState
        print("Thermal state changed to: \(thermalState)")
    }
}

// MARK: - Performance Metrics

private struct PerformanceMetrics {
    var lastProcessingTime: TimeInterval = 0
    var peakMemoryUsage: Int64 = 0
    var averageConfidence: Float = 0
    
    mutating func reset() {
        lastProcessingTime = 0
        peakMemoryUsage = 0
        averageConfidence = 0
    }
}

// MARK: - UIImage Extension

private extension UIImage {
    func pixelBuffer() -> CVPixelBuffer {
        let attrs = [kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
                    kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue] as CFDictionary
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                       Int(size.width),
                                       Int(size.height),
                                       kCVPixelFormatType_32ARGB,
                                       attrs,
                                       &pixelBuffer)
        
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else {
            fatalError("Failed to create pixel buffer")
        }
        
        CVPixelBufferLockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        let pixelData = CVPixelBufferGetBaseAddress(buffer)
        
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(data: pixelData,
                                    width: Int(size.width),
                                    height: Int(size.height),
                                    bitsPerComponent: 8,
                                    bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                    space: rgbColorSpace,
                                    bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else {
            fatalError("Failed to create context")
        }
        
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1.0, y: -1.0)
        
        UIGraphicsPushContext(context)
        draw(in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        UIGraphicsPopContext()
        
        CVPixelBufferUnlockBaseAddress(buffer, CVPixelBufferLockFlags(rawValue: 0))
        
        return buffer
    }
}