//
//  DatabaseIntegrityService.swift
//  MediaWatch
//
//  Database integrity maintenance and repair service
//  Comprehensive scanning for Core Data consistency issues
//

import Foundation
import CoreData
import UIKit

@MainActor
final class DatabaseIntegrityService: ObservableObject {
    
    // MARK: - Shared Instance
    
    static let shared = DatabaseIntegrityService()
    
    // MARK: - Published Properties
    
    @Published var scanStatus: ScanStatus = .idle
    @Published var lastScanDate: Date?
    @Published var integrityReport: IntegrityReport?
    
    // MARK: - Types
    
    enum ScanStatus {
        case idle
        case scanning(progress: Double)
        case completed
        case error(String)
    }
    
    struct IntegrityReport {
        let scanDate: Date
        let totalEntities: Int
        let issuesFound: [IntegrityIssue]
        let autoFixesApplied: [IntegrityFix]
        let manualActionsRequired: [IntegrityIssue]
        let scanDuration: TimeInterval
        
        var isHealthy: Bool {
            return issuesFound.isEmpty
        }
        
        var summary: String {
            if isHealthy {
                return "✅ Database is healthy - no issues found"
            } else {
                return "⚠️ Found \(issuesFound.count) issues (\(autoFixesApplied.count) auto-fixed)"
            }
        }
    }
    
    struct IntegrityIssue {
        let id: UUID = UUID()
        let type: IssueType
        let severity: Severity
        let entity: String
        let recordId: String?
        let description: String
        let details: String?
        let canAutoFix: Bool
        let fixAction: (() -> Void)?
        
        enum IssueType: String, CaseIterable, Identifiable {
            case duplicateId = "Duplicate ID"
            case duplicateName = "Duplicate Name"
            case missingId = "Missing ID"
            case invalidTimestamp = "Invalid Timestamp"
            case orphanedRecord = "Orphaned Record"
            case brokenRelation = "Broken Relation"
            case invalidOrder = "Invalid Order"
            case malformedData = "Malformed Data"
            case syncInconsistency = "Sync Inconsistency"
            case tombstoneIssue = "Tombstone Issue"
            
            var id: String { rawValue }
        }
        
        enum Severity: Int, CaseIterable {
            case low = 1, medium = 2, high = 3, critical = 4
            
            var emoji: String {
                switch self {
                case .low: return "🟡"
                case .medium: return "🟠" 
                case .high: return "🔴"
                case .critical: return "💥"
                }
            }
        }
    }
    
    struct IntegrityFix {
        let issue: IntegrityIssue
        let action: String
        let timestamp: Date
    }
    
    // MARK: - Private Properties
    
    private let context: NSManagedObjectContext
    private let deviceId: String
    private var progressCallback: ((Double) -> Void)?
    
    // MARK: - Initialization
    
    init() {
        self.context = PersistenceController.shared.viewContext
        self.deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    }
    
    // MARK: - Public API
    
