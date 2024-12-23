//
// Collection.swift
// WildlifeSafari
//
// Core Data managed object model representing a user's collection of wildlife and fossil discoveries
// with enhanced security and sync capabilities.
//

import Foundation // Latest - Basic iOS functionality
import CoreData   // Latest - Data persistence framework
import CryptoKit  // Latest - Cryptographic operations

// MARK: - Constants

private let kMaxCollectionNameLength = 100
private let kDefaultCollectionName = "My Collection"
private let kMaxDiscoveries = 10000
private let kSecurityHashKey = "collection_integrity_"
private let kSyncBatchSize = 50

// MARK: - Error Types

enum CollectionError: LocalizedError {
    case invalidName
    case maxDiscoveriesExceeded
    case securityValidationFailed
    case discoveryValidationFailed
    case syncError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidName:
            return "Invalid collection name"
        case .maxDiscoveriesExceeded:
            return "Maximum number of discoveries exceeded"
        case .securityValidationFailed:
            return "Security validation failed"
        case .discoveryValidationFailed:
            return "Discovery validation failed"
        case .syncError(let message):
            return "Sync error: \(message)"
        }
    }
}

// MARK: - Collection Entity

@objc(Collection)
@objcMembers
public class Collection: NSManagedObject {
    
    // MARK: - Properties
    
    @NSManaged public private(set) var collectionId: UUID
    @NSManaged public var name: String
    @NSManaged public private(set) var createdAt: Date
    @NSManaged public private(set) var updatedAt: Date
    @NSManaged public private(set) var discoveries: NSSet
    @NSManaged public private(set) var isSynced: Bool
    @NSManaged public var description: String?
    @NSManaged private var securityHash: Data
    @NSManaged private var syncVersion: Int
    @NSManaged private var lastSyncedAt: Date?
    
    // MARK: - Initialization
    
    public override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?) {
        super.init(entity: entity, insertInto: context)
        
        self.collectionId = UUID()
        self.name = kDefaultCollectionName
        self.createdAt = Date()
        self.updatedAt = Date()
        self.discoveries = NSSet()
        self.isSynced = false
        self.syncVersion = 1
        
        updateSecurityHash()
    }
    
    // MARK: - Public Methods
    
    /// Securely adds a discovery to the collection with validation
    /// - Parameter discovery: The discovery to add
    /// - Returns: Result indicating success or error
    public func addDiscovery(_ discovery: Discovery) -> Result<Void, CollectionError> {
        // Validate collection size
        guard (discoveries.count + 1) <= kMaxDiscoveries else {
            return .failure(.maxDiscoveriesExceeded)
        }
        
        // Validate discovery
        guard case .success = discovery.validate() else {
            return .failure(.discoveryValidationFailed)
        }
        
        // Verify security hash
        guard validateSecurityHash() else {
            return .failure(.securityValidationFailed)
        }
        
        // Add discovery
        let mutableDiscoveries = discoveries.mutableCopy() as! NSMutableSet
        mutableDiscoveries.add(discovery)
        self.discoveries = mutableDiscoveries
        
        // Update metadata
        self.updatedAt = Date()
        self.isSynced = false
        
        updateSecurityHash()
        
        return .success(())
    }
    
    /// Securely removes a discovery with relationship cleanup
    /// - Parameter discovery: The discovery to remove
    /// - Returns: Result indicating success or error
    public func removeDiscovery(_ discovery: Discovery) -> Result<Void, CollectionError> {
        // Verify security hash
        guard validateSecurityHash() else {
            return .failure(.securityValidationFailed)
        }
        
        // Remove discovery
        let mutableDiscoveries = discoveries.mutableCopy() as! NSMutableSet
        mutableDiscoveries.remove(discovery)
        self.discoveries = mutableDiscoveries
        
        // Update metadata
        self.updatedAt = Date()
        self.isSynced = false
        
        updateSecurityHash()
        
        return .success(())
    }
    
    /// Retrieves all discoveries with secure sorting and pagination
    /// - Parameter config: Optional pagination configuration
    /// - Returns: Result containing sorted array of discoveries or error
    public func getDiscoveries(config: PaginationConfig? = nil) -> Result<[Discovery], CollectionError> {
        // Verify security hash
        guard validateSecurityHash() else {
            return .failure(.securityValidationFailed)
        }
        
        // Convert to array and sort
        let discoveryArray = (discoveries.allObjects as! [Discovery])
            .sorted { $0.timestamp > $1.timestamp }
        
        // Apply pagination if configured
        if let config = config {
            let startIndex = config.page * config.pageSize
            let endIndex = min(startIndex + config.pageSize, discoveryArray.count)
            return .success(Array(discoveryArray[startIndex..<endIndex]))
        }
        
        return .success(discoveryArray)
    }
    
    /// Converts collection to secure data transfer object
    /// - Returns: Result containing DTO or error
    public func toDTO() -> Result<CollectionDTO, CollectionError> {
        // Verify security hash
        guard validateSecurityHash() else {
            return .failure(.securityValidationFailed)
        }
        
        let dto = CollectionDTO(
            id: collectionId,
            name: name,
            createdAt: createdAt,
            updatedAt: updatedAt,
            description: description,
            syncVersion: syncVersion,
            discoveryCount: discoveries.count
        )
        
        return .success(dto)
    }
    
    // MARK: - Private Methods
    
    private func updateSecurityHash() {
        var hasher = SHA256()
        hasher.update(data: collectionId.uuidString.data(using: .utf8)!)
        hasher.update(data: name.data(using: .utf8)!)
        hasher.update(data: createdAt.timeIntervalSince1970.description.data(using: .utf8)!)
        hasher.update(data: String(syncVersion).data(using: .utf8)!)
        securityHash = Data(hasher.finalize())
    }
    
    private func validateSecurityHash() -> Bool {
        var hasher = SHA256()
        hasher.update(data: collectionId.uuidString.data(using: .utf8)!)
        hasher.update(data: name.data(using: .utf8)!)
        hasher.update(data: createdAt.timeIntervalSince1970.description.data(using: .utf8)!)
        hasher.update(data: String(syncVersion).data(using: .utf8)!)
        let computedHash = Data(hasher.finalize())
        
        return securityHash == computedHash
    }
}

// MARK: - Validation

extension Collection {
    public override func validateForInsert() throws {
        try super.validateForInsert()
        try validateName()
    }
    
    public override func validateForUpdate() throws {
        try super.validateForUpdate()
        try validateName()
    }
    
    private func validateName() throws {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty && trimmedName.count <= kMaxCollectionNameLength else {
            throw CollectionError.invalidName
        }
    }
}

// MARK: - Supporting Types

struct PaginationConfig {
    let page: Int
    let pageSize: Int
}

struct CollectionDTO: Codable {
    let id: UUID
    let name: String
    let createdAt: Date
    let updatedAt: Date
    let description: String?
    let syncVersion: Int
    let discoveryCount: Int
}