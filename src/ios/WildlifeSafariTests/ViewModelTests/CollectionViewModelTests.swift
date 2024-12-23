//
// CollectionViewModelTests.swift
// WildlifeSafariTests
//
// Created by Wildlife Safari Team
// Copyright © 2024 Wildlife Safari. All rights reserved.
//

import XCTest
import Combine
@testable import WildlifeSafari

@available(iOS 14.0, *)
final class CollectionViewModelTests: XCTestCase {
    
    // MARK: - Properties
    
    private var sut: CollectionViewModel!
    private var mockService: MockCollectionService!
    private var cancellables: Set<AnyCancellable>
    private let testQueue = DispatchQueue(label: "com.wildlifesafari.tests")
    
    // MARK: - Test Constants
    
    private let testTimeout: TimeInterval = 5.0
    private let mockCollection = Collection(
        id: UUID(),
        name: "Test Collection",
        discoveries: []
    )
    
    // MARK: - Setup & Teardown
    
    override func setUp() {
        super.setUp()
        mockService = MockCollectionService()
        sut = CollectionViewModel(service: mockService)
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDown() {
        cancellables.forEach { $0.cancel() }
        mockService = nil
        sut = nil
        super.tearDown()
    }
    
    // MARK: - Initial State Tests
    
    func testInitialState() {
        XCTAssertTrue(sut.collections.isEmpty, "Collections should be empty on initialization")
        XCTAssertFalse(sut.isLoading, "Loading state should be false initially")
        XCTAssertNil(sut.error, "Error should be nil initially")
        XCTAssertNil(sut.selectedCollection, "No collection should be selected initially")
        XCTAssertFalse(sut.isOfflineMode, "Offline mode should be disabled initially")
    }
    
    // MARK: - Collection Management Tests
    
    func testLoadCollections() {
        // Given
        let expectation = expectation(description: "Load collections")
        mockService.mockCollections = [mockCollection]
        
        // When
        sut.loadCollections()
        
        // Then
        sut.$collections
            .dropFirst()
            .sink { collections in
                XCTAssertEqual(collections.count, 1, "Should load one collection")
                XCTAssertEqual(collections.first?.id, self.mockCollection.id)
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: testTimeout)
    }
    
    func testCreateCollection() {
        // Given
        let expectation = expectation(description: "Create collection")
        let newCollectionName = "New Test Collection"
        
        // When
        sut.createCollection(name: newCollectionName)
        
        // Then
        sut.$collections
            .dropFirst()
            .sink { collections in
                XCTAssertEqual(collections.count, 1, "Should create one collection")
                XCTAssertEqual(collections.first?.name, newCollectionName)
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: testTimeout)
    }
    
    // MARK: - Offline Capability Tests
    
    func testOfflineCapability() {
        // Given
        let expectation = expectation(description: "Offline operations")
        sut.isOfflineMode = true
        
        // When
        sut.createCollection(name: "Offline Collection")
        
        // Then
        sut.$collections
            .dropFirst()
            .sink { collections in
                XCTAssertEqual(collections.count, 1, "Should create collection in offline mode")
                XCTAssertTrue(self.sut.pendingSync, "Should have pending sync")
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: testTimeout)
    }
    
    func testOfflineSync() {
        // Given
        let syncExpectation = expectation(description: "Sync after offline")
        sut.isOfflineMode = true
        sut.createCollection(name: "Offline Collection")
        
        // When
        sut.isOfflineMode = false
        sut.syncPendingChanges()
        
        // Then
        sut.$pendingSync
            .dropFirst()
            .sink { isPending in
                XCTAssertFalse(isPending, "Should complete sync")
                syncExpectation.fulfill()
            }
            .store(in: &cancellables)
        
        wait(for: [syncExpectation], timeout: testTimeout)
    }
    
    // MARK: - Error Handling Tests
    
    func testErrorHandling() {
        // Given
        let expectation = expectation(description: "Error handling")
        mockService.shouldFail = true
        
        // When
        sut.loadCollections()
        
        // Then
        sut.$error
            .dropFirst()
            .sink { error in
                XCTAssertNotNil(error, "Should receive error")
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: testTimeout)
    }
    
    func testErrorRecovery() {
        // Given
        let errorExpectation = expectation(description: "Error occurs")
        let recoveryExpectation = expectation(description: "Error recovery")
        mockService.shouldFail = true
        
        // When - First attempt fails
        sut.loadCollections()
        
        sut.$error
            .dropFirst()
            .sink { error in
                XCTAssertNotNil(error, "Should receive error")
                errorExpectation.fulfill()
                
                // When - Second attempt succeeds
                self.mockService.shouldFail = false
                self.sut.retry()
                
                self.sut.$collections
                    .dropFirst()
                    .sink { collections in
                        XCTAssertTrue(collections.isEmpty, "Should recover and load empty collection")
                        recoveryExpectation.fulfill()
                    }
                    .store(in: &self.cancellables)
            }
            .store(in: &cancellables)
        
        wait(for: [errorExpectation, recoveryExpectation], timeout: testTimeout)
    }
    
    // MARK: - Selection Tests
    
    func testCollectionSelection() {
        // Given
        let expectation = expectation(description: "Collection selection")
        mockService.mockCollections = [mockCollection]
        
        // When
        sut.loadCollections()
        
        sut.$collections
            .dropFirst()
            .sink { collections in
                self.sut.selectCollection(collections.first!)
                
                // Then
                XCTAssertEqual(self.sut.selectedCollection?.id, self.mockCollection.id)
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: testTimeout)
    }
    
    // MARK: - Performance Tests
    
    func testLoadPerformance() {
        measure {
            let expectation = expectation(description: "Load performance")
            sut.loadCollections()
            
            sut.$isLoading
                .dropFirst()
                .sink { isLoading in
                    if !isLoading {
                        expectation.fulfill()
                    }
                }
                .store(in: &cancellables)
            
            wait(for: [expectation], timeout: testTimeout)
        }
    }
}

// MARK: - Mock Collection Service

private class MockCollectionService: CollectionServiceProtocol {
    var mockCollections: [Collection] = []
    var shouldFail = false
    
    func fetchCollections() -> AnyPublisher<[Collection], Error> {
        if shouldFail {
            return Fail(error: NSError(domain: "com.wildlifesafari.error",
                                     code: -1,
                                     userInfo: [NSLocalizedDescriptionKey: "Mock error"]))
                .eraseToAnyPublisher()
        }
        return Just(mockCollections)
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }
    
    func createCollection(_ collection: Collection) -> AnyPublisher<Collection, Error> {
        if shouldFail {
            return Fail(error: NSError(domain: "com.wildlifesafari.error",
                                     code: -1,
                                     userInfo: [NSLocalizedDescriptionKey: "Mock error"]))
                .eraseToAnyPublisher()
        }
        return Just(collection)
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }
    
    func updateCollection(_ collection: Collection) -> AnyPublisher<Collection, Error> {
        if shouldFail {
            return Fail(error: NSError(domain: "com.wildlifesafari.error",
                                     code: -1,
                                     userInfo: [NSLocalizedDescriptionKey: "Mock error"]))
                .eraseToAnyPublisher()
        }
        return Just(collection)
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
    }
}