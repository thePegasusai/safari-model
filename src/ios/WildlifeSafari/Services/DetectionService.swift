//
// DetectionService.swift
// WildlifeSafari
//
// Core service coordinating wildlife species detection and fossil identification
// with enhanced thermal management and memory optimization.
//

import Combine      // Latest - Enhanced reactive programming support
import CoreML      // Latest - Machine learning model execution
import UIKit       // Latest - Image handling and UI integration
import Foundation  // Latest - Basic functionality

// MARK: - Types

/// Detection modes supported by the service
public enum DetectionMode {
    case species
    case fossil
}

/// Detection options for configuring the detection process
public struct DetectionOptions {
    let confidenceThreshold: Float
    let enableThermalProtection: Bool
    let enableMemoryOptimization: Bool
    let processingQuality: ProcessingQuality
    
    public static let `default` = DetectionOptions(
        confidenceThreshold: 0.90,
        enableThermalProtection: true,
        enableMemoryOptimization: true,
        processingQuality: .balanced
    )
}

/// Processing quality levels
public enum ProcessingQuality {
    case low
    case balanced
    case high
}

/// Detection result types
public enum DetectionResult {
    case species(SpeciesPrediction)
    case fossil(FossilDetection)
    
    var confidence: Float {
        switch self {
        case .species(let prediction):
            return prediction.confidence
        case .fossil(let detection):
            return detection.confidence
        }
    }
}

/// Detection-specific errors
public enum DetectionError: LocalizedError {
    case invalidInput
    case detectionFailed(String)
    case lowConfidence
    case thermalLimitReached
    case memoryPressure
    case offlineUnavailable
    
    public var errorDescription: String? {
        switch self {
        case .invalidInput:
            return "Invalid input provided"
        case .detectionFailed(let message):
            return "Detection failed: \(message)"
        case .lowConfidence:
            return "Detection confidence below threshold"
        case .thermalLimitReached:
            return "Device thermal limit reached"
        case .memoryPressure:
            return "Insufficient memory available"
        case .offlineUnavailable:
            return "Offline detection unavailable"
        }
    }
}

// MARK: - DetectionService

@available(iOS 14.0, *)
public final class DetectionService {
    
    // MARK: - Private Properties
    
    private let speciesClassifier: SpeciesClassifier
    private let fossilDetector: FossilDetector
    private let options: DetectionOptions
    private var currentMode: DetectionMode = .species
    private let detectionSubject = PassthroughSubject<DetectionResult, DetectionError>()
    private var cancellables = Set<AnyCancellable>()
    
    private let processingQueue: DispatchQueue
    private let logger = Logger(subsystem: "com.wildlifesafari", category: "DetectionService")
    
    // MARK: - Public Properties
    
    public var thermalState: ProcessInfo.ThermalState {
        ProcessInfo.processInfo.thermalState
    }
    
    // MARK: - Initialization
    
    /// Initializes the detection service with specified configuration
    /// - Parameters:
    ///   - configuration: ML model configuration
    ///   - options: Detection options
    public init(configuration: MLModelConfiguration = MLModelConfiguration(),
                options: DetectionOptions = .default) throws {
        self.options = options
        
        // Initialize core components
        self.speciesClassifier = try SpeciesClassifier()
        self.fossilDetector = try FossilDetector(configuration: configuration)
        
        // Configure processing queue
        self.processingQueue = DispatchQueue(
            label: "com.wildlifesafari.detection",
            qos: .userInitiated
        )
        
        // Set up monitoring
        setupThermalMonitoring()
        setupMemoryMonitoring()
        
        logger.info("DetectionService initialized successfully")
    }
    
    // MARK: - Public Methods
    
