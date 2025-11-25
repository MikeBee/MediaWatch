//
//  CloudKitLWWSyncAdapter.swift
//  MediaWatch
//
//  Adapter to integrate LWW sync with your existing CloudKit Public Database service
//  Provides Cross-Apple ID sync support using the LWW pattern
//

import Foundation
import CloudKit
import CoreData
import UIKit
import Combine

@MainActor
final class CloudKitLWWSyncAdapter: ObservableObject {
    
    // MARK: - Dependencies
    
    private let lwwSyncService = LWWSyncService.shared
    private let cloudKitService = CloudKitPublicSyncService.shared
    
    // MARK: - Published Properties
    
    @Published var isEnabled: Bool {
        didSet {
            cloudKitService.isEnabled = isEnabled
        }
    }
    
    @Published var syncStatus: SyncStatus = .idle
    @Published var lastSyncDate: Date?
    @Published var crossAppleIDSyncEnabled = true
    
    enum SyncStatus {
        case idle
        case syncing
        case success(String)
        case error(String)
    }
    
    // MARK: - Initialization
    
    init() {
        self.isEnabled = cloudKitService.isEnabled
        
        // Observe CloudKit sync status
        cloudKitService.$syncStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.handleCloudKitStatus(status)
            }
            .store(in: &cancellables)
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Public API
    
    /// Enable LWW sync with CloudKit Public Database for Cross-Apple ID support
    func enableSync() async {
        guard lwwSyncService.isFreshInstall else {
            syncStatus = .error("LWW sync requires fresh install")
            return
        }
        
        syncStatus = .syncing
        
        do {
            // Enable CloudKit sync
            await cloudKitService.enableSync()
            
            // Perform initial LWW sync
            try await performLWWSync()
            
            syncStatus = .success("Cross-Apple ID sync enabled")
            
        } catch {
            syncStatus = .error("Failed to enable sync: \(error.localizedDescription)")
        }
    }
    
    /// Disable LWW sync
    func disableSync() async {
        await cloudKitService.disableSync()
        isEnabled = false
        syncStatus = .idle
    }
    
    /// Perform manual sync
    func forceSync() async {
        guard isEnabled else { return }
        
        syncStatus = .syncing
        
        do {
            try await performLWWSync()
            syncStatus = .success("Sync completed")
            lastSyncDate = Date()
        } catch {
            syncStatus = .error("Sync failed: \(error.localizedDescription)")
        }
    }
    
    // MARK: - LWW Sync Integration
    
    private func performLWWSync() async throws {
        // Step 1: Generate local LWW data
        let localData = try await lwwSyncService.generateLocalSyncData()
        
        // Step 2: Convert to CloudKit format and upload
        try await uploadLWWDataToCloudKit(localData)
        
        // Step 3: Fetch remote LWW data from CloudKit
        let remoteData = try await fetchLWWDataFromCloudKit()
        
        // Step 4: Perform LWW merge
        let mergeResult = try await lwwSyncService.mergeWithLWW(remoteData: remoteData)
        
        print("✅ LWW Sync completed - resolved \(mergeResult.conflictsResolved) conflicts")
    }
    
    // MARK: - CloudKit Integration
    
