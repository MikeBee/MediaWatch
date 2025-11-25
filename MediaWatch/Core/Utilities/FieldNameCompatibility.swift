//
//  FieldNameCompatibility.swift
//  MediaWatch
//
//  Compatibility extensions to support the transition to LWW field names
//  This allows existing code to continue working while we transition to the new field names
//

import Foundation
import CoreData
import UIKit

// MARK: - MediaList Compatibility

extension MediaList {
    
    /// Compatibility property for old code
    var dateCreated: Date? {
        get { createdAt }
        set { 
            createdAt = newValue ?? Date()
            markAsModified()
        }
    }
    
    /// Compatibility property for old code
    var dateModified: Date? {
        get { updatedAt }
        set { 
            updatedAt = newValue ?? Date()
            markAsModified()
        }
    }
    
    /// Compatibility property for old code
    var sortOrder: Int16 {
        get { Int16(order) }
        set { 
            order = Double(newValue)
            markAsModified()
        }
    }
}

// MARK: - Title Compatibility

extension Title {
    
    /// Compatibility property for old code
    var dateAdded: Date? {
        get { createdAt }
        set { 
            createdAt = newValue ?? Date()
            updatedAt = Date()
            deviceID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        }
    }
    
    /// Compatibility property for old code
    var dateModified: Date? {
        get { updatedAt }
        set { 
            updatedAt = newValue ?? Date()
            deviceID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        }
    }
}

// MARK: - ListItem Compatibility

extension ListItem {
    
    /// Compatibility property for old code
    var dateAdded: Date? {
        get { createdAt }
        set { 
            createdAt = newValue ?? Date()
            updatedAt = Date()
            deviceID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        }
    }
    
    /// Compatibility property for old code
    var orderIndex: Int16 {
        get { Int16(order) }
        set { 
            order = Double(newValue)
            updatedAt = Date()
            deviceID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        }
    }
}

// MARK: - Note Compatibility

extension Note {
    
    /// Compatibility property for old code
    var dateCreated: Date? {
        get { createdAt }
        set { 
            createdAt = newValue ?? Date()
            updatedAt = Date()
            deviceID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        }
    }
    
    /// Compatibility property for old code
    var dateModified: Date? {
        get { updatedAt }
        set { 
            updatedAt = newValue ?? Date()
            deviceID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        }
    }
}