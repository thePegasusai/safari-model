//
// Fossil.swift
// WildlifeSafari
//
// Core model representing a fossil specimen with comprehensive support for
// 3D visualization, location tracking, and educational metadata
//
// Foundation: Latest - Basic data types and Codable support
// CoreLocation: Latest - Location handling
// SceneKit: Latest - 3D model visualization

import Foundation
import CoreLocation
import SceneKit

/// Errors that can occur during fossil-related operations
enum FossilError: Error {
    case invalidModelURL
    case modelLoadingFailed
    case invalidMeasurements
    case serializationFailed
    case threadingError
}

/// Comprehensive model representing a fossil specimen with support for identification,
/// 3D visualization, location tracking, and educational metadata
@objc
@objcMembers
public class Fossil: NSObject, Codable {
    
    // MARK: - Public Properties
    
    /// Unique identifier for the fossil specimen
    public let id: UUID
    
    /// Scientific name following taxonomic nomenclature
    public let scientificName: String
    
    /// Common name for general reference
    public let commonName: String
    
    /// Geological period of origin
    public let period: String
    
    /// Estimated age in millions of years
    public let estimatedAge: Double
    
    /// Location where the fossil was discovered
    public let discoveryLocation: CLLocation
    
    /// Date when the fossil was discovered or recorded
    public let discoveryDate: Date
    
    /// AI model confidence score for identification (0.0 to 1.0)
    public private(set) var confidenceScore: Double
    
    /// Physical measurements in standardized units (meters)
    public private(set) var measurements: [String: Double]
    
    /// URL to the 3D model file
    public let threeDModelURL: URL?
    
    /// Collection of fossil image URLs
    public private(set) var images: [URL]
    
    /// Extended metadata for research purposes
    public private(set) var metadata: [String: Any]
    
    /// Loaded 3D model representation
    public private(set) var threeDModel: SCNNode?
    
    /// Flag indicating if 3D model is loaded
    public private(set) var isModelLoaded: Bool
    
    /// Last update timestamp
    public private(set) var lastUpdated: Date
    
    /// Taxonomic classification details
    public let taxonomicClassification: String
    
    /// Educational notes and descriptions
    public private(set) var educationalNotes: [String: String]
    
    // MARK: - Private Properties
    
    private let measurementsQueue = DispatchQueue(label: "com.wildlifesafari.fossil.measurements",
                                                attributes: .concurrent)
    private let modelLoadingQueue = DispatchQueue(label: "com.wildlifesafari.fossil.modelLoading",
                                                qos: .userInitiated)
    
    // MARK: - Initialization
    
    /// Initializes a new fossil instance with required properties and optional educational content
    /// - Parameters:
    ///   - id: Unique identifier for the fossil
    ///   - scientificName: Scientific taxonomic name
    ///   - commonName: Common reference name
    ///   - period: Geological period
    ///   - estimatedAge: Age in millions of years
    ///   - discoveryLocation: Location where found
    ///   - educationalNotes: Optional educational content
    ///   - taxonomicClassification: Optional taxonomic details
    public init(id: UUID,
                scientificName: String,
                commonName: String,
                period: String,
                estimatedAge: Double,
                discoveryLocation: CLLocation,
                educationalNotes: [String: String]? = nil,
                taxonomicClassification: String? = nil) {
        self.id = id
        self.scientificName = scientificName
        self.commonName = commonName
        self.period = period
        self.estimatedAge = estimatedAge
        self.discoveryLocation = discoveryLocation
        self.discoveryDate = Date()
        self.confidenceScore = 0.0
        self.measurements = [:]
        self.images = []
        self.metadata = [:]
        self.isModelLoaded = false
        self.lastUpdated = Date()
        self.educationalNotes = educationalNotes ?? [:]
        self.taxonomicClassification = taxonomicClassification ?? "Unclassified"
        
        super.init()
    }
    
    // MARK: - Public Methods
    
