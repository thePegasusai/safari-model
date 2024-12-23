//
// Constants.swift
// WildlifeSafari
//
// Centralized constants definition file containing configuration values,
// API settings, ML parameters, and other app-wide constants.
//
// Version: 1.0
// Foundation version: Latest
//

import Foundation

/// Primary namespace for all application-wide constants, organized into logical domains.
public struct AppConstants {
    
    /// API-related constants and configuration values for network operations.
    public struct API {
        /// Base URL for the Wildlife Safari API
        public static let baseURL = "https://api.wildlifesafari.com/v1"
        
        /// Default timeout interval for network requests (in seconds)
        public static let defaultTimeout: TimeInterval = 30.0
        
        /// Maximum number of retry attempts for failed requests
        public static let maxRetries: Int = 3
        
        /// Rate limit for species detection API (requests per minute)
        public static let detectionRateLimit: Int = 60
        
        /// Rate limit for collection management API (requests per minute)
        public static let collectionRateLimit: Int = 120
        
        /// Timeout interval for individual API requests (in seconds)
        public static let requestTimeout: TimeInterval = 10.0
        
        /// Batch size for bulk operations
        public static let batchSize: Int = 50
        
        /// Delay between retry attempts (in seconds)
        public static let retryDelay: TimeInterval = 1.0
        
        /// Maximum number of concurrent network requests
        public static let maxConcurrentRequests: Int = 4
    }
    
    /// Machine Learning related constants for LNN configuration and processing.
    public struct ML {
        /// Size of the Liquid Neural Network layer (number of neurons)
        public static let lnnLayerSize: Int = 1024
        
        /// Minimum time constant for neural dynamics (in milliseconds)
        public static let minTimeConstant: Double = 10.0
        
        /// Maximum time constant for neural dynamics (in milliseconds)
        public static let maxTimeConstant: Double = 100.0
        
        /// Learning rate for model adaptation
        public static let learningRate: Double = 0.001
        
        /// Standard input resolution for image processing
        public static let inputResolution = CGSize(width: 640, height: 640)
        
        /// Minimum confidence threshold for species detection
        public static let confidenceThreshold: Double = 0.85
        
        /// Maximum number of detections per frame
        public static let maxDetections: Int = 10
        
        /// Maximum time allowed for inference (in seconds)
        public static let inferenceTimeout: TimeInterval = 0.1
        
        /// Batch size for processing multiple images
        public static let batchProcessingSize: Int = 4
    }
    
    /// Storage and persistence related constants for data management.
    public struct Storage {
        /// Name of the Core Data model
        public static let modelName = "WildlifeSafari"
        
        /// Maximum cache size in bytes (100 MB)
        public static let cacheSizeLimit: Int = 100 * 1024 * 1024
        
        /// Interval between data synchronization attempts (in seconds)
        public static let syncInterval: TimeInterval = 300.0
        
        /// Maximum number of entries in the cache
        public static let maxCacheEntries: Int = 1000
        
        /// Time interval after which cache entries expire (24 hours)
        public static let cacheExpirationInterval: TimeInterval = 86400.0
        
        /// Maximum database size in bytes (500 MB)
        public static let maxDatabaseSize: Int = 500 * 1024 * 1024
        
        /// Threshold for database compaction (70% of max size)
        public static let compactionThreshold: Double = 0.7
        
        /// Interval between automatic backups (1 hour)
        public static let backupInterval: TimeInterval = 3600.0
    }
    
    // Prevent initialization of this constants container
    private init() {}
}