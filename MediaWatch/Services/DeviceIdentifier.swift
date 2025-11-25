//
//  DeviceIdentifier.swift
//  MediaWatch
//
//  Robust, persistent per-device ID using Keychain with UserDefaults fallback
//

import Foundation
import Security

final class DeviceIdentifier {
    static let shared = DeviceIdentifier()
    
    private let keychainService = "reasonality.MediaShows.deviceId"
    private let keychainAccount = "device_identifier"
    private let userDefaultsKey = "device_identifier_fallback"
    
    private var _cachedDeviceID: String?
    
    private init() {}
    
    var deviceID: String {
        if let cached = _cachedDeviceID {
            return cached
        }
        
        let deviceId = loadOrGenerateDeviceID()
        _cachedDeviceID = deviceId
        return deviceId
    }
    
    private func loadOrGenerateDeviceID() -> String {
        // Try to load from Keychain first
        if let keychainID = loadFromKeychain() {
            return keychainID
        }
        
        // Fallback to UserDefaults
        if let userDefaultsID = UserDefaults.standard.string(forKey: userDefaultsKey) {
            // Migrate to Keychain for future use
            saveToKeychain(userDefaultsID)
            return userDefaultsID
        }
        
        // Generate new device ID
        let newDeviceID = UUID().uuidString
        
        // Save to both Keychain and UserDefaults
        saveToKeychain(newDeviceID)
        UserDefaults.standard.set(newDeviceID, forKey: userDefaultsKey)
        
        return newDeviceID
    }
    
    private func loadFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        guard status == errSecSuccess,
              let data = item as? Data,
              let deviceID = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return deviceID
    }
    
    private func saveToKeychain(_ deviceID: String) {
        guard let data = deviceID.data(using: .utf8) else { return }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]
        
        // Try to update existing item first
        let updateQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data
        ]
        
        let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)
        
        if updateStatus == errSecItemNotFound {
            // Item doesn't exist, create new one
            SecItemAdd(query as CFDictionary, nil)
        }
    }
    
    // MARK: - Debug Helpers
    
    #if DEBUG
    /// Reset device ID for testing (debug mode only)
    func resetDeviceID() {
        _cachedDeviceID = nil
        
        // Remove from Keychain
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount
        ]
        SecItemDelete(query as CFDictionary)
        
        // Remove from UserDefaults
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
        
        print("🔄 Device ID reset - new ID will be generated on next access")
    }
    
    /// Get current device ID without caching (for debugging)
    func getCurrentDeviceIDForDebugging() -> String {
        let tempCached = _cachedDeviceID
        _cachedDeviceID = nil
        let currentID = deviceID
        _cachedDeviceID = tempCached
        return currentID
    }
    #endif
}