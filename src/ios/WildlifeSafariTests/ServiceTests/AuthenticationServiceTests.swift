//
// AuthenticationServiceTests.swift
// WildlifeSafariTests
//
// Created by Wildlife Safari Team
// Copyright © 2023 Wildlife Safari. All rights reserved.
//

import XCTest
import Combine
@testable import WildlifeSafari

@available(iOS 13.0, *)
class AuthenticationServiceTests: XCTestCase {
    
    // MARK: - Properties
    
    private var sut: AuthenticationService!
    private var mockAPIClient: MockAPIClient!
    private var mockKeychainManager: MockKeychainManager!
    private var mockBiometricManager: MockBiometricManager!
    private var cancellables: Set<AnyCancellable>!
    
    // MARK: - Test Constants
    
    private let validEmail = "test@example.com"
    private let validPassword = "SecurePass123!"
    private let validToken = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.valid"
    private let validRefreshToken = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.refresh"
    private let tokenExpiryInterval: TimeInterval = 3600
    
    // MARK: - Test Lifecycle
    
    override func setUp() {
        super.setUp()
        mockAPIClient = MockAPIClient()
        mockKeychainManager = MockKeychainManager()
        mockBiometricManager = MockBiometricManager()
        cancellables = Set<AnyCancellable>()
        
        sut = AuthenticationService(
            apiClient: mockAPIClient,
            keychainManager: mockKeychainManager,
            biometricManager: mockBiometricManager
        )
    }
    
    override func tearDown() {
        cancellables.forEach { $0.cancel() }
        cancellables = nil
        mockAPIClient = nil
        mockKeychainManager = nil
        mockBiometricManager = nil
        sut = nil
        super.tearDown()
    }
    
    // MARK: - OAuth Sign In Tests
    
    func testOAuthSignInSuccess() {
        // Given
        let expectation = XCTestExpectation(description: "OAuth sign in succeeds")
        let mockAuthResult = AuthResult(
            accessToken: validToken,
            refreshToken: validRefreshToken,
            expiresIn: tokenExpiryInterval,
            tokenType: "Bearer"
        )
        mockAPIClient.mockAuthResult = .success(mockAuthResult)
        
        // When
        sut.signIn(email: validEmail, password: validPassword)
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        XCTFail("Sign in failed with error: \(error)")
                    }
                },
                receiveValue: { result in
                    // Then
                    XCTAssertEqual(result.accessToken, self.validToken)
                    XCTAssertEqual(result.refreshToken, self.validRefreshToken)
                    XCTAssertEqual(result.expiresIn, self.tokenExpiryInterval)
                    XCTAssertTrue(self.mockKeychainManager.saveTokenCalled)
                    expectation.fulfill()
                }
            )
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testOAuthSignInFailure() {
        // Given
        let expectation = XCTestExpectation(description: "OAuth sign in fails")
        mockAPIClient.mockAuthResult = .failure(.invalidCredentials)
        
        // When
        sut.signIn(email: validEmail, password: "wrongpassword")
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        // Then
                        XCTAssertEqual(error, .invalidCredentials)
                        expectation.fulfill()
                    }
                },
                receiveValue: { _ in
                    XCTFail("Sign in should not succeed")
                }
            )
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    // MARK: - Biometric Authentication Tests
    
    func testBiometricAuthenticationSuccess() {
        // Given
        let expectation = XCTestExpectation(description: "Biometric authentication succeeds")
        mockBiometricManager.mockAvailabilityResult = .success(.available(.faceID))
        mockBiometricManager.mockAuthResult = .success(BiometricAuthResult(
            success: true,
            type: .faceID,
            timestamp: Date()
        ))
        mockKeychainManager.mockTokenResult = .success(validRefreshToken)
        
        // When
        sut.signInWithBiometrics()
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        XCTFail("Biometric auth failed with error: \(error)")
                    }
                },
                receiveValue: { result in
                    // Then
                    XCTAssertEqual(result.accessToken, self.validToken)
                    XCTAssertTrue(self.mockBiometricManager.authenticateCalled)
                    expectation.fulfill()
                }
            )
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testBiometricAuthenticationUnavailable() {
        // Given
        let expectation = XCTestExpectation(description: "Biometric authentication unavailable")
        mockBiometricManager.mockAvailabilityResult = .success(.unavailable("Not enrolled"))
        
        // When
        sut.signInWithBiometrics()
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        // Then
                        XCTAssertEqual(error, .biometricError(.notAvailable))
                        expectation.fulfill()
                    }
                },
                receiveValue: { _ in
                    XCTFail("Biometric auth should not succeed")
                }
            )
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    // MARK: - Token Management Tests
    
    func testTokenRefreshSuccess() {
        // Given
        let expectation = XCTestExpectation(description: "Token refresh succeeds")
        mockKeychainManager.mockTokenResult = .success(validRefreshToken)
        let newToken = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.new"
        let mockRefreshResult = AuthResult(
            accessToken: newToken,
            refreshToken: validRefreshToken,
            expiresIn: tokenExpiryInterval,
            tokenType: "Bearer"
        )
        mockAPIClient.mockRefreshResult = .success(mockRefreshResult)
        
        // When
        sut.refreshToken()
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        XCTFail("Token refresh failed with error: \(error)")
                    }
                },
                receiveValue: { result in
                    // Then
                    XCTAssertEqual(result.accessToken, newToken)
                    XCTAssertTrue(self.mockKeychainManager.saveTokenCalled)
                    expectation.fulfill()
                }
            )
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    func testTokenRefreshFailure() {
        // Given
        let expectation = XCTestExpectation(description: "Token refresh fails")
        mockKeychainManager.mockTokenResult = .success(validRefreshToken)
        mockAPIClient.mockRefreshResult = .failure(.refreshFailed)
        
        // When
        sut.refreshToken()
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        // Then
                        XCTAssertEqual(error, .refreshFailed)
                        expectation.fulfill()
                    }
                },
                receiveValue: { _ in
                    XCTFail("Token refresh should not succeed")
                }
            )
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 5.0)
    }
    
    // MARK: - Sign Out Tests
    
    func testSignOutSuccess() {
        // Given
        let expectation = XCTestExpectation(description: "Sign out succeeds")
        mockKeychainManager.mockClearResult = .success(())
        
        // When
        sut.signOut()
            .sink(
                receiveCompletion: { completion in
                    if case .failure(let error) = completion {
                        XCTFail("Sign out failed with error: \(error)")
                    }
                },
                receiveValue: {
                    // Then
                    XCTAssertTrue(self.mockKeychainManager.clearAllCalled)
                    expectation.fulfill()
                }
            )
            .store(in: &cancellables)
        
        wait(for: [expectation], timeout: 5.0)
    }
}

