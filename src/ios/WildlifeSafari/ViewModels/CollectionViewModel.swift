//
// CollectionViewModel.swift
// WildlifeSafari
//
// ViewModel for managing collections of wildlife and fossil discoveries with
// comprehensive offline support and reactive data binding.
//

import Foundation // Latest - Basic iOS functionality
import Combine    // Latest - Reactive programming support
import SwiftUI   // Latest - UI state management

// MARK: - Constants

private enum Constants {
    static let debounceInterval: TimeInterval = 0.5
    static let pageSize = 20
    static let maxOfflineStorageSize = 1000
    static let maxRetryAttempts = 3
}

// MARK: - Collection View Model

@MainActor
@available(iOS 14.0, *)
public final class CollectionViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published private(set) var collections: [Collection] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSyncing = false
    @Published private(set) var error: CollectionError?
    @Published var selectedCollection: Collection?
    @Published private(set) var hasMorePages = true
    @Published private(set) var networkStatus = NetworkStatus.online
    
    // MARK: - Private Properties
    
    private let collectionService: CollectionService
    private let currentPage = CurrentValueSubject<Int, Never>(1)
    private var cancellables = Set<AnyCancellable>()
    private var loadingTask: Task<Void, Error>?
    
    // MARK: - Initialization
    
    public init(collectionService: CollectionService) {
        self.collectionService = collectionService
        
        setupBindings()
        setupNetworkMonitoring()
        loadInitialData()
    }
    
    // MARK: - Public Methods
    
    /// Loads or refreshes collections with pagination support
    /// - Parameter forceRefresh: Whether to force a refresh from the server
    public func loadCollections(forceRefresh: Bool = false) {
        loadingTask?.cancel()
        
        loadingTask = Task { [weak self] in
            guard let self = self else { return }
            
            do {
                self.isLoading = true
                self.error = nil
                
                let page = forceRefresh ? 1 : self.currentPage.value
                
                // Load collections from service
                let result = try await withCheckedThrowingContinuation { continuation in
                    self.collectionService.getCollections(
                        page: page,
                        limit: Constants.pageSize
                    )
                    .sink(
                        receiveCompletion: { completion in
                            switch completion {
                            case .finished:
                                break
                            case .failure(let error):
                                continuation.resume(throwing: error)
                            }
                        },
                        receiveValue: { collections in
                            continuation.resume(returning: collections)
                        }
                    )
                    .store(in: &self.cancellables)
                }
                
                // Update collections
                if forceRefresh {
                    self.collections = result
                } else {
                    self.collections.append(contentsOf: result)
                }
                
                // Update pagination state
                self.hasMorePages = result.count >= Constants.pageSize
                if self.hasMorePages {
                    self.currentPage.send(page + 1)
                }
                
            } catch {
                self.error = error as? CollectionError ?? .persistenceError("Failed to load collections")
            }
            
            self.isLoading = false
        }
    }
    
    /// Creates a new collection with offline support
    /// - Parameters:
    ///   - name: Collection name
    ///   - description: Optional collection description
    public func createCollection(
        name: String,
        description: String? = nil
    ) -> AnyPublisher<Collection, CollectionError> {
        // Validate input
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return Fail(error: .invalidCollection).eraseToAnyPublisher()
        }
        
        // Check offline storage limits
        if collections.count >= Constants.maxOfflineStorageSize {
            return Fail(error: .maxCollectionsExceeded).eraseToAnyPublisher()
        }
        
        return collectionService.createCollection(name: name, description: description)
            .handleEvents(
                receiveOutput: { [weak self] collection in
                    self?.collections.insert(collection, at: 0)
                },
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.error = error as? CollectionError
                    }
                }
            )
            .eraseToAnyPublisher()
    }
    
    /// Updates an existing collection
    /// - Parameters:
    ///   - collection: The collection to update
    ///   - updates: Update closure
    public func updateCollection(
        _ collection: Collection,
        updates: @escaping (Collection) throws -> Void
    ) -> AnyPublisher<Collection, CollectionError> {
        return collectionService.updateCollection(collection.collectionId) { collection in
            try updates(collection)
        }
        .handleEvents(
            receiveOutput: { [weak self] updatedCollection in
                if let index = self?.collections.firstIndex(where: { $0.collectionId == updatedCollection.collectionId }) {
                    self?.collections[index] = updatedCollection
                }
            },
            receiveCompletion: { [weak self] completion in
                if case .failure(let error) = completion {
                    self?.error = error as? CollectionError
                }
            }
        )
        .eraseToAnyPublisher()
    }
    
    /// Deletes a collection
    /// - Parameter collection: The collection to delete
    public func deleteCollection(_ collection: Collection) -> AnyPublisher<Void, CollectionError> {
        return collectionService.deleteCollection(collection.collectionId)
            .handleEvents(
                receiveCompletion: { [weak self] completion in
                    switch completion {
                    case .finished:
                        self?.collections.removeAll { $0.collectionId == collection.collectionId }
                    case .failure(let error):
                        self?.error = error as? CollectionError
                    }
                }
            )
            .eraseToAnyPublisher()
    }
    
    /// Adds a discovery to a collection
    /// - Parameters:
    ///   - discovery: The discovery to add
    ///   - collection: The target collection
    public func addDiscoveryToCollection(
        _ discovery: Discovery,
        to collection: Collection
    ) -> AnyPublisher<Void, CollectionError> {
        return collectionService.addDiscoveryToCollection(discovery, collectionId: collection.collectionId)
            .handleEvents(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.error = error as? CollectionError
                    }
                }
            )
            .eraseToAnyPublisher()
    }
    
    /// Triggers manual synchronization
    public func syncCollections() {
        guard !isSyncing else { return }
        
        isSyncing = true
        
        collectionService.syncCollections()
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    self?.isSyncing = false
                    if case .failure(let error) = completion {
                        self?.error = error as? CollectionError
                    }
                },
                receiveValue: { [weak self] _ in
                    self?.loadCollections(forceRefresh: true)
                }
            )
            .store(in: &cancellables)
    }
    
    // MARK: - Private Methods
    
    private func setupBindings() {
        // Handle pagination
        currentPage
            .dropFirst()
            .debounce(for: .seconds(Constants.debounceInterval), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.loadCollections()
            }
            .store(in: &cancellables)
    }
    
    private func setupNetworkMonitoring() {
        // Monitor network status changes
        NotificationCenter.default.publisher(for: .networkStatusChanged)
            .sink { [weak self] notification in
                if let status = notification.object as? NetworkStatus {
                    self?.networkStatus = status
                    
                    // Trigger sync when coming online
                    if status == .online {
                        self?.syncCollections()
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    private func loadInitialData() {
        loadCollections(forceRefresh: true)
    }
}

// MARK: - Network Status

public enum NetworkStatus {
    case online
    case offline
}

extension Notification.Name {
    static let networkStatusChanged = Notification.Name("networkStatusChanged")
}