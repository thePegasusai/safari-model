//
// SpeciesViewModel.swift
// WildlifeSafari
//
// Enterprise-grade ViewModel managing species detection, collection integration,
// and user interactions with comprehensive error handling and offline support.
//

import Combine // Latest - Reactive programming support
import SwiftUI // Latest - UI state management and accessibility support
import Foundation

// MARK: - Constants

private enum Constants {
    static let kMinDetectionConfidence: Float = 0.90
    static let kDetectionDebounceInterval: TimeInterval = 0.5
    static let kMaxRetryAttempts: Int = 3
    static let kOfflineCacheLimit: Int = 1000
    static let kThermalThrottleDelay: TimeInterval = 2.0
}

// MARK: - Types

/// Represents the current state of species detection
public enum DetectionState: Equatable {
    case idle
    case detecting
    case detected(Species)
    case failed(Error)
    case throttled
}

/// Represents the network connectivity state
public enum NetworkState: Equatable {
    case online
    case offline
    case limited
}

// MARK: - SpeciesViewModel

@MainActor
@available(iOS 14.0, *)
public final class SpeciesViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var currentSpecies: Species?
    @Published private(set) var detectionState: DetectionState = .idle
    @Published private(set) var networkState: NetworkState = .online
    @Published private(set) var detectionError: Error?
    
    // MARK: - Private Properties
    
    private let detectionService: DetectionService
    private let collectionService: CollectionService
    private var cancellables = Set<AnyCancellable>()
    private let detectionQueue = DispatchQueue(label: "com.wildlifesafari.detection",
                                             qos: .userInitiated)
    private var detectionDebouncer: AnyCancellable?
    private var thermalStateObserver: AnyCancellable?
    private let logger = Logger(subsystem: "com.wildlifesafari", category: "SpeciesViewModel")
    
    // MARK: - Initialization
    
    /// Initializes the species view model with required services
    /// - Parameters:
    ///   - detectionService: Service for species detection
    ///   - collectionService: Service for collection management
    public init(
        detectionService: DetectionService,
        collectionService: CollectionService
    ) {
        self.detectionService = detectionService
        self.collectionService = collectionService
        
        setupObservers()
        setupThermalMonitoring()
        configureAccessibility()
    }
    
    // MARK: - Public Methods
    
    /// Starts continuous species detection with thermal management
    /// - Returns: Publisher with detection state updates
    public func startDetection() -> AnyPublisher<DetectionState, Never> {
        guard case .idle = detectionState else {
            return Just(detectionState).eraseToAnyPublisher()
        }
        
        detectionState = .detecting
        
        return detectionService.startDetection(mode: .species)
            .debounce(for: .seconds(Constants.kDetectionDebounceInterval),
                     scheduler: detectionQueue)
            .map { [weak self] result -> DetectionState in
                guard let self = self else { return .idle }
                
                switch result {
                case .species(let prediction):
                    guard prediction.confidence >= Constants.kMinDetectionConfidence else {
                        return .failed(DetectionError.lowConfidence)
                    }
                    
                    self.currentSpecies = prediction.species
                    return .detected(prediction.species)
                    
                case .fossil:
                    return .failed(DetectionError.invalidInput)
                }
            }
            .catch { error -> AnyPublisher<DetectionState, Never> in
                return Just(.failed(error)).eraseToAnyPublisher()
            }
            .handleEvents(
                receiveOutput: { [weak self] state in
                    self?.detectionState = state
                },
                receiveCompletion: { [weak self] _ in
                    self?.detectionState = .idle
                }
            )
            .eraseToAnyPublisher()
    }
    
    /// Stops ongoing detection
    public func stopDetection() {
        detectionService.stopDetection()
        detectionState = .idle
        detectionDebouncer?.cancel()
    }
    
    /// Performs single species detection on an image
    /// - Parameter image: Input image for detection
    /// - Returns: Publisher with detection result
    public func detectSpeciesInImage(_ image: UIImage) -> AnyPublisher<Species, Error> {
        return detectionService.detectSpecies(image)
            .tryMap { result -> Species in
                switch result {
                case .species(let prediction):
                    guard prediction.confidence >= Constants.kMinDetectionConfidence else {
                        throw DetectionError.lowConfidence
                    }
                    return prediction.species
                    
                case .fossil:
                    throw DetectionError.invalidInput
                }
            }
            .handleEvents(
                receiveOutput: { [weak self] species in
                    self?.currentSpecies = species
                },
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.detectionError = error
                    }
                }
            )
            .eraseToAnyPublisher()
    }
    
    /// Adds current species to collection with offline support
    /// - Parameter collectionId: Target collection ID
    /// - Returns: Publisher with operation result
    public func addToCollection(_ collectionId: UUID) -> AnyPublisher<Void, Error> {
        guard let species = currentSpecies else {
            return Fail(error: CollectionError.invalidCollection)
                .eraseToAnyPublisher()
        }
        
        return collectionService.addDiscoveryToCollection(
            species,
            collectionId: collectionId
        )
        .handleEvents(
            receiveCompletion: { [weak self] completion in
                if case .failure(let error) = completion {
                    self?.logger.error("Failed to add to collection: \(error.localizedDescription)")
                }
            }
        )
        .eraseToAnyPublisher()
    }
    
    // MARK: - Private Methods
    
    private func setupObservers() {
        // Monitor network state changes
        NetworkReachability.shared.reachabilityPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isReachable in
                self?.networkState = isReachable ? .online : .offline
            }
            .store(in: &cancellables)
    }
    
    private func setupThermalMonitoring() {
        thermalStateObserver = NotificationCenter.default
            .publisher(for: ProcessInfo.thermalStateDidChangeNotification)
            .sink { [weak self] _ in
                self?.handleThermalStateChange()
            }
    }
    
    private func handleThermalStateChange() {
        let thermalState = ProcessInfo.processInfo.thermalState
        
        if thermalState == .critical {
            stopDetection()
            detectionState = .throttled
            
            DispatchQueue.main.asyncAfter(deadline: .now() + Constants.kThermalThrottleDelay) {
                self.detectionState = .idle
            }
        }
    }
    
    private func configureAccessibility() {
        // Configure accessibility labels and hints
        UIAccessibility.post(notification: .announcement,
                           argument: NSLocalizedString(
                            "Species detection ready",
                            comment: "Accessibility announcement"
                           ))
    }
}

// MARK: - Error Types

private enum DetectionError: LocalizedError {
    case invalidInput
    case lowConfidence
    case thermalThrottling
    
    var errorDescription: String? {
        switch self {
        case .invalidInput:
            return NSLocalizedString(
                "Invalid input for species detection",
                comment: "Invalid input error"
            )
        case .lowConfidence:
            return NSLocalizedString(
                "Detection confidence too low",
                comment: "Low confidence error"
            )
        case .thermalThrottling:
            return NSLocalizedString(
                "Detection paused due to device temperature",
                comment: "Thermal throttling error"
            )
        }
    }
}