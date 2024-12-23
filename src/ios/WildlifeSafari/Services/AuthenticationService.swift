//
// AuthenticationService.swift
// WildlifeSafari
//
// Created by Wildlife Safari Team
// Copyright © 2023 Wildlife Safari. All rights reserved.
//

import Foundation // latest
import Combine // latest
import AuthenticationServices // latest
import LocalAuthentication // latest

// MARK: - Constants
private let AUTH_TOKEN_KEY = "auth_token"
private let REFRESH_TOKEN_KEY = "refresh_token"
private let TOKEN_EXPIRY_KEY = "token_expiry"
private let MAX_RETRY_ATTEMPTS = 3
private let TOKEN_REFRESH_THRESHOLD: TimeInterval = 300 // 5 minutes

// MARK: - AuthState
public enum AuthState {
    case initial
    case authenticating
    case authenticated
    case refreshing
    case error(AuthError)
}

// MARK: - AuthError
public enum AuthError: LocalizedError {
    case invalidCredentials
    case networkError(Error)
    case biometricError(BiometricError)
    case tokenExpired
    case refreshFailed
    case serverError
    case unauthorized
    case unknown
    
    public var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid email or password"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .biometricError(let error):
            return error.errorDescription
        case .tokenExpired:
            return "Authentication session expired"
        case .refreshFailed:
            return "Failed to refresh authentication"
        case .serverError:
            return "Server error occurred"
        case .unauthorized:
            return "Unauthorized access"
        case .unknown:
            return "An unknown error occurred"
        }
    }
}

// MARK: - AuthResult
public struct AuthResult {
    let accessToken: String
    let refreshToken: String
    let expiresIn: TimeInterval
    let tokenType: String
}

// MARK: - AuthenticationService
@available(iOS 13.0, *)
public final class AuthenticationService {
    
    // MARK: - Properties
    private let apiClient: APIClient
    private let keychainManager: KeychainManager
    private let biometricManager: BiometricAuthManager
    
    private var tokenRefreshTimer: Timer?
    private var retryCount: Int = 0
    
    private let isAuthenticated = CurrentValueSubject<Bool, Never>(false)
    private let authState = CurrentValueSubject<AuthState, Never>(.initial)
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    public init() {
        self.apiClient = APIClient()
        self.keychainManager = KeychainManager.shared
        self.biometricManager = BiometricAuthManager.shared
        
        // Configure secure networking
        configureSecurity()
        
        // Start monitoring authentication state
        setupAuthenticationMonitoring()
    }
    
    // MARK: - Public Methods
    
