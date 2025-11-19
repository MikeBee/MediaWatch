# MediaWatch - Architecture

## Overview

MediaWatch follows a clean MVVM (Model-View-ViewModel) architecture with SwiftUI, leveraging modern Swift concurrency, Combine for reactive updates, and Core Data with CloudKit for persistence and sync.

---

## 1. Architecture Layers

```
┌─────────────────────────────────────────────────┐
│                   Views (SwiftUI)               │
│  - Declarative UI                               │
│  - Observes ViewModels                          │
│  - User interactions                            │
└─────────────────────┬───────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────┐
│               ViewModels (@Observable)          │
│  - Business logic                               │
│  - State management                             │
│  - Coordinates Services                         │
└─────────────────────┬───────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────┐
│                   Services                      │
│  - Data operations                              │
│  - API communication                            │
│  - CloudKit sync                                │
└─────────────────────┬───────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────┐
│            Core Data + CloudKit                 │
│  - NSPersistentCloudKitContainer               │
│  - Managed Object Context                       │
│  - Automatic sync                               │
└─────────────────────────────────────────────────┘
```

---

## 2. Project Structure

```
MediaWatch/
├── App/
│   ├── MediaWatchApp.swift          # App entry point
│   ├── AppDelegate.swift            # CloudKit notifications
│   └── SceneDelegate.swift          # Scene lifecycle
│
├── Core/
│   ├── Persistence/
│   │   ├── PersistenceController.swift
│   │   ├── CoreDataStack.swift
│   │   └── CloudKitManager.swift
│   │
│   ├── Services/
│   │   ├── TMDbService.swift
│   │   ├── ImageCacheService.swift
│   │   ├── BackupService.swift
│   │   └── SyncService.swift
│   │
│   └── Utilities/
│       ├── Constants.swift
│       ├── Extensions/
│       └── Helpers/
│
├── Features/
│   ├── Library/
│   │   ├── Views/
│   │   │   ├── LibraryView.swift
│   │   │   ├── ListsView.swift
│   │   │   ├── ListDetailView.swift
│   │   │   └── Components/
│   │   └── ViewModels/
│   │       ├── LibraryViewModel.swift
│   │       └── ListDetailViewModel.swift
│   │
│   ├── Search/
│   │   ├── Views/
│   │   │   ├── SearchView.swift
│   │   │   ├── SearchResultsView.swift
│   │   │   └── AddTitleView.swift
│   │   └── ViewModels/
│   │       ├── SearchViewModel.swift
│   │       └── AddTitleViewModel.swift
│   │
│   ├── TitleDetail/
│   │   ├── Views/
│   │   │   ├── TitleDetailView.swift
│   │   │   ├── EpisodesListView.swift
│   │   │   ├── NotesView.swift
│   │   │   └── Components/
│   │   └── ViewModels/
│   │       └── TitleDetailViewModel.swift
│   │
│   ├── Settings/
│   │   ├── Views/
│   │   │   ├── SettingsView.swift
│   │   │   ├── BackupView.swift
│   │   │   └── AboutView.swift
│   │   └── ViewModels/
│   │       └── SettingsViewModel.swift
│   │
│   └── Sharing/
│       ├── Views/
│       │   ├── ShareListView.swift
│       │   └── SharedWithMeView.swift
│       └── ViewModels/
│           └── SharingViewModel.swift
│
├── Models/
│   ├── CoreData/
│   │   ├── MediaWatch.xcdatamodeld
│   │   ├── Title+Extensions.swift
│   │   ├── Episode+Extensions.swift
│   │   ├── List+Extensions.swift
│   │   ├── ListItem+Extensions.swift
│   │   └── Note+Extensions.swift
│   │
│   └── DTOs/
│       ├── TMDbModels.swift
│       └── ExportModels.swift
│
├── Resources/
│   ├── Assets.xcassets
│   ├── Localizable.strings
│   └── Info.plist
│
└── MediaWatch.entitlements
```

---

## 3. Core Components

### 3.1 PersistenceController

Central manager for Core Data and CloudKit operations.

