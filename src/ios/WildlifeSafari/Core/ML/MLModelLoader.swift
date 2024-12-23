//
// MLModelLoader.swift
// WildlifeSafari
//
// Core ML model management utility providing thread-safe loading, caching,
// and versioning support for wildlife detection and fossil classification models.
//
// CoreML Version: 6.0+
// Foundation Version: Latest iOS SDK
//

import CoreML
import Foundation

/// Comprehensive error types for model loading and management operations
public enum ModelLoadingError: Error {
    case modelNotFound(String)
    case compilationFailed(String, Error)
    case invalidConfiguration(String)
    case versionMismatch(current: String, required: String)
    case insufficientMemory(requiredBytes: Int64)
}

/// Constants for model management
private enum Constants {
    static let kModelCacheSize: Int = 5
    static let kModelDirectory: String = "MLModels"
    static let kModelVersionKey: String = "ModelVersion"
    static let kCacheCountLimit: Int = 10
    static let kCacheCostLimit: Int = 524_288_000 // 500MB in bytes
}

/// Thread-safe singleton class for efficient ML model management
public final class MLModelLoader {
    
    // MARK: - Singleton Instance
    
    public static let shared = MLModelLoader()
    
    // MARK: - Private Properties
    
    private let modelCache: NSCache<NSString, MLModel>
    private let loadingQueue: DispatchQueue
    private let weakModelReferences: NSMapTable<NSString, MLModel>
    private let modelObservers: NSHashTable<AnyObject>
    private var memoryPressureToken: NSObjectProtocol?
    
    // MARK: - Initialization
    
    private init() {
        modelCache = NSCache<NSString, MLModel>()
        modelCache.countLimit = Constants.kCacheCountLimit
        modelCache.totalCostLimit = Constants.kCacheCostLimit
        
        loadingQueue = DispatchQueue(label: "com.wildlifesafari.modelloader", qos: .userInitiated)
        weakModelReferences = NSMapTable.strongToWeakObjects()
        modelObservers = NSHashTable.weakObjects()
        
        setupMemoryPressureHandling()
        setupModelDirectory()
    }
    
    // MARK: - Public Methods
    
    /// Asynchronously loads and compiles a Core ML model
    /// - Parameters:
    ///   - modelName: Name of the model to load
    ///   - configuration: Optional model configuration
    ///   - version: Optional version requirement
    /// - Returns: Result containing either the loaded model or an error
    @discardableResult
    public func loadModelWithName(
        _ modelName: String,
        configuration: MLModelConfiguration? = nil,
        version: String? = nil
    ) async -> Result<MLModel, ModelLoadingError> {
        return await loadingQueue.sync {
            // Check cache first
            if let cachedModel = modelCache.object(forKey: modelName as NSString) {
                if let version = version {
                    guard validateModelVersion(cachedModel, requiredVersion: version) else {
                        return .failure(.versionMismatch(
                            current: getCurrentModelVersion(cachedModel) ?? "unknown",
                            required: version
                        ))
                    }
                }
                return .success(cachedModel)
            }
            
            // Prepare model configuration
            let modelConfig = configuration ?? MLModelConfiguration()
            modelConfig.computeUnits = .cpuAndNeuralEngine
            
            // Attempt to load and compile model
            do {
                guard let modelURL = findModelURL(for: modelName) else {
                    return .failure(.modelNotFound(modelName))
                }
                
                let compiledModel = try await MLModel.load(
                    contentsOf: modelURL,
                    configuration: modelConfig
                )
                
                // Version validation for newly loaded model
                if let version = version {
                    guard validateModelVersion(compiledModel, requiredVersion: version) else {
                        return .failure(.versionMismatch(
                            current: getCurrentModelVersion(compiledModel) ?? "unknown",
                            required: version
                        ))
                    }
                }
                
                // Cache the successfully loaded model
                cacheModel(compiledModel, forKey: modelName)
                
                return .success(compiledModel)
            } catch {
                return .failure(.compilationFailed(modelName, error))
            }
        }
    }
    
    /// Preloads multiple models asynchronously
    /// - Parameters:
    ///   - modelNames: Array of model names to preload
    ///   - configuration: Optional shared configuration for all models
    public func preloadModels(
        _ modelNames: [String],
        configuration: MLModelConfiguration? = nil
    ) async {
        await withTaskGroup(of: Void.self) { group in
            for modelName in modelNames {
                group.addTask {
                    _ = await self.loadModelWithName(modelName, configuration: configuration)
                }
            }
        }
    }
    
    /// Clears model cache based on memory pressure
    /// - Parameter pressureLevel: Optional memory pressure level to consider
    public func clearModelCache(pressureLevel: MemoryPressureLevel? = nil) {
        loadingQueue.async {
            self.modelCache.removeAllObjects()
            self.weakModelReferences.removeAllObjects()
        }
    }
    
    /// Removes specific model from cache with optional disk cleanup
    /// - Parameters:
    ///   - modelName: Name of the model to purge
    ///   - removeFromDisk: Whether to also remove the model from disk
    public func purgeModel(_ modelName: String, removeFromDisk: Bool = false) {
        loadingQueue.async {
            self.modelCache.removeObject(forKey: modelName as NSString)
            self.weakModelReferences.removeObject(forKey: modelName as NSString)
            
            if removeFromDisk {
                if let modelURL = self.findModelURL(for: modelName) {
                    try? FileManager.default.removeItem(at: modelURL)
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func setupMemoryPressureHandling() {
        memoryPressureToken = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.clearModelCache(pressureLevel: .critical)
        }
    }
    
    private func setupModelDirectory() {
        guard let documentsPath = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else { return }
        
        let modelDirectoryURL = documentsPath.appendingPathComponent(Constants.kModelDirectory)
        
        if !FileManager.default.fileExists(atPath: modelDirectoryURL.path) {
            try? FileManager.default.createDirectory(
                at: modelDirectoryURL,
                withIntermediateDirectories: true
            )
        }
    }
    
    private func findModelURL(for modelName: String) -> URL? {
        // Check bundle first
        if let bundleURL = Bundle.main.url(
            forResource: modelName,
            withExtension: "mlmodelc"
        ) {
            return bundleURL
        }
        
        // Check documents directory
        if let documentsPath = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first {
            let modelURL = documentsPath
                .appendingPathComponent(Constants.kModelDirectory)
                .appendingPathComponent(modelName)
                .appendingPathExtension("mlmodelc")
            
            if FileManager.default.fileExists(atPath: modelURL.path) {
                return modelURL
            }
        }
        
        return nil
    }
    
    private func cacheModel(_ model: MLModel, forKey key: String) {
        modelCache.setObject(model, forKey: key as NSString)
        weakModelReferences.setObject(model, forKey: key as NSString)
    }
    
    private func validateModelVersion(_ model: MLModel, requiredVersion: String) -> Bool {
        guard let currentVersion = getCurrentModelVersion(model) else {
            return false
        }
        return currentVersion == requiredVersion
    }
    
    private func getCurrentModelVersion(_ model: MLModel) -> String? {
        return model.modelDescription.metadata[Constants.kModelVersionKey] as? String
    }
}

// MARK: - Supporting Types

private enum MemoryPressureLevel {
    case normal
    case warning
    case critical
}