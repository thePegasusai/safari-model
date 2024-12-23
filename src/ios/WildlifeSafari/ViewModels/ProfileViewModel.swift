//
// ProfileViewModel.swift
// WildlifeSafari
//
// Enterprise-grade ViewModel managing user profile data, authentication state,
// collection statistics, and secure data handling.
//

import Foundation // latest
import Combine // latest
import CoreData // latest

// MARK: - Constants

private let PROFILE_UPDATE_DEBOUNCE: TimeInterval = 0.5
private let MAX_RETRY_ATTEMPTS: Int = 3
private let SYNC_INTERVAL: TimeInterval = 300

// MARK: - Supporting Types

/// Represents the current state of user profile
public enum UserState: Equatable {
    case initial
    case loading
    case authenticated(User)
    case unauthenticated
    case error(String)
}

/// Represents profile update data
public struct UserUpdateData {
    let name: String?
    let preferences: [String: Any]?
    let securitySettings: [String: Any]?
}

/// Error states specific to profile management
public enum ProfileError: LocalizedError {
    case authenticationFailed
    case updateFailed
    case validationFailed(String)
    case securityError(String)
    case syncError(String)
    
    public var errorDescription: String? {
        switch self {
        case .authenticationFailed:
            return "Authentication failed"
        case .updateFailed:
            return "Failed to update profile"
        case .validationFailed(let message):
            return "Validation failed: \(message)"
        case .securityError(let message):
            return "Security error: \(message)"
        case .syncError(let message):
            return "Sync error: \(message)"
        }
    }
}

// MARK: - ProfileViewModel Implementation

@MainActor
@available(iOS 13.0, *)
public final class ProfileViewModel {
    
    // MARK: - Properties
    
    private let authService: AuthenticationService
    private let collectionService: CollectionService
    private let secureStorage: SecureStorageManager
    private let errorHandler: ErrorHandlingProtocol
    private let analyticsTracker: AnalyticsProtocol
    
    private var cancellables = Set<AnyCancellable>()
    private let userState = CurrentValueSubject<UserState, Never>(.initial)
    private let profileUpdateQueue: OperationQueue
    
    @Published private(set) var isLoading = false
    @Published private(set) var error: ProfileError?
    
    // MARK: - Initialization
    
    public init(
        authService: AuthenticationService,
        collectionService: CollectionService,
        secureStorage: SecureStorageManager,
        errorHandler: ErrorHandlingProtocol,
        analyticsTracker: AnalyticsProtocol
    ) {
        self.authService = authService
        self.collectionService = collectionService
        self.secureStorage = secureStorage
        self.errorHandler = errorHandler
        self.analyticsTracker = analyticsTracker
        
        // Configure profile update queue
        self.profileUpdateQueue = OperationQueue()
        self.profileUpdateQueue.maxConcurrentOperationCount = 1
        self.profileUpdateQueue.qualityOfService = .userInitiated
        
        setupBindings()
        setupAutomaticSessionRefresh()
    }
    
    // MARK: - Public Methods
    
    /// Loads and validates user profile with comprehensive error handling
    /// - Returns: Publisher emitting user state updates
    public func loadUserProfile() -> AnyPublisher<UserState, ProfileError> {
        return Future { [weak self] promise in
            guard let self = self else {
                promise(.failure(.securityError("ViewModel deallocated")))
                return
            }
            
            self.isLoading = true
            
            // Validate current session
            guard self.authService.isAuthenticated.value else {
                self.userState.send(.unauthenticated)
                promise(.failure(.authenticationFailed))
                return
            }
            
            // Attempt to load profile with retry logic
            var retryCount = 0
            
            func attemptLoad() {
                self.secureStorage.retrieveUserData()
                    .flatMap { userData -> AnyPublisher<User, Error> in
                        // Validate user data integrity
                        guard let user = userData else {
                            throw ProfileError.validationFailed("Invalid user data")
                        }
                        return Just(user)
                            .setFailureType(to: Error.self)
                            .eraseToAnyPublisher()
                    }
                    .sink(
                        receiveCompletion: { [weak self] completion in
                            guard let self = self else { return }
                            
                            switch completion {
                            case .finished:
                                self.isLoading = false
                            case .failure(let error):
                                if retryCount < MAX_RETRY_ATTEMPTS {
                                    retryCount += 1
                                    attemptLoad()
                                } else {
                                    self.isLoading = false
                                    self.error = .validationFailed(error.localizedDescription)
                                    self.userState.send(.error(error.localizedDescription))
                                    promise(.failure(.validationFailed(error.localizedDescription)))
                                }
                            }
                        },
                        receiveValue: { [weak self] user in
                            guard let self = self else { return }
                            
                            // Update state and trigger background sync
                            self.userState.send(.authenticated(user))
                            self.triggerBackgroundSync()
                            
                            // Track analytics event
                            self.analyticsTracker.trackEvent("profile_loaded", properties: [
                                "user_id": user.id.uuidString,
                                "collections_count": user.collections.count
                            ])
                            
                            promise(.success(self.userState.value))
                        }
                    )
                    .store(in: &self.cancellables)
            }
            
            attemptLoad()
        }
        .eraseToAnyPublisher()
    }
    
