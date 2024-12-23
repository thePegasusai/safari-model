//
// User.swift
// WildlifeSafari
//
// Core Data managed object subclass representing a user with secure data handling
// and comprehensive collection management functionality.
//

import CoreData // Latest - Core Data framework for model persistence
import Foundation // Latest - Basic iOS foundation functionality
import CryptoKit // Latest - Cryptographic operations for secure data handling

/// Enumeration representing user synchronization status
@objc enum UserSyncStatus: Int16 {
    case pending = 0
    case syncing = 1
    case synced = 2
    case failed = 3
}

/// User model representing an authenticated user in the Wildlife Safari application
@objc(User)
public class User: NSManagedObject {
    
    // MARK: - Core Data Properties
    
    @NSManaged public private(set) var id: UUID
    @NSManaged public private(set) var email: String
    @NSManaged public var name: String
    @NSManaged public private(set) var createdAt: Date
    @NSManaged public private(set) var lastLoginAt: Date
    @NSManaged private var encryptedPreferences: Data?
    @NSManaged public private(set) var collections: NSSet
    @NSManaged public private(set) var syncStatus: Int16
    @NSManaged private var authenticationData: Data?
    @NSManaged public private(set) var isAuthenticated: Bool
    
    // MARK: - Computed Properties
    
    public var preferences: [String: Any]? {
        get {
            guard let encryptedData = encryptedPreferences else { return nil }
            return try? decryptPreferences(encryptedData)
        }
        set {
            guard let newValue = newValue else {
                encryptedPreferences = nil
                return
            }
            encryptedPreferences = try? encryptPreferences(newValue)
        }
    }
    
    public var syncStatusEnum: UserSyncStatus {
        get { UserSyncStatus(rawValue: syncStatus) ?? .pending }
        set { syncStatus = newValue.rawValue }
    }
    
    // MARK: - Initialization
    
    /// Creates a new User instance with secure initialization
    /// - Parameter context: The managed object context for the new user
    public override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?) {
        super.init(entity: entity, insertInto: context)
        
        // Initialize with secure defaults
        self.id = UUID()
        self.createdAt = Date()
        self.lastLoginAt = Date()
        self.collections = NSSet()
        self.syncStatus = UserSyncStatus.pending.rawValue
        self.isAuthenticated = false
    }
    
    // MARK: - Collection Management
    
    /// Securely adds a new collection to the user's collections set
    /// - Parameter collection: The collection to add
    /// - Returns: Success status of the operation
    public func addCollection(_ collection: Collection) -> Bool {
        guard isAuthenticated else { return false }
        
        let mutableCollections = mutableSetValue(forKey: "collections")
        mutableCollections.add(collection)
        collection.setValue(self, forKey: "user")
        
        syncStatusEnum = .pending
        return true
    }
    
    /// Securely removes a collection from the user's collections set
    /// - Parameter collection: The collection to remove
    /// - Returns: Success status of the operation
    public func removeCollection(_ collection: Collection) -> Bool {
        guard isAuthenticated else { return false }
        
        let mutableCollections = mutableSetValue(forKey: "collections")
        mutableCollections.remove(collection)
        collection.setValue(nil, forKey: "user")
        
        syncStatusEnum = .pending
        return true
    }
    
    // MARK: - Preference Management
    
    /// Updates user preferences with encryption
    /// - Parameter newPreferences: The new preferences to store
    /// - Returns: Success status of the operation
    public func updatePreferences(_ newPreferences: [String: Any]) -> Bool {
        guard isAuthenticated else { return false }
        
        do {
            encryptedPreferences = try encryptPreferences(newPreferences)
            syncStatusEnum = .pending
            return true
        } catch {
            return false
        }
    }
    
    // MARK: - Authentication
    
    /// Validates user credentials securely
    /// - Parameter credentials: The credentials to validate
    /// - Returns: Validation result
    public func validateCredentials(_ credentials: String) -> Bool {
        guard let storedAuthData = authenticationData else { return false }
        
        do {
            let validated = try validateStoredCredentials(credentials, against: storedAuthData)
            if validated {
                lastLoginAt = Date()
                isAuthenticated = true
            }
            return validated
        } catch {
            return false
        }
    }
    
    // MARK: - Private Helpers
    
    private func encryptPreferences(_ preferences: [String: Any]) throws -> Data {
        guard let jsonData = try? JSONSerialization.data(withJSONObject: preferences) else {
            throw NSError(domain: "UserPreferencesError", code: -1, userInfo: nil)
        }
        
        let key = SymmetricKey(size: .bits256)
        let sealedBox = try AES.GCM.seal(jsonData, using: key)
        return sealedBox.combined ?? Data()
    }
    
    private func decryptPreferences(_ encryptedData: Data) throws -> [String: Any]? {
        let key = SymmetricKey(size: .bits256)
        let sealedBox = try AES.GCM.SealedBox(combined: encryptedData)
        let decryptedData = try AES.GCM.open(sealedBox, using: key)
        
        return try JSONSerialization.jsonObject(with: decryptedData) as? [String: Any]
    }
    
    private func validateStoredCredentials(_ credentials: String, against storedData: Data) throws -> Bool {
        // Implement secure credential validation using CryptoKit
        // This is a placeholder for actual secure credential validation
        return false
    }
}

// MARK: - Fetch Request

extension User {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<User> {
        return NSFetchRequest<User>(entityName: "User")
    }
}

// MARK: - Collection Relationship Management

extension User {
    @objc(addCollectionsObject:)
    @NSManaged public func addToCollections(_ value: Collection)
    
    @objc(removeCollectionsObject:)
    @NSManaged public func removeFromCollections(_ value: Collection)
    
    @objc(addCollections:)
    @NSManaged public func addToCollections(_ values: NSSet)
    
    @objc(removeCollections:)
    @NSManaged public func removeFromCollections(_ values: NSSet)
}