```swift
import CoreData
import CloudKit

@MainActor
final class PersistenceController: ObservableObject {
    static let shared = PersistenceController()

    let container: NSPersistentCloudKitContainer

    // Private and shared store coordinators
    private var privateStore: NSPersistentStore?
    private var sharedStore: NSPersistentStore?

    init(inMemory: Bool = false) {
        container = NSPersistentCloudKitContainer(name: "MediaWatch")

        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        } else {
            setupCloudKitStores()
        }

        container.loadPersistentStores { description, error in
            if let error = error {
                fatalError("Core Data failed to load: \(error.localizedDescription)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        // Track persistent history
        container.persistentStoreDescriptions.forEach { description in
            description.setOption(true as NSNumber,
                                  forKey: NSPersistentHistoryTrackingKey)
            description.setOption(true as NSNumber,
                                  forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        }
    }

    private func setupCloudKitStores() {
        guard let description = container.persistentStoreDescriptions.first else { return }

        let containerIdentifier = "iCloud.com.yourcompany.MediaWatch"

        // Private store
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: containerIdentifier
        )

        // Shared store
        let sharedStoreURL = description.url!
            .deletingLastPathComponent()
            .appendingPathComponent("MediaWatch-shared.sqlite")

        let sharedDescription = NSPersistentStoreDescription(url: sharedStoreURL)
        sharedDescription.configuration = "Shared"
        sharedDescription.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: containerIdentifier
        )
        sharedDescription.cloudKitContainerOptions?.databaseScope = .shared

        container.persistentStoreDescriptions.append(sharedDescription)
    }

    // MARK: - Context Management

    var viewContext: NSManagedObjectContext {
        container.viewContext
    }

    func newBackgroundContext() -> NSManagedObjectContext {
        container.newBackgroundContext()
    }

    // MARK: - Save

    func save() throws {
        let context = viewContext
        if context.hasChanges {
            try context.save()
        }
    }

    // MARK: - Sharing

    func isShared(_ object: NSManagedObject) -> Bool {
        isShared(objectID: object.objectID)
    }

    func isShared(objectID: NSManagedObjectID) -> Bool {
        var isShared = false
        if let persistentStore = objectID.persistentStore {
            if persistentStore == sharedStore {
                isShared = true
            } else {
                let container = persistentCloudKitContainer
                do {
                    let shares = try container.fetchShares(matching: [objectID])
                    isShared = !shares.isEmpty
                } catch {
                    print("Failed to fetch shares: \(error)")
                }
            }
        }
        return isShared
    }

    var persistentCloudKitContainer: NSPersistentCloudKitContainer {
        container
    }
}
```

### 3.2 TMDbService

Handles all TMDb API communication.

```swift
import Foundation

actor TMDbService {
    static let shared = TMDbService()

    private let apiKey: String
    private let baseURL = "https://api.themoviedb.org/3"
    private let imageBaseURL = "https://image.tmdb.org/t/p/"

    private init() {
        // Load API key from secure storage
        apiKey = Bundle.main.infoDictionary?["TMDB_API_KEY"] as? String ?? ""
    }

    // MARK: - Search

    func searchMulti(query: String, page: Int = 1) async throws -> TMDbSearchResponse {
        let endpoint = "/search/multi"
        let queryItems = [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "include_adult", value: "false")
        ]

        return try await request(endpoint: endpoint, queryItems: queryItems)
    }

    // MARK: - Details

    func movieDetails(id: Int) async throws -> TMDbMovieDetail {
        let endpoint = "/movie/\(id)"
        return try await request(endpoint: endpoint)
    }

    func tvDetails(id: Int) async throws -> TMDbTVDetail {
        let endpoint = "/tv/\(id)"
        return try await request(endpoint: endpoint)
    }

    func seasonDetails(tvId: Int, seasonNumber: Int) async throws -> TMDbSeasonDetail {
        let endpoint = "/tv/\(tvId)/season/\(seasonNumber)"
        return try await request(endpoint: endpoint)
    }

    // MARK: - Images

    func imageURL(path: String, size: String = "w500") -> URL? {
        URL(string: "\(imageBaseURL)\(size)\(path)")
    }

    // MARK: - Private

    private func request<T: Decodable>(
        endpoint: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> T {
        var components = URLComponents(string: baseURL + endpoint)!
        var items = queryItems
        items.append(URLQueryItem(name: "api_key", value: apiKey))
        components.queryItems = items

        guard let url = components.url else {
            throw TMDbError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TMDbError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw TMDbError.httpError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        return try decoder.decode(T.self, from: data)
    }
}

enum TMDbError: Error {
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case decodingError(Error)
}
```