    /// Perform a comprehensive database integrity scan
    func performIntegrityScan(autoFix: Bool = true) async throws {
        let startTime = Date()
        scanStatus = .scanning(progress: 0.0)
        
        var allIssues: [IntegrityIssue] = []
        var autoFixes: [IntegrityFix] = []
        
        do {
            // 1. Structure & Schema Check (10%)
            updateProgress(0.1, "Checking database structure...")
            let structureIssues = try await scanStructureIntegrity()
            allIssues.append(contentsOf: structureIssues)
            
            // 2. Identity Consistency (20%)
            updateProgress(0.2, "Scanning identity consistency...")
            let identityResults = try await scanIdentityConsistency(autoFix: autoFix)
            allIssues.append(contentsOf: identityResults.issues)
            autoFixes.append(contentsOf: identityResults.fixes)
            
            // 3. Timestamp Consistency (30%)
            updateProgress(0.3, "Validating timestamps...")
            let timestampResults = try await scanTimestampConsistency(autoFix: autoFix)
            allIssues.append(contentsOf: timestampResults.issues)
            autoFixes.append(contentsOf: timestampResults.fixes)
            
            // 4. Content Validation (40%)
            updateProgress(0.4, "Validating content integrity...")
            let contentResults = try await scanContentValidation(autoFix: autoFix)
            allIssues.append(contentsOf: contentResults.issues)
            autoFixes.append(contentsOf: contentResults.fixes)
            
            // 5. Ordering & Sorting Consistency (50%)
            updateProgress(0.5, "Checking ordering consistency...")
            let orderResults = try await scanOrderingConsistency(autoFix: autoFix)
            allIssues.append(contentsOf: orderResults.issues)
            autoFixes.append(contentsOf: orderResults.fixes)
            
            // 6. Deletion & Tombstone Integrity (70%)
            updateProgress(0.7, "Scanning deletion integrity...")
            let deletionResults = try await scanDeletionIntegrity(autoFix: autoFix)
            allIssues.append(contentsOf: deletionResults.issues)
            autoFixes.append(contentsOf: deletionResults.fixes)
            
            // 7. Sync State Consistency (85%)
            updateProgress(0.85, "Validating sync state...")
            let syncResults = try await scanSyncStateConsistency(autoFix: autoFix)
            allIssues.append(contentsOf: syncResults.issues)
            autoFixes.append(contentsOf: syncResults.fixes)
            
            // 8. Relational Consistency (100%)
            updateProgress(1.0, "Checking relational integrity...")
            let relationResults = try await scanRelationalConsistency(autoFix: autoFix)
            allIssues.append(contentsOf: relationResults.issues)
            autoFixes.append(contentsOf: relationResults.fixes)
            
            // Generate final report
            let totalEntities = try await getTotalEntityCount()
            let manualActions = allIssues.filter { !$0.canAutoFix }
            
            integrityReport = IntegrityReport(
                scanDate: Date(),
                totalEntities: totalEntities,
                issuesFound: allIssues,
                autoFixesApplied: autoFixes,
                manualActionsRequired: manualActions,
                scanDuration: Date().timeIntervalSince(startTime)
            )
            
            lastScanDate = Date()
            scanStatus = .completed
            
        } catch {
            scanStatus = .error(error.localizedDescription)
            throw error
        }
    }
    
    // MARK: - 1. Structure & Schema Check
    
    private func scanStructureIntegrity() async throws -> [IntegrityIssue] {
        return try await withCheckedThrowingContinuation { continuation in
            context.perform {
                var issues: [IntegrityIssue] = []
                
                // Check if all expected entities exist
                let expectedEntities = ["List", "ListItem", "Title", "Episode", "Note", "UserPreferences"]
                let model = self.context.persistentStoreCoordinator?.managedObjectModel
                let actualEntities = model?.entities.map { $0.name ?? "" } ?? []
                
                for entity in expectedEntities {
                    if !actualEntities.contains(entity) {
                        issues.append(IntegrityIssue(
                            type: .malformedData,
                            severity: .critical,
                            entity: entity,
                            recordId: nil,
                            description: "Missing expected entity: \(entity)",
                            details: "Core Data model may be corrupted or incomplete",
                            canAutoFix: false,
                            fixAction: nil
                        ))
                    }
                }
                
                continuation.resume(returning: issues)
            }
        }
    }
    
    // MARK: - 2. Identity Consistency
    
