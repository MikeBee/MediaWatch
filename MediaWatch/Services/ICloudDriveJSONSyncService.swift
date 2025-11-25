//
//  ICloudDriveJSONSyncService.swift
//  MediaWatch
//
//  Robust iCloud Drive JSON file sync with conflict resolution
//  Does NOT use CloudKit - uses iCloud Drive Ubiquity container
//

import Foundation
import CoreData
import Combine
import UIKit

@MainActor
final class ICloudDriveJSONSyncService: NSObject, ObservableObject {
    
    // MARK: - Shared Instance
    
    static let shared = ICloudDriveJSONSyncService()
    
    // MARK: - Published Properties
    
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "iCloudDriveJSONSync.enabled")
            // Dispatch to background to prevent UI freezing
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
    
    // MARK: - Types
    
    enum SyncStatus: Equatable {
        case idle
        case syncing
        case success(String)
        case error(String)
        case iCloudUnavailable
        case migrating
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
    
    private let syncQueue = DispatchQueue(label: "icloud-drive-json-sync", qos: .utility)
    private let fileManager = FileManager.default
    private var deviceId: String {
        return DeviceIdentifier.shared.deviceID
    }
    
    private var fileCoordinator: NSFileCoordinator?
    private var filePresenter: SyncFilePresenter?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var cancellables = Set<AnyCancellable>()
    private var lastSyncTime: Date = Date.distantPast
    private let minimumSyncInterval: TimeInterval = 60.0 // Minimum 60 seconds between syncs
    private var migrationCompleted: Bool {
        get { UserDefaults.standard.bool(forKey: "iCloudDriveJSONSync.migrationCompleted") }
        set { UserDefaults.standard.set(newValue, forKey: "iCloudDriveJSONSync.migrationCompleted") }
    }
    
    // MARK: - URLs
    
    private var ubiquityContainerURL: URL? {
        fileManager.url(forUbiquityContainerIdentifier: "iCloud.reasonality.MediaShows")
    }
    
    private var syncDirectoryURL: URL? {
        ubiquityContainerURL?.appendingPathComponent("Documents/MediaShowsSync")
    }
    
    private var syncFileURL: URL? {
        syncDirectoryURL?.appendingPathComponent("MediaShowsData.json")
    }
    
    private var localQueueURL: URL {
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsURL.appendingPathComponent("iCloudDriveSync").appendingPathComponent("PendingChanges.json")
    }
    
    // MARK: - Initialization
    
    override init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: "iCloudDriveJSONSync.enabled")
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
    
    private func initialize() async {
        guard ubiquityContainerURL != nil else {
            await MainActor.run {
                syncStatus = .iCloudUnavailable
                logDiagnostic("iCloud Drive unavailable on initialization", isError: true)
            }
            return
        }
        
        if isEnabled {
            await enableSync()
        }
        
        if !migrationCompleted {
            await performInitialMigration()
        }
    }
    
    // MARK: - Public Interface
    
    func enableSync() async {
        await MainActor.run {
            syncStatus = .syncing
        }
        
        guard ubiquityContainerURL != nil else {
            await MainActor.run {
                syncStatus = .iCloudUnavailable
                logDiagnostic("Cannot enable sync: iCloud Drive unavailable", isError: true)
            }
            return
        }
        
        await MainActor.run {
            logDiagnostic("Enabling iCloud Drive JSON sync")
        }
        
        do {
            try await createDirectoryStructure()
            await setupFilePresenter()
            
            // Don't block on initial sync - do it in background after a delay
            Task.detached {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
                await self.performFullSync()
            }
            
            await MainActor.run {
                syncStatus = .success("Sync enabled")
                logDiagnostic("iCloud Drive sync enabled successfully")
            }
        } catch {
            await MainActor.run {
                syncStatus = .error("Failed to enable sync: \(error.localizedDescription)")
                logDiagnostic("Failed to enable sync", details: error.localizedDescription, isError: true)
            }
        }
    }
    
    func disableSync() async {
        logDiagnostic("Disabling iCloud Drive JSON sync")
        await teardownFilePresenter()
        syncStatus = .idle
    }
    
    func forceSync() async {
        guard isEnabled else { return }
        await performFullSync()
    }
    
    func getMigrationStatus() -> SyncMigrationStatus {
        let context = PersistenceController.shared.viewContext
        let listCount = (try? context.count(for: MediaList.fetchAll())) ?? 0
        let titleCount = (try? context.count(for: Title.fetchRequest())) ?? 0
        let totalCount = listCount + titleCount
        
        return SyncMigrationStatus(
            isRequired: !migrationCompleted && totalCount > 0,
            coreDataItemCount: totalCount,
            canMigrate: ubiquityContainerURL != nil
        )
    }
    
    func resetMigrationFlag() {
        migrationCompleted = false
    }
    
    // MARK: - Migration
    
    private func performInitialMigration() async {
        guard !migrationCompleted else { return }
        
        logDiagnostic("Starting initial migration from Core Data to iCloud Drive JSON")
        syncStatus = .migrating
        
        do {
            let context = PersistenceController.shared.viewContext
            let hasData = try await context.perform {
                let listCount = try context.count(for: MediaList.fetchAll())
                let titleCount = try context.count(for: Title.fetchRequest())
                return listCount > 0 || titleCount > 0
            }
            
            if hasData {
                await exportCurrentDataToJSON()
                logDiagnostic("Migration completed: exported existing Core Data to JSON")
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
    
    /// Generate local sync data for comparison and merging
    func generateLocalSyncData() async throws -> SyncJSONData {
        let context = PersistenceController.shared.viewContext
        let data = try await generateJSONData(context: context)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let syncData = try decoder.decode(SyncJSONData.self, from: data)
        
        return syncData
    }
    
    private func performFullSync() async {
        await MainActor.run {
            logDiagnostic("🚀 Starting performFullSync")
        }
        
        guard isEnabled else {
            await MainActor.run {
                logDiagnostic("❌ Sync not enabled, aborting")
            }
            return
        }
        
        guard let syncFileURL = syncFileURL else {
            await MainActor.run {
                logDiagnostic("❌ No sync file URL available")
            }
            return
        }
        
        await MainActor.run {
            logDiagnostic("📁 Sync file URL: \(syncFileURL.path)")
        }
        
        // Rate limiting: prevent sync spam
        let now = Date()
        if now.timeIntervalSince(lastSyncTime) < minimumSyncInterval {
            await MainActor.run {
                logDiagnostic("⏱️ Skipping sync - too soon since last sync", details: "Last sync: \(lastSyncTime)")
            }
            return
        }
        lastSyncTime = now
        
        await MainActor.run {
            syncStatus = .syncing
            logDiagnostic("🔄 Setting status to syncing")
            startBackgroundTask()
            logDiagnostic("🏃‍♂️ Started background task")
        }
        
        do {
            await MainActor.run {
                logDiagnostic("📋 Creating file coordinator")
            }
            
            let coordinator = NSFileCoordinator()
            var error: NSError?
            
            await MainActor.run {
                logDiagnostic("🔒 About to start file coordination")
            }
            
            // Use async coordinate instead of semaphore to avoid deadlock
            let syncResult: Result<String, Error> = await withCheckedContinuation { continuation in
                coordinator.coordinate(writingItemAt: syncFileURL, options: [], error: &error) { (url) in
                    Task { @MainActor in
                        self.logDiagnostic("📝 Inside coordinate block with URL: \(url.path)")
                    }
                    
                    Task {
                        do {
                            Task { @MainActor in
                                self.logDiagnostic("🛠️ About to perform sync operation")
                            }
                            let result = try await self.performSyncOperation(at: url)
                            Task { @MainActor in
                                self.logDiagnostic("✅ Sync operation completed: \(result)")
                            }
                            continuation.resume(returning: .success(result))
                        } catch {
                            Task { @MainActor in
                                self.logDiagnostic("❌ Sync operation failed: \(error.localizedDescription)")
                            }
                            continuation.resume(returning: .failure(error))
                        }
                    }
                }
            }
            
            await MainActor.run {
                logDiagnostic("🔓 File coordination completed")
            }
            
            if let error = error {
                await MainActor.run {
                    logDiagnostic("❌ File coordination error: \(error.localizedDescription)")
                }
                throw error
            }
            
            switch syncResult {
            case .success(let message):
                await MainActor.run {
                    syncStatus = .success(message)
                    lastSyncDate = Date()
                    logDiagnostic("✨ Sync completed", details: message)
                }
            case .failure(let error):
                await MainActor.run {
                    logDiagnostic("❌ Sync result error: \(error.localizedDescription)")
                }
                throw error
            }
            
        } catch {
            await MainActor.run {
                syncStatus = .error(error.localizedDescription)
                logDiagnostic("💥 Sync failed", details: error.localizedDescription, isError: true)
            }
        }
        
        await MainActor.run {
            endBackgroundTask()
        }
    }
    
    private func performSyncOperation(at url: URL) async throws -> String {
        let remoteExists = fileManager.fileExists(atPath: url.path)
        
        if remoteExists {
            // Check if remote file is valid before attempting merge
            do {
                return try await performMergeSync(remoteURL: url)
            } catch ICloudDriveSyncError.invalidJSON {
                await MainActor.run {
                    logDiagnostic("Remote JSON corrupted, overwriting with local data", isError: true)
                }
                // Backup the corrupted file
                let backupURL = url.appendingPathExtension("corrupted-\(Date().timeIntervalSince1970)")
                try? fileManager.copyItem(at: url, to: backupURL)
                // Overwrite with fresh local data
                return try await performInitialUpload(to: url)
            }
        } else {
            return try await performInitialUpload(to: url)
        }
    }
    
    private func performMergeSync(remoteURL: URL) async throws -> String {
        // Get local data
        let context = PersistenceController.shared.viewContext
        let localData = try await generateJSONData(context: context)
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        let localJSON = try decoder.decode(SyncJSONData.self, from: localData)
        
        // Get remote data with file coordination
        let remoteData: Data
        var coordinatorError: NSError?
        var readData: Data?
        
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: remoteURL, options: [], error: &coordinatorError) { (readURL) in
            do {
                readData = try Data(contentsOf: readURL)
            } catch {
                logDiagnostic("Failed to read remote file", details: error.localizedDescription, isError: true)
            }
        }
        
        if let error = coordinatorError {
            logDiagnostic("File coordination error", details: error.localizedDescription, isError: true)
            throw ICloudDriveSyncError.fileCoordinationFailed
        }
        
        guard let data = readData else {
            logDiagnostic("No data read from remote file", isError: true)
            throw ICloudDriveSyncError.invalidJSON
        }
        
        remoteData = data
        
        // Debug: Log the raw JSON data for troubleshooting
        if let jsonString = String(data: remoteData, encoding: .utf8) {
            logDiagnostic("Remote JSON data", details: "Size: \(remoteData.count) bytes", isError: false)
            // Log first 200 chars for debugging
            let preview = String(jsonString.prefix(200))
            logDiagnostic("JSON preview", details: preview, isError: false)
        } else {
            logDiagnostic("Failed to convert remote data to string", isError: true)
        }
        
        let remoteJSON: SyncJSONData
        do {
            remoteJSON = try decoder.decode(SyncJSONData.self, from: remoteData)
        } catch {
            logDiagnostic("JSON decode error", details: error.localizedDescription, isError: true)
            throw ICloudDriveSyncError.invalidJSON
        }
        
        // Perform deterministic merge
        let mergedJSON = try performDeterministicMerge(local: localJSON, remote: remoteJSON)
        
        // Check if merge created changes
        if !isDataEquivalent(localJSON, mergedJSON) {
            // Apply merged data back to Core Data
            try applyJSONToCoreData(mergedJSON, context: context)
            logDiagnostic("Applied remote changes to local Core Data")
        }
        
        // Always update remote with merged result
        let mergedData = try JSONEncoder().encode(mergedJSON)
        try await writeAtomically(data: mergedData, to: remoteURL)
        
        return "Merged local and remote changes"
    }
    
    private func performInitialUpload(to url: URL) async throws -> String {
        let context = PersistenceController.shared.viewContext
        let jsonData = try await generateJSONData(context: context)
        try await writeAtomically(data: jsonData, to: url)
        return "Uploaded initial data to iCloud Drive"
    }
    
    // MARK: - Deterministic Merge Algorithm
    
    private func performDeterministicMerge(local: SyncJSONData, remote: SyncJSONData) throws -> SyncJSONData {
        logDiagnostic("Performing deterministic merge", details: "Local device: \(local.deviceId), Remote device: \(remote.deviceId)")
        
        // Merge lists
        let mergedLists = mergeItems(
            local: local.lists,
            remote: remote.lists,
            keyPath: \.id,
            timestampPath: \.updatedAt,
            deviceIdComparison: { local.deviceId.compare(remote.deviceId) == .orderedAscending }
        )
        
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
            logDiagnostic("Resolved \(conflictCount) conflicts using last-writer-wins", details: "Merge completed deterministically")
        }
        
        return merged
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
        
        for id in allIds {
            let localItem = localDict[id]
            let remoteItem = remoteDict[id]
            
            switch (localItem, remoteItem) {
            case (let local?, let remote?):
                // Both exist - apply last-writer-wins with tie breaking
                if local[keyPath: timestampPath] > remote[keyPath: timestampPath] {
                    result.append(local)
                } else if local[keyPath: timestampPath] < remote[keyPath: timestampPath] {
                    result.append(remote)
                } else {
                    // Timestamps equal - use deterministic device ID ordering
                    result.append(deviceIdComparison() ? local : remote)
                }
            case (let local?, nil):
                result.append(local)
            case (nil, let remote?):
                result.append(remote)
            case (nil, nil):
                break // Should not happen
            }
        }
        
        return result
    }
    
    // MARK: - JSON Data Generation
    
    private func generateJSONData(context: NSManagedObjectContext) async throws -> Data {
        await MainActor.run {
            logDiagnostic("🗂️ Starting JSON data generation")
        }
        
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
                    
                    Task { @MainActor in
                        self.logDiagnostic("🔧 Configuring JSON encoder")
                    }
                    
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
                    
                    // Get episodes with proper casting
                    let episodeSet = title.episodes as? Set<Episode> ?? Set<Episode>()
                    let sortedEpisodes = episodeSet.sorted { ($0.seasonNumber, $0.episodeNumber) < ($1.seasonNumber, $1.episodeNumber) }
                    let episodes = sortedEpisodes.compactMap { episode -> SyncEpisodeData? in
                        guard let episodeId = episode.id?.uuidString else {
                            logDiagnostic("Episode missing ID, skipping", isError: true)
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
                                logDiagnostic("Note missing ID, skipping", isError: true)
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
                        logDiagnostic("Title missing ID, skipping", isError: true)
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
                logDiagnostic("List missing ID, using generated UUID", isError: false)
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
    
    // MARK: - Core Data Application
    
    private func applyJSONToCoreData(_ syncData: SyncJSONData, context: NSManagedObjectContext) throws {
        try context.performAndWait {
            // Clear existing data and rebuild from JSON
            try clearAllData(context: context)
            
            for listData in syncData.lists.filter({ $0.deletedAt == nil }) {
                let list = MediaList(context: context)
                list.id = UUID(uuidString: listData.id) ?? UUID()
                list.name = listData.name
                list.dateCreated = listData.createdAt
                list.updatedAt = listData.updatedAt
                list.order = Double(syncData.lists.firstIndex(where: { $0.id == listData.id }) ?? 0)
                list.isDefault = list.order == 0
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
            
            try context.save()
        }
    }
    
    // MARK: - Validation
    
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
    
    // MARK: - Utility Methods
    
    private func createDirectoryStructure() async throws {
        guard let syncDir = syncDirectoryURL else {
            throw ICloudDriveSyncError.iCloudUnavailable
        }
        
        try fileManager.createDirectory(at: syncDir, withIntermediateDirectories: true, attributes: nil)
        
        var resourceValues: [URLResourceKey: Any] = [:]
        resourceValues[.isExcludedFromBackupKey] = false
        try (syncDir as NSURL).setResourceValues(resourceValues)
    }
    
    private func writeAtomically(data: Data, to url: URL) async throws {
        let tempURL = url.appendingPathExtension("tmp")
        try data.write(to: tempURL)
        _ = try fileManager.replaceItem(at: url, withItemAt: tempURL, backupItemName: nil, options: [], resultingItemURL: nil)
        
        // Give iCloud Drive a moment to process the file (non-blocking)
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
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
    
    private func exportCurrentDataToJSON() async {
        guard let syncFileURL = syncFileURL else { return }
        
        do {
            let context = PersistenceController.shared.viewContext
            let jsonData = try await generateJSONData(context: context)
            try await writeAtomically(data: jsonData, to: syncFileURL)
            logDiagnostic("Exported current Core Data to iCloud Drive JSON")
        } catch {
            logDiagnostic("Failed to export current data", details: error.localizedDescription, isError: true)
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
    
    private func isDataEquivalent(_ data1: SyncJSONData, _ data2: SyncJSONData) -> Bool {
        // Simple comparison - could be more sophisticated
        return data1.lists.count == data2.lists.count
    }
    
    internal func logDiagnostic(_ event: String, details: String? = nil, isError: Bool = false) {
        let entry = DiagnosticEntry(event: event, details: details, isError: isError)
        diagnosticsLog.append(entry)
        
        // Keep only last 100 entries
        if diagnosticsLog.count > 100 {
            diagnosticsLog.removeFirst(diagnosticsLog.count - 100)
        }
        
        // Also log to console in debug builds
        #if DEBUG
        print("🔄 iCloudSync: \(event)" + (details.map { " - \($0)" } ?? ""))
        #endif
    }
    
    // MARK: - Background Tasks
    
    @MainActor
    private func startBackgroundTask() {
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "iCloudDriveSync") {
            Task { @MainActor in
                self.endBackgroundTask()
            }
        }
    }
    
    @MainActor
    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
    
    // MARK: - File Presenter Setup
    
    private func setupFilePresenter() async {
        guard let syncFileURL = syncFileURL else { return }
        
        filePresenter = SyncFilePresenter(url: syncFileURL) { [weak self] in
            Task { @MainActor in
                await self?.performFullSync()
            }
        }
        
        NSFileCoordinator.addFilePresenter(filePresenter!)
        logDiagnostic("File presenter setup for remote change detection")
    }
    
    private func teardownFilePresenter() async {
        if let presenter = filePresenter {
            NSFileCoordinator.removeFilePresenter(presenter)
            filePresenter = nil
            logDiagnostic("File presenter removed")
        }
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

// MARK: - Sync Errors

enum ICloudDriveSyncError: Error {
    case iCloudUnavailable
    case fileCoordinationFailed
    case invalidJSON
    case coreDataError(String)
    
    var localizedDescription: String {
        switch self {
        case .iCloudUnavailable:
            return "iCloud Drive is not available. Please check your iCloud settings."
        case .fileCoordinationFailed:
            return "Failed to coordinate file access"
        case .invalidJSON:
            return "Invalid JSON data format"
        case .coreDataError(let message):
            return "Core Data error: \(message)"
        }
    }
}

// MARK: - File Presenter

private class SyncFilePresenter: NSObject, NSFilePresenter {
    var presentedItemURL: URL?
    let presentedItemOperationQueue = OperationQueue()
    private let changeHandler: () -> Void
    
    init(url: URL, changeHandler: @escaping () -> Void) {
        self.presentedItemURL = url
        self.changeHandler = changeHandler
        super.init()
    }
    
    func presentedItemDidChange() {
        changeHandler()
    }
    
    func presentedItemDidGain(_ version: NSFileVersion) {
        changeHandler()
    }
}