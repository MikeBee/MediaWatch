//
//  TimestampMigrationHelper.swift
//  MediaWatch
//
//  Helper to fix existing data with 2001-01-01 placeholder timestamps
//  Should be run once to clean up existing data
//

import Foundation
import CoreData

@MainActor
final class TimestampMigrationHelper {
    
    static let shared = TimestampMigrationHelper()
    
    private let context = PersistenceController.shared.viewContext
    private let placeholderDate = Date(timeIntervalSinceReferenceDate: 0) // 2001-01-01
    
    private init() {}
    
    /// Fix all existing entities with placeholder timestamps
    func fixPlaceholderTimestamps() async throws {
        print("🔧 Starting timestamp migration...")
        
        var totalFixed = 0
        let now = Date()
        let deviceID = DeviceIdentifier.shared.deviceID
        
        // Process in smaller batches to avoid Core Data issues
        try await fixListTimestamps(now: now, deviceID: deviceID, totalFixed: &totalFixed)
        try await fixTitleTimestamps(now: now, deviceID: deviceID, totalFixed: &totalFixed)
        try await fixListItemTimestamps(now: now, deviceID: deviceID, totalFixed: &totalFixed)
        try await fixEpisodeTimestamps(now: now, deviceID: deviceID, totalFixed: &totalFixed)
        try await fixNoteTimestamps(now: now, deviceID: deviceID, totalFixed: &totalFixed)
        
        if totalFixed > 0 {
            print("✅ Fixed \(totalFixed) entities with placeholder timestamps")
            // Mark migration as completed
            UserDefaults.standard.set(true, forKey: "timestamp_migration_completed")
        } else {
            print("ℹ️ No entities needed timestamp fixes")
        }
    }
    
    private func fixListTimestamps(now: Date, deviceID: String, totalFixed: inout Int) async throws {
        let listFetch = MediaList.fetchAll()
        listFetch.fetchBatchSize = 20
        let lists = try context.fetch(listFetch)
        
        for list in lists {
            var needsUpdate = false
            
            if list.createdAt == placeholderDate || list.createdAt == nil {
                list.setPrimitiveValue(now, forKey: "createdAt")
                needsUpdate = true
            }
            
            if list.updatedAt == placeholderDate || list.updatedAt == nil {
                list.setPrimitiveValue(now, forKey: "updatedAt")
                needsUpdate = true
            }
            
            if list.deviceID?.isEmpty != false {
                list.setPrimitiveValue(deviceID, forKey: "deviceID")
                needsUpdate = true
            }
            
            if needsUpdate {
                totalFixed += 1
            }
        }
        
        if totalFixed > 0 {
            try context.save()
        }
    }
    
    private func fixTitleTimestamps(now: Date, deviceID: String, totalFixed: inout Int) async throws {
        let titleFetch = NSFetchRequest<Title>(entityName: "Title")
        titleFetch.fetchBatchSize = 20
        let titles = try context.fetch(titleFetch)
        let startCount = totalFixed
        
        for title in titles {
            var needsUpdate = false
            
            if title.createdAt == placeholderDate || title.createdAt == nil {
                title.setPrimitiveValue(now, forKey: "createdAt")
                needsUpdate = true
            }
            
            if title.updatedAt == placeholderDate || title.updatedAt == nil {
                title.setPrimitiveValue(now, forKey: "updatedAt")
                needsUpdate = true
            }
            
            if title.deviceID?.isEmpty != false {
                title.setPrimitiveValue(deviceID, forKey: "deviceID")
                needsUpdate = true
            }
            
            if needsUpdate {
                totalFixed += 1
            }
        }
        
        if totalFixed > startCount {
            try context.save()
        }
    }
    
    private func fixListItemTimestamps(now: Date, deviceID: String, totalFixed: inout Int) async throws {
        let listItemFetch = NSFetchRequest<ListItem>(entityName: "ListItem")
        listItemFetch.fetchBatchSize = 20
        let listItems = try context.fetch(listItemFetch)
        let startCount = totalFixed
        
        for listItem in listItems {
            var needsUpdate = false
            
            if listItem.createdAt == placeholderDate || listItem.createdAt == nil {
                listItem.setPrimitiveValue(now, forKey: "createdAt")
                needsUpdate = true
            }
            
            if listItem.updatedAt == placeholderDate || listItem.updatedAt == nil {
                listItem.setPrimitiveValue(now, forKey: "updatedAt")
                needsUpdate = true
            }
            
            if listItem.deviceID?.isEmpty != false {
                listItem.setPrimitiveValue(deviceID, forKey: "deviceID")
                needsUpdate = true
            }
            
            if needsUpdate {
                totalFixed += 1
            }
        }
        
        if totalFixed > startCount {
            try context.save()
        }
    }
    
    private func fixEpisodeTimestamps(now: Date, deviceID: String, totalFixed: inout Int) async throws {
        let episodeFetch = NSFetchRequest<Episode>(entityName: "Episode")
        episodeFetch.fetchBatchSize = 20
        let episodes = try context.fetch(episodeFetch)
        let startCount = totalFixed
        
        for episode in episodes {
            var needsUpdate = false
            
            if episode.createdAt == placeholderDate || episode.createdAt == nil {
                episode.setPrimitiveValue(now, forKey: "createdAt")
                needsUpdate = true
            }
            
            if episode.updatedAt == placeholderDate || episode.updatedAt == nil {
                episode.setPrimitiveValue(now, forKey: "updatedAt")
                needsUpdate = true
            }
            
            if episode.deviceID?.isEmpty != false {
                episode.setPrimitiveValue(deviceID, forKey: "deviceID")
                needsUpdate = true
            }
            
            if needsUpdate {
                totalFixed += 1
            }
        }
        
        if totalFixed > startCount {
            try context.save()
        }
    }
    
    private func fixNoteTimestamps(now: Date, deviceID: String, totalFixed: inout Int) async throws {
        let noteFetch = NSFetchRequest<Note>(entityName: "Note")
        noteFetch.fetchBatchSize = 20
        let notes = try context.fetch(noteFetch)
        let startCount = totalFixed
        
        for note in notes {
            var needsUpdate = false
            
            if note.createdAt == placeholderDate || note.createdAt == nil {
                note.setPrimitiveValue(now, forKey: "createdAt")
                needsUpdate = true
            }
            
            if note.updatedAt == placeholderDate || note.updatedAt == nil {
                note.setPrimitiveValue(now, forKey: "updatedAt")
                needsUpdate = true
            }
            
            if note.deviceID?.isEmpty != false {
                note.setPrimitiveValue(deviceID, forKey: "deviceID")
                needsUpdate = true
            }
            
            if needsUpdate {
                totalFixed += 1
            }
        }
        
        if totalFixed > startCount {
            try context.save()
        }
    }
    
    /// Check if timestamp migration has been completed
    var isTimestampMigrationCompleted: Bool {
        return UserDefaults.standard.bool(forKey: "timestamp_migration_completed")
    }
    
    /// Reset migration flag for testing
    func resetMigrationFlag() {
        UserDefaults.standard.removeObject(forKey: "timestamp_migration_completed")
    }
}

// MARK: - App Integration

extension PersistenceController {
    /// Run timestamp migration if needed during app startup
    func runTimestampMigrationIfNeeded() async {
        let migrationHelper = await TimestampMigrationHelper.shared
        
        let isCompleted = await migrationHelper.isTimestampMigrationCompleted
        if !isCompleted {
            do {
                try await migrationHelper.fixPlaceholderTimestamps()
            } catch {
                print("❌ Timestamp migration failed: \(error)")
            }
        }
    }
}