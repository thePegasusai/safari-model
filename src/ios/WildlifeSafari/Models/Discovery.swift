//
// Discovery.swift
// WildlifeSafari
//
// Core Data managed object model representing a wildlife or fossil discovery
// with enhanced security and validation features.
//

import Foundation  // Latest - Basic iOS functionality
import CoreData    // Latest - Data persistence framework
import CoreLocation // Latest - Location services integration
import CryptoKit   // Latest - Data encryption and security

// MARK: - Constants

private let kDefaultConfidence: Double = 0.0
private let kMinimumConfidenceThreshold: Double = 0.7
private let kMaxImageSize: Int = 10 * 1024 * 1024 // 10MB
private let kLocationPrecisionLevel: Int = 3
private let kMaxNotesLength: Int = 1000

// MARK: - Error Types

enum DiscoveryError: LocalizedError {
    case invalidSpecies
    case invalidLocation
    case invalidConfidence
    case invalidImage
    case invalidNotes
    case securityValidationFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidSpecies: return "Invalid species data"
        case .invalidLocation: return "Invalid location data"
        case .invalidConfidence: return "Confidence score below threshold"
        case .invalidImage: return "Invalid image data"
        case .invalidNotes: return "Invalid notes content"
        case .securityValidationFailed: return "Security validation failed"
        }
    }
}

// MARK: - Discovery Entity

@objc(Discovery)
@objcMembers
public class Discovery: NSManagedObject {
    
    // MARK: - Properties
    
    @NSManaged public private(set) var discoveryId: UUID
    @NSManaged public private(set) var timestamp: Date
    @NSManaged public private(set) var location: Location?
    @NSManaged public private(set) var species: Species?
    @NSManaged public private(set) var confidence: Double
    @NSManaged private var encryptedImageData: Data?
    @NSManaged public private(set) var sanitizedNotes: String?
    @NSManaged public private(set) var isVerified: Bool
    @NSManaged public private(set) var isSynced: Bool
    @NSManaged public private(set) var collection: NSManagedObject?
    @NSManaged public private(set) var lastModified: Date
    @NSManaged public private(set) var createdBy: String
    @NSManaged private var securityHash: Data?
    
    // MARK: - Initialization
    
    public override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?) {
        super.init(entity: entity, insertInto: context)
        
        // Initialize with secure random UUID
        self.discoveryId = UUID()
        self.timestamp = Date()
        self.confidence = kDefaultConfidence
        self.isVerified = false
        self.isSynced = false
        self.lastModified = Date()
        self.createdBy = UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        
        // Initialize security hash
        updateSecurityHash()
    }
    
    // MARK: - Public Methods
    
    /// Securely associates the discovery with a species
    /// - Parameters:
    ///   - species: The species to associate
    ///   - confidence: Confidence score of the identification
    /// - Returns: Result indicating success or failure
    public func setSpecies(_ species: Species, confidence: Double) -> Result<Void, Error> {
        guard confidence >= kMinimumConfidenceThreshold else {
            return .failure(DiscoveryError.invalidConfidence)
        }
        
        do {
            // Validate species relationship
            try species.validateForUpdate()
            
            self.species = species
            self.confidence = confidence
            self.lastModified = Date()
            self.isSynced = false
            
            try species.addDiscovery(self)
            updateSecurityHash()
            
            return .success(())
        } catch {
            return .failure(error)
        }
    }
    
    /// Securely sets and anonymizes the location
    /// - Parameter location: The location to set
    /// - Returns: Result indicating success or failure
    public func setLocation(_ location: Location) -> Result<Void, Error> {
        do {
            // Create anonymized location
            let secureLocation = location.anonymize()
            
            // Validate location data
            guard CLLocationCoordinate2DIsValid(secureLocation.coordinate) else {
                return .failure(DiscoveryError.invalidLocation)
            }
            
            self.location = secureLocation
            self.lastModified = Date()
            self.isSynced = false
            
            updateSecurityHash()
            
            return .success(())
        } catch {
            return .failure(error)
        }
    }
    
    /// Securely stores and processes image data
    /// - Parameter imageData: The image data to store
    /// - Returns: Result indicating success or failure
    public func setImage(_ imageData: Data) -> Result<Void, Error> {
        guard imageData.count <= kMaxImageSize else {
            return .failure(DiscoveryError.invalidImage)
        }
        
        do {
            // Strip metadata and compress if needed
            let processedData = try processImageData(imageData)
            
            // Encrypt image data
            let encryptedData = try encryptImageData(processedData)
            
            self.encryptedImageData = encryptedData
            self.lastModified = Date()
            self.isSynced = false
            
            updateSecurityHash()
            
            return .success(())
        } catch {
            return .failure(error)
        }
    }
    
    /// Comprehensive validation of discovery data
    /// - Returns: Result indicating validation success or failure
    public func validate() -> Result<Void, Error> {
        do {
            // Verify security hash
            guard validateSecurityHash() else {
                throw DiscoveryError.securityValidationFailed
            }
            
            // Validate required fields
            guard species != nil else {
                throw DiscoveryError.invalidSpecies
            }
            
            guard location != nil else {
                throw DiscoveryError.invalidLocation
            }
            
            guard confidence >= kMinimumConfidenceThreshold else {
                throw DiscoveryError.invalidConfidence
            }
            
            // Validate relationships
            try species?.validateForUpdate()
            
            return .success(())
        } catch {
            return .failure(error)
        }
    }
    
    // MARK: - Private Methods
    
    private func processImageData(_ data: Data) throws -> Data {
        // Implementation for stripping metadata and compressing image
        // This is a placeholder for the actual implementation
        return data
    }
    
    private func encryptImageData(_ data: Data) throws -> Data {
        let key = SymmetricKey(size: .bits256)
        let nonce = try AES.GCM.Nonce(data: Data(count: 12))
        let sealedBox = try AES.GCM.seal(data, using: key, nonce: nonce)
        return sealedBox.combined ?? Data()
    }
    
    private func updateSecurityHash() {
        var hasher = SHA256()
        hasher.update(data: discoveryId.uuidString.data(using: .utf8) ?? Data())
        hasher.update(data: timestamp.timeIntervalSince1970.description.data(using: .utf8) ?? Data())
        hasher.update(data: confidence.description.data(using: .utf8) ?? Data())
        securityHash = Data(hasher.finalize())
    }
    
    private func validateSecurityHash() -> Bool {
        guard let currentHash = securityHash else { return false }
        
        var hasher = SHA256()
        hasher.update(data: discoveryId.uuidString.data(using: .utf8) ?? Data())
        hasher.update(data: timestamp.timeIntervalSince1970.description.data(using: .utf8) ?? Data())
        hasher.update(data: confidence.description.data(using: .utf8) ?? Data())
        let computedHash = Data(hasher.finalize())
        
        return currentHash == computedHash
    }
}

// MARK: - Validation

extension Discovery {
    public override func validateForInsert() throws {
        try super.validateForInsert()
        try validateRequiredFields()
    }
    
    public override func validateForUpdate() throws {
        try super.validateForUpdate()
        try validateRequiredFields()
    }
    
    private func validateRequiredFields() throws {
        guard species != nil else {
            throw DiscoveryError.invalidSpecies
        }
        
        guard location != nil else {
            throw DiscoveryError.invalidLocation
        }
        
        guard confidence >= kMinimumConfidenceThreshold else {
            throw DiscoveryError.invalidConfidence
        }
    }
}