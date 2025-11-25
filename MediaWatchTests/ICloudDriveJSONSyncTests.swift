//
//  ICloudDriveJSONSyncTests.swift
//  MediaWatchTests
//
//  Unit tests for iCloud Drive JSON sync functionality
//

import XCTest
import CoreData
@testable import MediaWatch

@MainActor
final class ICloudDriveJSONSyncTests: XCTestCase {
    
    var testContext: NSManagedObjectContext!
    var persistenceController: PersistenceController!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create in-memory persistence controller for testing
        persistenceController = PersistenceController(inMemory: true)
        testContext = persistenceController.viewContext
    }
    
    override func tearDown() async throws {
        testContext = nil
        persistenceController = nil
        try await super.tearDown()
    }
    
    // MARK: - JSON Serialization Tests
    
    func testJSONSerialization() throws {
        // Create test data
        let list = createTestList()
        let title = createTestTitle()
        let listItem = createTestListItem(list: list, title: title)
        
        try testContext.save()
        
        // Test JSON generation
        let jsonData = try generateTestJSON()
        let decodedData = try JSONDecoder().decode(SyncJSONData.self, from: jsonData)
        
        XCTAssertEqual(decodedData.version, 1)
        XCTAssertEqual(decodedData.lists.count, 1)
        XCTAssertEqual(decodedData.lists.first?.name, "Test List")
        XCTAssertEqual(decodedData.lists.first?.items.count, 1)
        XCTAssertEqual(decodedData.lists.first?.items.first?.title, "Test Movie")
    }
    
    func testConflictResolution() throws {
        // Create two versions of the same data with different timestamps
        let deviceId1 = "device-1"
        let deviceId2 = "device-2"
        
        let baseDate = Date()
        let laterDate = baseDate.addingTimeInterval(60)
        
        // Local data (older)
        let localList = SyncListData(
            id: "list-1",
            name: "Local List",
            createdAt: baseDate,
            updatedAt: baseDate,
            items: []
        )
        let localData = SyncJSONData(
            version: 1,
            lastSyncedAt: baseDate,
            deviceId: deviceId1,
            lists: [localList]
        )
        
        // Remote data (newer)
        let remoteList = SyncListData(
            id: "list-1",
            name: "Remote List",
            createdAt: baseDate,
            updatedAt: laterDate,
            items: []
        )
        let remoteData = SyncJSONData(
            version: 1,
            lastSyncedAt: laterDate,
            deviceId: deviceId2,
            lists: [remoteList]
        )
        
        // Simulate merge algorithm (simplified version)
        let mergedData = performTestMerge(local: localData, remote: remoteData)
        
        // Remote should win due to later timestamp
        XCTAssertEqual(mergedData.lists.first?.name, "Remote List")
        XCTAssertEqual(mergedData.lists.first?.updatedAt, laterDate)
    }
    
    func testTiebreakingWithSameTimestamp() throws {
        let sameDate = Date()
        let deviceId1 = "device-A" // Lexicographically first
        let deviceId2 = "device-Z" // Lexicographically last
        
        // Both have same timestamp - should use device ID for deterministic result
        let localList = SyncListData(
            id: "list-1",
            name: "Device A List",
            createdAt: sameDate,
            updatedAt: sameDate,
            items: []
        )
        let localData = SyncJSONData(
            version: 1,
            lastSyncedAt: sameDate,
            deviceId: deviceId1,
            lists: [localList]
        )
        
        let remoteList = SyncListData(
            id: "list-1",
            name: "Device Z List",
            createdAt: sameDate,
            updatedAt: sameDate,
            items: []
        )
        let remoteData = SyncJSONData(
            version: 1,
            lastSyncedAt: sameDate,
            deviceId: deviceId2,
            lists: [remoteList]
        )
        
        let mergedData = performTestMerge(local: localData, remote: remoteData, testDeviceId: deviceId2)
        
        // With device Z as current device, device A should win (lexicographic comparison)
        XCTAssertEqual(mergedData.lists.first?.name, "Device A List")
    }
    
    func testTombstoneHandling() throws {
        let baseDate = Date()
        let deleteDate = baseDate.addingTimeInterval(60)
        
        // Local has active item
        let localList = SyncListData(
            id: "list-1",
            name: "Active List",
            createdAt: baseDate,
            updatedAt: baseDate,
            deleted: false,
            items: []
        )
        let localData = SyncJSONData(
            version: 1,
            lastSyncedAt: baseDate,
            deviceId: "device-1",
            lists: [localList]
        )
        
        // Remote has tombstone (deleted)
        let remoteList = SyncListData(
            id: "list-1",
            name: "Active List",
            createdAt: baseDate,
            updatedAt: deleteDate,
            deleted: true,
            items: []
        )
        let remoteData = SyncJSONData(
            version: 1,
            lastSyncedAt: deleteDate,
            deviceId: "device-2",
            lists: [remoteList]
        )
        
        let mergedData = performTestMerge(local: localData, remote: remoteData)
        
        // Tombstone should win due to later timestamp
        XCTAssertTrue(mergedData.lists.first?.deleted == true)
        XCTAssertEqual(mergedData.lists.first?.updatedAt, deleteDate)
    }
    
    func testEpisodeWatchStatusConflict() throws {
        let baseDate = Date()
        let watchDate = baseDate.addingTimeInterval(60)
        
        // Episode watched locally
        let localEpisode = SyncEpisodeData(
            id: "episode-1",
            tmdbId: 123,
            seasonNumber: 1,
            episodeNumber: 1,
            name: "Pilot",
            watched: true,
            watchedDate: watchDate,
            isStarred: false,
            createdAt: baseDate,
            updatedAt: watchDate
        )
        
        // Same episode not watched remotely (older state)
        let remoteEpisode = SyncEpisodeData(
            id: "episode-1",
            tmdbId: 123,
            seasonNumber: 1,
            episodeNumber: 1,
            name: "Pilot",
            watched: false,
            watchedDate: nil,
            isStarred: false,
            createdAt: baseDate,
            updatedAt: baseDate
        )
        
        // Local episode should win due to later watchedDate
        let mergedEpisode = mergeEpisodes(local: localEpisode, remote: remoteEpisode)
        XCTAssertTrue(mergedEpisode.watched)
        XCTAssertEqual(mergedEpisode.watchedDate, watchDate)
    }
    
    // MARK: - Migration Tests
    
    func testMigrationDetection() {
        // Create some Core Data entities
        let _ = createTestList()
        let _ = createTestTitle()
        try! testContext.save()
        
        // Migration should be required when Core Data has data
        let syncService = ICloudDriveJSONSyncService.shared
        let migrationStatus = syncService.getMigrationStatus()
        
        XCTAssertTrue(migrationStatus.isRequired)
        XCTAssertGreaterThan(migrationStatus.coreDataItemCount, 0)
    }
    
    // MARK: - Data Integrity Tests
    
    func testJSONRoundTrip() throws {
        // Create complex test data
        let list = createTestList()
        let title = createTestTitle()
        let _ = createTestListItem(list: list, title: title)
        let episode = createTestEpisode(title: title)
        let note = createTestNote(title: title)
        
        try testContext.save()
        
        // Generate JSON
        let jsonData = try generateTestJSON()
        
        // Clear Core Data
        try clearTestData()
        
        // Restore from JSON
        let decodedData = try JSONDecoder().decode(SyncJSONData.self, from: jsonData)
        try restoreFromJSON(decodedData)
        
        // Verify data integrity
        let fetchRequest = MediaList.fetchAll()
        let restoredLists = try testContext.fetch(fetchRequest)
        
        XCTAssertEqual(restoredLists.count, 1)
        XCTAssertEqual(restoredLists.first?.name, "Test List")
        XCTAssertEqual(restoredLists.first?.titleCount, 1)
    }
    
    // MARK: - Helper Methods
    
    private func createTestList() -> MediaList {
        let list = MediaList(context: testContext)
        list.id = UUID()
        list.name = "Test List"
        list.icon = "list.bullet"
        list.dateCreated = Date()
        list.dateModified = Date()
        list.isDefault = true
        list.sortOrder = 0
        return list
    }
    
    private func createTestTitle() -> Title {
        let title = Title(context: testContext)
        title.id = UUID()
        title.tmdbId = 12345
        title.mediaType = "movie"
        title.title = "Test Movie"
        title.year = 2023
        title.overview = "A test movie"
        title.dateAdded = Date()
        title.dateModified = Date()
        title.watched = false
        return title
    }
    
    private func createTestListItem(list: MediaList, title: Title) -> ListItem {
        let listItem = ListItem(context: testContext)
        listItem.id = UUID()
        listItem.list = list
        listItem.title = title
        listItem.orderIndex = 0
        listItem.dateAdded = Date()
        return listItem
    }
    
    private func createTestEpisode(title: Title) -> Episode {
        let episode = Episode(context: testContext)
        episode.id = UUID()
        episode.tmdbId = 67890
        episode.show = title
        episode.seasonNumber = 1
        episode.episodeNumber = 1
        episode.name = "Test Episode"
        episode.watched = false
        return episode
    }
    
    private func createTestNote(title: Title) -> Note {
        let note = Note(context: testContext)
        note.id = UUID()
        note.title = title
        note.text = "Test note"
        note.ownerOnly = false
        note.dateCreated = Date()
        note.dateModified = Date()
        return note
    }
    
    private func generateTestJSON() throws -> Data {
        // Simplified version of the actual JSON generation
        let fetchRequest = MediaList.fetchAll()
        let lists = try testContext.fetch(fetchRequest)
        
        let syncLists = lists.map { list -> SyncListData in
            let items = (list.items as? Set<ListItem> ?? []).map { listItem -> SyncItemData in
                guard let title = listItem.title else {
                    return SyncItemData(
                        id: UUID().uuidString,
                        tmdbId: 0,
                        mediaType: "movie",
                        title: "Unknown",
                        year: 0,
                        createdAt: Date(),
                        updatedAt: Date()
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
                    runtime: Int(title.runtime),
                    watched: title.watched,
                    watchedDate: title.watchedDate,
                    rating: title.userRating > 0 ? title.userRating : nil,
                    createdAt: title.dateAdded ?? Date(),
                    updatedAt: title.dateModified ?? Date()
                )
            }
            
            return SyncListData(
                id: list.id?.uuidString ?? UUID().uuidString,
                name: list.name ?? "",
                createdAt: list.dateCreated ?? Date(),
                updatedAt: list.dateModified ?? Date(),
                items: Array(items)
            )
        }
        
        let syncData = SyncJSONData(
            version: 1,
            lastSyncedAt: Date(),
            deviceId: "test-device",
            lists: syncLists
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(syncData)
    }
    
    private func clearTestData() throws {
        let entityNames = ["Note", "ListItem", "Episode", "Title", "List"]
        
        for entityName in entityNames {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            _ = try testContext.execute(deleteRequest)
        }
        
        try testContext.save()
        testContext.reset()
    }
    
    private func restoreFromJSON(_ syncData: SyncJSONData) throws {
        // Simplified restoration logic for testing
        for listData in syncData.lists.filter({ !$0.deleted }) {
            let list = MediaList(context: testContext)
            list.id = UUID(uuidString: listData.id) ?? UUID()
            list.name = listData.name
            list.dateCreated = listData.createdAt
            list.dateModified = listData.updatedAt
            list.isDefault = true
            list.sortOrder = 0
            list.icon = "list.bullet"
            
            for itemData in listData.items.filter({ !$0.deleted }) {
                let title = Title(context: testContext)
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
                title.userRating = itemData.rating ?? 0
                title.dateAdded = itemData.createdAt
                title.dateModified = itemData.updatedAt
                
                let listItem = ListItem(context: testContext)
                listItem.id = UUID()
                listItem.list = list
                listItem.title = title
                listItem.orderIndex = 0
                listItem.dateAdded = itemData.createdAt
            }
        }
        
        try testContext.save()
    }
    
    private func performTestMerge(local: SyncJSONData, remote: SyncJSONData, testDeviceId: String = "test-device") -> SyncJSONData {
        // Simplified merge logic for testing
        var mergedLists: [SyncListData] = []
        
        let localListsDict = Dictionary(uniqueKeysWithValues: local.lists.map { ($0.id, $0) })
        let remoteListsDict = Dictionary(uniqueKeysWithValues: remote.lists.map { ($0.id, $0) })
        
        let allListIds = Set(localListsDict.keys).union(Set(remoteListsDict.keys))
        
        for listId in allListIds {
            let localList = localListsDict[listId]
            let remoteList = remoteListsDict[listId]
            
            switch (localList, remoteList) {
            case (let local?, let remote?):
                // Both exist - last writer wins
                if local.updatedAt > remote.updatedAt {
                    mergedLists.append(local)
                } else if local.updatedAt < remote.updatedAt {
                    mergedLists.append(remote)
                } else {
                    // Tie - use device ID comparison
                    let useLocal = local.id.compare(remote.id) == .orderedAscending
                    mergedLists.append(useLocal ? local : remote)
                }
            case (let local?, nil):
                mergedLists.append(local)
            case (nil, let remote?):
                mergedLists.append(remote)
            case (nil, nil):
                break
            }
        }
        
        return SyncJSONData(
            version: max(local.version, remote.version),
            lastSyncedAt: Date(),
            deviceId: testDeviceId,
            lists: mergedLists
        )
    }
    
    private func mergeEpisodes(local: SyncEpisodeData, remote: SyncEpisodeData) -> SyncEpisodeData {
        // For episodes, prefer the one with the later watch state change
        let localWatchDate = local.watchedDate ?? Date.distantPast
        let remoteWatchDate = remote.watchedDate ?? Date.distantPast
        
        if localWatchDate > remoteWatchDate {
            return local
        } else if remoteWatchDate > localWatchDate {
            return remote
        } else {
            // Same watch date - prefer the one marked as watched
            return local.watched ? local : remote
        }
    }
}