//
//  PersistenceController.swift
//  MediaShows
//
//  Core Data + CloudKit persistence controller with sharing support
//

import CoreData
import CloudKit
import UIKit

/// Manages Core Data persistence with CloudKit sync and sharing
final class PersistenceController: ObservableObject {

    // MARK: - Shared Instance

    static let shared = PersistenceController()

    // MARK: - Preview Instance

    @MainActor
    static let preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext

        // Create sample list with LWW fields
        let list = MediaList(context: context)
        list.id = UUID()
        list.name = "Shared"
        list.icon = "list.bullet"
        list.order = 0.0
        list.isDefault = true
        list.createdAt = Date()
        list.updatedAt = Date()
        list.deviceID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString

        // Create sample movie
        let movie = Title(context: context)
        movie.id = UUID()
        movie.tmdbId = 550
        movie.mediaType = "movie"
        movie.title = "Fight Club"
        movie.year = 1999
        movie.overview = "A depressed man suffering from insomnia meets a strange soap salesman named Tyler Durden and soon finds himself living in his squalid house after his perfect apartment is destroyed."
        movie.runtime = 139
        movie.posterPath = "/pB8BM7pdSp6B6Ih7QZ4DrQ3PmJK.jpg"
        movie.voteAverage = 8.4
        movie.createdAt = Date()
        movie.updatedAt = Date()
        movie.deviceID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString

        // Create sample TV show
        let tvShow = Title(context: context)
        tvShow.id = UUID()
        tvShow.tmdbId = 1396
        tvShow.mediaType = "tv"
        tvShow.title = "Breaking Bad"
        tvShow.year = 2008
        tvShow.overview = "When Walter White, a New Mexico chemistry teacher, is diagnosed with Stage III cancer and given a prognosis of only two years left to live, he becomes filled with a sense of fearlessness."
        tvShow.numberOfSeasons = 5
        tvShow.numberOfEpisodes = 62
        tvShow.posterPath = "/ggFHVNu6YYI5L9pCfOacjizRGt.jpg"
        tvShow.voteAverage = 8.9
        tvShow.status = "Ended"
        tvShow.createdAt = Date()
        tvShow.updatedAt = Date()
        tvShow.deviceID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString

        // Add titles to list
        let listItem1 = ListItem(context: context)
        listItem1.id = UUID()
        listItem1.list = list
        listItem1.title = movie
        listItem1.order = 0.0
        listItem1.createdAt = Date()
        listItem1.updatedAt = Date()
        listItem1.deviceID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString

        let listItem2 = ListItem(context: context)
        listItem2.id = UUID()
        listItem2.list = list
        listItem2.title = tvShow
        listItem2.order = 1.0
        listItem2.createdAt = Date()
        listItem2.updatedAt = Date()
        listItem2.deviceID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString

        // Create sample episodes for TV show
        for season in 1...2 {
            for episode in 1...3 {
                let ep = Episode(context: context)
                ep.id = UUID()
                ep.show = tvShow
                ep.seasonNumber = Int16(season)
                ep.episodeNumber = Int16(episode)
                ep.name = "Episode \(episode)"
                ep.watched = season == 1
                ep.createdAt = Date()
                ep.updatedAt = Date()
                ep.deviceID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
                if ep.watched {
                    ep.watchedDate = Date()
                }
            }
        }

        do {
            try context.save()
            // print("Saved line 98 to Core Data / CloudKit")
        } catch {
            let nsError = error as NSError
            fatalError("Unresolved error \(nsError), \(nsError.userInfo)")
        }