### 3.3 ImageCacheService

Manages downloading and caching images locally.

```swift
import SwiftUI
import Foundation

actor ImageCacheService {
    static let shared = ImageCacheService()

    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private var memoryCache = NSCache<NSString, UIImage>()

    private init() {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = caches.appendingPathComponent("ImageCache", isDirectory: true)

        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        memoryCache.countLimit = 100
        memoryCache.totalCostLimit = 50 * 1024 * 1024 // 50MB
    }

    func image(for path: String, size: String = "w500") async throws -> UIImage {
        let cacheKey = "\(size)\(path)" as NSString
        let localURL = cacheDirectory.appendingPathComponent(cacheKey.hash.description)

        // Check memory cache
        if let cached = memoryCache.object(forKey: cacheKey) {
            return cached
        }

        // Check disk cache
        if let data = try? Data(contentsOf: localURL),
           let image = UIImage(data: data) {
            memoryCache.setObject(image, forKey: cacheKey)
            return image
        }

        // Download
        guard let url = await TMDbService.shared.imageURL(path: path, size: size) else {
            throw ImageCacheError.invalidURL
        }

        let (data, _) = try await URLSession.shared.data(from: url)

        guard let image = UIImage(data: data) else {
            throw ImageCacheError.invalidData
        }

        // Save to disk
        try? data.write(to: localURL)

        // Save to memory
        memoryCache.setObject(image, forKey: cacheKey)

        return image
    }

    func clearCache() async throws {
        memoryCache.removeAllObjects()
        try fileManager.removeItem(at: cacheDirectory)
        try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    func cacheSize() async throws -> Int64 {
        let contents = try fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        )

        return try contents.reduce(0) { total, url in
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            return total + Int64(size)
        }
    }
}

enum ImageCacheError: Error {
    case invalidURL
    case invalidData
}
```

---

## 4. ViewModels

### 4.1 Base ViewModel Pattern

```swift
import Foundation
import Observation
import CoreData

@Observable
class BaseViewModel {
    var isLoading = false
    var errorMessage: String?

    let persistenceController: PersistenceController

    var viewContext: NSManagedObjectContext {
        persistenceController.viewContext
    }

    init(persistenceController: PersistenceController = .shared) {
        self.persistenceController = persistenceController
    }

    func save() {
        do {
            try persistenceController.save()
        } catch {
            errorMessage = "Failed to save: \(error.localizedDescription)"
        }
    }

    func handleError(_ error: Error) {
        errorMessage = error.localizedDescription
    }
}
```

### 4.2 LibraryViewModel

```swift
import Foundation
import Observation
import CoreData

@Observable
final class LibraryViewModel: BaseViewModel {
    var lists: [List] = []
    var selectedList: List?
    var searchText = ""

    private var listsController: NSFetchedResultsController<List>?

    override init(persistenceController: PersistenceController = .shared) {
        super.init(persistenceController: persistenceController)
        setupFetchController()
    }

    private func setupFetchController() {
        let request = List.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \List.sortOrder, ascending: true)]

        listsController = NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: viewContext,
            sectionNameKeyPath: nil,
            cacheName: nil
        )

        do {
            try listsController?.performFetch()
            lists = listsController?.fetchedObjects ?? []
        } catch {
            handleError(error)
        }
    }

    func createList(name: String, icon: String? = nil, color: String? = nil) {
        let list = List(context: viewContext)
        list.id = UUID()
        list.name = name
        list.icon = icon
        list.colorHex = color
        list.sortOrder = Int16(lists.count)
        list.dateCreated = Date()
        list.dateModified = Date()

        save()
        lists = listsController?.fetchedObjects ?? []
    }

    func deleteList(_ list: List) {
        viewContext.delete(list)
        save()
        lists = listsController?.fetchedObjects ?? []
    }

    func moveList(from source: IndexSet, to destination: Int) {
        var reorderedLists = lists
        reorderedLists.move(fromOffsets: source, toOffset: destination)

        for (index, list) in reorderedLists.enumerated() {
            list.sortOrder = Int16(index)
        }

        save()
        lists = reorderedLists
    }
}
```

### 4.3 SearchViewModel

