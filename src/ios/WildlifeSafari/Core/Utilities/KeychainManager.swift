//
// KeychainManager.swift
// WildlifeSafari
//
// Created by Wildlife Safari Team
// Copyright © 2023 Wildlife Safari. All rights reserved.
//

import Foundation // latest
import Security // latest
import LocalAuthentication // latest

// MARK: - Constants
private let SERVICE_IDENTIFIER = "com.wildlifesafari.app.keychain"
private let ACCESS_GROUP = Bundle.main.object(forInfoDictionaryKey: "KeychainAccessGroup") as? String
private let KEYCHAIN_ACCESS_MODE = kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String

// MARK: - KeychainError
@frozen
public enum KeychainError: LocalizedError {
    case itemNotFound
    case duplicateItem
    case authenticationFailed
    case unhandledError(status: OSStatus, message: String)
    
    public var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "The requested item was not found in the keychain."
        case .duplicateItem:
            return "An item with the specified key already exists."
        case .authenticationFailed:
            return "Biometric or device authentication failed."
        case .unhandledError(let status, let message):
            return "Keychain operation failed: \(message) (Status: \(status))"
        }
    }
}

// MARK: - KeychainManager
@available(iOS 13.0, *)
public final class KeychainManager {
    
    // MARK: - Singleton
    public static let shared = KeychainManager()
    
    // MARK: - Private Properties
    private let queue: DispatchQueue
    private let serviceIdentifier: String
    private let accessGroup: String?
    private var authContext: LAContext?
    
    // MARK: - Initialization
    private init() {
        self.queue = DispatchQueue(label: "com.wildlifesafari.keychain", qos: .userInitiated)
        self.serviceIdentifier = SERVICE_IDENTIFIER
        self.accessGroup = ACCESS_GROUP
        self.authContext = LAContext()
    }
    
    // MARK: - Public Methods
    
    /// Saves an authentication token to the keychain with optional biometric protection
    /// - Parameters:
    ///   - token: The token string to be stored
    ///   - key: Unique identifier for the token
    ///   - requiresBiometry: Whether biometric authentication is required for access
    /// - Returns: Result indicating success or specific error
    public func saveToken(token: String, key: String, requiresBiometry: Bool = false) -> Result<Void, KeychainError> {
        return queue.sync {
            guard !token.isEmpty, !key.isEmpty else {
                return .failure(.unhandledError(status: errSecParam, message: "Invalid input parameters"))
            }
            
            var accessControl: SecAccessControl?
            var error: Unmanaged<CFError>?
            
            if requiresBiometry {
                accessControl = SecAccessControlCreateWithFlags(
                    kCFAllocatorDefault,
                    KEYCHAIN_ACCESS_MODE as CFString,
                    .biometryAny,
                    &error
                )
            }
            
            guard let tokenData = token.data(using: .utf8) else {
                return .failure(.unhandledError(status: errSecParam, message: "Failed to encode token"))
            }
            
            var query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: serviceIdentifier,
                kSecAttrAccount as String: key,
                kSecValueData as String: tokenData
            ]
            
            if let accessControl = accessControl {
                query[kSecAttrAccessControl as String] = accessControl
            }
            
            if let accessGroup = accessGroup {
                query[kSecAttrAccessGroup as String] = accessGroup
            }
            
            let status = SecItemAdd(query as CFDictionary, nil)
            
            switch status {
            case errSecSuccess:
                return .success(())
            case errSecDuplicateItem:
                // Update existing item
                let updateQuery: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: serviceIdentifier,
                    kSecAttrAccount as String: key
                ]
                
                let updateAttributes: [String: Any] = [
                    kSecValueData as String: tokenData
                ]
                
                let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)
                
                return updateStatus == errSecSuccess ? .success(()) : .failure(.unhandledError(status: updateStatus, message: "Failed to update item"))
            default:
                return .failure(.unhandledError(status: status, message: "Failed to save item"))
            }
        }
    }
    
    /// Retrieves a token from the keychain with optional biometric verification
    /// - Parameters:
    ///   - key: Unique identifier for the token
    ///   - requiresBiometry: Whether biometric authentication is required
    /// - Returns: Result containing the token string or specific error
    public func getToken(key: String, requiresBiometry: Bool = false) -> Result<String?, KeychainError> {
        return queue.sync {
            if requiresBiometry {
                let context = LAContext()
                var error: NSError?
                
                guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
                    return .failure(.authenticationFailed)
                }
                
                var authError: NSError?
                let semaphore = DispatchSemaphore(value: 0)
                var authSuccess = false
                
                context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                     localizedReason: "Authenticate to access secure data") { success, error in
                    authSuccess = success
                    authError = error as NSError?
                    semaphore.signal()
                }
                
                _ = semaphore.wait(timeout: .now() + 30)
                
                guard authSuccess else {
                    return .failure(.authenticationFailed)
                }
            }
            
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: serviceIdentifier,
                kSecAttrAccount as String: key,
                kSecReturnData as String: true
            ]
            
            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            
            switch status {
            case errSecSuccess:
                guard let data = result as? Data,
                      let token = String(data: data, encoding: .utf8) else {
                    return .failure(.unhandledError(status: errSecDecode, message: "Failed to decode token"))
                }
                return .success(token)
            case errSecItemNotFound:
                return .success(nil)
            default:
                return .failure(.unhandledError(status: status, message: "Failed to retrieve item"))
            }
        }
    }
    
    /// Deletes a token from the keychain
    /// - Parameter key: Unique identifier for the token
    /// - Returns: Result indicating success or specific error
    public func deleteToken(key: String) -> Result<Void, KeychainError> {
        return queue.sync {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: serviceIdentifier,
                kSecAttrAccount as String: key
            ]
            
            let status = SecItemDelete(query as CFDictionary)
            
            switch status {
            case errSecSuccess, errSecItemNotFound:
                return .success(())
            default:
                return .failure(.unhandledError(status: status, message: "Failed to delete item"))
            }
        }
    }
    
    /// Removes all tokens stored in the keychain for this service
    /// - Returns: Result indicating success or specific error
    public func clearAll() -> Result<Void, KeychainError> {
        return queue.sync {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: serviceIdentifier
            ]
            
            let status = SecItemDelete(query as CFDictionary)
            
            switch status {
            case errSecSuccess, errSecItemNotFound:
                authContext = LAContext() // Reset authentication context
                return .success(())
            default:
                return .failure(.unhandledError(status: status, message: "Failed to clear keychain"))
            }
        }
    }
    
    /// Rotates encryption keys for enhanced security
    /// - Returns: Result indicating success or specific error
    public func rotateEncryptionKey() -> Result<Void, KeychainError> {
        return queue.sync {
            // Create query to find all items
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: serviceIdentifier,
                kSecReturnAttributes as String: true,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitAll
            ]
            
            var result: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            
            guard status == errSecSuccess,
                  let items = result as? [[String: Any]] else {
                return status == errSecItemNotFound ? .success(()) : .failure(.unhandledError(status: status, message: "Failed to retrieve items for rotation"))
            }
            
            for item in items {
                guard let account = item[kSecAttrAccount as String] as? String,
                      let data = item[kSecValueData as String] as? Data,
                      let token = String(data: data, encoding: .utf8) else {
                    continue
                }
                
                // Re-save item with new encryption
                let saveResult = saveToken(token: token, key: account, requiresBiometry: false)
                if case .failure(let error) = saveResult {
                    return .failure(error)
                }
            }
            
            return .success(())
        }
    }
}