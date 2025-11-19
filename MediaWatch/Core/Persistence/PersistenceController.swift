//
//  PersistenceController.swift
//  MediaWatch
//
//  Core Data + CloudKit persistence controller with sharing support
//

import CoreData
import CloudKit

/// Manages Core Data persistence with CloudKit sync and sharing
final class PersistenceController: ObservableObject {

    // MARK: - Shared Instance

    static let shared = PersistenceController()

    // MARK: - Preview Instance

    @MainActor
    static let preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)
        let context = controller.container.viewContext

        // Create sample list
        let list = MediaList(context: context)
        list.id = UUID()
        list.name = "Watchlist"
        list.icon = "list.bullet"
        list.sortOrder = 0
        list.isDefault = true
        list.dateCreated = Date()
        list.dateModified = Date()

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
        movie.dateAdded = Date()
        movie.dateModified = Date()

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
        tvShow.dateAdded = Date()
        tvShow.dateModified = Date()

        // Add titles to list
        let listItem1 = ListItem(context: context)
        listItem1.id = UUID()
        listItem1.list = list
        listItem1.title = movie
        listItem1.orderIndex = 0
        listItem1.dateAdded = Date()

        let listItem2 = ListItem(context: context)
        listItem2.id = UUID()
        listItem2.list = list
        listItem2.title = tvShow
        listItem2.orderIndex = 1
        listItem2.dateAdded = Date()

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
                if ep.watched {
                    ep.watchedDate = Date()
                }
            }
        }

        do {
            try context.save()
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
    private let cloudKitContainerIdentifier = "iCloud.com.mediawatch.app"

    // MARK: - Computed Properties

    var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    // MARK: - Initialization

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "MediaWatch")

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        } else {
            configureCloudKitStores()
        }

        // Configure store descriptions for history tracking
        container.persistentStoreDescriptions.forEach { description in
            description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        }

        container.loadPersistentStores { [weak self] description, error in
            if let error = error as NSError? {
                // In production, handle this more gracefully
                fatalError("Failed to load persistent store: \(error), \(error.userInfo)")
            }

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

    // MARK: - CloudKit Configuration

    private func configureCloudKitStores() {
        guard let description = container.persistentStoreDescriptions.first else {
            fatalError("No persistent store descriptions found")
        }

        // Configure private store
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: cloudKitContainerIdentifier
        )

        // Configure shared store
        let sharedStoreURL = description.url!
            .deletingLastPathComponent()
            .appendingPathComponent("MediaWatch-shared.sqlite")

        let sharedDescription = NSPersistentStoreDescription(url: sharedStoreURL)
        sharedDescription.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: cloudKitContainerIdentifier
        )
        sharedDescription.cloudKitContainerOptions?.databaseScope = .shared

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
}

// MARK: - Notification Names

extension Notification.Name {
    static let didReceiveRemoteChanges = Notification.Name("didReceiveRemoteChanges")
}