```swift
import Foundation
import Observation

@Observable
final class SearchViewModel: BaseViewModel {
    var searchText = ""
    var results: [TMDbSearchResult] = []
    var selectedResult: TMDbSearchResult?

    private var searchTask: Task<Void, Never>?

    func search() {
        searchTask?.cancel()

        guard searchText.count >= 2 else {
            results = []
            return
        }

        searchTask = Task {
            isLoading = true

            do {
                try await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce

                let response = try await TMDbService.shared.searchMulti(query: searchText)
                results = response.results.filter { $0.mediaType == "movie" || $0.mediaType == "tv" }
            } catch is CancellationError {
                // Ignore cancellation
            } catch {
                handleError(error)
            }

            isLoading = false
        }
    }
}
```

### 4.4 TitleDetailViewModel

```swift
import Foundation
import Observation
import CoreData

@Observable
final class TitleDetailViewModel: BaseViewModel {
    var title: Title
    var episodes: [Episode] = []
    var notes: [Note] = []
    var isLoadingEpisodes = false

    init(title: Title, persistenceController: PersistenceController = .shared) {
        self.title = title
        super.init(persistenceController: persistenceController)

        loadEpisodes()
        loadNotes()
    }

    private func loadEpisodes() {
        guard title.mediaType == "tv" else { return }

        let request = Episode.fetchRequest()
        request.predicate = NSPredicate(format: "show == %@", title)
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Episode.seasonNumber, ascending: true),
            NSSortDescriptor(keyPath: \Episode.episodeNumber, ascending: true)
        ]

        do {
            episodes = try viewContext.fetch(request)
        } catch {
            handleError(error)
        }
    }

    private func loadNotes() {
        let request = Note.fetchRequest()
        request.predicate = NSPredicate(format: "title == %@", title)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Note.dateCreated, ascending: false)]

        do {
            notes = try viewContext.fetch(request)
        } catch {
            handleError(error)
        }
    }

    func toggleWatched() {
        title.watched.toggle()
        title.watchedDate = title.watched ? Date() : nil
        title.dateModified = Date()
        save()
    }

    func setLikedStatus(_ status: LikedStatus) {
        title.likedStatus = Int16(status.rawValue)
        title.dateModified = Date()
        save()
    }

    func markAllEpisodesWatched(_ watched: Bool) {
        for episode in episodes {
            episode.watched = watched
            episode.watchedDate = watched ? Date() : nil
            episode.dateModified = Date()
        }
        save()
    }

    func fetchEpisodes() async {
        guard title.mediaType == "tv" else { return }

        isLoadingEpisodes = true

        do {
            let details = try await TMDbService.shared.tvDetails(id: Int(title.tmdbId))

            for seasonNumber in 1...details.numberOfSeasons {
                let seasonDetail = try await TMDbService.shared.seasonDetails(
                    tvId: Int(title.tmdbId),
                    seasonNumber: seasonNumber
                )

                await MainActor.run {
                    for episodeData in seasonDetail.episodes {
                        let episode = Episode(context: viewContext)
                        episode.id = UUID()
                        episode.tmdbId = Int64(episodeData.id)
                        episode.seasonNumber = Int16(episodeData.seasonNumber)
                        episode.episodeNumber = Int16(episodeData.episodeNumber)
                        episode.name = episodeData.name
                        episode.overview = episodeData.overview
                        episode.stillPath = episodeData.stillPath
                        episode.show = title
                        episode.dateModified = Date()
                    }
                }
            }

            await MainActor.run {
                save()
                loadEpisodes()
            }
        } catch {
            await MainActor.run {
                handleError(error)
            }
        }

        isLoadingEpisodes = false
    }

    func addNote(text: String, ownerOnly: Bool = true) {
        let note = Note(context: viewContext)
        note.id = UUID()
        note.text = text
        note.ownerOnly = ownerOnly
        note.title = title
        note.dateCreated = Date()
        note.dateModified = Date()

        save()
        loadNotes()
    }
}
```

---

## 5. Dependency Injection

### 5.1 Environment Setup

```swift
import SwiftUI

@main
struct MediaWatchApp: App {
    @StateObject private var persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.viewContext)
                .environmentObject(persistenceController)
        }
    }
}
```

### 5.2 Service Locator (Optional)