    /// Authenticates user with email and password
    /// - Parameters:
    ///   - email: User's email address
    ///   - password: User's password
    ///   - mfaToken: Optional MFA token if required
    /// - Returns: Publisher that emits authentication result or error
    public func signIn(
        email: String,
        password: String,
        mfaToken: String? = nil
    ) -> AnyPublisher<AuthResult, AuthError> {
        authState.send(.authenticating)
        
        let credentials = LoginCredentials(
            email: email,
            password: password,
            mfaToken: mfaToken
        )
        
        return apiClient.request(.login(credentials: credentials))
            .mapError { error -> AuthError in
                switch error {
                case .unauthorized:
                    return .invalidCredentials
                case .networkError(let error):
                    return .networkError(error)
                default:
                    return .serverError
                }
            }
            .flatMap { [weak self] authResult -> AnyPublisher<AuthResult, AuthError> in
                guard let self = self else {
                    return Fail(error: .unknown).eraseToAnyPublisher()
                }
                
                return self.handleAuthenticationSuccess(authResult)
            }
            .handleEvents(
                receiveOutput: { [weak self] _ in
                    self?.isAuthenticated.send(true)
                    self?.authState.send(.authenticated)
                },
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.authState.send(.error(error))
                    }
                }
            )
            .eraseToAnyPublisher()
    }
    
    /// Authenticates user using biometric authentication
    /// - Returns: Publisher that emits authentication result or error
    public func signInWithBiometrics() -> AnyPublisher<AuthResult, AuthError> {
        return Future { [weak self] promise in
            guard let self = self else {
                promise(.failure(.unknown))
                return
            }
            
            // Check biometric availability
            let availabilityResult = self.biometricManager.canUseBiometrics()
            
            switch availabilityResult {
            case .success(let availability):
                switch availability {
                case .available(let type):
                    self.performBiometricAuth(type: type) { result in
                        switch result {
                        case .success(let authResult):
                            promise(.success(authResult))
                        case .failure(let error):
                            promise(.failure(.biometricError(error)))
                        }
                    }
                case .unavailable:
                    promise(.failure(.biometricError(.notAvailable)))
                }
            case .failure(let error):
                promise(.failure(.biometricError(error)))
            }
        }
        .eraseToAnyPublisher()
    }
    
    /// Signs out the current user
    /// - Returns: Publisher that emits completion or error
    public func signOut() -> AnyPublisher<Void, AuthError> {
        return Future { [weak self] promise in
            guard let self = self else {
                promise(.failure(.unknown))
                return
            }
            
            // Clear tokens from keychain
            let clearResult = self.keychainManager.clearAll()
            
            switch clearResult {
            case .success:
                self.isAuthenticated.send(false)
                self.authState.send(.initial)
                self.stopTokenRefreshTimer()
                promise(.success(()))
            case .failure:
                promise(.failure(.unknown))
            }
        }
        .eraseToAnyPublisher()
    }
    
    // MARK: - Private Methods
    
    private func configureSecurity() {
        // Configure certificate pinning
        apiClient.configureCertificatePinning()
        
        // Configure biometric policy
        biometricManager.configureBiometricPolicy(.strict)
    }
    
    private func setupAuthenticationMonitoring() {
        // Monitor token expiration
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                self?.checkTokenExpiration()
            }
            .store(in: &cancellables)
    }
    
    private func handleAuthenticationSuccess(_ authResult: AuthResult) -> AnyPublisher<AuthResult, AuthError> {
        return Future { [weak self] promise in
            guard let self = self else {
                promise(.failure(.unknown))
                return
            }
            
            // Save tokens securely
            let saveAccessToken = self.keychainManager.saveToken(
                token: authResult.accessToken,
                key: AUTH_TOKEN_KEY,
                requiresBiometry: true
            )
            
            let saveRefreshToken = self.keychainManager.saveToken(
                token: authResult.refreshToken,
                key: REFRESH_TOKEN_KEY,
                requiresBiometry: true
            )
            
            // Save expiry time
            let expiryDate = Date().addingTimeInterval(authResult.expiresIn)
            UserDefaults.standard.set(expiryDate.timeIntervalSince1970, forKey: TOKEN_EXPIRY_KEY)
            
            switch (saveAccessToken, saveRefreshToken) {
            case (.success, .success):
                self.setupTokenRefreshTimer(timeInterval: authResult.expiresIn)
                promise(.success(authResult))
            case (.failure, _), (_, .failure):
                promise(.failure(.unknown))
            }
        }
        .eraseToAnyPublisher()
    }
    
    private func performBiometricAuth(
        type: BiometricType,
        completion: @escaping (Result<AuthResult, BiometricError>) -> Void
    ) {
        let reason = "Sign in to Wildlife Safari"
        
        biometricManager.authenticateWithBiometrics(
            localizedReason: reason,
            policy: .strict
        ) { [weak self] result in
            switch result {
            case .success(let biometricResult):
                // Retrieve stored credentials and refresh if needed
                self?.refreshStoredCredentials(completion: completion)
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    private func refreshStoredCredentials(
        completion: @escaping (Result<AuthResult, BiometricError>) -> Void
    ) {
        // Attempt to retrieve stored refresh token
        let refreshResult = keychainManager.getToken(key: REFRESH_TOKEN_KEY)
        
        switch refreshResult {
        case .success(let token):
            guard let refreshToken = token else {
                completion(.failure(.securityError("No stored credentials found")))
                return
            }
            
            // Refresh authentication using stored token
            refreshAuthentication(with: refreshToken) { result in
                switch result {
                case .success(let authResult):
                    completion(.success(authResult))
                case .failure:
                    completion(.failure(.securityError("Failed to refresh authentication")))
                }
            }
            
        case .failure:
            completion(.failure(.securityError("Failed to retrieve stored credentials")))
        }
    }
    
    private func refreshAuthentication(
        with refreshToken: String,
        completion: @escaping (Result<AuthResult, AuthError>) -> Void
    ) {
        authState.send(.refreshing)
        
        // Implement token refresh logic using APIClient
        // This is a placeholder - actual implementation would refresh the token
        completion(.failure(.refreshFailed))
    }
    
    private func setupTokenRefreshTimer(timeInterval: TimeInterval) {
        stopTokenRefreshTimer()
        
        // Schedule refresh before token expires
        let refreshInterval = timeInterval - TOKEN_REFRESH_THRESHOLD
        tokenRefreshTimer = Timer.scheduledTimer(
            withTimeInterval: refreshInterval,
            repeats: false
        ) { [weak self] _ in
            self?.refreshTokenIfNeeded()
        }
    }
    
    private func stopTokenRefreshTimer() {
        tokenRefreshTimer?.invalidate()
        tokenRefreshTimer = nil
    }
    
    private func refreshTokenIfNeeded() {
        guard let refreshToken = try? keychainManager.getToken(key: REFRESH_TOKEN_KEY).get() else {
            authState.send(.error(.refreshFailed))
            return
        }
        
        refreshAuthentication(with: refreshToken) { [weak self] result in
            switch result {
            case .success(let authResult):
                self?.handleAuthenticationSuccess(authResult)
                    .sink(
                        receiveCompletion: { _ in },
                        receiveValue: { _ in }
                    )
                    .store(in: &self!.cancellables)
            case .failure(let error):
                self?.authState.send(.error(error))
            }
        }
    }
    
    private func checkTokenExpiration() {
        let expiryTimestamp = UserDefaults.standard.double(forKey: TOKEN_EXPIRY_KEY)
        let expiryDate = Date(timeIntervalSince1970: expiryTimestamp)
        
        if Date() > expiryDate {
            refreshTokenIfNeeded()
        }
    }
}