    /// Asynchronously loads and optimizes 3D model for visualization
    /// - Parameter lowMemoryMode: Flag to enable memory optimization
    /// - Returns: Result containing loaded model or error
    public func load3DModel(lowMemoryMode: Bool = false) async -> Result<SCNNode, Error> {
        return await withCheckedContinuation { continuation in
            modelLoadingQueue.async {
                guard let modelURL = self.threeDModelURL else {
                    continuation.resume(returning: .failure(FossilError.invalidModelURL))
                    return
                }
                
                if self.isModelLoaded, let model = self.threeDModel {
                    continuation.resume(returning: .success(model))
                    return
                }
                
                do {
                    let scene = try SCNScene(url: modelURL, options: [
                        .checkConsistency: true,
                        .flattenScene: lowMemoryMode
                    ])
                    
                    let node = scene.rootNode.clone()
                    
                    // Apply optimizations
                    if lowMemoryMode {
                        node.geometry?.firstMaterial?.lightingModel = .blinn
                        node.geometry?.firstMaterial?.diffuse.contents = nil
                    }
                    
                    self.threeDModel = node
                    self.isModelLoaded = true
                    self.lastUpdated = Date()
                    
                    continuation.resume(returning: .success(node))
                } catch {
                    continuation.resume(returning: .failure(FossilError.modelLoadingFailed))
                }
            }
        }
    }
    
    /// Thread-safe update of fossil measurements with validation
    /// - Parameter newMeasurements: Dictionary of new measurements to add/update
    /// - Returns: Result indicating success or failure
    public func updateMeasurements(_ newMeasurements: [String: Double]) -> Result<Void, Error> {
        var result: Result<Void, Error> = .success(())
        
        measurementsQueue.sync(flags: .barrier) {
            // Validate measurements
            guard newMeasurements.values.allSatisfy({ $0 > 0 }) else {
                result = .failure(FossilError.invalidMeasurements)
                return
            }
            
            self.measurements.merge(newMeasurements) { current, _ in current }
            self.lastUpdated = Date()
            
            // Update metadata
            self.metadata["lastMeasurementUpdate"] = Date()
            self.metadata["measurementCount"] = self.measurements.count
        }
        
        return result
    }
    
    /// Converts fossil data to JSON format with comprehensive error handling
    /// - Returns: Result containing JSON data or error
    public func toJSONData() -> Result<Data, Error> {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        do {
            let data = try encoder.encode(self)
            return .success(data)
        } catch {
            return .failure(FossilError.serializationFailed)
        }
    }
}

// MARK: - Codable Implementation

extension Fossil {
    private enum CodingKeys: String, CodingKey {
        case id, scientificName, commonName, period, estimatedAge
        case discoveryLocation, discoveryDate, confidenceScore
        case measurements, threeDModelURL, images, metadata
        case isModelLoaded, lastUpdated, taxonomicClassification
        case educationalNotes
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(scientificName, forKey: .scientificName)
        try container.encode(commonName, forKey: .commonName)
        try container.encode(period, forKey: .period)
        try container.encode(estimatedAge, forKey: .estimatedAge)
        try container.encode(discoveryDate, forKey: .discoveryDate)
        try container.encode(confidenceScore, forKey: .confidenceScore)
        try container.encode(measurements, forKey: .measurements)
        try container.encode(threeDModelURL, forKey: .threeDModelURL)
        try container.encode(images, forKey: .images)
        try container.encode(isModelLoaded, forKey: .isModelLoaded)
        try container.encode(lastUpdated, forKey: .lastUpdated)
        try container.encode(taxonomicClassification, forKey: .taxonomicClassification)
        try container.encode(educationalNotes, forKey: .educationalNotes)
        
        // Handle CLLocation encoding
        let locationDict: [String: Double] = [
            "latitude": discoveryLocation.coordinate.latitude,
            "longitude": discoveryLocation.coordinate.longitude,
            "altitude": discoveryLocation.altitude
        ]
        try container.encode(locationDict, forKey: .discoveryLocation)
    }
}