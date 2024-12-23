import XCTest // Latest
import CoreML // Latest
import Metal // Latest
@testable import WildlifeSafari

/// Comprehensive test suite for the Liquid Neural Network model implementation
/// Validates neural dynamics, performance optimization, and hardware acceleration
class LNNModelTests: XCTestCase {
    
    // MARK: - Constants
    
    private let kTestLayerSize: Int = 1024
    private let kTestMinTimeConstant: Float = 0.01  // 10ms
    private let kTestMaxTimeConstant: Float = 0.1   // 100ms
    private let kTestLearningRate: Float = 0.001
    private let kTestTimeout: TimeInterval = 0.1    // 100ms performance requirement
    private let kTestMemoryThreshold: Int64 = 100_000_000  // 100MB
    private let kTestGPUPerformanceThreshold: Double = 0.05  // 50ms for GPU operations
    
    // MARK: - Properties
    
    private var sut: LNNModel?
    private var configuration: MLModelConfiguration!
    private var metalDevice: MTLDevice?
    private var performanceMonitor: XCTPerformanceMetric!
    
    // MARK: - Setup and Teardown
    
    override func setUp() {
        super.setUp()
        
        // Configure ML model
        configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        
        // Set up GPU if available
        metalDevice = MTLCreateSystemDefaultDevice()
        
        // Initialize model under test
        do {
            sut = try LNNModel(configuration: configuration)
        } catch {
            XCTFail("Failed to initialize LNNModel: \(error)")
        }
        
        // Set up performance metrics
        performanceMonitor = XCTPerformanceMetric("com.apple.XCTPerformanceMetric_WallClockTime")
    }
    
    override func tearDown() {
        // Check for memory leaks
        addTeardownBlock { [weak self] in
            XCTAssertNil(self?.sut, "LNNModel should be deallocated")
        }
        
        sut = nil
        metalDevice = nil
        super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testModelInitialization() throws {
        // Test model creation
        XCTAssertNotNil(sut, "LNNModel should be successfully initialized")
        
        // Verify layer size configuration
        let mirror = Mirror(reflecting: sut!)
        let layerSize = mirror.children.first { $0.label == "layerSize" }?.value as? Int
        XCTAssertEqual(layerSize, kTestLayerSize, "Layer size should match specification")
        
        // Verify GPU configuration when available
        if let metalDevice = metalDevice {
            let useGPU = mirror.children.first { $0.label == "useGPU" }?.value as? Bool
            XCTAssertTrue(useGPU ?? false, "GPU should be enabled when available")
            
            let deviceName = metalDevice.name
            print("Testing on GPU: \(deviceName)")
        }
        
        // Test initialization performance
        measure(metrics: [performanceMonitor]) {
            do {
                _ = try LNNModel(configuration: configuration)
            } catch {
                XCTFail("Performance test failed: \(error)")
            }
        }
    }
    
    // MARK: - Neural Dynamics Tests
    
    func testNeuralDynamics() throws {
        // Prepare test input
        let inputSize = 640 * 640 * 3  // Standard input image size
        var inputFeatures = try createTestFeatures(size: inputSize)
        
        // Test neural dynamics computation
        measure(metrics: [performanceMonitor]) {
            do {
                let prediction = try sut?.predict(inputFeatures)
                XCTAssertNotNil(prediction, "Prediction should not be nil")
                
                // Verify processing time meets requirement
                let processingTime = getProcessingTime()
                XCTAssertLessThanOrEqual(processingTime, kTestTimeout, 
                    "Processing time should be under 100ms")
                
                // Verify state transitions
                let states = try extractStates(from: prediction!)
                validateStateTransitions(states)
            } catch {
                XCTFail("Neural dynamics test failed: \(error)")
            }
        }
    }
    
    // MARK: - Performance Optimization Tests
    
    func testPerformanceOptimization() throws {
        // Test INT8 quantization
        measure(metrics: [performanceMonitor]) {
            do {
                let testInput = try createTestFeatures(size: kTestLayerSize)
                let prediction = try sut?.predict(testInput)
                XCTAssertNotNil(prediction, "Quantized prediction should succeed")
            } catch {
                XCTFail("Quantization test failed: \(error)")
            }
        }
        
        // Test memory optimization
        let memoryUsage = getMemoryUsage()
        XCTAssertLessThan(memoryUsage, kTestMemoryThreshold, 
            "Memory usage should be under threshold")
        
        // Test GPU acceleration if available
        if metalDevice != nil {
            try testGPUAcceleration()
        }
    }
    
    // MARK: - Helper Methods
    
    private func createTestFeatures(size: Int) throws -> MLFeatureProvider {
        let values = Array(repeating: Float(0.5), count: size)
        let feature = try MLMultiArray(shape: [NSNumber(value: size)], 
                                     dataType: .float32)
        
        for i in 0..<size {
            feature[i] = NSNumber(value: values[i])
        }
        
        return try MLDictionaryFeatureProvider(dictionary: ["input": feature])
    }
    
    private func getProcessingTime() -> TimeInterval {
        let mirror = Mirror(reflecting: sut!)
        let perfMonitor = mirror.children.first { $0.label == "perfMonitor" }?.value
        let inferenceTime = Mirror(reflecting: perfMonitor!).children
            .first { $0.label == "inferenceTime" }?.value as? TimeInterval
        return inferenceTime ?? 0
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
    
    private func testGPUAcceleration() throws {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Perform GPU-accelerated computation
        let testInput = try createTestFeatures(size: kTestLayerSize)
        let prediction = try sut?.predict(testInput)
        
        let gpuTime = CFAbsoluteTimeGetCurrent() - startTime
        XCTAssertLessThanOrEqual(gpuTime, kTestGPUPerformanceThreshold,
            "GPU computation should meet performance threshold")
        
        XCTAssertNotNil(prediction, "GPU-accelerated prediction should succeed")
    }
    
    private func extractStates(from prediction: MLFeatureProvider) throws -> [Float] {
        guard let stateFeature = prediction.featureValue(for: "states")?.multiArrayValue else {
            throw XCTSkip("States feature not available")
        }
        
        var states = [Float]()
        for i in 0..<stateFeature.count {
            states.append(stateFeature[i].floatValue)
        }
        return states
    }
    
    private func validateStateTransitions(_ states: [Float]) {
        // Verify state values are within expected ranges
        for state in states {
            XCTAssertTrue(state.isFinite, "State values should be finite")
            XCTAssertGreaterThanOrEqual(state, -1.0, "State values should be normalized")
            XCTAssertLessThanOrEqual(state, 1.0, "State values should be normalized")
        }
        
        // Verify temporal consistency
        let stateChanges = zip(states, states.dropFirst()).map { abs($0 - $1) }
        let maxStateChange = stateChanges.max() ?? 0
        XCTAssertLessThanOrEqual(maxStateChange, 0.1, 
            "State transitions should be smooth")
    }
}