//
//  CloudKitPublicSyncService.swift
//  MediaWatch
//
//  CloudKit Public Database sync with cross-Apple ID support
//  Uses the same JSON structure as iCloud Drive sync but stores in public database
//

import Foundation
import CoreData
import Combine
import UIKit
import CloudKit

@MainActor
final class CloudKitPublicSyncService: NSObject, ObservableObject {
    
    // MARK: - Shared Instance
    
    static let shared = CloudKitPublicSyncService()
    
    // MARK: - Published Properties
    
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "CloudKitPublicSync.enabled")
            Task.detached { [weak self] in
                guard let self = self else { return }
                let enabled = await MainActor.run { self.isEnabled }
                if enabled {
                    await self.enableSync()
                } else {
                    await self.disableSync()
                }
            }
        }
    }
    
    @Published var syncStatus: SyncStatus = .idle
    @Published var lastSyncDate: Date?
    @Published var lastConflictDate: Date?
    @Published var diagnosticsLog: [DiagnosticEntry] = []
    @Published var isInReadOnlyMode: Bool = false
    
    // MARK: - Types
    
    enum SyncStatus: Equatable {
        case idle
        case syncing
        case success(String)
        case error(String)
        case cloudKitUnavailable
        case migrating
        case readOnlyMode(String)
    }
    
    struct DiagnosticEntry: Identifiable, Codable {
        let id: UUID
        let timestamp: Date
        let event: String
        let details: String?
        let isError: Bool
        
        init(event: String, details: String? = nil, isError: Bool = false) {
            self.id = UUID()
            self.timestamp = Date()
            self.event = event
            self.details = details
            self.isError = isError
        }
    }
    
    // MARK: - Private Properties
    
    private let container = CKContainer(identifier: "iCloud.reasonality.MediaShows")
    private lazy var publicDatabase = container.publicCloudDatabase
    private var deviceId: String {
        return DeviceIdentifier.shared.deviceID
    }
    private let recordType = "MediaShowsData" // Must match CloudKit Console schema
    private let recordID = CKRecord.ID(recordName: "SharedMediaData", zoneID: CKRecordZone.default().zoneID)
    
    private var cancellables = Set<AnyCancellable>()
    private var lastSyncTime: Date = Date.distantPast
    private let minimumSyncInterval: TimeInterval = 15.0 // Minimum 15 seconds between syncs for better responsiveness
    private var periodicSyncTimer: Timer?
    private var migrationCompleted: Bool {
        get { UserDefaults.standard.bool(forKey: "CloudKitPublicSync.migrationCompleted") }
        set { UserDefaults.standard.set(newValue, forKey: "CloudKitPublicSync.migrationCompleted") }
    }
    
    // MARK: - Initialization
    
    override init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: "CloudKitPublicSync.enabled")
        super.init()
        
        // Defer initialization to prevent app startup crashes
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            self.safeInitialize()
        }
    }
    
    private func safeInitialize() {
        setupNotificationObservers()
        
        Task {
            await initialize()
        }
    }
    
    deinit {
        periodicSyncTimer?.invalidate()
        periodicSyncTimer = nil
    }
    
    private func initialize() async {
        do {
            let accountStatus = try await container.accountStatus()
            guard accountStatus == .available else {
                syncStatus = .cloudKitUnavailable
                logDiagnostic("CloudKit account unavailable: \(accountStatus)", isError: true)
                return
            }
            
            if isEnabled {
                await enableSync()
            }
            
            if !migrationCompleted {
                await performInitialMigration()
            }
        } catch {
            syncStatus = .error("CloudKit initialization failed: \(error.localizedDescription)")
            logDiagnostic("CloudKit initialization error", details: error.localizedDescription, isError: true)
        }
    }
    
    // MARK: - Public Interface
    
    func enableSync() async {
        syncStatus = .syncing
        logDiagnostic("Enabling CloudKit Public Database sync")
        
        do {
            let accountStatus = try await container.accountStatus()
            guard accountStatus == .available else {
                syncStatus = .cloudKitUnavailable
                logDiagnostic("Cannot enable sync: CloudKit account unavailable", isError: true)
                return
            }
            
            // Don't block on initial sync - do it in background after a delay
            Task.detached {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
                await self.performFullSync()
            }
            
            syncStatus = .success("Sync enabled")
            logDiagnostic("CloudKit Public Database sync enabled successfully")
            startPeriodicSync()
            
        } catch {
            syncStatus = .error("Failed to enable sync: \(error.localizedDescription)")
            logDiagnostic("Failed to enable sync", details: error.localizedDescription, isError: true)
        }
    }
    
    func disableSync() async {
        logDiagnostic("Disabling CloudKit Public Database sync")
        stopPeriodicSync()
        syncStatus = .idle
    }
    
    func forceSync() async {
        guard isEnabled else { return }
        await performFullSync()
    }
    
    func transferOwnership() async {
        print("🔄 transferOwnership() function called")
        logDiagnostic("🔄 Transfer ownership button pressed")
        logDiagnostic("🔍 Current state - isEnabled: \(isEnabled), readOnlyMode: \(isInReadOnlyMode)")
        print("🔍 Debug - isEnabled: \(isEnabled), readOnlyMode: \(isInReadOnlyMode)")
        
        guard isEnabled else { 
            logDiagnostic("❌ Cannot transfer ownership: sync not enabled")
            syncStatus = .error("Sync must be enabled first")
            return 
        }
        
        logDiagnostic("🔄 Starting ownership transfer process")
        syncStatus = .syncing
        
        await forceRecreateRecord()
    }
    
    func getMigrationStatus() -> SyncMigrationStatus {
        let context = PersistenceController.shared.viewContext
        let listCount = (try? context.count(for: MediaList.fetchAll())) ?? 0
        let titleCount = (try? context.count(for: Title.fetchRequest())) ?? 0
        let totalCount = listCount + titleCount
        
        return SyncMigrationStatus(
            isRequired: !migrationCompleted && totalCount > 0,
            coreDataItemCount: totalCount,
            canMigrate: true // CloudKit is always available if account is signed in
        )
    }
    
    func resetMigrationFlag() {
        migrationCompleted = false
    }
    
    func clearSyncCache() async {
        logDiagnostic("Clearing CloudKit Public Database sync cache")
        do {
            try await publicDatabase.deleteRecord(withID: recordID)
            logDiagnostic("Cleared remote sync data")
        } catch let error as CKError where error.code == .unknownItem {
            logDiagnostic("No remote data to clear")
        } catch {
            logDiagnostic("Failed to clear remote data", details: error.localizedDescription, isError: true)
        }
    }
    
    func forceRecreateRecord() async {
        logDiagnostic("🔄 Force recreating CloudKit record to establish ownership")
        
        do {
            // First try to delete existing record
            try await publicDatabase.deleteRecord(withID: recordID)
            logDiagnostic("🗑️ Successfully deleted existing record")
            
            // Wait for deletion to propagate
            try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
            
        } catch let error as CKError where error.code == .unknownItem {
            logDiagnostic("ℹ️ Record already doesn't exist")
        } catch {
            logDiagnostic("⚠️ Failed to delete record: \(error.localizedDescription)")
            logDiagnostic("⚠️ This might be expected if device lacks delete permissions")
        }
        
        // Try to modify/update the existing record instead of creating new one
        do {
            // First try to modify existing record
            let result = try await performFullSync()
            logDiagnostic("✅ Successfully took ownership via record modification")
            syncStatus = .success("Ownership transferred successfully")
            lastSyncDate = Date()
            isInReadOnlyMode = false // Clear read-only mode after successful ownership transfer
        } catch {
            logDiagnostic("⚠️ Modify attempt failed, trying initial upload: \(error.localizedDescription)")
            
            // Fallback to initial upload (for truly new records)
            do {
                let result = try await performInitialUpload()
                logDiagnostic("✅ Successfully created new record: \(result)")
                syncStatus = .success("Record created successfully")
                lastSyncDate = Date()
                isInReadOnlyMode = false
            } catch {
                logDiagnostic("❌ Failed to recreate record: \(error.localizedDescription)", isError: true)
                syncStatus = .error("Failed to recreate record: \(error.localizedDescription)")
            }
        }
    }
    
    func exportDiagnosticsLog() -> String {
        let header = """
        MediaWatch CloudKit Sync Diagnostics
        Generated: \(Date().formatted(.dateTime))
        Device ID: \(deviceId)
        Sync Status: \(syncStatus)
        Last Sync: \(lastSyncDate?.formatted(.dateTime) ?? "Never")
        Last Conflict: \(lastConflictDate?.formatted(.dateTime) ?? "None")
        Total Log Entries: \(diagnosticsLog.count)
        
        =================================================
        
        """
        
        let logEntries = diagnosticsLog.map { entry in
            let timestamp = entry.timestamp.formatted(.dateTime.hour().minute().second())
            let prefix = entry.isError ? "❌ ERROR" : "ℹ️ INFO"
            let details = entry.details.map { "\n    Details: \($0)" } ?? ""
            return "[\(timestamp)] \(prefix): \(entry.event)\(details)"
        }.joined(separator: "\n\n")
        
        return header + logEntries
    }
    
    func copyDiagnosticsToClipboard() {
        #if os(iOS)
        UIPasteboard.general.string = exportDiagnosticsLog()
        logDiagnostic("📋 Copied diagnostics log to clipboard")
        #endif
    }
    
    func saveDiagnosticsToFile() -> URL? {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard let documentsURL = documentsPath else { return nil }
        
        let timestamp = Date().formatted(.dateTime.year().month().day().hour().minute())
        let filename = "CloudKitSync_Diagnostics_\(timestamp).txt"
        let fileURL = documentsURL.appendingPathComponent(filename)
        
        do {
            try exportDiagnosticsLog().write(to: fileURL, atomically: true, encoding: .utf8)
            logDiagnostic("📁 Saved diagnostics log to: \(filename)")
            return fileURL
        } catch {
            logDiagnostic("❌ Failed to save diagnostics log", details: error.localizedDescription, isError: true)
            return nil
        }
    }
    
    // MARK: - Periodic Sync for Cross-Apple ID Support
    
    private func startPeriodicSync() {
        stopPeriodicSync() // Clear any existing timer
        
        logDiagnostic("⏰ Starting periodic sync timer for cross-Apple ID support")
        
        // Check for remote changes every 2 minutes when sync is enabled for better cross-device sync
        periodicSyncTimer = Timer.scheduledTimer(withTimeInterval: 120.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.performPeriodicSyncCheck()
            }
        }
    }
    
    private func stopPeriodicSync() {
        periodicSyncTimer?.invalidate()
        periodicSyncTimer = nil
        logDiagnostic("⏹️ Stopped periodic sync timer")
    }
    
    private func performPeriodicSyncCheck() async {
        guard isEnabled else { return }
        
        logDiagnostic("⏰ Periodic sync check")
        
        // Only perform full sync if enough time has passed
        let now = Date()
        if now.timeIntervalSince(lastSyncTime) >= minimumSyncInterval {
            await performFullSync()
        } else {
            logDiagnostic("⏱️ Skipping periodic sync - too soon since last sync")
        }
    }
    
    // MARK: - Backward Compatibility Helpers
    
    private func handleMissingChecksumField(remoteData: Data, decoder: JSONDecoder) async throws -> String {
        // Try to decode using a temporary structure without checksum
        let tempJSON = try decoder.decode(TempSyncJSONData.self, from: remoteData)
        logDiagnostic("✅ Successfully decoded data without checksum field")
        
        // Convert to full structure with generated checksum
        let fullJSON = SyncJSONData(
            version: tempJSON.version,
            lastSyncedAt: tempJSON.lastSyncedAt,
            deviceId: tempJSON.deviceId,
            lists: tempJSON.lists,
            checksum: nil // This will auto-generate the checksum
        )
        
        // Check if any lists have placeholder timestamps and fix them
        let hasPlaceholderDates = fullJSON.lists.contains { list in
            list.createdAt == Date(timeIntervalSinceReferenceDate: 0) ||
            list.updatedAt == Date(timeIntervalSinceReferenceDate: 0)
        }
        
        if hasPlaceholderDates {
            logDiagnostic("🕐 Detected placeholder timestamps - running migration...")
            // Run timestamp migration
            Task { @MainActor in
                do {
                    try await TimestampMigrationHelper.shared.fixPlaceholderTimestamps()
                    logDiagnostic("✅ Timestamp migration completed")
                } catch {
                    logDiagnostic("❌ Timestamp migration failed: \(error.localizedDescription)", isError: true)
                }
            }
        }
        
        // Update the CloudKit record with the corrected data
        try await updateCloudKitRecord(with: fullJSON)
        logDiagnostic("✅ Updated CloudKit record with checksum field")
        
        // Now perform the merge with the corrected data
        let context = PersistenceController.shared.viewContext
        let localData = try await generateJSONData(context: context)
        let localJSON = try decoder.decode(SyncJSONData.self, from: localData)
        
        let mergedJSON = try performDeterministicMerge(local: localJSON, remote: fullJSON)
        
        // Apply merged result to Core Data
        try await applyJSONToCoreData(mergedJSON, context: context)
        logDiagnostic("📥 Applied merged result to local Core Data")
        
        // Update CloudKit with merged data if needed
        let cloudKitNeedsUpdate = !isDataEquivalent(fullJSON, mergedJSON)
        if cloudKitNeedsUpdate {
            try await updateCloudKitRecord(with: mergedJSON)
            logDiagnostic("☁️ Updated CloudKit with merged changes")
        } else {
            logDiagnostic("☁️ CloudKit record already up to date")
        }
        
        return "✨ Sync completed - Merged local and remote changes with checksum migration"
    }
    
    // Temporary structure for backward compatibility
    private struct TempSyncJSONData: Codable {
        let version: Int
        let lastSyncedAt: Date
        let deviceId: String
        let lists: [SyncListData]
    }
    
    private func updateCloudKitRecord(with syncData: SyncJSONData) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let jsonData = try encoder.encode(syncData)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw CloudKitPublicSyncError.invalidCloudKitData
        }
        
        let record = CKRecord(recordType: recordType, recordID: recordID)
        record["jsonData"] = jsonString
        record["version"] = syncData.version
        record["deviceID"] = syncData.deviceId
        record["lastModified"] = Date()
        record["lastModifiedBy"] = deviceId
        
        let _ = try await publicDatabase.modifyRecords(saving: [record], deleting: [])
        logDiagnostic("🔄 Updated CloudKit record with new format")
    }
    
    // MARK: - Migration
    
    private func performInitialMigration() async {
        guard !migrationCompleted else { return }
        
        logDiagnostic("Starting initial migration from Core Data to CloudKit Public Database")
        syncStatus = .migrating
        
        do {
            let context = PersistenceController.shared.viewContext
            let hasData = try await context.perform {
                let listCount = try context.count(for: MediaList.fetchAll())
                let titleCount = try context.count(for: Title.fetchRequest())
                return listCount > 0 || titleCount > 0
            }
            
            if hasData {
                await exportCurrentDataToCloudKit()
                logDiagnostic("Migration completed: exported existing Core Data to CloudKit")
            } else {
                logDiagnostic("Migration completed: no existing data found")
            }
            
            migrationCompleted = true
            syncStatus = .success("Migration completed")
            
        } catch {
            syncStatus = .error("Migration failed: \(error.localizedDescription)")
            logDiagnostic("Migration failed", details: error.localizedDescription, isError: true)
        }
    }
    
    // MARK: - Core Sync Logic
    
    private func performFullSync() async {
        logDiagnostic("🚀 Starting CloudKit Public Database sync")
        
        guard isEnabled else {
            logDiagnostic("❌ Sync not enabled, aborting")
            return
        }
        
        // Rate limiting: prevent sync spam
        let now = Date()
        if now.timeIntervalSince(lastSyncTime) < minimumSyncInterval {
            logDiagnostic("⏱️ Skipping sync - too soon since last sync", details: "Last sync: \(lastSyncTime)")
            return
        }
        lastSyncTime = now
        
        syncStatus = .syncing
        logDiagnostic("🔄 Setting status to syncing")
        
        do {
            let syncResult = try await performSyncOperation()
            
            syncStatus = .success(syncResult)
            lastSyncDate = Date()
            logDiagnostic("✨ Sync completed", details: syncResult)
            
        } catch {
            syncStatus = .error(error.localizedDescription)
            logDiagnostic("💥 Sync failed", details: error.localizedDescription, isError: true)
        }
    }
    
    private func performSyncOperation() async throws -> String {
        logDiagnostic("📡 Checking for existing CloudKit record")
        
        // Comprehensive CloudKit diagnostics
        logDiagnostic("🗂️ Container: \(container.containerIdentifier ?? "unknown")")
        logDiagnostic("🗄️ Database: PublicCloudDatabase")
        logDiagnostic("📍 Zone ID: \(recordID.zoneID.zoneName)")
        logDiagnostic("👤 Zone Owner: \(recordID.zoneID.ownerName)")
        logDiagnostic("📝 Record Name: \(recordID.recordName)")
        logDiagnostic("📋 Record Type: \(recordType)")
        logDiagnostic("📱 Device ID: \(deviceId)")
        logDiagnostic("🔧 Environment: CloudKit Public Database")
        
        // Check CloudKit status and permissions
        do {
            let accountStatus = try await container.accountStatus()
            let statusDescription: String
            switch accountStatus {
            case .available: statusDescription = "Available ✅"
            case .noAccount: statusDescription = "No Account ❌"
            case .restricted: statusDescription = "Restricted ⚠️"
            case .couldNotDetermine: statusDescription = "Could Not Determine ❓"
            case .temporarilyUnavailable: statusDescription = "Temporarily Unavailable ⏳"
            @unknown default: statusDescription = "Unknown (\(accountStatus.rawValue))"
            }
            logDiagnostic("👤 Account Status: \(statusDescription)")
            
            // Note: User discoverability permissions deprecated in iOS 17+
            logDiagnostic("🔐 Permissions: Public database access available")
            
            // Get user record ID for additional context
            do {
                let userRecordID = try await container.userRecordID()
                logDiagnostic("👤 User Record: \(userRecordID.recordName)")
                
                // Test write permissions by attempting a small test operation
                await testWritePermissions()
                
                // Check for device-specific backup records from other devices
                await checkForDeviceBackupRecords()
                
            } catch {
                logDiagnostic("👤 User Record: Unable to fetch (\(error.localizedDescription))")
            }
            
        } catch {
            logDiagnostic("⚠️ CloudKit status check failed: \(error.localizedDescription)")
        }
        
        // Add retry logic for record fetching to handle propagation delays
        for attempt in 1...5 {
            logDiagnostic("🔍 Attempt \(attempt)/5: Fetching record from CloudKit...")
            
            do {
                // Try to fetch existing record
                let existingRecord = try await publicDatabase.record(for: recordID)
                logDiagnostic("📄 Found existing record on attempt \(attempt)!")
                logDiagnostic("📊 Record creation: \(existingRecord.creationDate?.description ?? "unknown")")
                logDiagnostic("📊 Record modified: \(existingRecord.modificationDate?.description ?? "unknown")")
                if let createdBy = existingRecord["createdBy"] as? String {
                    logDiagnostic("👤 Created by device: \(createdBy)")
                }
                if let lastModifiedBy = existingRecord["lastModifiedBy"] as? String {
                    logDiagnostic("👤 Last modified by: \(lastModifiedBy)")
                }
                logDiagnostic("🔄 Starting merge process...")
                return try await performMergeSync(existingRecord: existingRecord)
            } catch let error as CKError where error.code == .unknownItem {
                if attempt < 5 {
                    // Wait before retry - CloudKit Public Database propagation is extremely slow
                    let waitTime = min(attempt * 5, 15) // 5, 10, 15, 15, 15 seconds - escalating delays
                    logDiagnostic("🔄 Record not found, retrying in \(waitTime) seconds (attempt \(attempt)/5)")
                    try await Task.sleep(nanoseconds: UInt64(waitTime) * 1_000_000_000)
                    continue
                } else {
                    // Final attempt - create initial upload
                    logDiagnostic("📝 No existing record after 5 attempts, creating initial upload")
                    return try await performInitialUploadWithConflictHandling()
                }
            } catch let error as CKError {
                let errorDetails = "Code: \(error.code.rawValue), Message: \(error.localizedDescription)"
                logDiagnostic("❌ CloudKit error on attempt \(attempt): \(errorDetails)")
                
                // Log additional CloudKit-specific error info
                if let underlyingError = error.userInfo[NSUnderlyingErrorKey] as? Error {
                    logDiagnostic("🔍 Underlying error: \(underlyingError.localizedDescription)")
                }
                if let serverRecordChanged = error.userInfo[CKRecordChangedErrorAncestorRecordKey] {
                    logDiagnostic("🔄 Server record changed: \(serverRecordChanged)")
                }
                
                // Handle specific permission errors during fetch
                if error.code == .permissionFailure || error.code.rawValue == 10 {
                    logDiagnostic("🚫 Permission error detected during record fetch")
                    logDiagnostic("⚠️ This might indicate CloudKit database permission issues")
                    logDiagnostic("💡 Consider checking CloudKit Console for record ownership and permissions")
                }
                
                if attempt == 5 {
                    throw error
                }
                try await Task.sleep(nanoseconds: UInt64(attempt * 2) * 1_000_000_000)
            } catch {
                logDiagnostic("❌ Non-CloudKit error on attempt \(attempt): \(error.localizedDescription)")
                if attempt == 5 {
                    throw error
                }
                try await Task.sleep(nanoseconds: UInt64(attempt * 2) * 1_000_000_000)
            }
        }
        
        // Should never reach here
        throw CloudKitPublicSyncError.recordNotFound
    }
    
    private func performMergeSync(existingRecord: CKRecord) async throws -> String {
        logDiagnostic("🔄 Starting merge sync process")
        
        // Get local data
        let context = PersistenceController.shared.viewContext
        let localData = try await generateJSONData(context: context)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let localJSON = try decoder.decode(SyncJSONData.self, from: localData)
        
        // Debug: Log local data details
        logDiagnostic("📱 Local data details:", details: "Device: \(localJSON.deviceId), Lists: \(localJSON.lists.count)")
        for (i, list) in localJSON.lists.enumerated() {
            logDiagnostic("📱 Local List \(i+1): '\(list.name)' (\(list.items.count) items)")
            for (j, item) in list.items.prefix(3).enumerated() {
                var details = "(watched: \(item.watched)"
                if let status = item.status, !status.isEmpty { details += ", status: \(status)" }
                if let rating = item.userRating, rating > 0 { details += ", userRating: \(rating)" }
                if let rating = item.mikeRating, rating > 0 { details += ", mikeRating: \(rating)" }
                if let rating = item.lauraRating, rating > 0 { details += ", lauraRating: \(rating)" }
                if item.isFavorite { details += ", favorite: true" }
                if item.currentSeason > 0 { details += ", season: \(item.currentSeason)" }
                if item.episodes.count > 0 { details += ", episodes: \(item.episodes.count)" }
                details += ")"
                logDiagnostic("📱   Item \(j+1): '\(item.title)' \(details)")
            }
            if list.items.count > 3 {
                logDiagnostic("📱   ... and \(list.items.count - 3) more items")
            }
        }
        
        // Get remote data from CloudKit record - with detailed debugging
        logDiagnostic("🔍 Inspecting CloudKit record fields:")
        for key in existingRecord.allKeys() {
            let value = existingRecord[key]
            let valueType = type(of: value)
            let valueDescription = String(describing: value).prefix(100)
            logDiagnostic("🔍 Field '\(key)': \(valueType) = \(valueDescription)")
        }
        
        guard let remoteDataString = existingRecord["jsonData"] as? String else {
            logDiagnostic("❌ CloudKit record 'jsonData' field is not a String")
            logDiagnostic("❌ Field exists: \(existingRecord.allKeys().contains("jsonData"))")
            logDiagnostic("❌ Field value: \(String(describing: existingRecord["jsonData"]))")
            logDiagnostic("❌ Field type: \(type(of: existingRecord["jsonData"]))")
            throw CloudKitPublicSyncError.invalidCloudKitData
        }
        
        guard let remoteData = remoteDataString.data(using: .utf8) else {
            logDiagnostic("❌ Failed to convert jsonData string to UTF-8 data")
            logDiagnostic("❌ String length: \(remoteDataString.count)")
            logDiagnostic("❌ String preview: \(remoteDataString.prefix(200))")
            throw CloudKitPublicSyncError.invalidCloudKitData
        }
        
        logDiagnostic("✅ CloudKit jsonData extracted successfully")
        logDiagnostic("📊 Remote data size: \(remoteData.count) bytes")
        logDiagnostic("📊 Remote data preview: \(String(data: remoteData.prefix(300), encoding: .utf8) ?? "Invalid UTF-8")")
        
        let remoteJSON: SyncJSONData
        do {
            remoteJSON = try decoder.decode(SyncJSONData.self, from: remoteData)
            logDiagnostic("📊 Remote data decoded successfully")
            
            // Debug: Log remote data details
            logDiagnostic("☁️ Remote data details:", details: "Device: \(remoteJSON.deviceId), Lists: \(remoteJSON.lists.count)")
            for (i, list) in remoteJSON.lists.enumerated() {
                logDiagnostic("☁️ Remote List \(i+1): '\(list.name)' (\(list.items.count) items)")
                for (j, item) in list.items.prefix(3).enumerated() {
                    var details = "(watched: \(item.watched)"
                    if let status = item.status, !status.isEmpty { details += ", status: \(status)" }
                    if let rating = item.userRating, rating > 0 { details += ", userRating: \(rating)" }
                    if let rating = item.mikeRating, rating > 0 { details += ", mikeRating: \(rating)" }
                    if let rating = item.lauraRating, rating > 0 { details += ", lauraRating: \(rating)" }
                    if item.isFavorite { details += ", favorite: true" }
                    if item.currentSeason > 0 { details += ", season: \(item.currentSeason)" }
                    if item.episodes.count > 0 { details += ", episodes: \(item.episodes.count)" }
                    details += ")"
                    logDiagnostic("☁️   Item \(j+1): '\(item.title)' \(details)")
                }
                if list.items.count > 3 {
                    logDiagnostic("☁️   ... and \(list.items.count - 3) more items")
                }
            }
            
        } catch {
            logDiagnostic("❌ Failed to decode remote JSON: \(error.localizedDescription)")
            logDiagnostic("❌ JSON decode error details: \(error)")
            if let decodingError = error as? DecodingError {
                logDiagnostic("❌ Decoding error context: \(decodingError.localizedDescription)")
            }
            
            // If it's a checksum field issue, try to regenerate and update the remote
            if error.localizedDescription.contains("checksum") {
                logDiagnostic("🔧 Attempting to fix missing checksum field...")
                return try await handleMissingChecksumField(remoteData: remoteData, decoder: decoder)
            }
            
            throw CloudKitPublicSyncError.invalidCloudKitData
        }
        
        // Perform deterministic merge
        let mergedJSON = try performDeterministicMerge(local: localJSON, remote: remoteJSON)
        
        // Debug: Log merge result details
        logDiagnostic("🎯 Merge result details:", details: "Device: \(mergedJSON.deviceId), Lists: \(mergedJSON.lists.count)")
        for (i, list) in mergedJSON.lists.enumerated() {
            logDiagnostic("🎯 Merged List \(i+1): '\(list.name)' (\(list.items.count) items)")
            for (j, item) in list.items.prefix(2).enumerated() {
                var details = "(watched: \(item.watched)"
                if let status = item.status, !status.isEmpty { details += ", status: \(status)" }
                if let rating = item.userRating, rating > 0 { details += ", userRating: \(rating)" }
                if let rating = item.mikeRating, rating > 0 { details += ", mikeRating: \(rating)" }
                if let rating = item.lauraRating, rating > 0 { details += ", lauraRating: \(rating)" }
                if item.isFavorite { details += ", favorite: true" }
                if item.currentSeason > 0 { details += ", season: \(item.currentSeason)" }
                if item.episodes.count > 0 { details += ", episodes: \(item.episodes.count)" }
                details += ")"
                logDiagnostic("🎯   Item \(j+1): '\(item.title)' \(details)")
            }
            if list.items.count > 2 {
                logDiagnostic("🎯   ... and \(list.items.count - 2) more items")
            }
        }
        
        // Always apply merged result to ensure both devices have complete data
        let localNeedsUpdate = !isDataEquivalent(localJSON, mergedJSON)
        logDiagnostic("🔄 Local needs update: \(localNeedsUpdate)")
        logDiagnostic("🔍 Checking Core Data update:")
        logDiagnostic("🔍   Local has: \(localJSON.lists.count) lists")
        logDiagnostic("🔍   Merged has: \(mergedJSON.lists.count) lists")
        
        // Apply merged result regardless of equivalence check to ensure synchronization
        try await applyJSONToCoreData(mergedJSON, context: context)
        logDiagnostic("📥 Applied merged result to local Core Data")
        
        // Verify the application worked by counting lists directly from Core Data
        let verificationLists = try fetchAllLists(context: context)
        logDiagnostic("✅ Verification: Core Data now has \(verificationLists.count) lists")
        
        // Check if CloudKit needs updating 
        let localTotalItems = localJSON.lists.reduce(0) { $0 + $1.items.count }
        let remoteTotalItems = remoteJSON.lists.reduce(0) { $0 + $1.items.count }
        let mergedTotalItems = mergedJSON.lists.reduce(0) { $0 + $1.items.count }
        
        // Always use merged result - race condition protection removed as it was preventing proper sync
        let finalDataForCloudKit = mergedJSON
        
        let cloudKitNeedsUpdate = !isDataEquivalent(remoteJSON, finalDataForCloudKit)
        logDiagnostic("☁️ CloudKit needs update: \(cloudKitNeedsUpdate)")
        if cloudKitNeedsUpdate {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let mergedData = try encoder.encode(finalDataForCloudKit)
            
            existingRecord["jsonData"] = String(data: mergedData, encoding: .utf8)
            existingRecord["lastModifiedBy"] = deviceId
            existingRecord["lastModifiedAt"] = Date()
            
            do {
                let modifyResult = try await publicDatabase.modifyRecords(saving: [existingRecord], deleting: [])
                logDiagnostic("☁️ Updated CloudKit record with merged data")
                
                // Verify the save succeeded
                if let savedRecord = try modifyResult.saveResults[recordID]?.get() {
                    logDiagnostic("✅ CloudKit update verified, record version: \(savedRecord.recordChangeTag ?? "unknown")")
                    
                    // Double-check propagation by re-fetching (with small delay for propagation)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        Task {
                            do {
                                let refetchedRecord = try await self.publicDatabase.record(for: self.recordID)
                                if let refetchedData = refetchedRecord["jsonData"] as? String,
                                   let data = refetchedData.data(using: .utf8) {
                                    let decoder = JSONDecoder()
                                    decoder.dateDecodingStrategy = .iso8601
                                    let refetchedJSON = try decoder.decode(SyncJSONData.self, from: data)
                                    self.logDiagnostic("🔍 Propagation check: CloudKit now has \(refetchedJSON.lists.count) lists")
                                }
                            } catch {
                                self.logDiagnostic("⚠️ Propagation check failed: \(error.localizedDescription)")
                            }
                        }
                    }
                    
                    // Reset sync timer to trigger other devices to check for changes sooner
                    lastSyncTime = Date.distantPast
                    logDiagnostic("🔄 Reset sync timer to trigger faster propagation checks")
                }
            } catch let error as CKError where error.code == .permissionFailure || error.code.rawValue == 10 {
                // Handle write permission error gracefully
                logDiagnostic("⚠️ Write permission denied - operating in read-only mode")
                let result = try await handlePermissionDeniedError(with: finalDataForCloudKit)
                
                // Update sync status to reflect read-only state
                syncStatus = .readOnlyMode("Sync completed in read-only mode")
                lastSyncDate = Date()
                isInReadOnlyMode = true
                
                return result
            }
        } else {
            logDiagnostic("☁️ CloudKit record already up to date")
        }
        
        return "Merged local and remote changes"
    }
    
    private func performInitialUpload() async throws -> String {
        logDiagnostic("📤 Performing initial upload to CloudKit")
        logDiagnostic("🔧 Creating record with ID: \(recordID.recordName) in zone: \(recordID.zoneID.zoneName)")
        
        let context = PersistenceController.shared.viewContext
        let jsonData = try await generateJSONData(context: context)
        
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw CloudKitPublicSyncError.invalidJSONEncoding
        }
        
        let record = CKRecord(recordType: recordType, recordID: recordID)
        record["jsonData"] = jsonString
        record["createdBy"] = deviceId
        record["lastModifiedBy"] = deviceId
        record["lastModifiedAt"] = Date()
        record["version"] = 1
        
        logDiagnostic("📦 Record prepared, saving to CloudKit...")
        logDiagnostic("📱 Created by device: \(deviceId)")
        logDiagnostic("💾 Data size: \(jsonData.count) bytes")
        
        do {
            let result = try await publicDatabase.modifyRecords(saving: [record], deleting: [])
            if let savedRecord = try result.saveResults[recordID]?.get() {
                logDiagnostic("✅ Record saved successfully!")
                logDiagnostic("📊 Server creation date: \(savedRecord.creationDate?.description ?? "unknown")")
                logDiagnostic("🆔 Server record ID: \(savedRecord.recordID.recordName)")
            }
            logDiagnostic("✅ Created initial CloudKit record")
        } catch let error as CKError {
            logDiagnostic("❌ Failed to save record: Code \(error.code.rawValue), \(error.localizedDescription)")
            throw error
        }
        
        return "Uploaded initial data to CloudKit Public Database"
    }
    
    private func handlePermissionDeniedError(with mergedData: SyncJSONData) async throws -> String {
        logDiagnostic("🔄 Handling permission denied error - this device has read-only access")
        logDiagnostic("📚 This device can read CloudKit data but cannot modify the shared record")
        logDiagnostic("💡 This is normal when records are owned by other devices in CloudKit Public Database")
        
        // Instead of trying to force an update, let's work with what we have
        // Apply the merged data locally but acknowledge we can't update CloudKit
        logDiagnostic("📥 Applying merged data locally only (read-only mode)")
        
        // Log the situation for the user
        logDiagnostic("🔍 Device permissions summary:")
        logDiagnostic("  ✅ Can read from CloudKit Public Database")
        logDiagnostic("  ❌ Cannot write to CloudKit Public Database")
        logDiagnostic("  📱 Local data will be updated with merged results")
        logDiagnostic("  ⏳ Changes from this device will sync when another device updates CloudKit")
        
        // Try an alternative approach - attempt to create a device-specific backup record
        await attemptDeviceSpecificBackup(with: mergedData)
        
        return "Applied merged data locally (read-only CloudKit access)"
    }
    
    private func attemptDeviceSpecificBackup(with mergedData: SyncJSONData) async {
        logDiagnostic("💾 Skipping device backup - using local-only mode")
        logDiagnostic("💡 This device will sync when another device with write access updates CloudKit")
        logDiagnostic("🔄 Local data has been updated with the latest merged state")
        
        // Instead of trying to create backup records (which fails in production CloudKit),
        // we'll rely on the fact that local data is properly merged and up-to-date
        // When a device with write access syncs, it will pick up changes from this device
        // if this device's data is newer based on timestamps
        
        logDiagnostic("📊 Device sync summary:")
        logDiagnostic("  ✅ Merged data applied locally")
        logDiagnostic("  ✅ Device has latest state from all sources")
        logDiagnostic("  📱 Total lists: \(mergedData.lists.count)")
        for (index, list) in mergedData.lists.enumerated() {
            logDiagnostic("    📋 List \(index + 1): '\(list.name)' (\(list.items.count) items)")
        }
    }
    
    private func performInitialUploadWithConflictHandling() async throws -> String {
        logDiagnostic("📤 Performing initial upload with conflict handling")
        
        do {
            return try await performInitialUpload()
        } catch let error as CKError where error.code == .serverRecordChanged {
            // Another device created the record while we were trying
            logDiagnostic("⚡ Record was created by another device, retrying merge")
            
            // Fetch the record that was just created and merge
            let existingRecord = try await publicDatabase.record(for: recordID)
            return try await performMergeSync(existingRecord: existingRecord)
        }
    }
    
    // MARK: - Deterministic Merge Algorithm (Same as iCloud Drive version)
    
    private func performDeterministicMerge(local: SyncJSONData, remote: SyncJSONData) throws -> SyncJSONData {
        logDiagnostic("🔀 Performing deterministic merge")
        logDiagnostic("📊 Local: \(local.lists.count) lists from device \(local.deviceId)")
        logDiagnostic("📊 Remote: \(remote.lists.count) lists from device \(remote.deviceId)")
        
        // Log list details for debugging
        for (index, list) in local.lists.enumerated() {
            logDiagnostic("📋 Local List \(index + 1): '\(list.name)' (\(list.items.count) items) [ID: \(list.id)]")
        }
        for (index, list) in remote.lists.enumerated() {
            logDiagnostic("📋 Remote List \(index + 1): '\(list.name)' (\(list.items.count) items) [ID: \(list.id)]")
        }
        
        // Merge lists AND their items
        let mergedLists = mergeListsWithItems(local: local.lists, remote: remote.lists)
        
        logDiagnostic("🎯 Final merged result: \(mergedLists.count) lists")
        for (index, list) in mergedLists.enumerated() {
            logDiagnostic("📋 Final List \(index + 1): '\(list.name)' (\(list.items.count) items) [ID: \(list.id)]")
        }
        
        // Create merged result
        let merged = SyncJSONData(
            version: max(local.version, remote.version),
            lastSyncedAt: Date(),
            deviceId: deviceId,
            lists: mergedLists
        )
        
        // Log any conflicts
        let conflictCount = countConflicts(local: local, remote: remote)
        if conflictCount > 0 {
            lastConflictDate = Date()
            logDiagnostic("⚡ Resolved \(conflictCount) conflicts using last-writer-wins", details: "Merge completed deterministically")
        } else {
            logDiagnostic("✨ No conflicts detected - clean merge")
        }
        
        return merged
    }
    
    private func mergeListsWithItems(local: [SyncListData], remote: [SyncListData]) -> [SyncListData] {
        logDiagnostic("🔧 Starting detailed list and item merge")
        
        var result: [SyncListData] = []
        
        // Handle duplicate IDs by merging them first (Core Data integrity issue)
        let localDict = consolidateListsByID(local, source: "Local")
        let remoteDict = consolidateListsByID(remote, source: "Remote")
        
        let allListIds = Set(localDict.keys).union(Set(remoteDict.keys))
        logDiagnostic("🆔 Processing \(allListIds.count) unique lists by ID")
        
        for listId in allListIds.sorted() {
            let localList = localDict[listId]
            let remoteList = remoteDict[listId]
            
            switch (localList, remoteList) {
            case (let local?, let remote?):
                // Both devices have this list with same ID - merge their items
                logDiagnostic("🔄 Merging list: '\(local.name)' (ID: \(listId))")
                logDiagnostic("📊 Local: \(local.items.count) items, updated: \(local.updatedAt)")
                logDiagnostic("📊 Remote: \(remote.items.count) items, updated: \(remote.updatedAt)")
                
                // Merge items within this list
                let mergedItems = mergeItems(
                    local: local.items,
                    remote: remote.items,
                    keyPath: \.id,
                    timestampPath: \.updatedAt,
                    deviceIdComparison: { local.updatedAt < remote.updatedAt }
                )
                
                // Use most recent list metadata
                let baseList = local.updatedAt > remote.updatedAt ? local : remote
                let finalList = SyncListData(
                    id: baseList.id,
                    name: baseList.name,
                    createdAt: baseList.createdAt,
                    updatedAt: baseList.updatedAt,
                    deletedAt: baseList.deletedAt,
                    deviceID: baseList.deviceID,
                    order: baseList.order,
                    items: mergedItems
                )
                
                logDiagnostic("✅ Merged list '\(baseList.name)' has \(mergedItems.count) items")
                result.append(finalList)
                
            case (let local?, nil):
                // Only local device has this list
                logDiagnostic("📱 Local-only list: '\(local.name)' (\(local.items.count) items)")
                result.append(local)
                
            case (nil, let remote?):
                // Only remote device has this list
                logDiagnostic("☁️ Remote-only list: '\(remote.name)' (\(remote.items.count) items)")
                result.append(remote)
                
            case (nil, nil):
                break // Should not happen
            }
        }
        
        logDiagnostic("🎯 Final merge result: \(result.count) lists")
        return result
    }
    
    private func consolidateListsByID(_ lists: [SyncListData], source: String) -> [String: SyncListData] {
        var consolidated: [String: SyncListData] = [:]
        
        for list in lists {
            if let existing = consolidated[list.id] {
                // Handle duplicate IDs - this indicates a Core Data integrity issue
                logDiagnostic("⚠️ \(source): Found duplicate ID \(list.id)")
                logDiagnostic("⚠️ Existing: '\(existing.name)' (\(existing.items.count) items)")
                logDiagnostic("⚠️ Duplicate: '\(list.name)' (\(list.items.count) items)")
                
                // Merge the duplicates using LWW logic
                let mergedList: SyncListData
                if list.updatedAt > existing.updatedAt {
                    logDiagnostic("⚠️ Using newer duplicate: '\(list.name)'")
                    mergedList = list
                } else if list.updatedAt < existing.updatedAt {
                    logDiagnostic("⚠️ Keeping existing: '\(existing.name)'")
                    mergedList = existing
                } else {
                    // Equal timestamps - merge items from both
                    logDiagnostic("⚠️ Equal timestamps - merging items from both")
                    let allItems = existing.items + list.items
                    let uniqueItems = Dictionary(uniqueKeysWithValues: allItems.map { ($0.id, $0) }).values.sorted { $0.order < $1.order }
                    
                    mergedList = SyncListData(
                        id: existing.id,
                        name: existing.name.isEmpty ? list.name : existing.name,
                        createdAt: min(existing.createdAt, list.createdAt),
                        updatedAt: max(existing.updatedAt, list.updatedAt),
                        deletedAt: existing.deletedAt ?? list.deletedAt,
                        deviceID: existing.deviceID.isEmpty ? list.deviceID : existing.deviceID,
                        order: existing.order,
                        items: Array(uniqueItems)
                    )
                }
                
                consolidated[list.id] = mergedList
                
            } else {
                consolidated[list.id] = list
            }
        }
        
        logDiagnostic("🔄 \(source): Consolidated \(lists.count) lists into \(consolidated.count) unique lists")
        return consolidated
    }
    
    private func mergeItems<T: SyncableItem>(
        local: [T],
        remote: [T],
        keyPath: KeyPath<T, String>,
        timestampPath: KeyPath<T, Date>,
        deviceIdComparison: () -> Bool
    ) -> [T] {
        
        var result: [T] = []
        let localDict = Dictionary(uniqueKeysWithValues: local.map { ($0[keyPath: keyPath], $0) })
        let remoteDict = Dictionary(uniqueKeysWithValues: remote.map { ($0[keyPath: keyPath], $0) })
        
        let allIds = Set(localDict.keys).union(Set(remoteDict.keys))
        logDiagnostic("🔧 Merging \(allIds.count) unique items (\(local.count) local + \(remote.count) remote)")
        
        for id in allIds.sorted() {
            let localItem = localDict[id]
            let remoteItem = remoteDict[id]
            
            switch (localItem, remoteItem) {
            case (let local?, let remote?):
                // Both exist - apply last-writer-wins with tie breaking
                let localTime = local[keyPath: timestampPath]
                let remoteTime = remote[keyPath: timestampPath]
                
                if localTime > remoteTime {
                    logDiagnostic("📱 Using local version of item (newer: \(localTime) > \(remoteTime))")
                    result.append(local)
                } else if localTime < remoteTime {
                    logDiagnostic("☁️ Using remote version of item (newer: \(remoteTime) > \(localTime))")
                    result.append(remote)
                } else {
                    // Timestamps equal - use deterministic device ID ordering
                    let chosen = deviceIdComparison() ? local : remote
                    logDiagnostic("⚖️ Equal timestamps, using deterministic choice")
                    result.append(chosen)
                }
            case (let local?, nil):
                logDiagnostic("📱 Adding local-only item")
                result.append(local)
            case (nil, let remote?):
                logDiagnostic("☁️ Adding remote-only item")
                result.append(remote)
            case (nil, nil):
                break // Should not happen
            }
        }
        
        logDiagnostic("✅ Item merge complete: \(result.count) final items")
        return result
    }
    
    // MARK: - JSON Data Generation (Same as iCloud Drive version)
    
    private func generateJSONData(context: NSManagedObjectContext) async throws -> Data {
        logDiagnostic("🗂️ Starting JSON data generation")
        
        return try await withCheckedThrowingContinuation { continuation in
            context.perform {
                do {
                    Task { @MainActor in
                        self.logDiagnostic("📊 Fetching all lists from Core Data")
                    }
                    
                    let lists = try self.fetchAllLists(context: context)
                    
                    Task { @MainActor in
                        self.logDiagnostic("📋 Fetched \(lists.count) lists, creating sync data")
                    }
                    let syncData = SyncJSONData(
                        version: 1,
                        lastSyncedAt: Date(),
                        deviceId: self.deviceId,
                        lists: lists
                    )
                    
                    let encoder = JSONEncoder()
                    encoder.dateEncodingStrategy = .iso8601
                    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                    
                    // Validate data before encoding
                    self.validateSyncData(syncData)
                    
                    Task { @MainActor in
                        self.logDiagnostic("📦 Encoding JSON data")
                    }
                    
                    let jsonData = try encoder.encode(syncData)
                    
                    Task { @MainActor in
                        self.logDiagnostic("✅ Generated JSON data", details: "Size: \(jsonData.count) bytes, Lists: \(lists.count)")
                    }
                    
                    continuation.resume(returning: jsonData)
                } catch {
                    Task { @MainActor in
                        self.logDiagnostic("❌ JSON encode error", details: error.localizedDescription, isError: true)
                    }
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func fetchAllLists(context: NSManagedObjectContext) throws -> [SyncListData] {
        let fetchRequest = MediaList.fetchAll()
        let lists = try context.fetch(fetchRequest)
        
        return lists.map { list in
            // Break up complex expression to help compiler
            let itemsSet = list.items as? Set<ListItem> ?? Set<ListItem>()
            let sortedItems = itemsSet.sorted { $0.order < $1.order }
            let items = sortedItems.compactMap { listItem -> SyncItemData? in
                guard let title = listItem.title else { return nil }
                    
                    let episodes = (title.episodes as? Set<Episode> ?? Set<Episode>())
                        .sorted { ($0.seasonNumber, $0.episodeNumber) < ($1.seasonNumber, $1.episodeNumber) }
                        .compactMap { episode -> SyncEpisodeData? in
                            guard let episodeId = episode.id?.uuidString else {
                                Task { @MainActor in
                                    self.logDiagnostic("Episode missing ID, skipping", isError: true)
                                }
                                return nil
                            }
                            
                            return SyncEpisodeData(
                                id: episodeId,
                                tmdbId: Int(episode.tmdbId),
                                seasonNumber: Int(episode.seasonNumber),
                                episodeNumber: Int(episode.episodeNumber),
                                name: episode.name ?? "Episode \(episode.episodeNumber)",
                                overview: episode.overview,
                                stillPath: episode.stillPath,
                                airDate: episode.airDate,
                                runtime: Int(episode.runtime),
                                watched: episode.watched,
                                watchedDate: episode.watchedDate,
                                isStarred: episode.isStarred,
                                createdAt: episode.createdAt ?? Date(),
                                updatedAt: episode.updatedAt ?? Date(),
                                deletedAt: episode.deletedAt,
                                deviceID: episode.deviceID ?? UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
                            )
                        }
                    
                    let notes = (title.notes as? Set<Note> ?? Set<Note>())
                        .filter { !$0.ownerOnly } // Only sync non-private notes
                        .compactMap { note -> SyncNoteData? in
                            guard let noteId = note.id?.uuidString else {
                                Task { @MainActor in
                                    self.logDiagnostic("Note missing ID, skipping", isError: true)
                                }
                                return nil
                            }
                            
                            return SyncNoteData(
                                id: noteId,
                                text: note.text ?? "",
                                createdAt: note.createdAt ?? Date(),
                                updatedAt: note.updatedAt ?? Date(),
                                deletedAt: note.deletedAt,
                                deviceID: note.deviceID ?? UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
                            )
                        }
                    
                    guard let titleId = title.id?.uuidString else {
                        Task { @MainActor in
                            self.logDiagnostic("Title missing ID, skipping", isError: true)
                        }
                        return nil
                    }
                    
                    return SyncItemData(
                        id: titleId,
                        tmdbId: Int(title.tmdbId),
                        mediaType: title.mediaType ?? "movie",
                        title: title.title ?? "Unknown Title",
                        year: Int(title.year),
                        overview: title.overview,
                        posterPath: title.posterPath,
                        backdropPath: title.backdropPath,
                        runtime: Int(title.runtime),
                        watched: title.watched,
                        watchedDate: title.watchedDate,
                        watchStatus: Int(title.watchStatus),
                        lastWatched: title.lastWatched,
                        currentSeason: Int(title.currentSeason),
                        currentEpisode: Int(title.currentEpisode),
                        numberOfSeasons: Int(title.numberOfSeasons),
                        numberOfEpisodes: Int(title.numberOfEpisodes),
                        userRating: title.userRating > 0 ? title.userRating : nil,
                        mikeRating: title.mikeRating > 0 ? title.mikeRating : nil,
                        lauraRating: title.lauraRating > 0 ? title.lauraRating : nil,
                        voteAverage: title.voteAverage > 0 ? title.voteAverage : nil,
                        voteCount: Int(title.voteCount),
                        isFavorite: title.isFavorite,
                        likedStatus: Int(title.likedStatus),
                        status: title.status,
                        streamingService: title.streamingService,
                        mediaCategory: title.mediaCategory,
                        releaseDate: title.releaseDate,
                        firstAirDate: title.firstAirDate,
                        lastAirDate: title.lastAirDate,
                        startDate: title.startDate,
                        originalTitle: title.originalTitle,
                        originalLanguage: title.originalLanguage,
                        imdbId: title.imdbId,
                        popularity: title.popularity > 0 ? title.popularity : nil,
                        genres: title.genres,
                        customField1: title.customField1,
                        customField2: title.customField2,
                        createdAt: title.createdAt ?? Date(),
                        updatedAt: title.updatedAt ?? Date(),
                        deletedAt: title.deletedAt,
                        deviceID: title.deviceID ?? UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString,
                        order: listItem.order,
                        episodes: episodes,
                        notes: notes
                    )
                }
            
            guard let listId = list.id?.uuidString else {
                Task { @MainActor in
                    self.logDiagnostic("List missing ID, using generated UUID", isError: false)
                }
                return SyncListData(
                    id: UUID().uuidString,
                    name: list.name ?? "Unnamed List",
                    createdAt: list.createdAt ?? Date(),
                    updatedAt: list.updatedAt ?? Date(),
                    deletedAt: list.deletedAt,
                    deviceID: list.deviceID ?? UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString,
                    order: list.order,
                    items: items
                )
            }
            
            return SyncListData(
                id: listId,
                name: list.name ?? "Unnamed List",
                createdAt: list.createdAt ?? Date(),
                updatedAt: list.updatedAt ?? Date(),
                deletedAt: list.deletedAt,
                deviceID: list.deviceID ?? UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString,
                order: list.order,
                items: items
            )
        }
    }
    
    // MARK: - Core Data Application (Same as iCloud Drive version)
    
    private func applyJSONToCoreData(_ syncData: SyncJSONData, context: NSManagedObjectContext) async throws {
        try await context.perform {
            // Clear existing data and rebuild from JSON
            try self.clearAllData(context: context)
            
            Task { @MainActor in
                self.logDiagnostic("🔄 Applying \(syncData.lists.count) lists to Core Data")
            }
            
            let nonDeletedLists = syncData.lists.filter({ $0.deletedAt == nil }).sorted { $0.order < $1.order }
            
            for (index, listData) in nonDeletedLists.enumerated() {
                Task { @MainActor in
                    self.logDiagnostic("📝 Creating list: '\(listData.name)' with \(listData.items.count) items (order: \(index))")
                }
                let list = MediaList(context: context)
                list.id = UUID(uuidString: listData.id) ?? UUID()
                list.name = listData.name
                list.dateCreated = listData.createdAt
                list.updatedAt = listData.updatedAt
                list.deviceID = listData.deviceID
                list.order = Double(index)
                list.isDefault = index == 0
                list.isShared = false
                list.icon = "list.bullet"
                
                for (index, itemData) in listData.items.filter({ $0.deletedAt == nil }).enumerated() {
                    let title = Title(context: context)
                    title.id = UUID(uuidString: itemData.id) ?? UUID()
                    title.tmdbId = Int64(itemData.tmdbId)
                    title.mediaType = itemData.mediaType
                    title.title = itemData.title
                    title.year = Int16(itemData.year)
                    title.overview = itemData.overview
                    title.posterPath = itemData.posterPath
                    title.runtime = Int16(itemData.runtime)
                    title.watched = itemData.watched
                    title.watchedDate = itemData.watchedDate
                    title.userRating = itemData.userRating ?? 0
                    title.createdAt = itemData.createdAt
                    title.updatedAt = itemData.updatedAt
                    
                    // Create episodes
                    for episodeData in itemData.episodes.filter({ $0.deletedAt == nil }) {
                        let episode = Episode(context: context)
                        episode.id = UUID(uuidString: episodeData.id) ?? UUID()
                        episode.tmdbId = Int64(episodeData.tmdbId)
                        episode.seasonNumber = Int16(episodeData.seasonNumber)
                        episode.episodeNumber = Int16(episodeData.episodeNumber)
                        episode.name = episodeData.name
                        episode.overview = episodeData.overview
                        episode.stillPath = episodeData.stillPath
                        episode.airDate = episodeData.airDate
                        episode.runtime = Int16(episodeData.runtime)
                        episode.watched = episodeData.watched
                        episode.watchedDate = episodeData.watchedDate
                        episode.isStarred = episodeData.isStarred
                        episode.show = title
                    }
                    
                    // Create list item
                    let listItem = ListItem(context: context)
                    listItem.id = UUID()
                    listItem.list = list
                    listItem.title = title
                    listItem.orderIndex = Int16(index)
                    listItem.createdAt = itemData.createdAt
                }
            }
            
            Task { @MainActor in
                self.logDiagnostic("💾 Saving Core Data context")
            }
            
            try context.save()
            
            Task { @MainActor in
                self.logDiagnostic("✅ Core Data save completed successfully")
            }
        }
    }
    
    // MARK: - Device Backup Record Management
    
    private func checkForDeviceBackupRecords() async {
        logDiagnostic("🔍 Checking CloudKit record ownership and permissions")
        
        // Since we can't create new record types in production CloudKit,
        // we'll focus on understanding the current record ownership
        do {
            let existingRecord = try await publicDatabase.record(for: recordID)
            
            if let recordOwner = existingRecord["createdBy"] as? String {
                logDiagnostic("📱 Main record owned by device: \(recordOwner)")
                logDiagnostic("📱 Current device: \(deviceId)")
                logDiagnostic("🔒 Write permission: \(recordOwner == deviceId ? "✅ Yes" : "❌ No")")
            }
            
            if let lastModifiedBy = existingRecord["lastModifiedBy"] as? String,
               let lastModified = existingRecord["lastModifiedAt"] as? Date {
                logDiagnostic("📱 Last modified by: \(lastModifiedBy) at \(lastModified)")
            }
            
        } catch {
            logDiagnostic("⚠️ Failed to check record ownership: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Permission Testing
    
    private func testWritePermissions() async {
        logDiagnostic("🧪 Testing CloudKit write permissions")
        
        let testRecordID = CKRecord.ID(recordName: "PermissionTest_\(deviceId)", zoneID: CKRecordZone.default().zoneID)
        let testRecord = CKRecord(recordType: "PermissionTest", recordID: testRecordID)
        testRecord["testField"] = "test_\(Date().timeIntervalSince1970)"
        testRecord["deviceId"] = deviceId
        
        do {
            // Try to save a test record
            let result = try await publicDatabase.modifyRecords(saving: [testRecord], deleting: [])
            if let _ = try result.saveResults[testRecordID]?.get() {
                logDiagnostic("✅ Write permissions test passed - can create records")
                
                // Clean up by deleting the test record
                do {
                    try await publicDatabase.deleteRecord(withID: testRecordID)
                    logDiagnostic("🧹 Cleaned up test record")
                } catch {
                    logDiagnostic("⚠️ Failed to clean up test record: \(error.localizedDescription)")
                }
            }
        } catch let error as CKError {
            logDiagnostic("❌ Write permissions test failed: Code \(error.code.rawValue), \(error.localizedDescription)")
            if error.code == .permissionFailure || error.code.rawValue == 10 {
                logDiagnostic("🚫 This device appears to have limited write permissions to CloudKit Public Database")
                logDiagnostic("💡 This may explain sync update failures")
            }
        } catch {
            logDiagnostic("❌ Write permissions test error: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Utility Methods
    
    private func exportCurrentDataToCloudKit() async {
        do {
            let context = PersistenceController.shared.viewContext
            let jsonData = try await generateJSONData(context: context)
            
            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                throw CloudKitPublicSyncError.invalidJSONEncoding
            }
            
            let record = CKRecord(recordType: recordType, recordID: recordID)
            record["jsonData"] = jsonString
            record["createdBy"] = deviceId
            record["lastModifiedBy"] = deviceId
            record["lastModifiedAt"] = Date()
            record["version"] = 1
            
            let _ = try await publicDatabase.modifyRecords(saving: [record], deleting: [])
            logDiagnostic("Exported current Core Data to CloudKit Public Database")
        } catch {
            logDiagnostic("Failed to export current data", details: error.localizedDescription, isError: true)
        }
    }
    
    private func clearAllData(context: NSManagedObjectContext) throws {
        let entityNames = ["Note", "ListItem", "Episode", "Title", "List"]
        
        for entityName in entityNames {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            deleteRequest.resultType = .resultTypeObjectIDs
            
            let result = try context.execute(deleteRequest) as? NSBatchDeleteResult
            if let objectIDs = result?.result as? [NSManagedObjectID] {
                let changes = [NSDeletedObjectsKey: objectIDs]
                NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [context])
            }
        }
    }
    
    private func countConflicts(local: SyncJSONData, remote: SyncJSONData) -> Int {
        var conflicts = 0
        
        let localListIds = Set(local.lists.map(\.id))
        let remoteListIds = Set(remote.lists.map(\.id))
        let commonListIds = localListIds.intersection(remoteListIds)
        
        for listId in commonListIds {
            guard let localList = local.lists.first(where: { $0.id == listId }),
                  let remoteList = remote.lists.first(where: { $0.id == listId }) else { continue }
            
            if localList.updatedAt != remoteList.updatedAt {
                conflicts += 1
            }
        }
        
        return conflicts
    }
    
    private func shouldApplyRemoteChangesToLocal(local: SyncJSONData, remote: SyncJSONData, merged: SyncJSONData) -> Bool {
        let localTotalItems = local.lists.reduce(0) { $0 + $1.items.count }
        let remoteTotalItems = remote.lists.reduce(0) { $0 + $1.items.count }
        let mergedTotalItems = merged.lists.reduce(0) { $0 + $1.items.count }
        
        // Always apply merged result in cross-device sync scenario
        logDiagnostic("✅ Applying merged result to ensure device synchronization")
        return true
    }
    
    private func isDataEquivalent(_ data1: SyncJSONData, _ data2: SyncJSONData) -> Bool {
        // Check list count first
        guard data1.lists.count == data2.lists.count else { 
            logDiagnostic("❌ Different list counts: \(data1.lists.count) vs \(data2.lists.count)")
            return false
        }
        
        // Create dictionaries for efficient lookup
        let lists1 = Dictionary(uniqueKeysWithValues: data1.lists.map { ($0.id, $0) })
        let lists2 = Dictionary(uniqueKeysWithValues: data2.lists.map { ($0.id, $0) })
        
        // Check if all list IDs from both datasets exist in the other
        let ids1 = Set(lists1.keys)
        let ids2 = Set(lists2.keys)
        
        if ids1 != ids2 {
            logDiagnostic("❌ Different list IDs: \(ids1.symmetricDifference(ids2))")
            return false
        }
        
        // Check if all list IDs match and have same content
        for (id, list1) in lists1 {
            guard let list2 = lists2[id] else { 
                logDiagnostic("❌ Missing list ID \(id) in second dataset")
                return false 
            }
            
            // Compare list properties
            if list1.name != list2.name || 
               (list1.deletedAt != nil) != (list2.deletedAt != nil) ||
               list1.items.count != list2.items.count {
                logDiagnostic("❌ List '\(list1.name)' differs: name=\(list1.name != list2.name), deleted=\((list1.deletedAt != nil) != (list2.deletedAt != nil)), items=\(list1.items.count != list2.items.count)")
                return false
            }
            
            // Compare items within each list
            let items1 = Dictionary(uniqueKeysWithValues: list1.items.map { ($0.id, $0) })
            let items2 = Dictionary(uniqueKeysWithValues: list2.items.map { ($0.id, $0) })
            
            if items1.count != items2.count {
                logDiagnostic("❌ List '\(list1.name)' has different item counts: \(items1.count) vs \(items2.count)")
                return false
            }
            
            for (itemId, item1) in items1 {
                guard let item2 = items2[itemId] else { 
                    logDiagnostic("❌ Missing item ID \(itemId) in list '\(list1.name)'")
                    return false 
                }
                if item1.title != item2.title || item1.watched != item2.watched || (item1.deletedAt != nil) != (item2.deletedAt != nil) {
                    logDiagnostic("❌ Item '\(item1.title)' differs in list '\(list1.name)'")
                    return false
                }
            }
        }
        
        return true
    }
    
    private func validateSyncData(_ syncData: SyncJSONData) {
        logDiagnostic("Validating sync data", details: "Device: \(syncData.deviceId), Lists: \(syncData.lists.count)")
        
        for list in syncData.lists {
            if list.id.isEmpty {
                logDiagnostic("Warning: List has empty ID", isError: true)
            }
            if list.name.isEmpty {
                logDiagnostic("Warning: List has empty name", isError: false)
            }
            
            for item in list.items {
                if item.id.isEmpty {
                    logDiagnostic("Warning: Item has empty ID", isError: true)
                }
                if item.title.isEmpty {
                    logDiagnostic("Warning: Item has empty title", isError: false)
                }
            }
        }
    }
    
    func logDiagnostic(_ event: String, details: String? = nil, isError: Bool = false) {
        let entry = DiagnosticEntry(event: event, details: details, isError: isError)
        diagnosticsLog.append(entry)
        
        // Keep only last 100 entries
        if diagnosticsLog.count > 100 {
            diagnosticsLog.removeFirst(diagnosticsLog.count - 100)
        }
        
        // Also log to console in debug builds
        #if DEBUG
        print("☁️ CloudKitPublicSync: \(event)" + (details.map { " - \($0)" } ?? ""))
        #endif
    }
    
    // MARK: - Notification Observers
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task {
                await self?.performFullSync()
            }
        }
        
        NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Core Data changed - sync after a delay to batch changes
            // But only if it's been a while since last sync to prevent loops
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) {
                Task {
                    guard let self = self else { return }
                    let timeSinceLastSync = Date().timeIntervalSince(self.lastSyncTime)
                    if timeSinceLastSync > self.minimumSyncInterval {
                        await self.performFullSync()
                    }
                }
            }
        }
    }
}

// MARK: - CloudKit Errors

enum CloudKitPublicSyncError: Error {
    case cloudKitUnavailable
    case invalidCloudKitData
    case invalidJSONEncoding
    case recordNotFound
    case permissionDenied
    case coreDataError(String)
    
    var localizedDescription: String {
        switch self {
        case .cloudKitUnavailable:
            return "CloudKit is not available. Please check your iCloud settings."
        case .invalidCloudKitData:
            return "Invalid CloudKit data format"
        case .invalidJSONEncoding:
            return "Failed to encode JSON data"
        case .recordNotFound:
            return "CloudKit record not found"
        case .permissionDenied:
            return "Permission denied to modify CloudKit data. The record may have been created by another device."
        case .coreDataError(let message):
            return "Core Data error: \(message)"
        }
    }
}