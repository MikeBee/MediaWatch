//
//  LWWSyncService.swift
//  MediaWatch
//
//  Last Writer Wins (LWW) sync service with tombstones
//  Implements the gold standard multi-device sync pattern with:
//  - UUID-based object identification
//  - Metadata: createdAt, updatedAt, deletedAt, deviceID
//  - Tombstone-based deletion tracking
//  - Fractional ordering for list items
//  - Deterministic conflict resolution
//

import Foundation
import CoreData
import Combine
import UIKit

@MainActor
final class LWWSyncService: NSObject, ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = LWWSyncService()
    
    // MARK: - Published Properties
    
    @Published var syncStatus: SyncStatus = .idle
    @Published var lastSyncDate: Date?
    @Published var lastPushDate: Date?
    @Published var lastPullDate: Date?
    @Published var conflictsResolved: Int = 0
    
    // MARK: - Types
    
    enum SyncStatus: Equatable {
        case idle
        case pulling
        case pushing
        case merging
        case success(String)
        case error(String)
    }
    
    // MARK: - Private Properties
    
    internal var currentDeviceID: String {
        return DeviceIdentifier.shared.deviceID
    }
    private let context: NSManagedObjectContext
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    override init() {
        self.context = PersistenceController.shared.viewContext
        super.init()
    }
    
    // MARK: - Public API
    
    /// Initialize the LWW sync service for fresh installs
    func initializeForFreshInstall() {
        // Mark that this is a fresh install with LWW support
        UserDefaults.standard.set(true, forKey: "lww_fresh_install")
        UserDefaults.standard.set(currentDeviceID, forKey: "lww_device_id")
        UserDefaults.standard.set(Date(), forKey: "lww_install_date")
        
        // Run timestamp migration for existing data
        Task {
            do {
                try await TimestampMigrationHelper.shared.fixPlaceholderTimestamps()
            } catch {
                print("Timestamp migration failed: \(error)")
            }
        }
        
        // No migration needed for fresh installs
        print("✅ LWW Sync initialized for fresh install with device ID: \(currentDeviceID)")
    }
    
    /// Check if this is a fresh LWW install
    var isFreshInstall: Bool {
        return UserDefaults.standard.bool(forKey: "lww_fresh_install")
    }
    
    /// Get device ID (for external access)
    var exposedDeviceID: String {
        return currentDeviceID
    }
    
    /// Perform a complete sync cycle following the LWW pattern
    func performSync() async throws {
        syncStatus = .pulling
        
        // Step 1: Pull remote changes and merge
        let remoteData = try await pullRemoteChanges()
        
        syncStatus = .merging
        
        // Step 2: Merge remote changes with local data using LWW
        let mergeResult = try await mergeWithLWW(remoteData: remoteData)
        
        syncStatus = .pushing
        
        // Step 3: Push local changes that are newer than last push
        try await pushLocalChanges()
        
        // Step 4: Update sync timestamps
        lastSyncDate = Date()
        conflictsResolved = mergeResult.conflictsResolved
        
        syncStatus = .success("Sync completed - resolved \(mergeResult.conflictsResolved) conflicts")
    }
    
    // MARK: - Step 1: Pull Remote Changes
    
    private func pullRemoteChanges() async throws -> SyncJSONData {
        // This would connect to your chosen sync backend (CloudKit, Firebase, etc.)
        // For now, we'll create a placeholder that would be implemented based on your backend
        
        // Example structure - replace with actual backend implementation
        let remoteJSON = SyncJSONData(
            version: 1,
            lastSyncedAt: Date(),
            deviceId: "remote-device",
            lists: []
        )
        
        lastPullDate = Date()
        return remoteJSON
    }
    
    // MARK: - Step 2: LWW Merge Logic
    
    internal func mergeWithLWW(remoteData: SyncJSONData) async throws -> MergeResult {
        return try await withCheckedThrowingContinuation { continuation in
            context.perform {
                do {
            var conflictsResolved = 0
            
            // Get current local data
            let localLists = try self.fetchAllListsFromCoreData()
            let localListsDict = Dictionary(uniqueKeysWithValues: localLists.map { ($0.id, $0) })
            
            // STEP 1: Handle list merging with proper name collision detection
            let mergedLists = try self.mergeListsWithNameCollision(localLists: localLists, remoteLists: remoteData.lists)
            conflictsResolved += mergedLists.conflictsResolved
            
            // STEP 2: Apply merged results to Core Data
            try self.applyMergedLists(mergedLists.lists)
            
                    try self.context.save()
                    continuation.resume(returning: MergeResult(conflictsResolved: conflictsResolved))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func mergeListItems(localList: SyncListData, remoteList: SyncListData) throws -> Int {
        var conflictsResolved = 0
        
        let localItemsDict = Dictionary(uniqueKeysWithValues: localList.items.map { ($0.id, $0) })
        let _ = Dictionary(uniqueKeysWithValues: remoteList.items.map { ($0.id, $0) })
        
        // Merge items using LWW
        for remoteItem in remoteList.items {
            if let localItem = localItemsDict[remoteItem.id] {
                if remoteItem.shouldWinOver(localItem) {
                    try applyItemUpdate(remoteItem, inListID: localList.id)
                    conflictsResolved += 1
                }
            } else if !remoteItem.isTombstone || remoteItem.updatedAt > (lastPullDate ?? Date.distantPast) {
                try createItemFromRemote(remoteItem, inListID: localList.id)
            }
        }
        
        // Handle episodes and notes within each item
        for remoteItem in remoteList.items {
            if let localItem = localItemsDict[remoteItem.id] {
                // Get the title for this item
                let titleFetch = NSFetchRequest<Title>(entityName: "Title")
                titleFetch.predicate = NSPredicate(format: "id == %@", localItem.id)
                if let title = try? context.fetch(titleFetch).first {
                    conflictsResolved += try mergeEpisodes(local: localItem.episodes, remote: remoteItem.episodes, title: title)
                    conflictsResolved += try mergeNotes(local: localItem.notes, remote: remoteItem.notes, title: title)
                }
            }
        }
        
        return conflictsResolved
    }
    
    private func mergeEpisodes(local: [SyncEpisodeData], remote: [SyncEpisodeData], title: Title) throws -> Int {
        var conflictsResolved = 0
        
        let localDict = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        
        for remoteEpisode in remote {
            if let localEpisode = localDict[remoteEpisode.id] {
                if remoteEpisode.shouldWinOver(localEpisode) {
                    try applyEpisodeUpdate(remoteEpisode, title: title)
                    conflictsResolved += 1
                }
            } else if !remoteEpisode.isTombstone {
                try createEpisodeFromRemote(remoteEpisode, title: title)
            }
        }
        
        return conflictsResolved
    }
    
    // MARK: - Enhanced List Merging with Name Collision Handling
    
    private func mergeListsWithNameCollision(localLists: [SyncListData], remoteLists: [SyncListData]) throws -> (lists: [SyncListData], conflictsResolved: Int) {
        var conflictsResolved = 0
        var mergedLists: [SyncListData] = []
        
        // Consolidate lists by unique ID first
        let localListsDict = Dictionary(uniqueKeysWithValues: localLists.map { ($0.id, $0) })
        let remoteListsDict = Dictionary(uniqueKeysWithValues: remoteLists.map { ($0.id, $0) })
        
        // Find all unique list IDs
        let allListIDs = Set(localListsDict.keys).union(Set(remoteListsDict.keys))
        
        // Process each unique list ID
        for listID in allListIDs {
            let localList = localListsDict[listID]
            let remoteList = remoteListsDict[listID]
            
            if let local = localList, let remote = remoteList {
                // Both exist - use LWW with extended comparison
                if remote.shouldWinOverExtended(local) {
                    let mergedItems = try mergeItemsForList(localItems: local.items, remoteItems: remote.items)
                    let finalList = SyncListData(
                        id: remote.id,
                        name: remote.name,
                        createdAt: earliestDate(remote.createdAt, local.createdAt),
                        updatedAt: remote.updatedAt,
                        deletedAt: remote.deletedAt,
                        deviceID: remote.deviceID,
                        order: remote.order,
                        items: mergedItems.items
                    )
                    mergedLists.append(finalList)
                    conflictsResolved += 1 + mergedItems.conflictsResolved
                } else {
                    let mergedItems = try mergeItemsForList(localItems: local.items, remoteItems: remote.items)
                    let finalList = SyncListData(
                        id: local.id,
                        name: local.name,
                        createdAt: earliestDate(local.createdAt, remote.createdAt),
                        updatedAt: local.updatedAt,
                        deletedAt: local.deletedAt,
                        deviceID: local.deviceID,
                        order: local.order,
                        items: mergedItems.items
                    )
                    mergedLists.append(finalList)
                    conflictsResolved += mergedItems.conflictsResolved
                }
            } else if let local = localList {
                // Local only - keep it
                mergedLists.append(local)
            } else if let remote = remoteList {
                // Remote only - add it if not a tombstone
                if remote.deletedAt == nil {
                    mergedLists.append(remote)
                }
            }
        }
        
        // Handle name collision merging
        let nameGroups = Dictionary(grouping: mergedLists) { $0.name }
        var finalMergedLists: [SyncListData] = []
        
        for (name, listsWithSameName) in nameGroups {
            if listsWithSameName.count > 1 {
                // Name collision - merge the lists
                let mergedList = try mergeListsWithSameName(listsWithSameName)
                finalMergedLists.append(mergedList)
                conflictsResolved += listsWithSameName.count - 1
            } else {
                // No collision
                finalMergedLists.append(listsWithSameName[0])
            }
        }
        
        return (finalMergedLists, conflictsResolved)
    }
    
    private func mergeListsWithSameName(_ lists: [SyncListData]) throws -> SyncListData {
        // Sort by creation date to get the oldest (most authoritative)
        let sortedLists = lists.sorted { first, second in
            if first.createdAt != second.createdAt {
                return first.createdAt < second.createdAt
            }
            // Tie breaker: lexicographic device ID comparison
            return first.deviceID < second.deviceID
        }
        
        let primaryList = sortedLists[0]
        var allItems: [SyncItemData] = primaryList.items
        
        // Merge items from all other lists
        for i in 1..<sortedLists.count {
            let otherList = sortedLists[i]
            let mergedItems = try mergeItemsForList(localItems: allItems, remoteItems: otherList.items)
            allItems = mergedItems.items
        }
        
        // Use the most recent updatedAt from any of the lists
        let mostRecentUpdate = lists.map { $0.updatedAt }.max() ?? Date()
        let mostRecentDevice = lists.first { $0.updatedAt == mostRecentUpdate }?.deviceID ?? currentDeviceID
        
        return SyncListData(
            id: primaryList.id, // Use the oldest list's ID
            name: primaryList.name,
            createdAt: primaryList.createdAt,
            updatedAt: mostRecentUpdate,
            deletedAt: primaryList.deletedAt,
            deviceID: mostRecentDevice,
            order: primaryList.order,
            items: allItems
        )
    }
    
    private func mergeItemsForList(localItems: [SyncItemData], remoteItems: [SyncItemData]) throws -> (items: [SyncItemData], conflictsResolved: Int) {
        var conflictsResolved = 0
        var mergedItems: [SyncItemData] = []
        
        let localItemsDict = Dictionary(uniqueKeysWithValues: localItems.map { ($0.id, $0) })
        let remoteItemsDict = Dictionary(uniqueKeysWithValues: remoteItems.map { ($0.id, $0) })
        
        let allItemIDs = Set(localItemsDict.keys).union(Set(remoteItemsDict.keys))
        
        for itemID in allItemIDs {
            let localItem = localItemsDict[itemID]
            let remoteItem = remoteItemsDict[itemID]
            
            if let local = localItem, let remote = remoteItem {
                // Both exist - use LWW
                if remote.shouldWinOverExtended(local) {
                    mergedItems.append(remote)
                    conflictsResolved += 1
                } else {
                    mergedItems.append(local)
                    if local.updatedAt != remote.updatedAt {
                        conflictsResolved += 1
                    }
                }
            } else if let local = localItem {
                // Local only
                mergedItems.append(local)
            } else if let remote = remoteItem {
                // Remote only
                if remote.deletedAt == nil {
                    mergedItems.append(remote)
                }
            }
        }
        
        return (mergedItems, conflictsResolved)
    }
    
    private func applyMergedLists(_ lists: [SyncListData]) throws {
        // Fetch existing lists and create lookup by ID
        let fetchRequest = MediaList.fetchAll()
        let existingLists = try context.fetch(fetchRequest)
        let existingListsById = Dictionary(uniqueKeysWithValues: existingLists.compactMap { list in
            guard let id = list.id else { return nil }
            return (id, list)
        })
        var processedListIds: Set<UUID> = []
        
        // Update or create lists from merged data
        for listData in lists {
            guard let listUUID = UUID(uuidString: listData.id) else { continue }
            processedListIds.insert(listUUID)
            
            if let deletedAt = listData.deletedAt {
                // Handle deleted lists
                if let existingList = existingListsById[listUUID] {
                    existingList.deletedAt = deletedAt
                    existingList.updatedAt = listData.updatedAt
                    existingList.deviceID = listData.deviceID
                }
            } else {
                // Handle active lists - update existing or create new
                if let existingList = existingListsById[listUUID] {
                    // Update existing list instead of deleting and recreating
                    existingList.name = listData.name
                    // Note: SyncListData doesn't have icon, colorHex, isShared - keep existing values
                    existingList.updatedAt = listData.updatedAt
                    existingList.deviceID = listData.deviceID
                    existingList.order = listData.order
                    existingList.deletedAt = nil // Ensure it's not marked as deleted
                    
                    // Update list items
                    try updateListItems(existingList, with: listData.items)
                } else {
                    // Create new list
                    try createListFromRemote(listData)
                }
            }
        }
        
        // Remove lists that weren't in the merged data (shouldn't happen in normal sync)
        for existingList in existingLists {
            if let listId = existingList.id, !processedListIds.contains(listId) {
                context.delete(existingList)
            }
        }
    }
    
    private func earliestDate(_ date1: Date, _ date2: Date) -> Date {
        return date1 < date2 ? date1 : date2
    }
    
    private func mergeNotes(local: [SyncNoteData], remote: [SyncNoteData], title: Title) throws -> Int {
        var conflictsResolved = 0
        
        let localDict = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        
        for remoteNote in remote {
            if let localNote = localDict[remoteNote.id] {
                if remoteNote.shouldWinOver(localNote) {
                    try applyNoteUpdate(remoteNote, title: title)
                    conflictsResolved += 1
                }
            } else if !remoteNote.isTombstone {
                try createNoteFromRemote(remoteNote, title: title)
            }
        }
        
        return conflictsResolved
    }
    
    // MARK: - Step 3: Push Local Changes
    
    private func pushLocalChanges() async throws {
        let localData = try await generateLocalSyncData()
        
        // Push only items that have been modified since last push
        let changesSincePush = filterChangesSinceLastPush(localData)
        
        if !changesSincePush.lists.isEmpty {
            try await pushToRemote(changesSincePush)
            lastPushDate = Date()
        }
    }
    
    private func filterChangesSinceLastPush(_ data: SyncJSONData) -> SyncJSONData {
        let lastPush = lastPushDate ?? Date.distantPast
        
        let filteredLists = data.lists.filter { list in
            list.updatedAt > lastPush || 
            list.deletedAt != nil && list.deletedAt! > lastPush ||
            list.items.contains { item in
                item.updatedAt > lastPush || 
                item.deletedAt != nil && item.deletedAt! > lastPush
            }
        }
        
        return SyncJSONData(
            version: data.version,
            lastSyncedAt: data.lastSyncedAt,
            deviceId: data.deviceId,
            lists: filteredLists
        )
    }
    
    private func pushToRemote(_ data: SyncJSONData) async throws {
        // Implementation depends on your chosen backend
        // This could be CloudKit, Firebase, custom API, etc.
        
        // Placeholder for actual push implementation
        print("Pushing \(data.lists.count) lists to remote...")
    }
    
    // MARK: - Data Generation and Application
    
    internal func generateLocalSyncData() async throws -> SyncJSONData {
        return try await withCheckedThrowingContinuation { continuation in
            context.perform {
                do {
            let lists = try self.fetchAllListsFromCoreData()
            
                    let syncData = SyncJSONData(
                        version: 1,
                        lastSyncedAt: Date(),
                        deviceId: self.currentDeviceID,
                        lists: lists
                    )
                    continuation.resume(returning: syncData)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func fetchAllListsFromCoreData() throws -> [SyncListData] {
        let fetchRequest = MediaList.fetchAll()
        let coreDataLists = try context.fetch(fetchRequest)
        
        return coreDataLists.map { coreDataList in
            let items = (coreDataList.items as? Set<ListItem> ?? [])
                .sorted { $0.order < $1.order }
                .compactMap { listItem -> SyncItemData? in
                    guard let title = listItem.title else { return nil }
                    
                    // Get episodes for this title
                    let episodes = (title.episodes as? Set<Episode> ?? [])
                        .sorted { ($0.seasonNumber, $0.episodeNumber) < ($1.seasonNumber, $1.episodeNumber) }
                        .compactMap { episode -> SyncEpisodeData? in
                            guard let episodeId = episode.id?.uuidString else { return nil }
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
                                deviceID: episode.deviceID ?? self.currentDeviceID
                            )
                        }
                    
                    // Get notes for this title (non-private only for cross-Apple ID sync)
                    let notes = (title.notes as? Set<Note> ?? [])
                        .filter { !$0.ownerOnly } // Only sync non-private notes
                        .compactMap { note -> SyncNoteData? in
                            guard let noteId = note.id?.uuidString else { return nil }
                            return SyncNoteData(
                                id: noteId,
                                text: note.text ?? "",
                                createdAt: note.createdAt ?? Date(),
                                updatedAt: note.updatedAt ?? Date(),
                                deletedAt: note.deletedAt,
                                deviceID: note.deviceID ?? self.currentDeviceID
                            )
                        }
                    
                    return SyncItemData(
                        id: title.id?.uuidString ?? UUID().uuidString,
                        tmdbId: Int(title.tmdbId),
                        mediaType: title.mediaType ?? "movie",
                        title: title.title ?? "",
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
                        deviceID: title.deviceID ?? self.currentDeviceID,
                        order: listItem.order,
                        episodes: episodes,
                        notes: notes
                    )
                }
            
            return SyncListData(
                id: coreDataList.id?.uuidString ?? UUID().uuidString,
                name: coreDataList.name ?? "",
                createdAt: coreDataList.createdAt ?? Date(),
                updatedAt: coreDataList.updatedAt ?? Date(),
                deletedAt: coreDataList.deletedAt,
                deviceID: coreDataList.deviceID ?? self.currentDeviceID,
                order: coreDataList.order,
                items: items
            )
        }
    }
    
    // MARK: - Core Data Update Operations
    
    private func applyListUpdate(_ syncList: SyncListData) throws {
        let fetchRequest = MediaList.fetchAll()
        fetchRequest.predicate = NSPredicate(format: "id == %@", syncList.id)
        
        let lists = try context.fetch(fetchRequest)
        let list = lists.first ?? MediaList(context: context)
        
        // Apply LWW update
        list.id = UUID(uuidString: syncList.id)
        list.name = syncList.name
        list.createdAt = syncList.createdAt
        list.updatedAt = syncList.updatedAt
        list.deletedAt = syncList.deletedAt
        list.deviceID = syncList.deviceID
        list.order = syncList.order
    }
    
    private func updateListItems(_ list: MediaList, with syncItems: [SyncItemData]) throws {
        // Get existing items for this list
        let existingItems = list.sortedItems
        let existingItemsById: [UUID: ListItem] = Dictionary(uniqueKeysWithValues: existingItems.compactMap { item in
            guard let title = item.title, let titleId = title.id else { return nil }
            return (titleId, item)
        })
        
        var processedItemIds: Set<UUID> = []
        
        // Update or create items from sync data
        for syncItem in syncItems {
            guard let itemUUID = UUID(uuidString: syncItem.id) else { continue }
            processedItemIds.insert(itemUUID)
            
            if let existingItem = existingItemsById[itemUUID] {
                if let deletedAt = syncItem.deletedAt {
                    // Mark item as deleted
                    existingItem.deletedAt = deletedAt
                    existingItem.updatedAt = syncItem.updatedAt
                    existingItem.deviceID = syncItem.deviceID
                } else {
                    // Update existing item
                    existingItem.order = syncItem.order
                    existingItem.updatedAt = syncItem.updatedAt
                    existingItem.deviceID = syncItem.deviceID
                    existingItem.deletedAt = nil
                    
                    // Update associated title if needed
                    if let title = existingItem.title {
                        title.tmdbId = Int64(syncItem.tmdbId)
                        title.mediaType = syncItem.mediaType
                        title.title = syncItem.title
                        title.year = Int16(syncItem.year)
                        title.overview = syncItem.overview
                        title.posterPath = syncItem.posterPath
                        title.backdropPath = syncItem.backdropPath
                        title.updatedAt = syncItem.updatedAt
                        title.deviceID = syncItem.deviceID
                    }
                }
            } else if syncItem.deletedAt == nil {
                // Create new item
                try createItemFromRemote(syncItem, inListID: list.id?.uuidString ?? "")
            }
        }
        
        // Handle items that weren't in sync data (mark as deleted if not already)
        for existingItem in existingItems {
            if let titleId = existingItem.title?.id, !processedItemIds.contains(titleId) {
                existingItem.deletedAt = Date()
                existingItem.updatedAt = Date()
                existingItem.deviceID = currentDeviceID
            }
        }
    }

    private func createListFromRemote(_ syncList: SyncListData) throws {
        let list = MediaList(context: context)
        list.id = UUID(uuidString: syncList.id)
        list.name = syncList.name
        list.createdAt = syncList.createdAt
        list.updatedAt = syncList.updatedAt
        list.deletedAt = syncList.deletedAt
        list.deviceID = syncList.deviceID
        list.order = syncList.order
        
        // Create items for this list
        for syncItem in syncList.items where syncItem.deletedAt == nil {
            try createItemFromRemote(syncItem, inListID: syncList.id)
        }
    }
    
    private func applyItemUpdate(_ syncItem: SyncItemData, inListID listID: String) throws {
        // Find the existing title
        let fetchRequest = NSFetchRequest<Title>(entityName: "Title")
        fetchRequest.predicate = NSPredicate(format: "id == %@", syncItem.id)
        
        let titles = try context.fetch(fetchRequest)
        guard let title = titles.first else {
            // Item doesn't exist locally, create it
            try createItemFromRemote(syncItem, inListID: listID)
            return
        }
        
        // Apply ALL synced fields using LWW
        title.tmdbId = Int64(syncItem.tmdbId)
        title.mediaType = syncItem.mediaType
        title.title = syncItem.title
        title.year = Int16(syncItem.year)
        title.overview = syncItem.overview
        title.posterPath = syncItem.posterPath
        title.backdropPath = syncItem.backdropPath
        title.runtime = Int16(syncItem.runtime)
        
        // Watch Status Fields - CRITICAL for sync
        title.watched = syncItem.watched
        title.watchedDate = syncItem.watchedDate
        title.watchStatus = Int16(syncItem.watchStatus)
        title.lastWatched = syncItem.lastWatched
        
        // Episode Tracking
        title.currentSeason = Int16(syncItem.currentSeason)
        title.currentEpisode = Int16(syncItem.currentEpisode)
        title.numberOfSeasons = Int16(syncItem.numberOfSeasons)
        title.numberOfEpisodes = Int16(syncItem.numberOfEpisodes)
        
        // Rating Fields - ALL of them
        title.userRating = syncItem.userRating ?? 0
        title.mikeRating = syncItem.mikeRating ?? 0
        title.lauraRating = syncItem.lauraRating ?? 0
        title.voteAverage = syncItem.voteAverage ?? 0
        title.voteCount = Int32(syncItem.voteCount)
        
        // Status and Preferences
        title.isFavorite = syncItem.isFavorite
        title.likedStatus = Int16(syncItem.likedStatus)
        title.status = syncItem.status
        title.streamingService = syncItem.streamingService
        title.mediaCategory = syncItem.mediaCategory
        
        // Dates
        title.releaseDate = syncItem.releaseDate
        title.firstAirDate = syncItem.firstAirDate
        title.lastAirDate = syncItem.lastAirDate
        title.startDate = syncItem.startDate
        
        // Additional Metadata
        title.originalTitle = syncItem.originalTitle
        title.originalLanguage = syncItem.originalLanguage
        title.imdbId = syncItem.imdbId
        title.popularity = syncItem.popularity ?? 0
        title.genres = syncItem.genres
        
        // Custom Fields
        title.customField1 = syncItem.customField1
        title.customField2 = syncItem.customField2
        
        // LWW Metadata
        title.createdAt = syncItem.createdAt
        title.updatedAt = syncItem.updatedAt
        title.deletedAt = syncItem.deletedAt
        title.deviceID = syncItem.deviceID
        
        // Update episodes
        try applyEpisodeUpdates(syncItem.episodes, to: title)
        
        // Update notes (non-private only)
        try applyNoteUpdates(syncItem.notes, to: title)
        
        // Update the list item order if needed
        if let listItem = findListItem(for: title, inListID: listID) {
            listItem.order = syncItem.order
            listItem.updatedAt = syncItem.updatedAt
            listItem.deviceID = syncItem.deviceID
        }
    }
    
    private func createItemFromRemote(_ syncItem: SyncItemData, inListID listID: String) throws {
        // Find the list
        let listFetch = MediaList.fetchAll()
        listFetch.predicate = NSPredicate(format: "id == %@", listID)
        
        guard let list = try context.fetch(listFetch).first else {
            throw LWWSyncError.listNotFound(listID)
        }
        
        // Create the title with ALL fields
        let title = Title(context: context)
        title.id = UUID(uuidString: syncItem.id) ?? UUID()
        title.tmdbId = Int64(syncItem.tmdbId)
        title.mediaType = syncItem.mediaType
        title.title = syncItem.title
        title.year = Int16(syncItem.year)
        title.overview = syncItem.overview
        title.posterPath = syncItem.posterPath
        title.backdropPath = syncItem.backdropPath
        title.runtime = Int16(syncItem.runtime)
        
        // Watch Status Fields
        title.watched = syncItem.watched
        title.watchedDate = syncItem.watchedDate
        title.watchStatus = Int16(syncItem.watchStatus)
        title.lastWatched = syncItem.lastWatched
        
        // Episode Tracking
        title.currentSeason = Int16(syncItem.currentSeason)
        title.currentEpisode = Int16(syncItem.currentEpisode)
        title.numberOfSeasons = Int16(syncItem.numberOfSeasons)
        title.numberOfEpisodes = Int16(syncItem.numberOfEpisodes)
        
        // Rating Fields
        title.userRating = syncItem.userRating ?? 0
        title.mikeRating = syncItem.mikeRating ?? 0
        title.lauraRating = syncItem.lauraRating ?? 0
        title.voteAverage = syncItem.voteAverage ?? 0
        title.voteCount = Int32(syncItem.voteCount)
        
        // Status and Preferences
        title.isFavorite = syncItem.isFavorite
        title.likedStatus = Int16(syncItem.likedStatus)
        title.status = syncItem.status
        title.streamingService = syncItem.streamingService
        title.mediaCategory = syncItem.mediaCategory
        
        // Dates
        title.releaseDate = syncItem.releaseDate
        title.firstAirDate = syncItem.firstAirDate
        title.lastAirDate = syncItem.lastAirDate
        title.startDate = syncItem.startDate
        
        // Additional Metadata
        title.originalTitle = syncItem.originalTitle
        title.originalLanguage = syncItem.originalLanguage
        title.imdbId = syncItem.imdbId
        title.popularity = syncItem.popularity ?? 0
        title.genres = syncItem.genres
        
        // Custom Fields
        title.customField1 = syncItem.customField1
        title.customField2 = syncItem.customField2
        
        // LWW Metadata
        title.createdAt = syncItem.createdAt
        title.updatedAt = syncItem.updatedAt
        title.deletedAt = syncItem.deletedAt
        title.deviceID = syncItem.deviceID
        
        // Create the list item
        let listItem = ListItem(context: context)
        listItem.id = UUID()
        listItem.list = list
        listItem.title = title
        listItem.order = syncItem.order
        listItem.createdAt = syncItem.createdAt
        listItem.updatedAt = syncItem.updatedAt
        listItem.deletedAt = syncItem.deletedAt
        listItem.deviceID = syncItem.deviceID
        
        // Create episodes
        for episodeData in syncItem.episodes {
            try createEpisodeFromRemote(episodeData, title: title)
        }
        
        // Create notes
        for noteData in syncItem.notes {
            try createNoteFromRemote(noteData, title: title)
        }
    }
    
    private func applyEpisodeUpdate(_ syncEpisode: SyncEpisodeData, title: Title) throws {
        let fetchRequest = NSFetchRequest<Episode>(entityName: "Episode")
        fetchRequest.predicate = NSPredicate(format: "id == %@", syncEpisode.id)
        
        let episodes = try context.fetch(fetchRequest)
        guard let episode = episodes.first else {
            // Episode doesn't exist, create it
            try createEpisodeFromRemote(syncEpisode, title: title)
            return
        }
        
        // Apply all episode fields
        episode.tmdbId = Int64(syncEpisode.tmdbId)
        episode.seasonNumber = Int16(syncEpisode.seasonNumber)
        episode.episodeNumber = Int16(syncEpisode.episodeNumber)
        episode.name = syncEpisode.name
        episode.overview = syncEpisode.overview
        episode.stillPath = syncEpisode.stillPath
        episode.airDate = syncEpisode.airDate
        episode.runtime = Int16(syncEpisode.runtime)
        episode.watched = syncEpisode.watched
        episode.watchedDate = syncEpisode.watchedDate
        episode.isStarred = syncEpisode.isStarred
        episode.createdAt = syncEpisode.createdAt
        episode.updatedAt = syncEpisode.updatedAt
        episode.deletedAt = syncEpisode.deletedAt
        episode.deviceID = syncEpisode.deviceID
    }
    
    private func createEpisodeFromRemote(_ syncEpisode: SyncEpisodeData, title: Title) throws {
        let episode = Episode(context: context)
        episode.id = UUID(uuidString: syncEpisode.id) ?? UUID()
        episode.tmdbId = Int64(syncEpisode.tmdbId)
        episode.seasonNumber = Int16(syncEpisode.seasonNumber)
        episode.episodeNumber = Int16(syncEpisode.episodeNumber)
        episode.name = syncEpisode.name
        episode.overview = syncEpisode.overview
        episode.stillPath = syncEpisode.stillPath
        episode.airDate = syncEpisode.airDate
        episode.runtime = Int16(syncEpisode.runtime)
        episode.watched = syncEpisode.watched
        episode.watchedDate = syncEpisode.watchedDate
        episode.isStarred = syncEpisode.isStarred
        episode.createdAt = syncEpisode.createdAt
        episode.updatedAt = syncEpisode.updatedAt
        episode.deletedAt = syncEpisode.deletedAt
        episode.deviceID = syncEpisode.deviceID
        episode.show = title
    }
    
    private func applyNoteUpdate(_ syncNote: SyncNoteData, title: Title) throws {
        let fetchRequest = NSFetchRequest<Note>(entityName: "Note")
        fetchRequest.predicate = NSPredicate(format: "id == %@", syncNote.id)
        
        let notes = try context.fetch(fetchRequest)
        guard let note = notes.first else {
            // Note doesn't exist, create it
            try createNoteFromRemote(syncNote, title: title)
            return
        }
        
        // Apply all note fields
        note.text = syncNote.text
        note.createdAt = syncNote.createdAt
        note.updatedAt = syncNote.updatedAt
        note.deletedAt = syncNote.deletedAt
        note.deviceID = syncNote.deviceID
        // Keep ownerOnly as false for synced notes
        note.ownerOnly = false
    }
    
    private func createNoteFromRemote(_ syncNote: SyncNoteData, title: Title) throws {
        let note = Note(context: context)
        note.id = UUID(uuidString: syncNote.id) ?? UUID()
        note.text = syncNote.text
        note.createdAt = syncNote.createdAt
        note.updatedAt = syncNote.updatedAt
        note.deletedAt = syncNote.deletedAt
        note.deviceID = syncNote.deviceID
        note.ownerOnly = false // Synced notes are shared
        note.title = title
    }
    
    // MARK: - Helper Methods
    
    private func applyEpisodeUpdates(_ episodes: [SyncEpisodeData], to title: Title) throws {
        for episodeData in episodes {
            try applyEpisodeUpdate(episodeData, title: title)
        }
    }
    
    private func applyNoteUpdates(_ notes: [SyncNoteData], to title: Title) throws {
        for noteData in notes {
            try applyNoteUpdate(noteData, title: title)
        }
    }
    
    private func findListItem(for title: Title, inListID listID: String) -> ListItem? {
        guard let listItems = title.listItems as? Set<ListItem> else { return nil }
        return listItems.first { listItem in
            listItem.list?.id?.uuidString == listID
        }
    }
    
    // MARK: - Public Operations with LWW Semantics
    
    /// Create a new list with proper LWW metadata
    func createList(name: String) throws -> MediaList {
        let list = MediaList(context: context)
        let now = Date()
        
        list.id = UUID()
        list.name = name
        list.createdAt = now
        list.updatedAt = now
        list.deletedAt = nil
        list.deviceID = currentDeviceID
        list.order = FractionalOrdering.first()
        
        try context.save()
        return list
    }
    
    /// Update a list with proper LWW metadata
    func updateList(_ list: MediaList, name: String) throws {
        list.name = name
        list.updatedAt = Date()
        list.deviceID = currentDeviceID
        
        try context.save()
    }
    
    /// Delete a list using tombstone pattern
    func deleteList(_ list: MediaList) throws {
        list.deletedAt = Date()
        list.updatedAt = Date()
        list.deviceID = currentDeviceID
        
        try context.save()
    }
    
    /// Add an item to a list with fractional ordering
    func addItem(_ title: Title, toList list: MediaList) throws {
        let listItem = ListItem(context: context)
        let now = Date()
        
        listItem.id = UUID()
        listItem.list = list
        listItem.title = title
        listItem.createdAt = now
        listItem.updatedAt = now
        listItem.deletedAt = nil
        listItem.deviceID = currentDeviceID
        
        // Calculate fractional order - place at end
        let lastOrder = list.sortedItems.last?.order ?? 0
        listItem.order = FractionalOrdering.atEnd(after: lastOrder)
        
        // Update list modification time
        list.updatedAt = now
        list.deviceID = currentDeviceID
        
        try context.save()
    }
    
    /// Remove an item from a list using tombstone pattern
    func removeItem(_ listItem: ListItem) throws {
        let now = Date()
        
        listItem.deletedAt = now
        listItem.updatedAt = now
        listItem.deviceID = currentDeviceID
        
        // Update list modification time
        listItem.list?.updatedAt = now
        listItem.list?.deviceID = currentDeviceID
        
        try context.save()
    }
    
    /// Reorder items in a list using fractional ordering
    func reorderItems(in list: MediaList, items: [ListItem]) throws {
        let now = Date()
        
        for (index, item) in items.enumerated() {
            let newOrder: Double
            
            if index == 0 {
                // First item
                if items.count > 1 {
                    newOrder = FractionalOrdering.atBeginning(before: items[1].order)
                } else {
                    newOrder = FractionalOrdering.first()
                }
            } else if index == items.count - 1 {
                // Last item
                newOrder = FractionalOrdering.atEnd(after: items[index - 1].order)
            } else {
                // Middle item
                newOrder = FractionalOrdering.between(items[index - 1].order, items[index + 1].order)
            }
            
            item.order = newOrder
            item.updatedAt = now
            item.deviceID = currentDeviceID
        }
        
        // Update list modification time
        list.updatedAt = now
        list.deviceID = currentDeviceID
        
        try context.save()
        
        // Periodically normalize ordering to prevent precision issues
        if items.count > 50 {
            try normalizeListOrdering(list)
        }
    }
    
    /// Normalize fractional ordering when it gets too granular
    private func normalizeListOrdering(_ list: MediaList) throws {
        let sortedItems = list.sortedItems
        let now = Date()
        
        for (index, item) in sortedItems.enumerated() {
            item.order = Double(index + 1)
            item.updatedAt = now
            item.deviceID = currentDeviceID
        }
        
        list.updatedAt = now
        list.deviceID = currentDeviceID
        
        try context.save()
    }
}

// MARK: - Supporting Types

struct MergeResult {
    let conflictsResolved: Int
}

// MARK: - LWW Sync Errors

enum LWWSyncError: Error, LocalizedError {
    case listNotFound(String)
    case titleNotFound(String)
    case invalidSyncData
    case networkUnavailable
    case backendError(String)
    case dataCorruption
    
    var errorDescription: String? {
        switch self {
        case .listNotFound(let id):
            return "List with ID \(id) not found"
        case .titleNotFound(let id):
            return "Title with ID \(id) not found"
        case .invalidSyncData:
            return "Invalid sync data received"
        case .networkUnavailable:
            return "Network unavailable for sync"
        case .backendError(let message):
            return "Backend error: \(message)"
        case .dataCorruption:
            return "Data corruption detected during sync"
        }
    }
}

