//
// SyncService.swift
// WildlifeSafari
//
// Service responsible for managing bidirectional data synchronization between
// local storage and remote backend with offline capabilities and conflict resolution.
//
// Foundation version: latest
// Combine version: latest
// CoreData version: latest
// BackgroundTasks version: latest

import Foundation
import Combine
import CoreData
import BackgroundTasks

// MARK: - Constants

private let SYNC_INTERVAL: TimeInterval = 300.0
private let MAX_BATCH_SIZE: Int = 100
private let MAX_RETRY_ATTEMPTS: Int = 3
private let SYNC_QUEUE = DispatchQueue(label: "com.wildlifesafari.sync", qos: .utility)
private let BACKGROUND_TASK_ID = "com.wildlifesafari.sync.background"

// MARK: - Supporting Types

/// Represents the current synchronization status
public enum SyncStatus {
    case idle
    case syncing(progress: Double)
    case error(Error)
    case completed(Date)
}

/// Configuration options for synchronization
public struct SyncOptions {
    let forceFull: Bool
    let batchSize: Int
    let priority: Operation.QueuePriority
    
    public static let `default` = SyncOptions(
        forceFull: false,
        batchSize: MAX_BATCH_SIZE,
        priority: .normal
    )
}

/// Represents a version vector for conflict resolution
private struct VersionVector: Codable {
    var timestamp: Date
    var counter: UInt64
    var deviceId: String
}

/// Represents a sync operation
private struct SyncOperation: Codable {
    let id: UUID
    let type: OperationType
    let data: Data
    let timestamp: Date
    let priority: Int
    
    enum OperationType: String, Codable {
        case create
        case update
        case delete
    }
}

// MARK: - SyncService Implementation

@available(iOS 13.0, *)
public final class SyncService {
    // MARK: - Properties
    
    private let apiClient: APIClient
    private let coreDataStack: CoreDataStack
    private let syncQueue: DispatchQueue
    private var pendingOperations: Set<UUID>
    private var syncSubscription: AnyCancellable?
    private let syncStatus = CurrentValueSubject<SyncStatus, Never>(.idle)
    private var versionVector: VersionVector
    private let retryPolicy: RetryPolicy
    
    // MARK: - Initialization
    
    public init(
        apiClient: APIClient,
        coreDataStack: CoreDataStack,
        retryPolicy: RetryPolicy? = nil
    ) {
        self.apiClient = apiClient
        self.coreDataStack = coreDataStack
        self.syncQueue = SYNC_QUEUE
        self.pendingOperations = Set<UUID>()
        self.retryPolicy = retryPolicy ?? RetryPolicy(maxRetries: MAX_RETRY_ATTEMPTS)
        
        // Initialize version vector
        self.versionVector = VersionVector(
            timestamp: Date(),
            counter: 0,
            deviceId: UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        )
        
        setupBackgroundTask()
        setupPeriodicSync()
    }
    
    // MARK: - Public Methods
    
