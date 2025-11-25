//
//  iCloudSyncService.swift
//  MediaWatch
//
//  Automatic sync via iCloud Drive JSON file
//

import Foundation
import CoreData
import Combine

class iCloudSyncService: ObservableObject {
    static let shared = iCloudSyncService()
    
    private let backupService = BackupService()
    private let persistenceController = PersistenceController.shared
    private var fileMonitor: DispatchSourceFileSystemObject?
    private var cancellables = Set<AnyCancellable>()
    
    @Published var isEnabled = true
    @Published var lastSyncDate: Date?
    @Published var syncStatus: SyncStatus = .idle
    
    enum SyncStatus {
        case idle
        case syncing
        case error(String)
        case success
    }
    
    private var iCloudDriveURL: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents")
            .appendingPathComponent("MediaWatch_Sync.json")
    }
    
    init() {
        setupFileMonitoring()
        startPeriodicSync()
    }
    
    // MARK: - Public Methods
    
    func enableSync() {
        isEnabled = true
        Task {
            do {
                try await uploadCurrentData()
            } catch {
                await MainActor.run {
                    syncStatus = .error(error.localizedDescription)
                }
            }
        }
    }
    
    func disableSync() {
        isEnabled = false
        stopFileMonitoring()
    }
    
    func forceSync() {
        guard isEnabled else { return }
        Task {
            await performFullSync()
        }
    }
    
    // MARK: - Core Sync Logic
    
    @MainActor
    private func performFullSync() async {
        guard isEnabled, let iCloudURL = iCloudDriveURL else { return }
        
        syncStatus = .syncing
        
        do {
            if FileManager.default.fileExists(atPath: iCloudURL.path) {
                _ = try FileManager.default.attributesOfItem(atPath: iCloudURL.path)[.modificationDate] as? Date ?? Date.distantPast
                _ = lastSyncDate ?? Date.distantPast
                
                // Always merge - don't overwrite everything
                try await mergeWithRemoteData()
            } else {
                // No remote file - upload current data
                try await uploadCurrentData()
            }
            
            lastSyncDate = Date()
            syncStatus = .success
            
        } catch {
            syncStatus = .error(error.localizedDescription)
            print("Sync error: \(error)")
        }
    }
    
    private func uploadCurrentData() async throws {
        guard let iCloudURL = iCloudDriveURL else { 
            throw SyncError.iCloudNotAvailable 
        }
        
        // Ensure Documents directory exists
        try FileManager.default.createDirectory(
            at: iCloudURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        
        // Export current data
        let jsonData = try await backupService.createBackup(context: persistenceController.viewContext)
        
        // Write to iCloud Drive
        try jsonData.write(to: iCloudURL)
        
        print("✅ Uploaded data to iCloud Drive")
    }
    
    private func mergeWithRemoteData() async throws {
        guard let iCloudURL = iCloudDriveURL else { 
            throw SyncError.iCloudNotAvailable 
        }
        
        // Get both local and remote data
        let localData = try await backupService.createBackup(context: persistenceController.viewContext)
        let localBackup = try JSONDecoder().decode(BackupService.BackupData.self, from: localData)
        
        let remoteData = try Data(contentsOf: iCloudURL)
        let remoteBackup = try JSONDecoder().decode(BackupService.BackupData.self, from: remoteData)
        
        // Merge the data (prefer most recent modifications)
        let mergedData = try await mergeBackupData(local: localBackup, remote: remoteBackup)
        
        // Apply merged data back to Core Data
        let mergedJson = try JSONEncoder().encode(mergedData)
        try await backupService.restoreBackup(from: mergedJson, context: persistenceController.viewContext)
        
        // Upload the merged result
        try mergedJson.write(to: iCloudURL)
        
        print("✅ Merged local and remote data")
    }
    
    private func mergeBackupData(local: BackupService.BackupData, remote: BackupService.BackupData) async throws -> BackupService.BackupData {
        // Create dictionaries for efficient lookups
        let localLists: [String: BackupService.ListBackup] = Dictionary(uniqueKeysWithValues: local.lists.map { ($0.id, $0) })
        let localTitles: [String: BackupService.TitleBackup] = Dictionary(uniqueKeysWithValues: local.titles.map { ($0.id, $0) })
        let localEpisodes: [String: BackupService.EpisodeBackup] = Dictionary(uniqueKeysWithValues: local.episodes.map { ($0.id, $0) })
        let localNotes: [String: BackupService.NoteBackup] = Dictionary(uniqueKeysWithValues: local.notes.map { ($0.id, $0) })
        
        var mergedLists: [BackupService.ListBackup] = []
        var mergedTitles: [BackupService.TitleBackup] = []
        var mergedEpisodes: [BackupService.EpisodeBackup] = []
        var mergedNotes: [BackupService.NoteBackup] = []
        
        // Merge Lists - prefer most recently modified
        let allListIds = Set(local.lists.map { $0.id } + remote.lists.map { $0.id })
        for listId in allListIds {
            let localList = localLists[listId]
            let remoteList = remote.lists.first { $0.id == listId }
            
            if let local = localList, let remote = remoteList {
                // Both exist - prefer most recent
                mergedLists.append(local.dateModified > remote.dateModified ? local : remote)
            } else if let local = localList {
                // Only local exists
                mergedLists.append(local)
            } else if let remote = remoteList {
                // Only remote exists
                mergedLists.append(remote)
            }
        }
        
        // Merge Titles - same logic
        let allTitleIds = Set(local.titles.map { $0.id } + remote.titles.map { $0.id })
        for titleId in allTitleIds {
            let localTitle = localTitles[titleId]
            let remoteTitle = remote.titles.first { $0.id == titleId }
            
            if let local = localTitle, let remote = remoteTitle {
                // Both exist - prefer most recent
                mergedTitles.append(local.dateModified > remote.dateModified ? local : remote)
            } else if let local = localTitle {
                mergedTitles.append(local)
            } else if let remote = remoteTitle {
                mergedTitles.append(remote)
            }
        }
        
        // Merge Episodes - same logic
        let allEpisodeIds = Set(local.episodes.map { $0.id } + remote.episodes.map { $0.id })
        for episodeId in allEpisodeIds {
            let localEpisode = localEpisodes[episodeId]
            let remoteEpisode = remote.episodes.first { $0.id == episodeId }
            
            if let local = localEpisode, let remote = remoteEpisode {
                // For episodes, prefer most recent watchedDate if different
                if local.watched != remote.watched {
                    let localWatchDate = local.watchedDate ?? Date.distantPast
                    let remoteWatchDate = remote.watchedDate ?? Date.distantPast
                    mergedEpisodes.append(localWatchDate > remoteWatchDate ? local : remote)
                } else {
                    mergedEpisodes.append(local)
                }
            } else if let local = localEpisode {
                mergedEpisodes.append(local)
            } else if let remote = remoteEpisode {
                mergedEpisodes.append(remote)
            }
        }
        
        // Merge Notes - prefer most recent
        let allNoteIds = Set(local.notes.map { $0.id } + remote.notes.map { $0.id })
        for noteId in allNoteIds {
            let localNote = localNotes[noteId]
            let remoteNote = remote.notes.first { $0.id == noteId }
            
            if let local = localNote, let remote = remoteNote {
                mergedNotes.append(local.dateModified > remote.dateModified ? local : remote)
            } else if let local = localNote {
                mergedNotes.append(local)
            } else if let remote = remoteNote {
                mergedNotes.append(remote)
            }
        }
        
        // Use local preferences (since PreferencesBackup doesn't have timestamp)
        let mergedPreferences = local.preferences ?? remote.preferences
        
        return BackupService.BackupData(
            version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            exportDate: Date(),
            lists: mergedLists,
            titles: mergedTitles,
            episodes: mergedEpisodes,
            notes: mergedNotes,
            preferences: mergedPreferences
        )
    }
    
    // MARK: - File Monitoring
    
    private func setupFileMonitoring() {
        guard let iCloudURL = iCloudDriveURL else { return }
        
        // Monitor the Documents directory for changes
        let descriptor = open(iCloudURL.deletingLastPathComponent().path, O_EVTONLY)
        guard descriptor != -1 else { return }
        
        fileMonitor = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: .write,
            queue: DispatchQueue.global(qos: .background)
        )
        
        fileMonitor?.setEventHandler { [weak self] in
            Task {
                await self?.performFullSync()
            }
        }
        
        fileMonitor?.setCancelHandler {
            close(descriptor)
        }
        
        fileMonitor?.resume()
    }
    
    private func stopFileMonitoring() {
        fileMonitor?.cancel()
        fileMonitor = nil
    }
    
    // MARK: - Periodic Sync
    
    private func startPeriodicSync() {
        Timer.publish(every: 30, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard self?.isEnabled == true else { return }
                Task {
                    await self?.performFullSync()
                }
            }
            .store(in: &cancellables)
    }
}


enum SyncError: Error {
    case iCloudNotAvailable
    case syncDisabled
    case fileNotFound
    
    var localizedDescription: String {
        switch self {
        case .iCloudNotAvailable:
            return "iCloud Drive is not available"
        case .syncDisabled:
            return "Sync is disabled"
        case .fileNotFound:
            return "Sync file not found"
        }
    }
}