        return controller
    }()

    // MARK: - Properties

    let container: NSPersistentCloudKitContainer

    private var privateStore: NSPersistentStore?
    private var sharedStore: NSPersistentStore?

    /// CloudKit container identifier
    private let cloudKitContainerIdentifier = "iCloud.reasonality.MediaShows" //was iCloud.com.MediaShows.app"

    // MARK: - Computed Properties

    var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    // MARK: - Initialization

    init(inMemory: Bool = false) {
        // MARK: - IMMEDIATE LWW RESET - BEFORE ANYTHING ELSE
        if !inMemory {
            let currentVersion = "1.56"
            let storedVersion = UserDefaults.standard.string(forKey: "app_version")
            let forceReset = storedVersion != currentVersion
            
            if forceReset {
                print("💣 IMMEDIATE RESET: Version change detected (\(storedVersion ?? "nil") → \(currentVersion))")
                print("💣 DELETING ALL STORES BEFORE Core Data initialization")
                
                // Delete immediately before any Core Data setup
                let storeDirectory = NSPersistentContainer.defaultDirectoryURL()
                let fileManager = FileManager.default
                
                // Delete ALL possible Core Data files
                do {
                    let allFiles = try fileManager.contentsOfDirectory(at: storeDirectory, includingPropertiesForKeys: nil)
                    for fileURL in allFiles {
                        let fileName = fileURL.lastPathComponent
                        if fileName.contains("MediaShows") || 
                           fileName.hasSuffix(".sqlite") ||
                           fileName.hasSuffix(".sqlite-shm") ||
                           fileName.hasSuffix(".sqlite-wal") ||
                           fileName.contains("ckAssetFiles") ||
                           fileName.contains(".cksqlite") {
                            try? fileManager.removeItem(at: fileURL)
                            print("🗑️ Deleted: \(fileName)")
                        }
                    }
                } catch {
                    print("⚠️ Could not list store directory: \(error)")
                }
                
                // Also clear CloudKit cache
                UserDefaults.standard.removeObject(forKey: "NSCloudKitMirroringDelegateLastHistoryTokenKey")
                UserDefaults.standard.removeObject(forKey: "PersistentCloudKitContainer.event.setupStarted")
                UserDefaults.standard.removeObject(forKey: "PersistentCloudKitContainer.event.setupFinished")
                
                // Also clear any Core Data UserDefaults that might cause issues
                UserDefaults.standard.removeObject(forKey: "lww_migration_completed")
                UserDefaults.standard.removeObject(forKey: "lww_migration_date")
                UserDefaults.standard.synchronize()
                
                // Force CloudKit to reset by clearing container identifier cache
                UserDefaults.standard.removeObject(forKey: "com.apple.coredata.cloudkit.zone.ownerName")
                UserDefaults.standard.removeObject(forKey: "NSCloudKitMirroringDelegate.setup")
                UserDefaults.standard.synchronize()
                
                UserDefaults.standard.set(currentVersion, forKey: "app_version")
                print("✅ NUCLEAR RESET complete - all stores, CloudKit cache, and preferences cleared")
                print("📱 Fresh LWW-compatible stores will be created on next launch")
            } else {
                print("ℹ️ Version \(currentVersion) already installed - no reset needed")
            }
        }
        
        container = NSPersistentCloudKitContainer(name: "MediaShows")

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        } else {
            configureCloudKitStores()
        }

        // Configure store descriptions for history tracking and migration
        container.persistentStoreDescriptions.forEach { description in
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
            // print("Final store description: \(description.url?.lastPathComponent ?? "nil")") //meb
             // print("CloudKit container: \(description.cloudKitContainerOptions?.containerIdentifier ?? "nil")") //meb
            // print("Database scope: \(description.cloudKitContainerOptions?.databaseScope.rawValue ?? -1)")  //meb
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        }

        container.loadPersistentStores { [weak self] description, error in
            if let error = error as NSError? {
                print("⚠️ Core Data load error: \(error)")
                print("⚠️ Description: \(description)")
                
                // ULTRA AGGRESSIVE: Delete everything and force fresh start
                let storeDirectory = NSPersistentContainer.defaultDirectoryURL()
                let fileManager = FileManager.default
                
                // Delete ALL Core Data files we can find
                do {
                    let allFiles = try fileManager.contentsOfDirectory(at: storeDirectory, includingPropertiesForKeys: nil)
                    for fileURL in allFiles {
                        if fileURL.pathExtension == "sqlite" || 
                           fileURL.lastPathComponent.contains("sqlite") ||
                           fileURL.lastPathComponent.contains("MediaShows") {
                            try? fileManager.removeItem(at: fileURL)
                            print("🔥 Emergency deleted: \(fileURL.lastPathComponent)")
                        }
                    }
                } catch {
                    print("Could not list store directory: \(error)")
                }
                
                // Try one more time with completely fresh store
                print("🔄 Attempting fresh store creation...")
            }

            // print("Loaded store URL: \(description.url?.absoluteString ?? "nil")")  //meb
            // print("Loaded CloudKit container: \(description.cloudKitContainerOptions?.containerIdentifier ?? "nil")") //meb
            // print("Loaded database scope: \(description.cloudKitContainerOptions?.databaseScope.rawValue ?? -1)") //meb

            
            // Track which store is which
            if description.cloudKitContainerOptions?.databaseScope == .shared {
                self?.sharedStore = self?.container.persistentStoreCoordinator.persistentStore(for: description.url!)
            } else {
                self?.privateStore = self?.container.persistentStoreCoordinator.persistentStore(for: description.url!)
            }
        }

        // Configure view context
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.name = "viewContext"

        // Pin to current query generation for consistent reads
        try? container.viewContext.setQueryGenerationFrom(.current)

        // Listen for remote changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRemoteChange(_:)),
            name: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator
        )
    }

    // MARK: - LWW Migration Handling
    
    private func checkAndHandleLWWMigration() {
        // Check if this is a pre-LWW install that needs reset
        let lwwMigrated = UserDefaults.standard.bool(forKey: "lww_migration_completed")
        
        if !lwwMigrated {
            // This is either a fresh install or needs migration to LWW
            // For TestFlight safety, we'll delete existing stores and start fresh
            deleteLegacyStores()
            UserDefaults.standard.set(true, forKey: "lww_migration_completed")
            UserDefaults.standard.set(Date(), forKey: "lww_migration_date")
            print("✅ LWW Migration: Completed fresh store creation")
        }
    }
    
    private func deleteLegacyStores() {
        let storeDirectory = NSPersistentContainer.defaultDirectoryURL()
        let fileManager = FileManager.default
        
        // Delete all Core Data files
        let filesToDelete = [
            "MediaShows.sqlite",
            "MediaShows.sqlite-shm",
            "MediaShows.sqlite-wal",
            "MediaShows-shared.sqlite",
            "MediaShows-shared.sqlite-shm", 
            "MediaShows-shared.sqlite-wal"
        ]
        
        for fileName in filesToDelete {
            let fileURL = storeDirectory.appendingPathComponent(fileName)
            try? fileManager.removeItem(at: fileURL)
        }
        
        print("🔄 Deleted legacy Core Data stores for LWW migration")
    }
    
    private func destroyAndRecreateStore(at storeURL: URL, description: NSPersistentStoreDescription) throws {
        print("💣 DESTROYING CORRUPTED STORE: \(storeURL)")
        
        let fileManager = FileManager.default
        let storeDirectory = storeURL.deletingLastPathComponent()
        let storeName = storeURL.deletingPathExtension().lastPathComponent
        
        // Delete all related files
        let relatedFiles = [
            "\(storeName).sqlite",
            "\(storeName).sqlite-shm",
            "\(storeName).sqlite-wal"
        ]
        
        for fileName in relatedFiles {
            let fileURL = storeDirectory.appendingPathComponent(fileName)
            try? fileManager.removeItem(at: fileURL)
        }
        
        // Try to recreate the store
        do {
            let _ = try container.persistentStoreCoordinator.addPersistentStore(
                ofType: NSSQLiteStoreType,
                configurationName: nil,
                at: storeURL,
                options: [
                    NSMigratePersistentStoresAutomaticallyOption: true,
                    NSInferMappingModelAutomaticallyOption: true
                ]
            )
            print("✅ Successfully recreated store at \(storeURL)")
        } catch {
            print("❌ Failed to recreate store: \(error)")
            fatalError("Could not recreate Core Data store after corruption")
        }
    }

    // MARK: - CloudKit Configuration

    private func configureCloudKitStores() {
        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("No persistent store descriptions found")
        }

        // Configure private store
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: cloudKitContainerIdentifier
        )

        // print("Private store URL: \(description.url?.absoluteString ?? "nil")") //meb
        // print("Private CloudKit container: \(description.cloudKitContainerOptions?.containerIdentifier ?? "nil")") //meb

        
        // Configure shared store
        let sharedStoreURL = description.url!
            .deletingLastPathComponent()
            .appendingPathComponent("MediaShows-shared.sqlite")

        let sharedDescription = NSPersistentStoreDescription(url: sharedStoreURL)
        sharedDescription.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: cloudKitContainerIdentifier
        )
        sharedDescription.cloudKitContainerOptions?.databaseScope = .shared
        
        // print("Shared store URL: \(sharedDescription.url?.absoluteString ?? "nil")")  //meb
        // print("Shared CloudKit container: \(sharedDescription.cloudKitContainerOptions?.containerIdentifier ?? "nil")") //meb
        // print("Shared database scope: \(sharedDescription.cloudKitContainerOptions?.databaseScope.rawValue ?? -1)")  //meb
        

        // Enable history tracking for shared store
        sharedDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        sharedDescription.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        container.persistentStoreDescriptions.append(sharedDescription)
    }

    // MARK: - Context Management

    /// Creates a new background context for performing work off the main thread
    func newBackgroundContext() -> NSManagedObjectContext {
        let context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        return context
    }

    // MARK: - Save Operations

    /// Saves the view context if there are changes
    @discardableResult
    func save() -> Bool {
        let context = viewContext
        guard context.hasChanges else { return true }

        do {
            try context.save()
            // print("Saved movie to Core Data / CloudKit")
            return true
        } catch {
            let nsError = error as NSError
            print("Failed to save context: \(nsError), \(nsError.userInfo)")
            return false
        }
    }

    /// Saves a specific context
    func save(context: NSManagedObjectContext) throws {
        guard context.hasChanges else { return }
        try context.save()
        // print("Saved content line 232  to Core Data / CloudKit")
    }

    // MARK: - Sharing

    /// Checks if an object is shared
    func isShared(_ object: NSManagedObject) -> Bool {
        isShared(objectID: object.objectID)
    }

    /// Checks if an object ID is in the shared store
    func isShared(objectID: NSManagedObjectID) -> Bool {
        guard let persistentStore = objectID.persistentStore else { return false }

        if persistentStore == sharedStore {
            return true
        }

        // Check if it has a share
        do {
            let shares = try container.fetchShares(matching: [objectID])
            return !shares.isEmpty
        } catch {
            print("Failed to fetch shares: \(error)")
            return false
        }
    }

    /// Gets the share for an object if it exists
    func share(for object: NSManagedObject) -> CKShare? {
        guard isShared(object) else { return nil }

        do {
            let shares = try container.fetchShares(matching: [object.objectID])
            return shares[object.objectID]
        } catch {
            print("Failed to fetch share: \(error)")
            return nil
        }
    }

    /// Fetches all shares
    func fetchAllShares() async throws -> [CKShare] {
        try await container.fetchShares(in: nil)
    }

    /// Creates a share for a list and its contents
    func shareList(_ list: MediaList) async throws -> CKShare {
        var objectsToShare: [NSManagedObject] = [list]

        // Include all list items and their titles
        if let items = list.items as? Set<ListItem> {
            for item in items {
                objectsToShare.append(item)

                if let title = item.title {
                    objectsToShare.append(title)

                    // Include episodes
                    if let episodes = title.episodes as? Set<Episode> {
                        objectsToShare.append(contentsOf: episodes)
                    }

                    // Include non-private notes
                    if let notes = title.notes as? Set<Note> {
                        let sharedNotes = notes.filter { !$0.ownerOnly }
                        objectsToShare.append(contentsOf: sharedNotes)
                    }
                }
            }
        }

        let (_, share, _) = try await container.share(objectsToShare, to: nil)

        // Configure share metadata
        share[CKShare.SystemFieldKey.title] = list.name
        share.publicPermission = .none

        return share
    }

    /// Accepts a share from another user
    func acceptShare(_ metadata: CKShare.Metadata) async throws {
        try await container.acceptShareInvitations(from: [metadata], into: sharedStore!)
    }

    // MARK: - Remote Change Handling

    @objc private func handleRemoteChange(_ notification: Notification) {
        // Process persistent history to merge remote changes
        // This happens automatically with automaticallyMergesChangesFromParent = true
        // but we can add custom logic here if needed

        DispatchQueue.main.async {
            // Post notification for UI updates if needed
            NotificationCenter.default.post(name: .didReceiveRemoteChanges, object: nil)
        }
    }

    // MARK: - Utility

    /// Deletes all data (for testing/reset)
    func deleteAllData() throws {
        let entityNames = container.managedObjectModel.entities.compactMap { $0.name }

        for entityName in entityNames {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            deleteRequest.resultType = .resultTypeObjectIDs

            let result = try viewContext.execute(deleteRequest) as? NSBatchDeleteResult
            let objectIDs = result?.result as? [NSManagedObjectID] ?? []

            let changes = [NSDeletedObjectsKey: objectIDs]
            NSManagedObjectContext.mergeChanges(fromRemoteContextSave: changes, into: [viewContext])
        }
    }
    
    /// NUCLEAR OPTION: Clear all local data and CloudKit sync state
    func clearAllDataAndCloudKitState() {
        print("💣 MANUAL NUCLEAR CLEAR: Deleting all data and CloudKit state")
        
        // 1. Delete all Core Data objects
        do {
            try deleteAllData()
            try viewContext.save()
            print("✅ Deleted all Core Data objects")
        } catch {
            print("❌ Failed to delete Core Data objects: \(error)")
        }
        
        // 2. Clear all CloudKit sync tokens
        UserDefaults.standard.removeObject(forKey: "NSCloudKitMirroringDelegateLastHistoryTokenKey")
        UserDefaults.standard.removeObject(forKey: "PersistentCloudKitContainer.event.setupStarted")
        UserDefaults.standard.removeObject(forKey: "PersistentCloudKitContainer.event.setupFinished")
        UserDefaults.standard.removeObject(forKey: "com.apple.coredata.cloudkit.zone.ownerName")
        UserDefaults.standard.removeObject(forKey: "NSCloudKitMirroringDelegate.setup")
        
        // 3. Clear all LWW migration flags
        UserDefaults.standard.removeObject(forKey: "lww_migration_completed")
        UserDefaults.standard.removeObject(forKey: "lww_migration_date")
        UserDefaults.standard.removeObject(forKey: "needs_lww_migration")
        
        // 4. Reset app version to force fresh setup
        UserDefaults.standard.removeObject(forKey: "app_version")
        UserDefaults.standard.synchronize()
        
        print("✅ NUCLEAR CLEAR complete - app will restart with fresh LWW setup")
        
        // 5. Force app restart to reload everything cleanly
        DispatchQueue.main.async {
            exit(0)
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let didReceiveRemoteChanges = Notification.Name("didReceiveRemoteChanges")
}
