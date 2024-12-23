//
// PersistenceController.swift
// WildlifeSafari
//
// Thread-safe singleton controller managing Core Data persistence with
// reactive updates, error handling, and security features.
//

import CoreData // Latest - Core Data framework for data persistence
import Combine  // Latest - Reactive programming support
import Foundation // Latest - Basic iOS foundation functionality

/// Thread-safe singleton controller providing centralized access to Core Data persistence
final class PersistenceController {
    
    // MARK: - Properties
    
    /// Shared singleton instance
    static let shared = PersistenceController()
    
    /// Core Data stack instance
    private let coreDataStack: CoreDataStack
    
    /// Main view context for UI operations
    var viewContext: NSManagedObjectContext {
        coreDataStack.viewContext
    }
    
    /// Subject for broadcasting save notifications
    let didSaveSubject = PassthroughSubject<Void, Never>()
    
    /// Dedicated queue for persistence operations
    private let persistenceQueue = DispatchQueue(
        label: "com.wildlifesafari.persistence",
        qos: .userInitiated
    )
    
    /// Set of cancellables for managing subscriptions
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    private init() {
        // Initialize CoreDataStack with security-optimized configuration
        let config = DatabaseConfiguration(
            enableEncryption: true,
            enableAutomaticBackups: true,
            enableWALMode: true,
            maxBatchSize: 100,
            mergePolicy: NSMergeByPropertyObjectTrumpMergePolicy
        )
        
        coreDataStack = CoreDataStack(modelName: "WildlifeSafari", configuration: config)
        
        setupNotificationHandling()
    }
    
    // MARK: - Private Methods
    
    private func setupNotificationHandling() {
        NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.didSaveSubject.send()
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    
    /// Saves the view context with retry mechanism and error handling
    /// - Returns: Result indicating success or detailed error information
    @discardableResult
    func saveContext() -> Result<Void, CoreDataError> {
        return persistenceQueue.sync {
            coreDataStack.saveContext(viewContext)
        }
    }
    
    /// Executes a task in a background context with optimized performance
    /// - Parameter block: The block to execute with the background context
    func performBackgroundTask(_ block: @escaping (NSManagedObjectContext) -> Void) {
        coreDataStack.performBackgroundTask(block)
    }
    
    /// Fetches entities with type safety and comprehensive error handling
    /// - Parameters:
    ///   - predicate: Optional predicate for filtering results
    ///   - sortDescriptors: Optional sort descriptors for ordering results
    ///   - resultType: The type of fetch request result
    /// - Returns: Result containing fetched entities or error information
    func fetchEntity<T: NSManagedObject>(
        predicate: NSPredicate? = nil,
        sortDescriptors: [NSSortDescriptor]? = nil,
        resultType: NSFetchRequestResultType = .managedObjectResultType
    ) -> Result<[T], CoreDataError> {
        let request = NSFetchRequest<T>(entityName: String(describing: T.self))
        request.predicate = predicate
        request.sortDescriptors = sortDescriptors
        request.resultType = resultType
        
        // Configure fetch request optimization
        request.returnsObjectsAsFaults = false
        request.includesPropertyValues = true
        
        do {
            let results = try viewContext.fetch(request)
            return .success(results)
        } catch {
            return .failure(.persistentStoreError("Failed to fetch \(T.self): \(error)"))
        }
    }
    
    /// Performs batch delete operation with error handling
    /// - Parameters:
    ///   - entityName: Name of the entity to delete
    ///   - predicate: Optional predicate for filtering deletion
    /// - Returns: Result indicating success or detailed error information
    func batchDelete(
        entityName: String,
        predicate: NSPredicate? = nil
    ) -> Result<Void, CoreDataError> {
        let request = NSBatchDeleteRequest(
            fetchRequest: NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        )
        request.predicate = predicate
        
        return persistenceQueue.sync {
            do {
                try viewContext.execute(request)
                return .success(())
            } catch {
                return .failure(.contextSaveError("Batch delete failed: \(error)"))
            }
        }
    }
    
    /// Resets the entire persistence stack with secure cleanup
    /// - Returns: Result indicating success or detailed error information
    func resetPersistentStore() -> Result<Void, CoreDataError> {
        persistenceQueue.sync {
            coreDataStack.resetStack()
        }
    }
}

// MARK: - Error Handling Extensions

extension PersistenceController {
    /// Validates the integrity of the persistent store
    /// - Returns: Boolean indicating store integrity
    func validatePersistentStore() -> Bool {
        do {
            _ = try viewContext.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: "Discovery"))
            return true
        } catch {
            return false
        }
    }
    
    /// Attempts to repair corrupted store
    /// - Returns: Result indicating success or detailed error information
    func repairPersistentStore() -> Result<Void, CoreDataError> {
        resetPersistentStore()
    }
}