    private func scanIdentityConsistency(autoFix: Bool) async throws -> (issues: [IntegrityIssue], fixes: [IntegrityFix]) {
        return try await withCheckedThrowingContinuation { continuation in
            context.perform {
                var issues: [IntegrityIssue] = []
                var fixes: [IntegrityFix] = []
                
                do {
                    // Check for duplicate List IDs
                    let listIssues = try self.checkDuplicateIds(
                        entityName: "List", 
                        idField: "id", 
                        autoFix: autoFix
                    )
                    issues.append(contentsOf: listIssues.issues)
                    fixes.append(contentsOf: listIssues.fixes)
                    
                    // Check for duplicate Title IDs
                    let titleIssues = try self.checkDuplicateIds(
                        entityName: "Title", 
                        idField: "id", 
                        autoFix: autoFix
                    )
                    issues.append(contentsOf: titleIssues.issues)
                    fixes.append(contentsOf: titleIssues.fixes)
                    
                    // Check for duplicate Episode IDs
                    let episodeIssues = try self.checkDuplicateIds(
                        entityName: "Episode", 
                        idField: "id", 
                        autoFix: autoFix
                    )
                    issues.append(contentsOf: episodeIssues.issues)
                    fixes.append(contentsOf: episodeIssues.fixes)
                    
                    // Check for duplicate List names
                    let duplicateNameIssues = try self.checkDuplicateListNames(autoFix: autoFix)
                    issues.append(contentsOf: duplicateNameIssues.issues)
                    fixes.append(contentsOf: duplicateNameIssues.fixes)
                    
                    // Check for missing IDs
                    let missingIdIssues = try self.checkMissingIds(autoFix: autoFix)
                    issues.append(contentsOf: missingIdIssues.issues)
                    fixes.append(contentsOf: missingIdIssues.fixes)
                    
                    continuation.resume(returning: (issues, fixes))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func checkDuplicateIds(entityName: String, idField: String, autoFix: Bool) throws -> (issues: [IntegrityIssue], fixes: [IntegrityFix]) {
        var issues: [IntegrityIssue] = []
        var fixes: [IntegrityFix] = []
        
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: entityName)
        let entities = try context.fetch(fetchRequest)
        
        var idCounts: [String: [NSManagedObject]] = [:]
        var entitiesWithoutId: [NSManagedObject] = []
        
        for entity in entities {
            if let id = entity.value(forKey: idField) as? UUID {
                let idString = id.uuidString
                idCounts[idString, default: []].append(entity)
            } else {
                entitiesWithoutId.append(entity)
            }
        }
        
        // Handle duplicates
        for (id, duplicates) in idCounts where duplicates.count > 1 {
            issues.append(IntegrityIssue(
                type: .duplicateId,
                severity: .high,
                entity: entityName,
                recordId: id,
                description: "Duplicate \(entityName) ID: \(id)",
                details: "Found \(duplicates.count) entities with same ID",
                canAutoFix: autoFix,
                fixAction: autoFix ? { [weak self] in
                    self?.fixDuplicateIds(duplicates: duplicates, entityName: entityName)
                } : nil
            ))
            
            if autoFix {
                fixes.append(IntegrityFix(
                    issue: issues.last!,
                    action: "Merged \(duplicates.count) duplicate \(entityName) entities",
                    timestamp: Date()
                ))
                self.fixDuplicateIds(duplicates: duplicates, entityName: entityName)
            }
        }
        
        // Handle missing IDs
        for entity in entitiesWithoutId {
            let objectIdString = entity.objectID.uriRepresentation().absoluteString
            issues.append(IntegrityIssue(
                type: .missingId,
                severity: .high,
                entity: entityName,
                recordId: objectIdString,
                description: "Missing ID for \(entityName)",
                details: "Entity exists but has no UUID",
                canAutoFix: autoFix,
                fixAction: autoFix ? { [weak self] in
                    entity.setValue(UUID(), forKey: idField)
                    entity.setValue(Date(), forKey: "createdAt")
                    entity.setValue(Date(), forKey: "updatedAt")
                    entity.setValue(self?.deviceId, forKey: "deviceID")
                } : nil
            ))
            
            if autoFix {
                entity.setValue(UUID(), forKey: idField)
                entity.setValue(Date(), forKey: "createdAt")
                entity.setValue(Date(), forKey: "updatedAt")
                entity.setValue(self.deviceId, forKey: "deviceID")
                
                fixes.append(IntegrityFix(
                    issue: issues.last!,
                    action: "Generated new UUID for \(entityName)",
                    timestamp: Date()
                ))
            }
        }
        
        if autoFix && (!issues.isEmpty) {
            try context.save()
        }
        
        return (issues, fixes)
    }
    
    private func checkDuplicateListNames(autoFix: Bool) throws -> (issues: [IntegrityIssue], fixes: [IntegrityFix]) {
        var issues: [IntegrityIssue] = []
        var fixes: [IntegrityFix] = []
        
        let fetchRequest: NSFetchRequest<MediaList> = MediaList.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "deletedAt == nil")
        
        let allLists = try context.fetch(fetchRequest)
        
        // Group lists by name
        let groupedByName = Dictionary(grouping: allLists) { $0.name ?? "" }
        
        // Find names with multiple lists
        for (name, lists) in groupedByName where lists.count > 1 {
            // Create an issue for each duplicate (except the first one)
            for (index, list) in lists.enumerated() where index > 0 {
                issues.append(IntegrityIssue(
                    type: .duplicateName,
                    severity: .medium,
                    entity: "List",
                    recordId: list.id?.uuidString,
                    description: "Duplicate list name: '\(name)'",
                    details: "Found \(lists.count) lists with the name '\(name)'. Please rename or delete duplicate lists to avoid confusion.",
                    canAutoFix: false, // Cannot auto-fix - user needs to decide which to keep/rename
                    fixAction: nil
                ))
            }
        }
        
        return (issues, fixes)
    }
    
    private func fixDuplicateIds(duplicates: [NSManagedObject], entityName: String) {
        // Keep the most recently updated entity, delete others
        let sorted = duplicates.sorted { (a, b) in
            let aUpdate = a.value(forKey: "updatedAt") as? Date ?? Date.distantPast
            let bUpdate = b.value(forKey: "updatedAt") as? Date ?? Date.distantPast
            return aUpdate > bUpdate
        }
        
        let keeper = sorted.first!
        let toDelete = Array(sorted.dropFirst())
        
        // For List: merge items before deleting
        if entityName == "List" {
            for duplicate in toDelete {
                if let items = duplicate.value(forKey: "items") as? Set<NSManagedObject> {
                    for item in items {
                        item.setValue(keeper, forKey: "list")
                    }
                }
            }
        }
        
        // Delete duplicates
        for duplicate in toDelete {
            context.delete(duplicate)
        }
    }
    
    // MARK: - 3. Timestamp Consistency
    
    private func scanTimestampConsistency(autoFix: Bool) async throws -> (issues: [IntegrityIssue], fixes: [IntegrityFix]) {
        return try await withCheckedThrowingContinuation { continuation in
            context.perform {
                var issues: [IntegrityIssue] = []
                var fixes: [IntegrityFix] = []
                
                do {
                    let entities = ["List", "Title", "Episode", "Note", "ListItem"]
                    
                    for entityName in entities {
                        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: entityName)
                        let objects = try self.context.fetch(fetchRequest)
                        
                        for object in objects {
                            let objectId = object.value(forKey: "id") as? UUID
                            let createdAt = object.value(forKey: "createdAt") as? Date
                            let updatedAt = object.value(forKey: "updatedAt") as? Date
                            let deletedAt = object.value(forKey: "deletedAt") as? Date
                            
                            // Check for missing timestamps
                            if createdAt == nil {
                                issues.append(IntegrityIssue(
                                    type: .invalidTimestamp,
                                    severity: .medium,
                                    entity: entityName,
                                    recordId: objectId?.uuidString,
                                    description: "Missing createdAt timestamp",
                                    details: "Entity has no creation timestamp",
                                    canAutoFix: autoFix,
                                    fixAction: autoFix ? { [weak self] in
                                        object.setValue(Date(), forKey: "createdAt")
                                    } : nil
                                ))
                                
                                if autoFix {
                                    object.setValue(Date(), forKey: "createdAt")
                                    fixes.append(IntegrityFix(
                                        issue: issues.last!,
                                        action: "Set missing createdAt timestamp",
                                        timestamp: Date()
                                    ))
                                }
                            }
                            
                            if updatedAt == nil {
                                issues.append(IntegrityIssue(
                                    type: .invalidTimestamp,
                                    severity: .medium,
                                    entity: entityName,
                                    recordId: objectId?.uuidString,
                                    description: "Missing updatedAt timestamp",
                                    details: "Entity has no update timestamp",
                                    canAutoFix: autoFix,
                                    fixAction: autoFix ? { [weak self] in
                                        object.setValue(Date(), forKey: "updatedAt")
                                    } : nil
                                ))
                                
                                if autoFix {
                                    object.setValue(Date(), forKey: "updatedAt")
                                    fixes.append(IntegrityFix(
                                        issue: issues.last!,
                                        action: "Set missing updatedAt timestamp",
                                        timestamp: Date()
                                    ))
                                }
                            }
                            
                            // Check timestamp logic
                            if let created = createdAt, let updated = updatedAt, created > updated {
                                issues.append(IntegrityIssue(
                                    type: .invalidTimestamp,
                                    severity: .medium,
                                    entity: entityName,
                                    recordId: objectId?.uuidString,
                                    description: "createdAt is after updatedAt",
                                    details: "Created: \(created), Updated: \(updated)",
                                    canAutoFix: autoFix,
                                    fixAction: autoFix ? { [weak self] in
                                        object.setValue(created, forKey: "updatedAt")
                                    } : nil
                                ))
                                
                                if autoFix {
                                    object.setValue(created, forKey: "updatedAt")
                                    fixes.append(IntegrityFix(
                                        issue: issues.last!,
                                        action: "Fixed updatedAt to match createdAt",
                                        timestamp: Date()
                                    ))
                                }
                            }
                            
                            // Check deletion logic
                            if let deleted = deletedAt, let updated = updatedAt, deleted < updated {
                                issues.append(IntegrityIssue(
                                    type: .invalidTimestamp,
                                    severity: .high,
                                    entity: entityName,
                                    recordId: objectId?.uuidString,
                                    description: "deletedAt is before updatedAt",
                                    details: "Deleted: \(deleted), Updated: \(updated)",
                                    canAutoFix: autoFix,
                                    fixAction: autoFix ? { [weak self] in
                                        object.setValue(updated, forKey: "deletedAt")
                                    } : nil
                                ))
                                
                                if autoFix {
                                    object.setValue(updated, forKey: "deletedAt")
                                    fixes.append(IntegrityFix(
                                        issue: issues.last!,
                                        action: "Fixed deletedAt timestamp",
                                        timestamp: Date()
                                    ))
                                }
                            }
                        }
                    }
                    
                    if autoFix && !fixes.isEmpty {
                        try self.context.save()
                    }
                    
                    continuation.resume(returning: (issues, fixes))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - 4. Content Validation
    
    private func scanContentValidation(autoFix: Bool) async throws -> (issues: [IntegrityIssue], fixes: [IntegrityFix]) {
        return try await withCheckedThrowingContinuation { continuation in
            context.perform {
                var issues: [IntegrityIssue] = []
                var fixes: [IntegrityFix] = []
                
                do {
                    // Validate MediaList content
                    let lists = try self.context.fetch(MediaList.fetchAll())
                    for list in lists {
                        if list.name?.isEmpty ?? true {
                            issues.append(IntegrityIssue(
                                type: .malformedData,
                                severity: .medium,
                                entity: "List",
                                recordId: list.id?.uuidString,
                                description: "List has empty name",
                                details: "List exists but has no name",
                                canAutoFix: autoFix,
                                fixAction: autoFix ? { [weak self] in
                                    list.name = "Unnamed List"
                                    list.updatedAt = Date()
                                    list.deviceID = self?.deviceId
                                } : nil
                            ))
                            
                            if autoFix {
                                list.name = "Unnamed List"
                                list.updatedAt = Date()
                                list.deviceID = self.deviceId
                                fixes.append(IntegrityFix(
                                    issue: issues.last!,
                                    action: "Set default name for unnamed list",
                                    timestamp: Date()
                                ))
                            }
                        }
                    }
                    
                    // Validate Title content
                    let titles = try self.context.fetch(Title.fetchRequest())
                    for title in titles {
                        if title.title?.isEmpty ?? true {
                            issues.append(IntegrityIssue(
                                type: .malformedData,
                                severity: .medium,
                                entity: "Title",
                                recordId: title.id?.uuidString,
                                description: "Title has empty title field",
                                details: "TMDB ID: \(title.tmdbId)",
                                canAutoFix: autoFix,
                                fixAction: autoFix ? { [weak self] in
                                    title.title = "Unknown Title (TMDB: \(title.tmdbId))"
                                    title.updatedAt = Date()
                                    title.deviceID = self?.deviceId
                                } : nil
                            ))
                            
                            if autoFix {
                                title.title = "Unknown Title (TMDB: \(title.tmdbId))"
                                title.updatedAt = Date()
                                title.deviceID = self.deviceId
                                fixes.append(IntegrityFix(
                                    issue: issues.last!,
                                    action: "Set default title for unnamed title",
                                    timestamp: Date()
                                ))
                            }
                        }
                        
                        if title.tmdbId <= 0 {
                            issues.append(IntegrityIssue(
                                type: .malformedData,
                                severity: .low,
                                entity: "Title",
                                recordId: title.id?.uuidString,
                                description: "Invalid TMDB ID",
                                details: "TMDB ID: \(title.tmdbId) is not valid",
                                canAutoFix: false,
                                fixAction: nil
                            ))
                        }
                    }
                    
                    if autoFix && !fixes.isEmpty {
                        try self.context.save()
                    }
                    
                    continuation.resume(returning: (issues, fixes))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - 5. Ordering Consistency
    
    private func scanOrderingConsistency(autoFix: Bool) async throws -> (issues: [IntegrityIssue], fixes: [IntegrityFix]) {
        return try await withCheckedThrowingContinuation { continuation in
            context.perform {
                var issues: [IntegrityIssue] = []
                var fixes: [IntegrityFix] = []
                
                do {
                    let lists = try self.context.fetch(MediaList.fetchAll())
                    
                    for list in lists {
                        let items = list.sortedItems
                        var previousOrder: Double = -1
                        var needsReordering = false
                        
                        for item in items {
                            if item.order <= previousOrder {
                                needsReordering = true
                                break
                            }
                            previousOrder = item.order
                        }
                        
                        if needsReordering {
                            issues.append(IntegrityIssue(
                                type: .invalidOrder,
                                severity: .medium,
                                entity: "ListItem",
                                recordId: list.id?.uuidString,
                                description: "List items have invalid ordering",
                                details: "List '\(list.name ?? "Unknown")' has \(items.count) items with inconsistent order",
                                canAutoFix: autoFix,
                                fixAction: autoFix ? { [weak self] in
                                    self?.fixListOrdering(list: list)
                                } : nil
                            ))
                            
                            if autoFix {
                                self.fixListOrdering(list: list)
                                fixes.append(IntegrityFix(
                                    issue: issues.last!,
                                    action: "Reordered \(items.count) list items",
                                    timestamp: Date()
                                ))
                            }
                        }
                    }
                    
                    if autoFix && !fixes.isEmpty {
                        try self.context.save()
                    }
                    
                    continuation.resume(returning: (issues, fixes))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func fixListOrdering(list: MediaList) {
        let items = list.sortedItems
        for (index, item) in items.enumerated() {
            item.order = Double(index + 1)
            item.updatedAt = Date()
            item.deviceID = self.deviceId
        }
        list.updatedAt = Date()
        list.deviceID = self.deviceId
    }
    
    // MARK: - 6. Deletion & Tombstone Integrity
    
    private func scanDeletionIntegrity(autoFix: Bool) async throws -> (issues: [IntegrityIssue], fixes: [IntegrityFix]) {
        return try await withCheckedThrowingContinuation { continuation in
            context.perform {
                var issues: [IntegrityIssue] = []
                var fixes: [IntegrityFix] = []
                
                do {
                    // Check for orphaned tombstones (deleted entities that should be cleaned up)
                    let oldThreshold = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date.distantPast
                    
                    let entities = ["List", "Title", "Episode", "Note", "ListItem"]
                    for entityName in entities {
                        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: entityName)
                        fetchRequest.predicate = NSPredicate(format: "deletedAt != nil AND deletedAt < %@", oldThreshold as NSDate)
                        
                        let oldTombstones = try self.context.fetch(fetchRequest)
                        
                        if !oldTombstones.isEmpty {
                            issues.append(IntegrityIssue(
                                type: .tombstoneIssue,
                                severity: .low,
                                entity: entityName,
                                recordId: nil,
                                description: "Old tombstones found",
                                details: "\(oldTombstones.count) deleted \(entityName) records older than 30 days",
                                canAutoFix: autoFix,
                                fixAction: autoFix ? { [weak self] in
                                    for tombstone in oldTombstones {
                                        self?.context.delete(tombstone)
                                    }
                                } : nil
                            ))
                            
                            if autoFix {
                                for tombstone in oldTombstones {
                                    self.context.delete(tombstone)
                                }
                                fixes.append(IntegrityFix(
                                    issue: issues.last!,
                                    action: "Cleaned up \(oldTombstones.count) old tombstones",
                                    timestamp: Date()
                                ))
                            }
                        }
                    }
                    
                    if autoFix && !fixes.isEmpty {
                        try self.context.save()
                    }
                    
                    continuation.resume(returning: (issues, fixes))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - 7. Sync State Consistency
    
    private func scanSyncStateConsistency(autoFix: Bool) async throws -> (issues: [IntegrityIssue], fixes: [IntegrityFix]) {
        return try await withCheckedThrowingContinuation { continuation in
            context.perform {
                var issues: [IntegrityIssue] = []
                var fixes: [IntegrityFix] = []
                
                do {
                    // Check for missing device IDs
                    let entities = ["List", "Title", "Episode", "Note", "ListItem"]
                    for entityName in entities {
                        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: entityName)
                        fetchRequest.predicate = NSPredicate(format: "deviceID == nil OR deviceID == ''")
                        
                        let missingDeviceId = try self.context.fetch(fetchRequest)
                        
                        if !missingDeviceId.isEmpty {
                            issues.append(IntegrityIssue(
                                type: .syncInconsistency,
                                severity: .medium,
                                entity: entityName,
                                recordId: nil,
                                description: "Missing device IDs",
                                details: "\(missingDeviceId.count) \(entityName) records without device ID",
                                canAutoFix: autoFix,
                                fixAction: autoFix ? { [weak self] in
                                    for entity in missingDeviceId {
                                        entity.setValue(self?.deviceId, forKey: "deviceID")
                                        entity.setValue(Date(), forKey: "updatedAt")
                                    }
                                } : nil
                            ))
                            
                            if autoFix {
                                for entity in missingDeviceId {
                                    entity.setValue(self.deviceId, forKey: "deviceID")
                                    entity.setValue(Date(), forKey: "updatedAt")
                                }
                                fixes.append(IntegrityFix(
                                    issue: issues.last!,
                                    action: "Set device ID for \(missingDeviceId.count) entities",
                                    timestamp: Date()
                                ))
                            }
                        }
                    }
                    
                    if autoFix && !fixes.isEmpty {
                        try self.context.save()
                    }
                    
                    continuation.resume(returning: (issues, fixes))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - 8. Relational Consistency
    
    private func scanRelationalConsistency(autoFix: Bool) async throws -> (issues: [IntegrityIssue], fixes: [IntegrityFix]) {
        return try await withCheckedThrowingContinuation { continuation in
            context.perform {
                var issues: [IntegrityIssue] = []
                var fixes: [IntegrityFix] = []
                
                do {
                    // Check for orphaned ListItems (items without a list or title)
                    let orphanedItems = try self.context.fetch(NSFetchRequest<ListItem>(entityName: "ListItem"))
                        .filter { $0.list == nil || $0.title == nil }
                    
                    if !orphanedItems.isEmpty {
                        issues.append(IntegrityIssue(
                            type: .orphanedRecord,
                            severity: .high,
                            entity: "ListItem",
                            recordId: nil,
                            description: "Orphaned list items",
                            details: "\(orphanedItems.count) list items without proper relationships",
                            canAutoFix: autoFix,
                            fixAction: autoFix ? { [weak self] in
                                for item in orphanedItems {
                                    self?.context.delete(item)
                                }
                            } : nil
                        ))
                        
                        if autoFix {
                            for item in orphanedItems {
                                self.context.delete(item)
                            }
                            fixes.append(IntegrityFix(
                                issue: issues.last!,
                                action: "Deleted \(orphanedItems.count) orphaned list items",
                                timestamp: Date()
                            ))
                        }
                    }
                    
                    // Check for orphaned Episodes (episodes without a show)
                    let orphanedEpisodes = try self.context.fetch(NSFetchRequest<Episode>(entityName: "Episode"))
                        .filter { $0.show == nil }
                    
                    if !orphanedEpisodes.isEmpty {
                        issues.append(IntegrityIssue(
                            type: .orphanedRecord,
                            severity: .medium,
                            entity: "Episode",
                            recordId: nil,
                            description: "Orphaned episodes",
                            details: "\(orphanedEpisodes.count) episodes without parent show",
                            canAutoFix: autoFix,
                            fixAction: autoFix ? { [weak self] in
                                for episode in orphanedEpisodes {
                                    self?.context.delete(episode)
                                }
                            } : nil
                        ))
                        
                        if autoFix {
                            for episode in orphanedEpisodes {
                                self.context.delete(episode)
                            }
                            fixes.append(IntegrityFix(
                                issue: issues.last!,
                                action: "Deleted \(orphanedEpisodes.count) orphaned episodes",
                                timestamp: Date()
                            ))
                        }
                    }
                    
                    // Check for orphaned Notes (notes without a title)
                    let orphanedNotes = try self.context.fetch(NSFetchRequest<Note>(entityName: "Note"))
                        .filter { $0.title == nil }
                    
                    if !orphanedNotes.isEmpty {
                        issues.append(IntegrityIssue(
                            type: .orphanedRecord,
                            severity: .medium,
                            entity: "Note",
                            recordId: nil,
                            description: "Orphaned notes",
                            details: "\(orphanedNotes.count) notes without parent title",
                            canAutoFix: autoFix,
                            fixAction: autoFix ? { [weak self] in
                                for note in orphanedNotes {
                                    self?.context.delete(note)
                                }
                            } : nil
                        ))
                        
                        if autoFix {
                            for note in orphanedNotes {
                                self.context.delete(note)
                            }
                            fixes.append(IntegrityFix(
                                issue: issues.last!,
                                action: "Deleted \(orphanedNotes.count) orphaned notes",
                                timestamp: Date()
                            ))
                        }
                    }
                    
                    if autoFix && !fixes.isEmpty {
                        try self.context.save()
                    }
                    
                    continuation.resume(returning: (issues, fixes))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func checkMissingIds(autoFix: Bool) throws -> (issues: [IntegrityIssue], fixes: [IntegrityFix]) {
        // Implementation moved to checkDuplicateIds for efficiency
        return ([], [])
    }
    
    private func getTotalEntityCount() async throws -> Int {
        return try await withCheckedThrowingContinuation { continuation in
            context.perform {
                do {
                    let entities = ["List", "ListItem", "Title", "Episode", "Note"]
                    var total = 0
                    
                    for entityName in entities {
                        let count = try self.context.count(for: NSFetchRequest(entityName: entityName))
                        total += count
                    }
                    
                    continuation.resume(returning: total)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func updateProgress(_ progress: Double, _ message: String) {
        scanStatus = .scanning(progress: progress)
        print("🔍 Database Integrity: \(message) (\(Int(progress * 100))%)")
    }
    
    // MARK: - Quick Health Check
    
    func performQuickHealthCheck() async throws -> String {
        let startTime = Date()
        
        let totalEntities = try await getTotalEntityCount()
        let duplicateIssues = try await scanIdentityConsistency(autoFix: false)
        let timestampIssues = try await scanTimestampConsistency(autoFix: false) 
        let relationIssues = try await scanRelationalConsistency(autoFix: false)
        
        let totalIssues = duplicateIssues.issues.count + timestampIssues.issues.count + relationIssues.issues.count
        let duration = Date().timeIntervalSince(startTime)
        
        if totalIssues == 0 {
            return "✅ Database health check passed (\(totalEntities) entities, \(String(format: "%.1f", duration))s)"
        } else {
            return "⚠️ Found \(totalIssues) issues in \(totalEntities) entities (\(String(format: "%.1f", duration))s)"
        }
    }
    
    // MARK: - Report Export
    
    func exportIntegrityReport() -> String? {
        guard let report = integrityReport else { return nil }
        
        let header = """
        MediaWatch Database Integrity Report
        Generated: \(report.scanDate.formatted(.dateTime))
        Scan Duration: \(String(format: "%.2f", report.scanDuration)) seconds
        Total Entities: \(report.totalEntities)
        Issues Found: \(report.issuesFound.count)
        Auto-Fixes Applied: \(report.autoFixesApplied.count)
        Manual Actions Required: \(report.manualActionsRequired.count)
        
        Overall Status: \(report.summary)
        
        =================================================
        
        """
        
        var details = ""
        
        if !report.issuesFound.isEmpty {
            details += "ISSUES FOUND:\n\n"
            for issue in report.issuesFound {
                details += "\(issue.severity.emoji) \(issue.type) - \(issue.entity)\n"
                details += "Description: \(issue.description)\n"
                if let details_text = issue.details {
                    details += "Details: \(details_text)\n"
                }
                if let recordId = issue.recordId {
                    details += "Record ID: \(recordId)\n"
                }
                details += "Can Auto-Fix: \(issue.canAutoFix ? "Yes" : "No")\n\n"
            }
        }
        
        if !report.autoFixesApplied.isEmpty {
            details += "AUTO-FIXES APPLIED:\n\n"
            for fix in report.autoFixesApplied {
                details += "✅ \(fix.action)\n"
                details += "Applied: \(fix.timestamp.formatted(.dateTime))\n\n"
            }
        }
        
        return header + details
    }
}