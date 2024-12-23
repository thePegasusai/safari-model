//
// CollectionServiceTests.swift
// WildlifeSafariTests
//
// Comprehensive test suite for CollectionService validation including security and offline capabilities.
//

import XCTest
import Combine
import CoreData
@testable import WildlifeSafari

final class CollectionServiceTests: XCTestCase {
    
    // MARK: - Properties
    
    private var sut: CollectionService?
    private var mockAPIClient: MockAPIClient!
    private var mockCoreDataStack: MockCoreDataStack!
    private var mockSyncService: MockSyncService!
    private var mockEncryptionService: MockEncryptionService!
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Test Constants
    
    private let TEST_TIMEOUT: TimeInterval = 5.0
    private let TEST_COLLECTION_NAME = "Test Collection"
    private let TEST_ENCRYPTION_KEY = "test_encryption_key"
    
    // MARK: - Setup & Teardown
    
    override func setUp() {
        super.setUp()
        
        // Initialize mocks
        mockAPIClient = MockAPIClient()
        mockCoreDataStack = MockCoreDataStack()
        mockSyncService = MockSyncService()
        mockEncryptionService = MockEncryptionService()
        
        // Initialize CollectionService with mocks
        sut = CollectionService(
            apiClient: mockAPIClient,
            coreDataStack: mockCoreDataStack,
            syncService: mockSyncService
        )
        
        // Initialize cancellables set
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDown() {
        cancellables.removeAll()
        sut = nil
        mockAPIClient = nil
        mockCoreDataStack = nil
        mockSyncService = nil
        mockEncryptionService = nil
        super.tearDown()
    }
    
    // MARK: - Collection Creation Tests
    
    func testCreateCollection() {
        // Given
        let expectation = expectation(description: "Create collection")
        let securityContext = SecurityContext(userId: "test_user", accessToken: "test_token", deviceId: "test_device")
        var resultCollection: Collection?
        var resultError: Error?
        
        // When
        sut?.createCollection(
            name: TEST_COLLECTION_NAME,
            description: "Test Description",
            securityContext: securityContext
        )
        .sink(
            receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    resultError = error
                }
                expectation.fulfill()
            },
            receiveValue: { collection in
                resultCollection = collection
            }
        )
        .store(in: &cancellables)
        
