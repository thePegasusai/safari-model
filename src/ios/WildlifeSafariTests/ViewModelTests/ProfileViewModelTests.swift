//
// ProfileViewModelTests.swift
// WildlifeSafariTests
//
// Comprehensive test suite for ProfileViewModel validating user profile management,
// authentication flows, and collection statistics with extensive error handling.
//

import XCTest
import Combine
@testable import WildlifeSafari

// MARK: - Constants

private let TEST_TIMEOUT: TimeInterval = 5.0
private let TEST_USER_EMAIL = "test@example.com"
private let TEST_USER_NAME = "Test User"
private let TEST_COLLECTION_SIZE = 100
private let TEST_PERFORMANCE_BASELINE = 0.1

// MARK: - ProfileViewModelTests

@available(iOS 13.0, *)
final class ProfileViewModelTests: XCTestCase {
    
    // MARK: - Properties
    
    private var viewModel: ProfileViewModel!
    private var mockAuthService: MockAuthenticationService!
    private var mockCollectionService: MockCollectionService!
    private var mockSecureStorage: MockSecureStorageManager!
    private var mockErrorHandler: MockErrorHandler!
    private var mockAnalytics: MockAnalyticsTracker!
    private var cancellables: Set<AnyCancellable>!
    
    private var testUser: User!
    private var testCollections: [Collection]!
    
    // MARK: - Setup & Teardown
    
    override func setUp() {
        super.setUp()
        
        // Initialize mock services
        mockAuthService = MockAuthenticationService()
        mockCollectionService = MockCollectionService()
        mockSecureStorage = MockSecureStorageManager()
        mockErrorHandler = MockErrorHandler()
        mockAnalytics = MockAnalyticsTracker()
        
        // Initialize test data
        setupTestData()
        
        // Initialize view model with mock services
        viewModel = ProfileViewModel(
            authService: mockAuthService,
            collectionService: mockCollectionService,
            secureStorage: mockSecureStorage,
            errorHandler: mockErrorHandler,
            analyticsTracker: mockAnalytics
        )
        
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDown() {
        viewModel = nil
        mockAuthService = nil
        mockCollectionService = nil
        mockSecureStorage = nil
        mockErrorHandler = nil
        mockAnalytics = nil
        cancellables = nil
        testUser = nil
        testCollections = nil
        
        super.tearDown()
    }
    
    // MARK: - Test Cases
    
    func testLoadUserProfile() {
        // Given
        let expectation = XCTestExpectation(description: "Load user profile")
        mockSecureStorage.storedUser = testUser
        mockAuthService.isAuthenticated.send(true)
        
        var receivedStates: [UserState] = []
        
        // When
        viewModel.loadUserProfile()
            .sink(
                receiveCompletion: { completion in
                    if case .failure = completion {
                        XCTFail("Profile loading should succeed")
                    }
                    expectation.fulfill()
                },
                receiveValue: { state in
                    receivedStates.append(state)
                }
            )
            .store(in: &cancellables)
        
        // Then
        wait(for: [expectation], timeout: TEST_TIMEOUT)
        
        XCTAssertEqual(receivedStates.count, 2)
        XCTAssertEqual(receivedStates.first, .loading)
        
        if case .authenticated(let user) = receivedStates.last {
            XCTAssertEqual(user.id, testUser.id)
            XCTAssertEqual(user.email, TEST_USER_EMAIL)
        } else {
            XCTFail("Final state should be authenticated")
        }
        
        // Verify analytics tracking
        XCTAssertTrue(mockAnalytics.trackedEvents.contains { event in
            event.name == "profile_loaded" &&
            event.properties["user_id"] as? String == testUser.id.uuidString
        })
    }
    
    func testLoadUserProfileFailure() {
        // Given
        let expectation = XCTestExpectation(description: "Load user profile failure")
        mockAuthService.isAuthenticated.send(false)
        
        // When
        viewModel.loadUserProfile()
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        XCTAssertEqual(error, .authenticationFailed)
                        expectation.fulfill()
                    }
                },
                receiveValue: { _ in
                    XCTFail("Should not receive value")
                }
            )
            .store(in: &cancellables)
        
        // Then
        wait(for: [expectation], timeout: TEST_TIMEOUT)
        XCTAssertNotNil(viewModel.error)
    }
    
    func testUpdateUserProfile() {
        // Given
        let expectation = XCTestExpectation(description: "Update user profile")
        let updateData = UserUpdateData(
            name: "Updated Name",
            preferences: ["theme": "dark"],
            securitySettings: ["biometrics": true]
        )
        
        mockSecureStorage.storedUser = testUser
        mockAuthService.isAuthenticated.send(true)
        
        // When
        viewModel.updateUserProfile(updateData)
            .sink(
                receiveCompletion: { completion in
                    if case .failure = completion {
                        XCTFail("Profile update should succeed")
                    }
                    expectation.fulfill()
                },
                receiveValue: { state in
                    if case .authenticated(let user) = state {
                        XCTAssertEqual(user.name, "Updated Name")
                    } else {
                        XCTFail("Should receive authenticated state")
                    }
                }
            )
            .store(in: &cancellables)
        
        // Then
        wait(for: [expectation], timeout: TEST_TIMEOUT)
        
        // Verify sync triggered
        XCTAssertTrue(mockCollectionService.syncTriggered)
        
        // Verify analytics
        XCTAssertTrue(mockAnalytics.trackedEvents.contains { event in
            event.name == "profile_updated" &&
            event.properties["updated_fields"] as? String == "theme"
        })
    }
    
    func testSignOut() {
        // Given
        let expectation = XCTestExpectation(description: "Sign out")
        mockAuthService.isAuthenticated.send(true)
        
        // When
        viewModel.signOut()
            .sink(
                receiveCompletion: { completion in
                    if case .failure = completion {
                        XCTFail("Sign out should succeed")
                    }
                    expectation.fulfill()
                },
                receiveValue: { _ in
                    XCTAssertFalse(self.mockAuthService.isAuthenticated.value)
                }
            )
            .store(in: &cancellables)
        
        // Then
        wait(for: [expectation], timeout: TEST_TIMEOUT)
        
        // Verify cleanup
        XCTAssertTrue(mockSecureStorage.wasCleared)
        XCTAssertNil(mockSecureStorage.storedUser)
    }
    
    func testCollectionStatistics() {
        // Given
        let expectation = XCTestExpectation(description: "Collection statistics")
        mockCollectionService.collections = testCollections
        
        // When
        measure {
            viewModel.getCollectionStatistics()
                .sink(
                    receiveCompletion: { completion in
                        if case .failure = completion {
                            XCTFail("Statistics calculation should succeed")
                        }
                        expectation.fulfill()
                    },
                    receiveValue: { stats in
                        // Verify statistics accuracy
                        XCTAssertEqual(stats.totalCollections, self.testCollections.count)
                        XCTAssertGreaterThan(stats.totalDiscoveries, 0)
                        XCTAssertNotNil(stats.lastUpdateDate)
                    }
                )
                .store(in: &cancellables)
        }
        
        // Then
        wait(for: [expectation], timeout: TEST_TIMEOUT)
    }
    
    // MARK: - Performance Tests
    
    func testProfileLoadingPerformance() {
        measure {
            let expectation = XCTestExpectation(description: "Profile loading performance")
            
            viewModel.loadUserProfile()
                .sink(
                    receiveCompletion: { _ in
                        expectation.fulfill()
                    },
                    receiveValue: { _ in }
                )
                .store(in: &cancellables)
            
            wait(for: [expectation], timeout: TEST_TIMEOUT)
        }
    }
    
    // MARK: - Helper Methods
    
    private func setupTestData() {
        // Create test user
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        testUser = User(entity: User.entity(), insertInto: context)
        testUser.email = TEST_USER_EMAIL
        testUser.name = TEST_USER_NAME
        
        // Create test collections
        testCollections = (0..<TEST_COLLECTION_SIZE).map { index in
            let collection = Collection(entity: Collection.entity(), insertInto: context)
            collection.name = "Collection \(index)"
            return collection
        }
    }
}