    private func uploadLWWDataToCloudKit(_ data: SyncJSONData) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        let jsonData = try encoder.encode(data)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw CloudKitLWWSyncError.invalidJSONEncoding
        }
        
        // Create CloudKit record with LWW data
        let container = CKContainer(identifier: "iCloud.reasonality.MediaShows")
        let database = container.publicCloudDatabase
        let recordID = CKRecord.ID(recordName: "LWWMediaData", zoneID: CKRecordZone.default().zoneID)
        
        let record = CKRecord(recordType: "LWWMediaDataV2", recordID: recordID)
        record["jsonData"] = jsonString
        record["schemaVersion"] = "2.0"
        record["deviceID"] = data.deviceId
        record["lastModified"] = Date()
        record["dataVersion"] = data.version
        
        let _ = try await database.modifyRecords(saving: [record], deleting: [])
    }
    
    private func fetchLWWDataFromCloudKit() async throws -> SyncJSONData {
        let container = CKContainer(identifier: "iCloud.reasonality.MediaShows")
        let database = container.publicCloudDatabase
        let recordID = CKRecord.ID(recordName: "LWWMediaData", zoneID: CKRecordZone.default().zoneID)
        
        do {
            let record = try await database.record(for: recordID)
            
            guard let jsonString = record["jsonData"] as? String,
                  let jsonData = jsonString.data(using: .utf8) else {
                throw CloudKitLWWSyncError.invalidCloudKitData
            }
            
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            return try decoder.decode(SyncJSONData.self, from: jsonData)
            
        } catch let error as CKError where error.code == .unknownItem {
            // No remote data yet, return empty structure
            return SyncJSONData(
                version: 1,
                lastSyncedAt: Date(),
                deviceId: lwwSyncService.publicDeviceID,
                lists: []
            )
        }
    }
    
    // MARK: - CloudKit Status Handling
    
    private func handleCloudKitStatus(_ status: CloudKitPublicSyncService.SyncStatus) {
        switch status {
        case .idle:
            if case .error = syncStatus {
                // Keep error state
            } else {
                syncStatus = .idle
            }
        case .syncing:
            syncStatus = .syncing
        case .success(let message):
            syncStatus = .success(message)
        case .error(let message):
            syncStatus = .error(message)
        case .cloudKitUnavailable:
            syncStatus = .error("CloudKit unavailable")
        case .migrating:
            syncStatus = .syncing
        case .readOnlyMode(let message):
            syncStatus = .success("Read-Only: \(message)")
        }
    }
    
    // MARK: - Cross-Apple ID Features
    
    /// Check if cross-Apple ID sync is properly configured
    var isCrossAppleIDSyncReady: Bool {
        return isEnabled && lwwSyncService.isFreshInstall && crossAppleIDSyncEnabled
    }
    
    /// Get sync statistics for monitoring
    func getSyncStatistics() -> LWWSyncStatistics {
        return LWWSyncStatistics(
            lastSyncDate: lastSyncDate,
            isEnabled: isEnabled,
            deviceID: lwwSyncService.publicDeviceID,
            conflictsResolved: lwwSyncService.conflictsResolved,
            isCrossAppleIDEnabled: crossAppleIDSyncEnabled,
            isFreshInstall: lwwSyncService.isFreshInstall
        )
    }
    
    /// Clear all sync data (for troubleshooting)
    func clearSyncData() async {
        await cloudKitService.clearSyncCache()
        
        // Reset LWW metadata
        UserDefaults.standard.removeObject(forKey: "lww_fresh_install")
        UserDefaults.standard.removeObject(forKey: "lww_device_id")
        UserDefaults.standard.removeObject(forKey: "lww_install_date")
        
        lastSyncDate = nil
        syncStatus = .idle
    }
}

// MARK: - Supporting Types

struct LWWSyncStatistics {
    let lastSyncDate: Date?
    let isEnabled: Bool
    let deviceID: String
    let conflictsResolved: Int
    let isCrossAppleIDEnabled: Bool
    let isFreshInstall: Bool
    
    var statusMessage: String {
        if !isEnabled {
            return "Sync disabled"
        } else if !isFreshInstall {
            return "Requires fresh install"
        } else if !isCrossAppleIDEnabled {
            return "Cross-Apple ID sync disabled"
        } else if let lastSync = lastSyncDate {
            return "Last sync: \(lastSync.formatted(.relative(presentation: .named)))"
        } else {
            return "Ready to sync"
        }
    }
}

enum CloudKitLWWSyncError: Error, LocalizedError {
    case invalidJSONEncoding
    case invalidCloudKitData
    case freshInstallRequired
    
    var errorDescription: String? {
        switch self {
        case .invalidJSONEncoding:
            return "Failed to encode sync data"
        case .invalidCloudKitData:
            return "Invalid CloudKit data format"
        case .freshInstallRequired:
            return "Fresh install required for LWW sync"
        }
    }
}

// MARK: - Extensions for Cross-Apple ID Sync

extension LWWSyncService {
    /// Expose deviceID for CloudKit adapter
    var publicDeviceID: String {
        return currentDeviceID
    }
}

// MARK: - Additional SafeGuards for iCloud Drive Integration

extension ICloudDriveJSONSyncService {
    /// Enhanced sync with checksum verification and timestamp safeguards
    func syncWithSafeguards(remoteData: SyncJSONData, isInitialSync: Bool = false) async throws {
        let localData = try await generateLocalSyncData()
        
        // Checksum comparison to detect changes
        if !isInitialSync && !remoteData.hasContentChanges(comparedTo: localData) {
            logDiagnostic("📊 No content changes detected via checksum - skipping sync")
            return
        }
        
        // Timestamp safeguard - only apply if remote is newer or initial sync
        if !isInitialSync {
            let shouldApplyRemote = remoteData.lastSyncedAt > localData.lastSyncedAt
            if !shouldApplyRemote {
                logDiagnostic("⏱️ Remote data is older - not applying changes")
                return
            }
        }
        
        // Apply the sync with LWW merge logic
        try await performSafeSync(with: remoteData)
    }
    
    private func performSafeSync(with remoteData: SyncJSONData) async throws {
        let lwwService = LWWSyncService.shared
        let mergeResult = try await lwwService.mergeWithLWW(remoteData: remoteData)
        
        logDiagnostic("✅ Safe sync completed", details: "Resolved \(mergeResult.conflictsResolved) conflicts")
        
        lastSyncDate = Date()
        if mergeResult.conflictsResolved > 0 {
            lastConflictDate = Date()
        }
    }
}