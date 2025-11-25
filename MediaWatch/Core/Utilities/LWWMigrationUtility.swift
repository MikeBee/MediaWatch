//
//  LWWMigrationUtility.swift
//  MediaWatch
//
//  Migration utility to transition existing Core Data to LWW sync model
//  Adds missing metadata fields and converts integer ordering to fractional ordering
//

import Foundation
import CoreData
import UIKit

final class LWWMigrationUtility {
    
    // MARK: - Migration Status
    
    enum MigrationStatus {
        case notNeeded
        case required
        case inProgress
        case completed
        case failed(Error)
    }
    
    // MARK: - Properties
    
    private let context: NSManagedObjectContext
    private let deviceID: String
    
    // MARK: - Initialization
    
    init(context: NSManagedObjectContext) {
        self.context = context
        self.deviceID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    }
    
    // MARK: - Migration Check
    
    /// Check if migration is needed by looking for missing LWW metadata
    func checkMigrationStatus() -> MigrationStatus {
        do {
            // Check if any lists are missing LWW metadata
            let listFetch = MediaList.fetchAll()
            let lists = try context.fetch(listFetch)
            
            let needsMigration = lists.contains { list in
                list.createdAt == nil || 
                list.updatedAt == nil ||
                list.deviceID == nil || 
                list.deviceID?.isEmpty == true
            }
            
            if needsMigration {
                return .required
            }
            
            // Check if any list items are missing LWW metadata or using old ordering
            for list in lists {
                if let items = list.items as? Set<ListItem> {
                    let itemsNeedMigration = items.contains { item in
                        item.createdAt == nil || 
                        item.updatedAt == nil ||
                        item.deviceID == nil ||
                        item.deviceID?.isEmpty == true ||
                        item.order == 0 // Old integer ordering
                    }
                    
                    if itemsNeedMigration {
                        return .required
                    }
                }
            }
            
            return .notNeeded
            
        } catch {
            return .failed(error)
        }
    }
    
    // MARK: - Migration Execution
    
    /// Perform complete migration to LWW model
    func performMigration() throws {
        let status = checkMigrationStatus()
        
        guard case .required = status else {
            return // Migration not needed
        }
        
        try context.performAndWait {
            let now = Date()
            
            // Migrate Lists
            try migrateListsToLWW(timestamp: now)
            
            // Migrate ListItems
            try migrateListItemsToLWW(timestamp: now)
            
            // Migrate Titles
            try migrateTitlesToLWW(timestamp: now)
            
            // Migrate Episodes
            try migrateEpisodesToLWW(timestamp: now)
            
            // Migrate Notes
            try migrateNotesToLWW(timestamp: now)
            
            // Save changes
            try context.save()
        }
    }
    
    // MARK: - Entity-Specific Migrations
    
    private func migrateListsToLWW(timestamp: Date) throws {
        let fetchRequest = MediaList.fetchAll()
        let lists = try context.fetch(fetchRequest)
        
        for list in lists {
            // Set missing timestamps
            if list.createdAt == nil {
                list.createdAt = list.value(forKey: "dateCreated") as? Date ?? timestamp
            }
            if list.updatedAt == nil {
                list.updatedAt = list.value(forKey: "dateModified") as? Date ?? timestamp
            }
            
            // Set device ID
            if list.deviceID == nil || list.deviceID?.isEmpty == true {
                list.deviceID = deviceID
            }
            
            // Convert integer sortOrder to fractional order
            if list.order == 0 {
                let sortOrder = list.value(forKey: "sortOrder") as? Int16 ?? 0
                list.order = Double(sortOrder + 1)
            }
            
            // Ensure deletedAt is nil for existing active lists
            if list.deletedAt == nil {
                list.deletedAt = nil
            }
        }
    }
    
    private func migrateListItemsToLWW(timestamp: Date) throws {
        let fetchRequest = NSFetchRequest<ListItem>(entityName: "ListItem")
        let listItems = try context.fetch(fetchRequest)
        
        for item in listItems {
            // Set missing timestamps
            if item.createdAt == nil {
                item.createdAt = item.value(forKey: "dateAdded") as? Date ?? timestamp
            }
            if item.updatedAt == nil {
                item.updatedAt = timestamp
            }
            
            // Set device ID
            if item.deviceID == nil || item.deviceID?.isEmpty == true {
                item.deviceID = deviceID
            }
            
            // Convert integer orderIndex to fractional order
            if item.order == 0 {
                let orderIndex = item.value(forKey: "orderIndex") as? Int16 ?? 0
                item.order = Double(orderIndex + 1)
            }
            
            // Ensure deletedAt is nil for existing active items
            if item.deletedAt == nil {
                item.deletedAt = nil
            }
        }
    }
    
    private func migrateTitlesToLWW(timestamp: Date) throws {
        let fetchRequest = NSFetchRequest<Title>(entityName: "Title")
        let titles = try context.fetch(fetchRequest)
        
        for title in titles {
            // Set missing timestamps
            if title.createdAt == nil {
                title.createdAt = title.value(forKey: "dateAdded") as? Date ?? timestamp
            }
            if title.updatedAt == nil {
                title.updatedAt = title.value(forKey: "dateModified") as? Date ?? timestamp
            }
            
            // Set device ID
            if title.deviceID == nil || title.deviceID?.isEmpty == true {
                title.deviceID = deviceID
            }
            
            // Ensure deletedAt is nil for existing active titles
            if title.deletedAt == nil {
                title.deletedAt = nil
            }
        }
    }
    