// MARK: - Mock Services

private class MockAuthenticationService: AuthenticationService {
    let isAuthenticated = CurrentValueSubject<Bool, Never>(false)
    
    override func signOut() -> AnyPublisher<Void, AuthError> {
        isAuthenticated.send(false)
        return Just(()).setFailureType(to: AuthError.self).eraseToAnyPublisher()
    }
}

private class MockCollectionService: CollectionService {
    var collections: [Collection] = []
    var syncTriggered = false
    
    override func syncCollections() -> AnyPublisher<Void, Error> {
        syncTriggered = true
        return Just(()).setFailureType(to: Error.self).eraseToAnyPublisher()
    }
}

private class MockSecureStorageManager: SecureStorageManager {
    var storedUser: User?
    var wasCleared = false
    
    override func retrieveUserData() -> AnyPublisher<User?, Error> {
        return Just(storedUser).setFailureType(to: Error.self).eraseToAnyPublisher()
    }
    
    override func clearAll() -> Result<Void, KeychainError> {
        wasCleared = true
        storedUser = nil
        return .success(())
    }
}

private class MockErrorHandler: ErrorHandlingProtocol {
    func handleError(_ error: Error) {}
}

private class MockAnalyticsTracker: AnalyticsProtocol {
    struct TrackedEvent {
        let name: String
        let properties: [String: Any]
    }
    
    var trackedEvents: [TrackedEvent] = []
    
    func trackEvent(_ name: String, properties: [String: Any]) {
        trackedEvents.append(TrackedEvent(name: name, properties: properties))
    }
}