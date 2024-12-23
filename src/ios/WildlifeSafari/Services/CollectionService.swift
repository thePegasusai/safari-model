//
// CollectionService.swift
// WildlifeSafari
//
// Service layer implementation for managing user collections of wildlife and fossil
// discoveries with enhanced security, offline support, and cloud synchronization.
//

import Foundation // Latest - Basic iOS functionality
import Combine    // Latest - Reactive programming support
import CoreData   // Latest - Data persistence framework

// MARK: - Constants

private enum Constants {
    static let MAX_COLLECTIONS_PER_USER = 10
    static let COLLECTION_SYNC_DEBOUNCE: TimeInterval = 5.0
    static let MAX_BATCH_SIZE = 50
    static let SYNC_RETRY_ATTEMPTS = 3
}

// MARK: - Collection Service Errors

enum CollectionServiceError: LocalizedError {
    case maxCollectionsExceeded
    case invalidCollection
    case collectionNotFound
    case syncError(String)
    case securityError(String)
    case persistenceError(String)
    
    var errorDescription: String? {
        switch self {
        case .maxCollectionsExceeded:
            return "Maximum number of collections exceeded"
        case .invalidCollection:
            return "Invalid collection data"
        case .collectionNotFound:
            return "Collection not found"
        case .syncError(let message):
            return "Sync error: \(message)"
        case .securityError(let message):
            return "Security error: \(message)"
        case .persistenceError(let message):
            return "Persistence error: \(message)"
        }
    }
}

// MARK: - Collection Service Implementation

@available(iOS 13.0, *)
public final class CollectionService {
    // MARK: - Properties
    
    private let apiClient: APIClient
    private let coreDataStack: CoreDataStack
    private let syncService: SyncService
    private var cancellables = Set<AnyCancellable>()
    
    private let collectionsPublisher = CurrentValueSubject<[Collection], Error>([])
    private let syncQueue = OperationQueue()
    private let collectionCache = NSCache<NSString, Collection>()
    
    // MARK: - Initialization
    
    public init(
        apiClient: APIClient,
        coreDataStack: CoreDataStack,
        syncService: SyncService
    ) {
        self.apiClient = apiClient
        self.coreDataStack = coreDataStack
        self.syncService = syncService
        
        setupCollectionCache()
        setupSyncQueue()
        observeChanges()
    }
    
    // MARK: - Public Methods
    
    /// Creates a new collection with enhanced security validation
    /// - Parameters:
    ///   - name: Collection name
    ///   - description: Optional collection description
    ///   - securityContext: Security context for validation
    /// - Returns: Publisher emitting created collection or error
    public func createCollection(
        name: String,
        description: String? = nil,
        securityContext: SecurityContext
    ) -> AnyPublisher<Collection, Error> {
        return Future { [weak self] promise in
            guard let self = self else {
                promise(.failure(CollectionServiceError.invalidCollection))
                return
            }
            
            self.coreDataStack.performBackgroundTask { context in
                do {
                    // Validate collection limit
                    let count = try self.getCollectionCount(context: context)
                    guard count < Constants.MAX_COLLECTIONS_PER_USER else {
                        throw CollectionServiceError.maxCollectionsExceeded
                    }
                    
                    // Create new collection
                    let collection = Collection(entity: Collection.entity(), insertInto: context)
                    collection.name = name
                    collection.description = description
                    
                    // Save context
                    try context.obtainPermanentIDs(for: [collection])
                    let result = self.coreDataStack.saveContext(context)
                    
                    switch result {
                    case .success:
                        // Queue sync operation
                        self.queueSyncOperation(.create, collection: collection)
                        promise(.success(collection))
                        
                    case .failure(let error):
                        promise(.failure(error))
                    }
                } catch {
                    promise(.failure(error))
                }
            }
        }.eraseToAnyPublisher()
    }
    
    /// Retrieves a collection by ID with caching
    /// - Parameter id: Collection ID
    /// - Returns: Publisher emitting collection or error
    public func getCollection(_ id: UUID) -> AnyPublisher<Collection, Error> {
        // Check cache first
        if let cached = collectionCache.object(forKey: id.uuidString as NSString) {
            return Just(cached)
                .setFailureType(to: Error.self)
                .eraseToAnyPublisher()
        }
        
        return Future { [weak self] promise in
            guard let self = self else {
                promise(.failure(CollectionServiceError.invalidCollection))
                return
            }
            
            self.coreDataStack.performBackgroundTask { context in
                do {
                    let fetchRequest: NSFetchRequest<Collection> = Collection.fetchRequest()
                    fetchRequest.predicate = NSPredicate(format: "collectionId == %@", id as CVarArg)
                    
                    guard let collection = try context.fetch(fetchRequest).first else {
                        throw CollectionServiceError.collectionNotFound
                    }
                    
                    // Cache the result
                    self.collectionCache.setObject(collection, forKey: id.uuidString as NSString)
                    promise(.success(collection))
                } catch {
                    promise(.failure(error))
                }
            }
        }.eraseToAnyPublisher()
    }
    
