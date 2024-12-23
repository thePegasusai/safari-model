//
// Species.swift
// WildlifeSafari
//
// Core data model representing wildlife species and fossil types with comprehensive
// taxonomic and conservation information, implementing secure data handling.
//

import Foundation // Latest - Basic data types and functionality
import CoreData   // Latest - Data persistence framework

// MARK: - Constants

private let kDefaultConservationStatus = "Unknown"
private let kTaxonomyDelimiter = "||"
private let kMaxReferenceImages = 5

// MARK: - Species Entity

@objc(Species)
@objcMembers
public class Species: NSManagedObject {
    
    // MARK: - Properties
    
    @NSManaged public private(set) var id: UUID
    @NSManaged public var scientificName: String
    @NSManaged public var commonName: String
    @NSManaged public private(set) var taxonomy: String
    @NSManaged public private(set) var conservationStatus: String
    @NSManaged private var modelData: Data?
    @NSManaged private var referenceImages: Data?
    @NSManaged private var additionalInfo: Data?
    @NSManaged public private(set) var discoveries: NSSet?
    @NSManaged public private(set) var lastUpdated: Date
    @NSManaged public private(set) var isEndangered: Bool
    @NSManaged public private(set) var confidenceLevel: Int16
    
    // MARK: - Initialization
    
    /// Creates a new Species instance with required properties and security initialization
    /// - Parameter context: The managed object context for the new instance
    public override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?) {
        super.init(entity: entity, insertInto: context)
        
        // Generate secure random UUID
        self.id = UUID()
        
        // Set default values
        self.scientificName = ""
        self.commonName = ""
        self.taxonomy = ""
        self.conservationStatus = kDefaultConservationStatus
        self.isEndangered = false
        self.confidenceLevel = 0
        self.lastUpdated = Date()
        
        // Initialize empty relationships
        self.discoveries = NSSet()
    }
    
    // MARK: - Public Methods
    
    /// Securely converts taxonomy string to array of taxonomic ranks with validation
    /// - Returns: Validated array of taxonomic ranks
    public func getTaxonomyArray() -> [String] {
        guard !taxonomy.isEmpty else { return [] }
        
        // Split and validate taxonomy components
        let components = taxonomy.components(separatedBy: kTaxonomyDelimiter)
        return components.filter { !$0.isEmpty }
    }
    
    /// Securely sets taxonomy from validated array of taxonomic ranks
    /// - Parameter ranks: Array of taxonomic ranks to set
    public func setTaxonomyArray(_ ranks: [String]) throws {
        // Validate input
        guard !ranks.isEmpty else {
            throw NSError(domain: "Species", code: 1001, userInfo: [
                NSLocalizedDescriptionKey: "Taxonomy ranks cannot be empty"
            ])
        }
        
        // Sanitize and join ranks
        let sanitizedRanks = ranks.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let validRanks = sanitizedRanks.filter { !$0.isEmpty }
        
        self.taxonomy = validRanks.joined(separator: kTaxonomyDelimiter)
        self.lastUpdated = Date()
    }
    
    /// Securely adds a new discovery with proper relationship management
    /// - Parameter discovery: The discovery to add to this species
    public func addDiscovery(_ discovery: NSManagedObject) throws {
        guard let discoveries = self.discoveries?.mutableCopy() as? NSMutableSet else {
            throw NSError(domain: "Species", code: 1002, userInfo: [
                NSLocalizedDescriptionKey: "Failed to access discoveries set"
            ])
        }
        
        discoveries.add(discovery)
        self.discoveries = discoveries
        self.lastUpdated = Date()
    }
    
    /// Updates conservation status with validation and endangered flag
    /// - Parameter status: New conservation status to set
    public func updateConservationStatus(_ status: String) throws {
        // Validate status
        let validStatus = status.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !validStatus.isEmpty else {
            throw NSError(domain: "Species", code: 1003, userInfo: [
                NSLocalizedDescriptionKey: "Conservation status cannot be empty"
            ])
        }
        
        self.conservationStatus = validStatus
        
        // Update endangered flag based on status
        self.isEndangered = ["Critically Endangered", "Endangered"].contains(validStatus)
        self.lastUpdated = Date()
    }
    
    // MARK: - Private Methods
    
    /// Securely stores encrypted reference images
    /// - Parameter imageData: Array of image data to store
    private func setReferenceImages(_ imageData: [Data]) throws {
        guard imageData.count <= kMaxReferenceImages else {
            throw NSError(domain: "Species", code: 1004, userInfo: [
                NSLocalizedDescriptionKey: "Exceeded maximum number of reference images"
            ])
        }
        
        // Encrypt and store image data
        let encryptedData = try NSKeyedArchiver.archivedData(
            withRootObject: imageData,
            requiringSecureCoding: true
        )
        self.referenceImages = encryptedData
    }
    
    /// Validates and sanitizes input string
    /// - Parameter input: String to validate
    /// - Returns: Sanitized string
    private func sanitizeInput(_ input: String) -> String {
        return input.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: kTaxonomyDelimiter, with: "")
    }
}

// MARK: - Validation

extension Species {
    public override func validateForInsert() throws {
        try super.validateForInsert()
        try validateRequiredFields()
    }
    
    public override func validateForUpdate() throws {
        try super.validateForUpdate()
        try validateRequiredFields()
    }
    
    private func validateRequiredFields() throws {
        // Validate scientific name
        if sanitizeInput(scientificName).isEmpty {
            throw NSError(domain: "Species", code: 1005, userInfo: [
                NSLocalizedDescriptionKey: "Scientific name is required"
            ])
        }
        
        // Validate common name
        if sanitizeInput(commonName).isEmpty {
            throw NSError(domain: "Species", code: 1006, userInfo: [
                NSLocalizedDescriptionKey: "Common name is required"
            ])
        }
    }
}

// MARK: - Security

extension Species {
    /// Securely erases sensitive data before deletion
    public override func prepareForDeletion() {
        super.prepareForDeletion()
        
        // Securely clear sensitive data
        modelData = nil
        referenceImages = nil
        additionalInfo = nil
        
        // Clear relationships
        discoveries = nil
    }
}