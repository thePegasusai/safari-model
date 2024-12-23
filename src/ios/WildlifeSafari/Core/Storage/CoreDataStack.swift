//
// CoreDataStack.swift
// WildlifeSafari
//
// Core Data stack implementation providing centralized database management
// with enhanced security and performance optimizations.
//

import CoreData // Latest - Core Data framework for data persistence
import Combine  // Latest - Reactive programming support
import Foundation // Latest - Basic iOS functionality and crypto

/// Enumeration of possible Core Data related errors
enum CoreDataError: Error {
    case persistentStoreError(String)
    case contextSaveError(String)
    case migrationError(String)
    case resetError(String)
    case validationError(String)
}

/// Configuration options for database setup
struct DatabaseConfiguration {
    let enableEncryption: Bool
    let enableAutomaticBackups: Bool
    let enableWALMode: Bool
    let maxBatchSize: Int
    let mergePolicy: Any
    
    static let `default` = DatabaseConfiguration(
        enableEncryption: true,
        enableAutomaticBackups: true,
        enableWALMode: true,
        maxBatchSize: 100,
        mergePolicy: NSMergeByPropertyObjectTrumpMergePolicy
    )
}

/// Manages Core Data stack initialization and persistent store coordination
final class CoreDataStack {
    
    // MARK: - Properties
    
    private let modelName: String
    private let configuration: DatabaseConfiguration
    
    private(set) var container: NSPersistentContainer
    private(set) var viewContext: NSManagedObjectContext
    private(set) var backgroundContext: NSManagedObjectContext
    private var storeDescription: NSPersistentStoreDescription
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    /// Initializes the Core Data stack with the specified model and configuration
    /// - Parameters:
    ///   - modelName: Name of the Core Data model file
    ///   - configuration: Configuration options for the database
    init(modelName: String, configuration: DatabaseConfiguration = .default) {
        self.modelName = modelName
        self.configuration = configuration
        
        // Initialize persistent container
        container = NSPersistentContainer(name: modelName)
        
        // Configure store description
        storeDescription = container.persistentStoreDescriptions.first ?? NSPersistentStoreDescription()
        configureStoreDescription()
        
        // Load persistent stores
        loadPersistentStores()
        
        // Configure contexts
        viewContext = container.viewContext
        backgroundContext = container.newBackgroundContext()
        
        configureContexts()
        setupNotificationHandling()
    }
    
    // MARK: - Private Configuration Methods
    
    private func configureStoreDescription() {
        // Enable encryption if specified
        if configuration.enableEncryption {
            storeDescription.setOption(FileProtectionType.complete as NSObject,
                                     forKey: NSPersistentStoreFileProtectionKey)
        }
        
        // Configure WAL journaling mode
        if configuration.enableWALMode {
            storeDescription.setOption(true as NSNumber,
                                     forKey: NSPersistentStoreJournalModeKey)
        }
        
        // Enable automatic lightweight migration
        storeDescription.shouldMigrateStoreAutomatically = true
        storeDescription.shouldInferMappingModelAutomatically = true
        
        container.persistentStoreDescriptions = [storeDescription]
    }
    
    private func loadPersistentStores() {
        container.loadPersistentStores { [weak self] description, error in
            if let error = error {
                fatalError("Failed to load persistent stores: \(error)")
            }
            self?.container.viewContext.automaticallyMergesChangesFromParent = true
        }
    }
    
    private func configureContexts() {
        // Configure view context
        viewContext.automaticallyMergesChangesFromParent = true
        viewContext.mergePolicy = configuration.mergePolicy
        
        // Configure background context
        backgroundContext.automaticallyMergesChangesFromParent = true
        backgroundContext.mergePolicy = configuration.mergePolicy
        
        // Set performance optimization flags
        viewContext.shouldDeleteInaccessibleFaults = true
        backgroundContext.shouldDeleteInaccessibleFaults = true
    }
    
    private func setupNotificationHandling() {
        NotificationCenter.default.publisher(
            for: .NSManagedObjectContextDidSave
        )
        .sink { [weak self] notification in
            guard let context = notification.object as? NSManagedObjectContext else { return }
            self?.handleContextDidSave(context)
        }
        .store(in: &cancellables)
    }
    
    private func handleContextDidSave(_ context: NSManagedObjectContext) {
        // Trigger automatic backup if enabled and needed
        if configuration.enableAutomaticBackups {
            triggerAutomaticBackupIfNeeded()
        }
    }
    
    private func triggerAutomaticBackupIfNeeded() {
        // Implement backup logic based on criteria (e.g., number of changes, time elapsed)
        // This is a placeholder for the actual implementation
    }
    
    // MARK: - Public Methods
    
    /// Saves changes in the specified context with enhanced error handling
    /// - Parameter context: The managed object context to save
    /// - Returns: Result indicating success or detailed error information
    func saveContext(_ context: NSManagedObjectContext) -> Result<Void, CoreDataError> {
        guard context.hasChanges else { return .success(()) }
        
        do {
            // Perform pre-save validation
            try context.obtainPermanentIDs(for: Array(context.insertedObjects))
            try context.save()
            
            return .success(())
        } catch let error as NSError {
            let errorMessage = "Failed to save context: \(error), \(error.userInfo)"
            return .failure(.contextSaveError(errorMessage))
        }
    }
    
    /// Executes a task in a background context with optimized performance
    /// - Parameter block: The block to execute with the background context
    func performBackgroundTask(_ block: @escaping (NSManagedObjectContext) -> Void) {
        let context = container.newBackgroundContext()
        context.performAndWait {
            context.mergePolicy = configuration.mergePolicy
            context.undoManager = nil // Disable undo management for performance
            
            // Set batch size limits
            if let fetchRequest = context.persistentStoreCoordinator?.managedObjectModel.fetchRequestTemplate(forName: "BatchFetchRequest") {
                fetchRequest.fetchBatchSize = configuration.maxBatchSize
            }
            
            block(context)
            
            // Attempt to save if there are changes
            if context.hasChanges {
                _ = saveContext(context)
            }
        }
    }
    
    /// Resets the entire Core Data stack with secure data cleanup
    /// - Returns: Result indicating success or detailed error information
    func resetStack() -> Result<Void, CoreDataError> {
        // Reset contexts
        viewContext.reset()
        backgroundContext.reset()
        
        // Remove persistent store
        guard let storeURL = container.persistentStoreCoordinator.persistentStores.first?.url else {
            return .failure(.resetError("No persistent store found"))
        }
        
        do {
            try container.persistentStoreCoordinator.destroyPersistentStore(at: storeURL, ofType: NSSQLiteStoreType, options: nil)
            
            // Perform secure cleanup
            try FileManager.default.removeItem(at: storeURL)
            try FileManager.default.removeItem(at: storeURL.appendingPathExtension("shm"))
            try FileManager.default.removeItem(at: storeURL.appendingPathExtension("wal"))
            
            // Recreate persistent store
            try container.persistentStoreCoordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: nil)
            
            return .success(())
        } catch {
            return .failure(.resetError("Failed to reset stack: \(error)"))
        }
    }
}

// MARK: - Error Handling Extensions

extension CoreDataError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .persistentStoreError(let message):
            return "Persistent Store Error: \(message)"
        case .contextSaveError(let message):
            return "Context Save Error: \(message)"
        case .migrationError(let message):
            return "Migration Error: \(message)"
        case .resetError(let message):
            return "Reset Error: \(message)"
        case .validationError(let message):
            return "Validation Error: \(message)"
        }
    }
}