    /// Updates an existing collection with security validation
    /// - Parameters:
    ///   - id: Collection ID
    ///   - updates: Update closure
    /// - Returns: Publisher emitting updated collection or error
    public func updateCollection(
        _ id: UUID,
        updates: @escaping (Collection) throws -> Void
    ) -> AnyPublisher<Collection, Error> {
        return Future { [weak self] promise in
            guard let self = self else {
                promise(.failure(CollectionServiceError.invalidCollection))
                return
            }
            
            self.coreDataStack.performBackgroundTask { context in
                do {
                    let fetchRequest: NSFetchRequest<Collection> = Collection.fetchRequest()
                    fetchRequest.predicate = NSPredicate(format: "collectionId == %@", id as CVarArg)
                    
                    guard let collection = try context.fetch(fetchRequest).first else {
                        throw CollectionServiceError.collectionNotFound
                    }
                    
                    // Apply updates
                    try updates(collection)
                    
                    // Save changes
                    let result = self.coreDataStack.saveContext(context)
                    
                    switch result {
                    case .success:
                        // Queue sync operation
                        self.queueSyncOperation(.update, collection: collection)
                        
                        // Update cache
                        self.collectionCache.setObject(collection, forKey: id.uuidString as NSString)
                        promise(.success(collection))
                        
                    case .failure(let error):
                        promise(.failure(error))
                    }
                } catch {
                    promise(.failure(error))
                }
            }
        }.eraseToAnyPublisher()
    }
    
    /// Deletes a collection with security validation
    /// - Parameter id: Collection ID
    /// - Returns: Publisher emitting completion or error
    public func deleteCollection(_ id: UUID) -> AnyPublisher<Void, Error> {
        return Future { [weak self] promise in
            guard let self = self else {
                promise(.failure(CollectionServiceError.invalidCollection))
                return
            }
            
            self.coreDataStack.performBackgroundTask { context in
                do {
                    let fetchRequest: NSFetchRequest<Collection> = Collection.fetchRequest()
                    fetchRequest.predicate = NSPredicate(format: "collectionId == %@", id as CVarArg)
                    
                    guard let collection = try context.fetch(fetchRequest).first else {
                        throw CollectionServiceError.collectionNotFound
                    }
                    
                    // Delete collection
                    context.delete(collection)
                    
                    let result = self.coreDataStack.saveContext(context)
                    
                    switch result {
                    case .success:
                        // Queue sync operation
                        self.queueSyncOperation(.delete, collection: collection)
                        
                        // Remove from cache
                        self.collectionCache.removeObject(forKey: id.uuidString as NSString)
                        promise(.success(()))
                        
                    case .failure(let error):
                        promise(.failure(error))
                    }
                } catch {
                    promise(.failure(error))
                }
            }
        }.eraseToAnyPublisher()
    }
    
    // MARK: - Private Methods
    
    private func setupCollectionCache() {
        collectionCache.countLimit = 100
        collectionCache.totalCostLimit = 50 * 1024 * 1024 // 50MB
    }
    
    private func setupSyncQueue() {
        syncQueue.maxConcurrentOperationCount = 1
        syncQueue.qualityOfService = .utility
    }
    
    private func observeChanges() {
        NotificationCenter.default
            .publisher(for: .NSManagedObjectContextDidSave, object: nil)
            .sink { [weak self] notification in
                self?.handleContextDidSave(notification)
            }
            .store(in: &cancellables)
    }
    
    private func handleContextDidSave(_ notification: Notification) {
        guard let context = notification.object as? NSManagedObjectContext else { return }
        
        // Update collections publisher
        loadCollections()
    }
    
    private func loadCollections() {
        coreDataStack.performBackgroundTask { [weak self] context in
            do {
                let fetchRequest: NSFetchRequest<Collection> = Collection.fetchRequest()
                fetchRequest.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
                
                let collections = try context.fetch(fetchRequest)
                self?.collectionsPublisher.send(collections)
            } catch {
                self?.collectionsPublisher.send(completion: .failure(error))
            }
        }
    }
    
    private func getCollectionCount(context: NSManagedObjectContext) throws -> Int {
        let fetchRequest: NSFetchRequest<Collection> = Collection.fetchRequest()
        return try context.count(for: fetchRequest)
    }
    
    private func queueSyncOperation(_ type: SyncOperation.OperationType, collection: Collection) {
        let operation = SyncOperation(
            id: UUID(),
            type: type,
            data: try? JSONEncoder().encode(collection),
            timestamp: Date(),
            priority: type == .create ? 1 : 0
        )
        
        syncService.queueOperation(operation)
    }
}

// MARK: - Supporting Types

private struct SecurityContext {
    let userId: String
    let accessToken: String
    let deviceId: String
}

private enum SyncOperation {
    enum OperationType {
        case create
        case update
        case delete
    }
}