    /// Updates user profile with validation and conflict resolution
    /// - Parameter updateData: Data to update in the profile
    /// - Returns: Publisher emitting updated user state
    public func updateUserProfile(_ updateData: UserUpdateData) -> AnyPublisher<UserState, ProfileError> {
        return Future { [weak self] promise in
            guard let self = self else {
                promise(.failure(.securityError("ViewModel deallocated")))
                return
            }
            
            // Validate current state
            guard case .authenticated(let currentUser) = self.userState.value else {
                promise(.failure(.authenticationFailed))
                return
            }
            
            // Create update operation
            let operation = BlockOperation { [weak self] in
                guard let self = self else { return }
                
                // Apply updates
                if let name = updateData.name {
                    currentUser.name = name
                }
                
                if let preferences = updateData.preferences {
                    guard currentUser.updatePreferences(preferences) else {
                        self.error = .updateFailed
                        promise(.failure(.updateFailed))
                        return
                    }
                }
                
                // Persist changes
                self.secureStorage.saveUserData(currentUser)
                    .sink(
                        receiveCompletion: { [weak self] completion in
                            guard let self = self else { return }
                            
                            switch completion {
                            case .finished:
                                // Trigger sync
                                self.triggerBackgroundSync()
                                
                                // Track update
                                self.analyticsTracker.trackEvent("profile_updated", properties: [
                                    "user_id": currentUser.id.uuidString,
                                    "updated_fields": updateData.preferences?.keys.joined(separator: ",") ?? ""
                                ])
                                
                                self.userState.send(.authenticated(currentUser))
                                promise(.success(self.userState.value))
                                
                            case .failure(let error):
                                self.error = .updateFailed
                                promise(.failure(.updateFailed))
                                self.errorHandler.handleError(error)
                            }
                        },
                        receiveValue: { _ in }
                    )
                    .store(in: &self.cancellables)
            }
            
            // Add operation to queue
            self.profileUpdateQueue.addOperation(operation)
        }
        .debounce(for: .seconds(PROFILE_UPDATE_DEBOUNCE), scheduler: RunLoop.main)
        .eraseToAnyPublisher()
    }
    
    // MARK: - Private Methods
    
    private func setupBindings() {
        // Observe authentication state changes
        authService.isAuthenticated
            .sink { [weak self] isAuthenticated in
                guard let self = self else { return }
                
                if !isAuthenticated {
                    self.userState.send(.unauthenticated)
                }
            }
            .store(in: &cancellables)
        
        // Observe collection changes
        collectionService.collectionsPublisher
            .sink { [weak self] completion in
                if case .failure(let error) = completion {
                    self?.error = .syncError(error.localizedDescription)
                }
            } receiveValue: { [weak self] _ in
                self?.refreshUserState()
            }
            .store(in: &cancellables)
    }
    
    private func setupAutomaticSessionRefresh() {
        Timer.publish(every: SYNC_INTERVAL, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshSession()
            }
            .store(in: &cancellables)
    }
    
    private func refreshSession() {
        guard case .authenticated = userState.value else { return }
        
        authService.refreshToken()
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure = completion {
                        self?.userState.send(.unauthenticated)
                    }
                },
                receiveValue: { _ in }
            )
            .store(in: &cancellables)
    }
    
    private func refreshUserState() {
        guard case .authenticated(let user) = userState.value else { return }
        
        // Validate session and refresh state
        authService.validateSession()
            .flatMap { [weak self] isValid -> AnyPublisher<User, Error> in
                guard let self = self, isValid else {
                    throw ProfileError.authenticationFailed
                }
                return self.secureStorage.retrieveUserData()
                    .compactMap { $0 }
                    .eraseToAnyPublisher()
            }
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure = completion {
                        self?.userState.send(.unauthenticated)
                    }
                },
                receiveValue: { [weak self] updatedUser in
                    self?.userState.send(.authenticated(updatedUser))
                }
            )
            .store(in: &cancellables)
    }
    
    private func triggerBackgroundSync() {
        // Queue background sync operation
        let syncOperation = BlockOperation { [weak self] in
            guard let self = self else { return }
            
            self.collectionService.syncCollections()
                .sink(
                    receiveCompletion: { [weak self] completion in
                        if case .failure(let error) = completion {
                            self?.error = .syncError(error.localizedDescription)
                        }
                    },
                    receiveValue: { _ in }
                )
                .store(in: &self.cancellables)
        }
        
        syncOperation.queuePriority = .background
        profileUpdateQueue.addOperation(syncOperation)
    }
}