        // Then
        waitForExpectations(timeout: TEST_TIMEOUT)
        XCTAssertNil(resultError)
        XCTAssertNotNil(resultCollection)
        XCTAssertEqual(resultCollection?.name, TEST_COLLECTION_NAME)
        XCTAssertFalse(resultCollection?.isSynced ?? true)
    }
    
    func testCreateCollectionExceedingLimit() {
        // Given
        let expectation = expectation(description: "Create collection exceeding limit")
        let securityContext = SecurityContext(userId: "test_user", accessToken: "test_token", deviceId: "test_device")
        mockCoreDataStack.mockCollectionCount = 10 // Max limit
        var resultError: Error?
        
        // When
        sut?.createCollection(
            name: TEST_COLLECTION_NAME,
            description: "Test Description",
            securityContext: securityContext
        )
        .sink(
            receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    resultError = error
                }
                expectation.fulfill()
            },
            receiveValue: { _ in }
        )
        .store(in: &cancellables)
        
        // Then
        waitForExpectations(timeout: TEST_TIMEOUT)
        XCTAssertNotNil(resultError)
        XCTAssertTrue(resultError is CollectionServiceError)
        XCTAssertEqual(resultError as? CollectionServiceError, .maxCollectionsExceeded)
    }
    
    // MARK: - Collection Retrieval Tests
    
    func testGetCollection() {
        // Given
        let expectation = expectation(description: "Get collection")
        let collectionId = UUID()
        let mockCollection = Collection(entity: Collection.entity(), insertInto: nil)
        mockCollection.name = TEST_COLLECTION_NAME
        mockCoreDataStack.mockCollection = mockCollection
        var resultCollection: Collection?
        var resultError: Error?
        
        // When
        sut?.getCollection(collectionId)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        resultError = error
                    }
                    expectation.fulfill()
                },
                receiveValue: { collection in
                    resultCollection = collection
                }
            )
            .store(in: &cancellables)
        
        // Then
        waitForExpectations(timeout: TEST_TIMEOUT)
        XCTAssertNil(resultError)
        XCTAssertNotNil(resultCollection)
        XCTAssertEqual(resultCollection?.name, TEST_COLLECTION_NAME)
    }
    
    // MARK: - Collection Update Tests
    
    func testUpdateCollection() {
        // Given
        let expectation = expectation(description: "Update collection")
        let collectionId = UUID()
        let updatedName = "Updated Collection"
        var resultCollection: Collection?
        var resultError: Error?
        
        // When
        sut?.updateCollection(collectionId) { collection in
            collection.name = updatedName
        }
        .sink(
            receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    resultError = error
                }
                expectation.fulfill()
            },
            receiveValue: { collection in
                resultCollection = collection
            }
        )
        .store(in: &cancellables)
        
        // Then
        waitForExpectations(timeout: TEST_TIMEOUT)
        XCTAssertNil(resultError)
        XCTAssertNotNil(resultCollection)
        XCTAssertEqual(resultCollection?.name, updatedName)
        XCTAssertFalse(resultCollection?.isSynced ?? true)
    }
    
    // MARK: - Collection Deletion Tests
    
    func testDeleteCollection() {
        // Given
        let expectation = expectation(description: "Delete collection")
        let collectionId = UUID()
        var resultError: Error?
        
        // When
        sut?.deleteCollection(collectionId)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        resultError = error
                    }
                    expectation.fulfill()
                },
                receiveValue: { }
            )
            .store(in: &cancellables)
        
        // Then
        waitForExpectations(timeout: TEST_TIMEOUT)
        XCTAssertNil(resultError)
        XCTAssertTrue(mockSyncService.syncOperationQueued)
    }
    
    // MARK: - Offline Operation Tests
    
    func testOfflineOperations() {
        // Given
        let expectation = expectation(description: "Offline operations")
        mockAPIClient.isOffline = true
        let securityContext = SecurityContext(userId: "test_user", accessToken: "test_token", deviceId: "test_device")
        var resultCollection: Collection?
        var resultError: Error?
        
        // When
        sut?.createCollection(
            name: TEST_COLLECTION_NAME,
            description: "Offline Test",
            securityContext: securityContext
        )
        .sink(
            receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    resultError = error
                }
                expectation.fulfill()
            },
            receiveValue: { collection in
                resultCollection = collection
            }
        )
        .store(in: &cancellables)
        
        // Then
        waitForExpectations(timeout: TEST_TIMEOUT)
        XCTAssertNil(resultError)
        XCTAssertNotNil(resultCollection)
        XCTAssertFalse(resultCollection?.isSynced ?? true)
        XCTAssertTrue(mockSyncService.syncOperationQueued)
    }
    
    // MARK: - Security Tests
    
    func testSecureCollectionCreation() {
        // Given
        let expectation = expectation(description: "Secure collection creation")
        let securityContext = SecurityContext(userId: "test_user", accessToken: "test_token", deviceId: "test_device")
        mockEncryptionService.encryptionKey = TEST_ENCRYPTION_KEY
        var resultCollection: Collection?
        var resultError: Error?
        
        // When
        sut?.createCollection(
            name: TEST_COLLECTION_NAME,
            description: "Encrypted Test",
            securityContext: securityContext
        )
        .sink(
            receiveCompletion: { completion in
                if case .failure(let error) = completion {
                    resultError = error
                }
                expectation.fulfill()
            },
            receiveValue: { collection in
                resultCollection = collection
            }
        )
        .store(in: &cancellables)
        
        // Then
        waitForExpectations(timeout: TEST_TIMEOUT)
        XCTAssertNil(resultError)
        XCTAssertNotNil(resultCollection)
        XCTAssertTrue(mockEncryptionService.encryptionCalled)
    }
}

// MARK: - Mock Classes

private class MockAPIClient: APIClient {
    var isOffline = false
    
    override func request<T>(_ endpoint: APIEndpoint, retryPolicy: RetryPolicy?, allowOfflineOperation: Bool) -> AnyPublisher<T, APIError> where T : Decodable {
        if isOffline {
            return Fail(error: APIError.offline).eraseToAnyPublisher()
        }
        return Empty().eraseToAnyPublisher()
    }
}

private class MockCoreDataStack: CoreDataStack {
    var mockCollectionCount = 0
    var mockCollection: Collection?
    
    override func saveContext(_ context: NSManagedObjectContext) -> Result<Void, CoreDataError> {
        return .success(())
    }
}

private class MockSyncService: SyncService {
    var syncOperationQueued = false
    
    override func queueOperation(_ operation: SyncOperation, priority: Operation.QueuePriority) {
        syncOperationQueued = true
    }
}

private class MockEncryptionService {
    var encryptionKey: String?
    var encryptionCalled = false
    
    func encrypt(_ data: Data) -> Data {
        encryptionCalled = true
        return data
    }
}

private struct SecurityContext {
    let userId: String
    let accessToken: String
    let deviceId: String
}