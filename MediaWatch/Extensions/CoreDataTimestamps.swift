//
//  CoreDataTimestamps.swift
//  MediaWatch
//
//  Extensions to ensure all Core Data entities have proper timestamps
//  Fixes the 2001-01-01 default timestamp issue for LWW sync
//

import CoreData
import Foundation

// MARK: - MediaList Timestamp Extension

extension MediaList {
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        let now = Date()
        setPrimitiveValue(now, forKey: "createdAt")
        setPrimitiveValue(now, forKey: "updatedAt")
        setPrimitiveValue(DeviceIdentifier.shared.deviceID, forKey: "deviceID")
    }
}

// MARK: - Title Timestamp Extension

extension Title {
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        let now = Date()
        setPrimitiveValue(now, forKey: "createdAt")
        setPrimitiveValue(now, forKey: "updatedAt")
        setPrimitiveValue(DeviceIdentifier.shared.deviceID, forKey: "deviceID")
    }
}

// MARK: - ListItem Timestamp Extension

extension ListItem {
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        let now = Date()
        setPrimitiveValue(now, forKey: "createdAt")
        setPrimitiveValue(now, forKey: "updatedAt")
        setPrimitiveValue(DeviceIdentifier.shared.deviceID, forKey: "deviceID")
    }
}

// MARK: - Episode Timestamp Extension

extension Episode {
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        let now = Date()
        setPrimitiveValue(now, forKey: "createdAt")
        setPrimitiveValue(now, forKey: "updatedAt")
        setPrimitiveValue(DeviceIdentifier.shared.deviceID, forKey: "deviceID")
    }
}

// MARK: - Note Timestamp Extension

extension Note {
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        let now = Date()
        setPrimitiveValue(now, forKey: "createdAt")
        setPrimitiveValue(now, forKey: "updatedAt")
        setPrimitiveValue(DeviceIdentifier.shared.deviceID, forKey: "deviceID")
    }
}