//
// AuthViewModel.swift
// WildlifeSafari
//
// Created by Wildlife Safari Team
// Copyright © 2023 Wildlife Safari. All rights reserved.
//

import Foundation // latest
import Combine // latest
import SwiftUI // latest

/// Constants for authentication operations
private enum AuthConstants {
    static let AUTH_ERROR_DOMAIN = "com.wildlifesafari.auth"
    static let TOKEN_REFRESH_INTERVAL: TimeInterval = 3600 // 1 hour
    static let MAX_RETRY_ATTEMPTS = 3
}

/// Represents user roles in the application
public enum UserRole: String {
    case anonymous
    case basicUser
    case researcher
    case moderator
    case administrator
}

/// Authentication-specific errors
public enum AuthenticationError: LocalizedError {
    case invalidCredentials
    case biometricFailed(BiometricError)
    case networkError(Error)
    case sessionExpired
    case unauthorized
    case unknown
    
    public var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid email or password"
        case .biometricFailed(let error):
            return error.errorDescription
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .sessionExpired:
            return "Your session has expired. Please sign in again"
        case .unauthorized:
            return "Unauthorized access"
        case .unknown:
            return "An unknown error occurred"
        }
    }
}

/// ViewModel that manages authentication state and secure user authentication operations
@MainActor
@available(iOS 13.0, *)
public final class AuthViewModel: ObservableObject {
    
    // MARK: - Properties
    
    private let authService: AuthenticationService
    private let biometricManager: BiometricAuthManager
    
    @Published private(set) var isLoading = false
    @Published private(set) var isAuthenticated = false
    @Published private(set) var error: AuthenticationError?
    @Published private(set) var currentRole: UserRole = .anonymous
    
    private var cancellables = Set<AnyCancellable>()
    private var tokenRefreshTimer: Timer?
    
    // MARK: - Initialization
    
    public init() {
        self.authService = AuthenticationService()
        self.biometricManager = BiometricAuthManager.shared
        
        // Set up authentication state observation
        setupAuthenticationObserver()
        
        // Validate device security state
        validateDeviceSecurity()
    }
    
    // MARK: - Public Methods
    
    /// Authenticates user with email and password
    /// - Parameters:
    ///   - email: User's email address
    ///   - password: User's password
    ///   - mfaCode: Optional MFA code if required
    /// - Returns: Task representing the authentication operation
    public func signIn(
        email: String,
        password: String,
        mfaCode: String? = nil
    ) -> Task<Void, Never> {
        Task {
            do {
                // Validate device security
                try await validateDeviceSecurity()
                
                self.isLoading = true
                self.error = nil
                
                // Attempt authentication
                let result = try await authService.signIn(
                    email: email,
                    password: password,
                    mfaToken: mfaCode
                ).async()
                
                // Handle successful authentication
                await handleAuthenticationSuccess(result)
                
            } catch let error as AuthError {
                await handleAuthenticationError(error)
            } catch {
                self.error = .unknown
            }
            
            self.isLoading = false
        }
    }
    
    /// Authenticates user using biometric authentication
    /// - Returns: Task representing the biometric authentication operation
    public func signInWithBiometrics() -> Task<Void, Never> {
        Task {
            do {
                // Check device security and biometric availability
                try await validateDeviceSecurity()
                
                guard case .success(.available) = biometricManager.canUseBiometrics() else {
                    throw BiometricError.notAvailable
                }
                
                self.isLoading = true
                self.error = nil
                
                // Attempt biometric authentication
                let result = try await authService.signInWithBiometrics().async()
                
                // Handle successful authentication
                await handleAuthenticationSuccess(result)
                
            } catch let error as BiometricError {
                self.error = .biometricFailed(error)
            } catch let error as AuthError {
                await handleAuthenticationError(error)
            } catch {
                self.error = .unknown
            }
            
            self.isLoading = false
        }
    }
    
    /// Signs out the current user
    /// - Returns: Task representing the sign out operation
    public func signOut() -> Task<Void, Never> {
        Task {
            self.isLoading = true
            
            do {
                try await authService.signOut().async()
                
                await MainActor.run {
                    self.isAuthenticated = false
                    self.currentRole = .anonymous
                    self.stopTokenRefreshTimer()
                }
            } catch {
                self.error = .unknown
            }
            
            self.isLoading = false
        }
    }
    
    // MARK: - Private Methods
    
    private func setupAuthenticationObserver() {
        // Observe authentication state changes
        authService.isAuthenticated
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isAuthenticated in
                self?.isAuthenticated = isAuthenticated
                if !isAuthenticated {
                    self?.currentRole = .anonymous
                    self?.stopTokenRefreshTimer()
                }
            }
            .store(in: &cancellables)
    }
    
    private func validateDeviceSecurity() async throws {
        let result = biometricManager.validateDeviceSecurity()
        switch result {
        case .success:
            return
        case .failure(let error):
            throw error
        }
    }
    
    private func handleAuthenticationSuccess(_ result: AuthResult) async {
        await MainActor.run {
            self.isAuthenticated = true
            self.currentRole = determineUserRole(from: result)
            self.startTokenRefreshTimer()
            self.error = nil
        }
    }
    
    private func handleAuthenticationError(_ error: AuthError) async {
        await MainActor.run {
            switch error {
            case .unauthorized:
                self.error = .unauthorized
            case .networkError(let underlyingError):
                self.error = .networkError(underlyingError)
            case .tokenExpired:
                self.error = .sessionExpired
            default:
                self.error = .unknown
            }
            self.isAuthenticated = false
            self.currentRole = .anonymous
        }
    }
    
    private func determineUserRole(from authResult: AuthResult) -> UserRole {
        // Determine user role based on authentication result
        // This is a placeholder - actual implementation would parse role from auth result
        return .basicUser
    }
    
    private func startTokenRefreshTimer() {
        stopTokenRefreshTimer()
        
        tokenRefreshTimer = Timer.scheduledTimer(
            withTimeInterval: AuthConstants.TOKEN_REFRESH_INTERVAL,
            repeats: true
        ) { [weak self] _ in
            self?.refreshTokens()
        }
    }
    
    private func stopTokenRefreshTimer() {
        tokenRefreshTimer?.invalidate()
        tokenRefreshTimer = nil
    }
    
    private func refreshTokens() {
        Task {
            do {
                try await authService.refreshToken().async()
            } catch {
                self.error = .sessionExpired
                await signOut().value
            }
        }
    }
}

// MARK: - Combine Extensions

extension Publisher {
    func async() async throws -> Output {
        try await withCheckedThrowingContinuation { continuation in
            var cancellable: AnyCancellable?
            
            cancellable = self.sink(
                receiveCompletion: { completion in
                    switch completion {
                    case .finished:
                        break
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                    cancellable?.cancel()
                },
                receiveValue: { value in
                    continuation.resume(returning: value)
                }
            )
        }
    }
}