    /// Initiates manual synchronization process
    @discardableResult
    public func startSync(options: SyncOptions = .default) -> AnyPublisher<Void, Error> {
        return Future { [weak self] promise in
            guard let self = self else {
                promise(.failure(NSError(domain: "SyncService", code: -1)))
                return
            }
            
            self.syncQueue.async {
                self.performSync(options: options) { result in
                    switch result {
                    case .success:
                        promise(.success(()))
                    case .failure(let error):
                        promise(.failure(error))
                    }
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    /// Queues an operation for synchronization
    public func queueOperation(_ operation: SyncOperation, priority: Operation.QueuePriority = .normal) {
        syncQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.pendingOperations.insert(operation.id)
            self.versionVector.counter += 1
            
            self.coreDataStack.performBackgroundTask { context in
                // Store operation in CoreData for persistence
                let syncEntry = SyncEntry(context: context)
                syncEntry.id = operation.id
                syncEntry.type = operation.type.rawValue
                syncEntry.data = operation.data
                syncEntry.timestamp = operation.timestamp
                syncEntry.priority = Int16(priority.rawValue)
                
                _ = self.coreDataStack.saveContext(context)
            }
            
            // Schedule background sync if needed
            if priority == .high {
                self.scheduleBackgroundSync()
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func setupBackgroundTask() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: BACKGROUND_TASK_ID,
            using: nil
        ) { [weak self] task in
            guard let self = self else {
                task.setTaskCompleted(success: false)
                return
            }
            
            let options = SyncOptions(
                forceFull: false,
                batchSize: MAX_BATCH_SIZE,
                priority: .background
            )
            
            self.performSync(options: options) { result in
                task.setTaskCompleted(success: result.isSuccess)
            }
        }
    }
    
    private func setupPeriodicSync() {
        syncSubscription = Timer.publish(
            every: SYNC_INTERVAL,
            on: .main,
            in: .common
        )
        .autoconnect()
        .sink { [weak self] _ in
            self?.scheduleBackgroundSync()
        }
    }
    
    private func performSync(
        options: SyncOptions,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        // Update sync status
        syncStatus.send(.syncing(progress: 0.0))
        
        // Validate network connectivity
        guard NetworkReachability.shared.isReachable else {
            syncStatus.send(.error(APIError.offline))
            completion(.failure(APIError.offline))
            return
        }
        
        // Fetch pending changes
        coreDataStack.performBackgroundTask { [weak self] context in
            guard let self = self else { return }
            
            do {
                // Fetch and prepare local changes
                let changes = try self.fetchPendingChanges(
                    context: context,
                    batchSize: options.batchSize
                )
                
                // Upload changes to server
                self.uploadChanges(changes) { result in
                    switch result {
                    case .success:
                        // Download and apply remote changes
                        self.downloadRemoteChanges { result in
                            switch result {
                            case .success:
                                self.syncStatus.send(.completed(Date()))
                                completion(.success(()))
                            case .failure(let error):
                                self.syncStatus.send(.error(error))
                                completion(.failure(error))
                            }
                        }
                    case .failure(let error):
                        self.syncStatus.send(.error(error))
                        completion(.failure(error))
                    }
                }
            } catch {
                self.syncStatus.send(.error(error))
                completion(.failure(error))
            }
        }
    }
    
    private func fetchPendingChanges(
        context: NSManagedObjectContext,
        batchSize: Int
    ) throws -> [SyncOperation] {
        let fetchRequest: NSFetchRequest<SyncEntry> = SyncEntry.fetchRequest()
        fetchRequest.fetchLimit = batchSize
        fetchRequest.sortDescriptors = [
            NSSortDescriptor(key: "priority", ascending: false),
            NSSortDescriptor(key: "timestamp", ascending: true)
        ]
        
        let entries = try context.fetch(fetchRequest)
        return entries.map { entry in
            SyncOperation(
                id: entry.id,
                type: SyncOperation.OperationType(rawValue: entry.type) ?? .update,
                data: entry.data,
                timestamp: entry.timestamp,
                priority: Int(entry.priority)
            )
        }
    }
    
    private func uploadChanges(
        _ changes: [SyncOperation],
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard !changes.isEmpty else {
            completion(.success(()))
            return
        }
        
        // Prepare sync payload
        let payload = SyncPayload(
            changes: changes,
            versionVector: versionVector
        )
        
        // Upload changes to server
        apiClient.request(
            .syncData(changes: changes, lastSyncTimestamp: versionVector.timestamp),
            retryPolicy: retryPolicy
        )
        .sink(
            receiveCompletion: { completionStatus in
                switch completionStatus {
                case .finished:
                    completion(.success(()))
                case .failure(let error):
                    completion(.failure(error))
                }
            },
            receiveValue: { _ in }
        )
        .store(in: &Set<AnyCancellable>())
    }
    
    private func downloadRemoteChanges(
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        apiClient.request(.getCollections(page: 1, limit: MAX_BATCH_SIZE))
            .sink(
                receiveCompletion: { completionStatus in
                    switch completionStatus {
                    case .finished:
                        completion(.success(()))
                    case .failure(let error):
                        completion(.failure(error))
                    }
                },
                receiveValue: { [weak self] (remoteData: RemoteData) in
                    self?.applyRemoteChanges(remoteData)
                }
            )
            .store(in: &Set<AnyCancellable>())
    }
    
    private func applyRemoteChanges(_ remoteData: RemoteData) {
        coreDataStack.performBackgroundTask { context in
            // Apply remote changes to local database
            // Implementation would handle merging and conflict resolution
        }
    }
    
    private func scheduleBackgroundSync() {
        let request = BGAppRefreshTaskRequest(identifier: BACKGROUND_TASK_ID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: SYNC_INTERVAL)
        
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Failed to schedule background sync: \(error)")
        }
    }
}

// MARK: - Supporting Types (CoreData)

@objc(SyncEntry)
class SyncEntry: NSManagedObject {
    @NSManaged var id: UUID
    @NSManaged var type: String
    @NSManaged var data: Data
    @NSManaged var timestamp: Date
    @NSManaged var priority: Int16
}