//
// BiometricAuthManager.swift
// WildlifeSafari
//
// Created by Wildlife Safari Team
// Copyright © 2023 Wildlife Safari. All rights reserved.
//

import Foundation // latest
import LocalAuthentication // latest

// MARK: - Constants
private let BIOMETRIC_STATE_KEY = "com.wildlifesafari.biometric_auth_enabled"
private let BIOMETRIC_POLICY_KEY = "com.wildlifesafari.biometric_policy"

// MARK: - BiometricAvailability
public enum BiometricAvailability {
    case available(BiometricType)
    case unavailable(String)
}

// MARK: - BiometricType
public enum BiometricType {
    case faceID
    case touchID
    case none
}

// MARK: - BiometricPolicy
public enum BiometricPolicy {
    case strict      // Requires successful biometric auth every time
    case relaxed     // Allows grace period between authentications
    case fallback    // Allows passcode fallback
}

// MARK: - BiometricError
@frozen
public enum BiometricError: LocalizedError {
    case notAvailable
    case notEnrolled
    case lockout
    case canceled
    case systemError(String)
    case securityError(String)
    case invalidState
    
    public var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Biometric authentication is not available on this device."
        case .notEnrolled:
            return "No biometric data is enrolled on this device."
        case .lockout:
            return "Biometric authentication is locked due to too many failed attempts."
        case .canceled:
            return "Biometric authentication was canceled by the user."
        case .systemError(let message):
            return "System error: \(message)"
        case .securityError(let message):
            return "Security error: \(message)"
        case .invalidState:
            return "Biometric authentication is in an invalid state."
        }
    }
}

// MARK: - BiometricAuthResult
public struct BiometricAuthResult {
    public let success: Bool
    public let type: BiometricType
    public let timestamp: Date
}

// MARK: - BiometricAuthManager
@available(iOS 13.0, *)
public final class BiometricAuthManager {
    
    // MARK: - Singleton
    public static let shared = BiometricAuthManager()
    
    // MARK: - Private Properties
    private let context: LAContext
    private let keychainManager: KeychainManager
    private let biometricQueue: DispatchQueue
    private let contextLock: NSLock
    
    // MARK: - Initialization
    private init() {
        self.context = LAContext()
        self.keychainManager = KeychainManager.shared
        self.biometricQueue = DispatchQueue(label: "com.wildlifesafari.biometric", qos: .userInitiated)
        self.contextLock = NSLock()
        
        // Configure initial context
        context.localizedCancelTitle = "Cancel"
        context.localizedFallbackTitle = "Use Passcode"
    }
    
    // MARK: - Public Methods
    
    /// Checks if biometric authentication is available and configured on the device
    /// - Returns: Result indicating biometric availability status or error
    public func canUseBiometrics() -> Result<BiometricAvailability, BiometricError> {
        return biometricQueue.sync {
            contextLock.lock()
            defer { contextLock.unlock() }
            
            var error: NSError?
            
            // Check if device supports biometric authentication
            guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
                if let error = error {
                    switch error.code {
                    case LAError.biometryNotAvailable.rawValue:
                        return .success(.unavailable("Biometric authentication not available"))
                    case LAError.biometryNotEnrolled.rawValue:
                        return .success(.unavailable("No biometric data enrolled"))
                    case LAError.biometryLockout.rawValue:
                        return .failure(.lockout)
                    default:
                        return .failure(.systemError(error.localizedDescription))
                    }
                }
                return .failure(.systemError("Unknown error checking biometric availability"))
            }
            
            // Determine biometric type
            let biometricType: BiometricType
            switch context.biometryType {
            case .faceID:
                biometricType = .faceID
            case .touchID:
                biometricType = .touchID
            default:
                biometricType = .none
            }
            
            return .success(.available(biometricType))
        }
    }
    
    /// Enables biometric authentication for the app
    /// - Returns: Result indicating success or error
    public func enableBiometrics() -> Result<Void, BiometricError> {
        return biometricQueue.sync {
            // Check biometric availability first
            let availabilityResult = canUseBiometrics()
            
            switch availabilityResult {
            case .success(let availability):
                switch availability {
                case .available:
                    // Store biometric enabled state securely
                    let saveResult = keychainManager.saveToken(
                        token: "enabled",
                        key: BIOMETRIC_STATE_KEY,
                        requiresBiometry: true
                    )
                    
                    switch saveResult {
                    case .success:
                        return .success(())
                    case .failure:
                        return .failure(.securityError("Failed to save biometric state"))
                    }
                    
                case .unavailable(let reason):
                    return .failure(.notAvailable)
                }
                
            case .failure(let error):
                return .failure(error)
            }
        }
    }
    
    /// Performs biometric authentication
    /// - Parameters:
    ///   - localizedReason: Reason string displayed to user
    ///   - policy: Authentication policy to apply
    /// - Returns: Result containing authentication result or error
    public func authenticateWithBiometrics(
        localizedReason: String,
        policy: BiometricPolicy
    ) -> Result<BiometricAuthResult, BiometricError> {
        return biometricQueue.sync {
            contextLock.lock()
            defer { contextLock.unlock() }
            
            // Configure context based on policy
            switch policy {
            case .strict:
                context.localizedFallbackTitle = nil
                context.interactionNotAllowed = true
            case .relaxed:
                context.localizedFallbackTitle = "Use Passcode"
                context.interactionNotAllowed = false
            case .fallback:
                context.localizedFallbackTitle = "Use Passcode"
                context.interactionNotAllowed = false
            }
            
            var error: NSError?
            let semaphore = DispatchSemaphore(value: 0)
            var authenticationResult: Result<BiometricAuthResult, BiometricError>?
            
            context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: localizedReason
            ) { success, evaluateError in
                if success {
                    let result = BiometricAuthResult(
                        success: true,
                        type: self.context.biometryType == .faceID ? .faceID : .touchID,
                        timestamp: Date()
                    )
                    authenticationResult = .success(result)
                } else if let error = evaluateError as? LAError {
                    switch error.code {
                    case .userCancel:
                        authenticationResult = .failure(.canceled)
                    case .biometryLockout:
                        authenticationResult = .failure(.lockout)
                    case .systemCancel:
                        authenticationResult = .failure(.systemError("System canceled authentication"))
                    default:
                        authenticationResult = .failure(.systemError(error.localizedDescription))
                    }
                } else {
                    authenticationResult = .failure(.systemError("Unknown error during authentication"))
                }
                semaphore.signal()
            }
            
            _ = semaphore.wait(timeout: .now() + 30)
            
            return authenticationResult ?? .failure(.systemError("Authentication timed out"))
        }
    }
}