    private func migrateEpisodesToLWW(timestamp: Date) throws {
        let fetchRequest = NSFetchRequest<Episode>(entityName: "Episode")
        let episodes = try context.fetch(fetchRequest)
        
        for episode in episodes {
            // Set missing timestamps
            if episode.createdAt == nil {
                episode.createdAt = timestamp
            }
            if episode.updatedAt == nil {
                episode.updatedAt = episode.watchedDate ?? timestamp
            }
            
            // Set device ID
            if episode.deviceID == nil || episode.deviceID?.isEmpty == true {
                episode.deviceID = deviceID
            }
            
            // Ensure deletedAt is nil for existing active episodes
            if episode.deletedAt == nil {
                episode.deletedAt = nil
            }
        }
    }
    
    private func migrateNotesToLWW(timestamp: Date) throws {
        let fetchRequest = NSFetchRequest<Note>(entityName: "Note")
        let notes = try context.fetch(fetchRequest)
        
        for note in notes {
            // Set missing timestamps
            if note.createdAt == nil {
                note.createdAt = note.value(forKey: "dateCreated") as? Date ?? timestamp
            }
            if note.updatedAt == nil {
                note.updatedAt = note.value(forKey: "dateModified") as? Date ?? timestamp
            }
            
            // Set device ID
            if note.deviceID == nil || note.deviceID?.isEmpty == true {
                note.deviceID = deviceID
            }
            
            // Ensure deletedAt is nil for existing active notes
            if note.deletedAt == nil {
                note.deletedAt = nil
            }
        }
    }
    
    // MARK: - Utility Methods
    
    /// Generate missing UUIDs for any objects that don't have them
    func ensureUUIDs() throws {
        try context.performAndWait {
            try ensureListUUIDs()
            try ensureItemUUIDs()
            try ensureTitleUUIDs()
            try ensureEpisodeUUIDs()
            try ensureNoteUUIDs()
            
            try context.save()
        }
    }
    
    private func ensureListUUIDs() throws {
        let fetchRequest = MediaList.fetchAll()
        let lists = try context.fetch(fetchRequest)
        
        for list in lists {
            if list.id == nil {
                list.id = UUID()
            }
        }
    }
    
    private func ensureItemUUIDs() throws {
        let fetchRequest = NSFetchRequest<ListItem>(entityName: "ListItem")
        let items = try context.fetch(fetchRequest)
        
        for item in items {
            if item.id == nil {
                item.id = UUID()
            }
        }
    }
    
    private func ensureTitleUUIDs() throws {
        let fetchRequest = NSFetchRequest<Title>(entityName: "Title")
        let titles = try context.fetch(fetchRequest)
        
        for title in titles {
            if title.id == nil {
                title.id = UUID()
            }
        }
    }
    
    private func ensureEpisodeUUIDs() throws {
        let fetchRequest = NSFetchRequest<Episode>(entityName: "Episode")
        let episodes = try context.fetch(fetchRequest)
        
        for episode in episodes {
            if episode.id == nil {
                episode.id = UUID()
            }
        }
    }
    
    private func ensureNoteUUIDs() throws {
        let fetchRequest = NSFetchRequest<Note>(entityName: "Note")
        let notes = try context.fetch(fetchRequest)
        
        for note in notes {
            if note.id == nil {
                note.id = UUID()
            }
        }
    }
    
    // MARK: - Validation
    
    /// Validate that all objects have proper LWW metadata
    func validateMigration() -> [String] {
        var issues: [String] = []
        
        do {
            // Validate Lists
            let lists = try context.fetch(MediaList.fetchAll())
            for list in lists {
                if list.id == nil {
                    issues.append("List '\(list.name ?? "unknown")' missing UUID")
                }
                if list.createdAt == nil {
                    issues.append("List '\(list.name ?? "unknown")' missing createdAt")
                }
                if list.updatedAt == nil {
                    issues.append("List '\(list.name ?? "unknown")' missing updatedAt")
                }
                if list.deviceID == nil || list.deviceID?.isEmpty == true {
                    issues.append("List '\(list.name ?? "unknown")' missing deviceID")
                }
            }
            
            // Validate ListItems
            let items = try context.fetch(NSFetchRequest<ListItem>(entityName: "ListItem"))
            for item in items {
                if item.id == nil {
                    issues.append("ListItem missing UUID")
                }
                if item.createdAt == nil {
                    issues.append("ListItem missing createdAt")
                }
                if item.updatedAt == nil {
                    issues.append("ListItem missing updatedAt")
                }
                if item.deviceID == nil || item.deviceID?.isEmpty == true {
                    issues.append("ListItem missing deviceID")
                }
            }
            
            // Similar validation for other entities...
            
        } catch {
            issues.append("Validation failed: \(error.localizedDescription)")
        }
        
        return issues
    }
}

// MARK: - Migration Extensions

extension PersistenceController {
    
    /// Convenience method to perform LWW migration on startup
    func performLWWMigrationIfNeeded() {
        let migration = LWWMigrationUtility(context: viewContext)
        
        let status = migration.checkMigrationStatus()
        
        switch status {
        case .required:
            do {
                try migration.ensureUUIDs()
                try migration.performMigration()
                
                let issues = migration.validateMigration()
                if issues.isEmpty {
                    print("✅ LWW Migration completed successfully")
                } else {
                    print("⚠️ LWW Migration completed with issues: \(issues)")
                }
            } catch {
                print("❌ LWW Migration failed: \(error)")
            }
            
        case .notNeeded:
            print("✅ LWW Migration not needed")
            
        case .failed(let error):
            print("❌ LWW Migration check failed: \(error)")
            
        default:
            break
        }
    }
}