    /// Starts continuous detection with specified mode
    /// - Parameters:
    ///   - mode: Detection mode to use
    ///   - options: Optional detection options
    /// - Returns: Publisher emitting detection results
    public func startDetection(
        mode: DetectionMode,
        options: DetectionOptions? = nil
    ) -> AnyPublisher<DetectionResult, DetectionError> {
        currentMode = mode
        
        // Configure detection based on mode
        switch mode {
        case .species:
            configureSpeciesDetection(options ?? self.options)
        case .fossil:
            configureFossilDetection(options ?? self.options)
        }
        
        return detectionSubject.eraseToAnyPublisher()
    }
    
    /// Stops ongoing detection
    public func stopDetection() {
        detectionSubject.send(completion: .finished)
    }
    
    /// Performs single species detection
    /// - Parameters:
    ///   - image: Input image
    ///   - options: Optional detection options
    /// - Returns: Publisher with detection result
    @discardableResult
    public func detectSpecies(
        _ image: UIImage,
        options: DetectionOptions? = nil
    ) -> AnyPublisher<DetectionResult, DetectionError> {
        return Future { [weak self] promise in
            guard let self = self else {
                promise(.failure(.detectionFailed("Service unavailable")))
                return
            }
            
            // Check thermal state
            guard self.thermalState != .critical else {
                promise(.failure(.thermalLimitReached))
                return
            }
            
            Task {
                do {
                    let prediction = try await self.speciesClassifier.classifySpecies(image)
                    
                    guard let topPrediction = prediction.first,
                          topPrediction.confidence >= (options ?? self.options).confidenceThreshold else {
                        promise(.failure(.lowConfidence))
                        return
                    }
                    
                    promise(.success(.species(topPrediction)))
                } catch {
                    promise(.failure(.detectionFailed(error.localizedDescription)))
                }
            }
        }.eraseToAnyPublisher()
    }
    
    /// Performs fossil detection
    /// - Parameters:
    ///   - session: AR session for 3D scanning
    ///   - options: Optional detection options
    /// - Returns: Publisher with detection result
    @discardableResult
    public func detectFossil(
        _ session: ARSession,
        options: DetectionOptions? = nil
    ) -> AnyPublisher<DetectionResult, DetectionError> {
        return Future { [weak self] promise in
            guard let self = self else {
                promise(.failure(.detectionFailed("Service unavailable")))
                return
            }
            
            // Check thermal state and memory pressure
            guard self.thermalState != .critical else {
                promise(.failure(.thermalLimitReached))
                return
            }
            
            // Create fossil input from AR session
            guard let frame = session.currentFrame,
                  let pixelBuffer = frame.capturedImage,
                  let depthData = frame.sceneDepth?.depthMap,
                  let pointCloud = frame.rawFeaturePoints else {
                promise(.failure(.invalidInput))
                return
            }
            
            let input = FossilInput(
                depthData: depthData,
                scanData: pointCloud,
                image: pixelBuffer,
                metadata: nil
            )
            
            // Perform detection
            let result = self.fossilDetector.detectFossil(input)
            
            switch result {
            case .success(let detection):
                guard detection.confidence >= (options ?? self.options).confidenceThreshold else {
                    promise(.failure(.lowConfidence))
                    return
                }
                promise(.success(.fossil(detection)))
            case .failure(let error):
                promise(.failure(.detectionFailed(error.localizedDescription)))
            }
        }.eraseToAnyPublisher()
    }
    
    // MARK: - Private Methods
    
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
    
    private func handleThermalStateChange() {
        if thermalState == .critical {
            detectionSubject.send(completion: .failure(.thermalLimitReached))
            stopDetection()
        }
    }
    
    private func handleMemoryWarning() {
        detectionSubject.send(completion: .failure(.memoryPressure))
        stopDetection()
    }
    
    private func configureSpeciesDetection(_ options: DetectionOptions) {
        // Configure species classifier with options
        // Implementation details would depend on SpeciesClassifier configuration options
    }
    
    private func configureFossilDetection(_ options: DetectionOptions) {
        // Configure fossil detector with options
        // Implementation details would depend on FossilDetector configuration options
    }
}