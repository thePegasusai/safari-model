//
// CameraViewModel.swift
// WildlifeSafari
//
// ViewModel that manages camera operations, real-time species detection, and UI state
// with advanced performance optimization and thermal management.
//

import Combine // Latest - Reactive programming support
import SwiftUI // Latest - UI state management and accessibility support

// MARK: - Constants

private enum Constants {
    static let kMinConfidenceThreshold: Float = 0.90
    static let kProcessingInterval: TimeInterval = 0.1
    static let kMaxBatchSize: Int = 4
    static let kThermalThrottleThreshold: Int = 2
    static let kMemoryWarningThreshold: Float = 0.8
    static let kFrameDropThreshold: Float = 0.2
}

// MARK: - Performance Metrics

public struct PerformanceMetrics {
    var frameRate: Double
    var processingTime: TimeInterval
    var thermalState: ProcessInfo.ThermalState
    var memoryUsage: Float
    var frameDropRate: Float
}

// MARK: - Camera View Model

@MainActor
@available(iOS 14.0, *)
public final class CameraViewModel: ObservableObject {
    
    // MARK: - Private Properties
    
    private let cameraManager: CameraManager
    private let speciesClassifier: SpeciesClassifier
    private let detectionPublisher = PassthroughSubject<SpeciesPrediction, Never>()
    private var processingQueue: DispatchQueue
    private var thermalState: ProcessInfo.ThermalState = .nominal
    private var frameDropper: Int = 0
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Published Properties
    
    @Published private(set) var isProcessing: Bool = false
    @Published private(set) var currentPrediction: SpeciesPrediction?
    @Published private(set) var error: Error?
    @Published private(set) var performanceMetrics = PerformanceMetrics(
        frameRate: 0,
        processingTime: 0,
        thermalState: .nominal,
        memoryUsage: 0,
        frameDropRate: 0
    )
    
    // MARK: - Initialization
    
    public init(cameraManager: CameraManager, speciesClassifier: SpeciesClassifier) {
        self.cameraManager = cameraManager
        self.speciesClassifier = speciesClassifier
        self.processingQueue = DispatchQueue(
            label: "com.wildlifesafari.camera.processing",
            qos: .userInteractive
        )
        
        setupDetectionPipeline()
        setupThermalMonitoring()
        setupMemoryMonitoring()
        setupPerformanceMonitoring()
    }
    
    // MARK: - Public Methods
    
    /// Sets up and configures the camera with thermal monitoring
    @MainActor
    public func setupCamera() async throws {
        do {
            try await cameraManager.setupCamera()
            setupAccessibility()
        } catch {
            self.error = error
            throw error
        }
    }
    
    /// Starts real-time species detection with performance optimization
    @MainActor
    public func startDetection() {
        guard !isProcessing else { return }
        
        isProcessing = true
        cameraManager.startCapture()
        
        // Start performance monitoring
        startPerformanceMonitoring()
    }
    
    /// Stops detection and releases resources
    @MainActor
    public func stopDetection() {
        guard isProcessing else { return }
        
        isProcessing = false
        cameraManager.stopCapture()
        
        // Stop performance monitoring
        stopPerformanceMonitoring()
    }
    
    // MARK: - Private Methods
    
    private func setupDetectionPipeline() {
        detectionPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] prediction in
                self?.handleNewPrediction(prediction)
            }
            .store(in: &cancellables)
    }
    
    private func setupThermalMonitoring() {
        NotificationCenter.default.publisher(
            for: ProcessInfo.thermalStateDidChangeNotification
        )
        .sink { [weak self] _ in
            self?.handleThermalStateChange()
        }
        .store(in: &cancellables)
    }
    
    private func setupMemoryMonitoring() {
        NotificationCenter.default.publisher(
            for: UIApplication.didReceiveMemoryWarningNotification
        )
        .sink { [weak self] _ in
            self?.handleMemoryWarning()
        }
        .store(in: &cancellables)
    }
    
    private func setupPerformanceMonitoring() {
        Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updatePerformanceMetrics()
            }
            .store(in: &cancellables)
    }
    
    private func handleNewPrediction(_ prediction: SpeciesPrediction) {
        guard prediction.confidence >= Constants.kMinConfidenceThreshold else { return }
        
        Task { @MainActor in
            self.currentPrediction = prediction
            updatePerformanceMetrics()
        }
    }
    
    private func handleThermalStateChange() {
        let newState = ProcessInfo.processInfo.thermalState
        thermalState = newState
        
        Task { @MainActor in
            performanceMetrics.thermalState = newState
            
            switch newState {
            case .nominal, .fair:
                adjustForNormalOperation()
            case .serious:
                adjustForThermalThrottling()
            case .critical:
                handleCriticalThermalState()
            @unknown default:
                adjustForNormalOperation()
            }
        }
    }
    
    private func handleMemoryWarning() {
        Task { @MainActor in
            performanceMetrics.memoryUsage = Float(ProcessInfo.processInfo.systemUptime)
            
            if performanceMetrics.memoryUsage > Constants.kMemoryWarningThreshold {
                adjustForMemoryPressure()
            }
        }
    }
    
    private func adjustForNormalOperation() {
        frameDropper = 0
        cameraManager.setThermalState(.nominal)
    }
    
    private func adjustForThermalThrottling() {
        frameDropper = Constants.kThermalThrottleThreshold
        cameraManager.setThermalState(.serious)
    }
    
    private func handleCriticalThermalState() {
        stopDetection()
        error = CameraError.thermalThrottling
    }
    
    private func adjustForMemoryPressure() {
        frameDropper = Constants.kThermalThrottleThreshold
        // Release non-essential resources
        currentPrediction = nil
    }
    
    private func updatePerformanceMetrics() {
        Task { @MainActor in
            performanceMetrics = PerformanceMetrics(
                frameRate: Double(30 - frameDropper),
                processingTime: ProcessInfo.processInfo.systemUptime,
                thermalState: thermalState,
                memoryUsage: Float(ProcessInfo.processInfo.systemUptime),
                frameDropRate: Float(frameDropper) / 30.0
            )
        }
    }
    
    private func setupAccessibility() {
        UIAccessibility.post(notification: .announcement, argument: "Camera ready for wildlife detection")
    }
    
    private func startPerformanceMonitoring() {
        // Reset metrics
        frameDropper = 0
        updatePerformanceMetrics()
    }
    
    private func stopPerformanceMonitoring() {
        // Clear metrics
        performanceMetrics = PerformanceMetrics(
            frameRate: 0,
            processingTime: 0,
            thermalState: .nominal,
            memoryUsage: 0,
            frameDropRate: 0
        )
    }
}

// MARK: - Error Types

public enum CameraError: LocalizedError {
    case setupFailed
    case thermalThrottling
    case processingError
    
    public var errorDescription: String? {
        switch self {
        case .setupFailed:
            return "Failed to setup camera"
        case .thermalThrottling:
            return "Camera stopped due to device temperature"
        case .processingError:
            return "Error processing camera feed"
        }
    }
}