// MARK: - Mock Classes

private class MockAPIClient {
    var mockAuthResult: Result<AuthResult, AuthError>?
    var mockRefreshResult: Result<AuthResult, AuthError>?
    var signInCalled = false
    var refreshTokenCalled = false
    
    func request(_ endpoint: APIEndpoint) -> AnyPublisher<AuthResult, AuthError> {
        switch endpoint {
        case .login:
            signInCalled = true
            return mockAuthResult?.publisher.eraseToAnyPublisher() ??
                Fail(error: .unknown).eraseToAnyPublisher()
        default:
            refreshTokenCalled = true
            return mockRefreshResult?.publisher.eraseToAnyPublisher() ??
                Fail(error: .unknown).eraseToAnyPublisher()
        }
    }
}

private class MockKeychainManager {
    var mockTokenResult: Result<String?, KeychainError>?
    var mockClearResult: Result<Void, KeychainError>?
    var saveTokenCalled = false
    var clearAllCalled = false
    
    func saveToken(token: String, key: String, requiresBiometry: Bool) -> Result<Void, KeychainError> {
        saveTokenCalled = true
        return .success(())
    }
    
    func getToken(key: String) -> Result<String?, KeychainError> {
        return mockTokenResult ?? .success(nil)
    }
    
    func clearAll() -> Result<Void, KeychainError> {
        clearAllCalled = true
        return mockClearResult ?? .success(())
    }
}

private class MockBiometricManager {
    var mockAvailabilityResult: Result<BiometricAvailability, BiometricError>?
    var mockAuthResult: Result<BiometricAuthResult, BiometricError>?
    var authenticateCalled = false
    
    func canUseBiometrics() -> Result<BiometricAvailability, BiometricError> {
        return mockAvailabilityResult ?? .failure(.notAvailable)
    }
    
    func authenticateWithBiometrics(
        localizedReason: String,
        policy: BiometricPolicy
    ) -> Result<BiometricAuthResult, BiometricError> {
        authenticateCalled = true
        return mockAuthResult ?? .failure(.notAvailable)
    }
}