```swift
@MainActor
final class ServiceLocator {
    static let shared = ServiceLocator()

    lazy var persistence = PersistenceController.shared
    lazy var tmdbService = TMDbService.shared
    lazy var imageCache = ImageCacheService.shared
    lazy var backupService = BackupService(persistence: persistence)
    lazy var syncService = SyncService(persistence: persistence)

    private init() {}
}
```

---

## 6. Error Handling

### 6.1 App Errors

```swift
enum MediaWatchError: LocalizedError {
    case coreDataError(Error)
    case networkError(Error)
    case cloudKitError(Error)
    case validationError(String)
    case importError(String)
    case exportError(String)

    var errorDescription: String? {
        switch self {
        case .coreDataError(let error):
            return "Database error: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .cloudKitError(let error):
            return "Sync error: \(error.localizedDescription)"
        case .validationError(let message):
            return "Validation error: \(message)"
        case .importError(let message):
            return "Import failed: \(message)"
        case .exportError(let message):
            return "Export failed: \(message)"
        }
    }
}
```

### 6.2 Error Presentation

```swift
struct ErrorAlert: ViewModifier {
    @Binding var errorMessage: String?

    func body(content: Content) -> some View {
        content
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                if let message = errorMessage {
                    Text(message)
                }
            }
    }
}

extension View {
    func errorAlert(_ errorMessage: Binding<String?>) -> some View {
        modifier(ErrorAlert(errorMessage: errorMessage))
    }
}
```

---

## 7. Navigation Architecture

### 7.1 Navigation State

```swift
import SwiftUI

@Observable
final class NavigationState {
    var selectedTab: Tab = .library
    var libraryPath = NavigationPath()
    var searchPath = NavigationPath()
    var settingsPath = NavigationPath()

    enum Tab: Hashable {
        case library
        case search
        case settings
    }
}
```

### 7.2 iPad Split View

```swift
struct iPadSplitView: View {
    @State private var selectedList: List?
    @State private var selectedTitle: Title?
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Sidebar - Lists
            ListsSidebarView(selection: $selectedList)
        } content: {
            // Content - Titles in List
            if let list = selectedList {
                ListDetailView(list: list, selection: $selectedTitle)
            } else {
                ContentUnavailableView("Select a List", systemImage: "list.bullet")
            }
        } detail: {
            // Detail - Title Detail
            if let title = selectedTitle {
                TitleDetailView(title: title)
            } else {
                ContentUnavailableView("Select a Title", systemImage: "film")
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
}
```

---

## 8. Testing Strategy

### 8.1 Unit Tests
- ViewModels with mock persistence
- Services with mock network
- Data validation logic

### 8.2 Integration Tests
- Core Data operations
- CloudKit sync (with test container)
- TMDb API integration

### 8.3 UI Tests
- Critical user flows
- Accessibility compliance
- Different device sizes

### 8.4 Preview Support

```swift
extension PersistenceController {
    static var preview: PersistenceController = {
        let controller = PersistenceController(inMemory: true)

        // Create sample data
        let context = controller.viewContext

        let list = List(context: context)
        list.id = UUID()
        list.name = "Watchlist"
        list.dateCreated = Date()
        list.dateModified = Date()

        let title = Title(context: context)
        title.id = UUID()
        title.tmdbId = 550
        title.mediaType = "movie"
        title.title = "Fight Club"
        title.year = 1999
        title.overview = "A ticking-Loss of identity... "
        title.dateAdded = Date()
        title.dateModified = Date()

        try? context.save()

        return controller
    }()
}
```

---

## 9. Performance Considerations

### 9.1 Core Data Optimization
- Use batch fetching for large lists
- Implement prefetching for relationships
- Use `NSFetchedResultsController` for table/collection views
- Limit fetch batch sizes

### 9.2 Image Loading
- Lazy loading with AsyncImage
- Memory cache with limits
- Disk cache with cleanup
- Progressive loading

### 9.3 CloudKit Optimization
- Batch operations when possible
- Handle CKError.limitExceeded
- Implement exponential backoff
- Monitor sync status

---

## 10. Security Considerations

### 10.1 API Key Storage
- Use Xcode build configuration
- Never commit to source control
- Use xcconfig files for different environments

### 10.2 Data Protection
- Enable data protection entitlement
- Use appropriate file protection levels
- Clear sensitive data on logout

### 10.3 Network Security
- Use HTTPS only
- Implement certificate pinning (optional)
- Validate all server responses
