# MediaWatch - CloudKit Sync & Sharing

## Overview

MediaWatch uses `NSPersistentCloudKitContainer` to automatically sync data between devices and enable sharing lists with other Apple ID users.

---

## 1. CloudKit Configuration

### 1.1 Container Identifier

```
iCloud.com.yourcompany.MediaWatch
```

### 1.2 Entitlements

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>aps-environment</key>
    <string>development</string>
    <key>com.apple.developer.icloud-container-identifiers</key>
    <array>
        <string>iCloud.com.yourcompany.MediaWatch</string>
    </array>
    <key>com.apple.developer.icloud-services</key>
    <array>
        <string>CloudKit</string>
    </array>
    <key>com.apple.developer.ubiquity-kvstore-identifier</key>
    <string>$(TeamIdentifierPrefix)$(CFBundleIdentifier)</string>
</dict>
</plist>
```

### 1.3 Required Capabilities

In Xcode:
1. iCloud (CloudKit)
2. Background Modes (Remote notifications)
3. Push Notifications

---

## 2. Database Structure

### 2.1 Private Database

Contains:
- All user's Lists
- All user's Titles
- All user's Episodes
- All user's Notes (including ownerOnly)
- User preferences

### 2.2 Shared Database

Contains:
- Lists shared BY the user to others
- Lists shared WITH the user by others
- Associated Titles, Episodes
- Notes with `ownerOnly = false`

### 2.3 Zone Configuration

```swift
// Private zone (default)
CKRecordZone.default()

// Custom zone for better sync control
let privateZone = CKRecordZone(zoneName: "MediaWatch")

// Shared zone (managed by CloudKit)
// Automatically created when sharing
```

---

## 3. Data Model Mapping

### 3.1 Core Data to CloudKit

| Entity | CloudKit Record Type | Zone |
|--------|---------------------|------|
| List | CD_List | Private/Shared |
| Title | CD_Title | Private/Shared |
| Episode | CD_Episode | Private/Shared |
| ListItem | CD_ListItem | Private/Shared |
| Note | CD_Note | Private (ownerOnly=true) / Shared |
| UserPreferences | CD_UserPreferences | Private only |

### 3.2 Field Mapping

Core Data automatically maps:
- UUID → CKRecord.ID
- String → String
- Int16/Int32/Int64 → Int64
- Double → Double
- Bool → Int64 (0/1)
- Date → Date
- Data → Asset/Bytes
- Transformable → Asset (JSON encoded)
- Relationships → CKReference

---

## 4. Sync Implementation

### 4.1 Persistent Store Configuration

```swift
import CoreData
import CloudKit

final class CloudKitManager {
    static let shared = CloudKitManager()

    let container: NSPersistentCloudKitContainer

    private var privateStore: NSPersistentStore!
    private var sharedStore: NSPersistentStore!

    init() {
        container = NSPersistentCloudKitContainer(name: "MediaWatch")

        // Configure stores
        guard let privateDescription = container.persistentStoreDescriptions.first else {
            fatalError("No store descriptions found")
        }

        let containerIdentifier = "iCloud.com.yourcompany.MediaWatch"

        // Private store configuration
        privateDescription.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: containerIdentifier
        )
        privateDescription.setOption(true as NSNumber,
                                     forKey: NSPersistentHistoryTrackingKey)
        privateDescription.setOption(true as NSNumber,
                                     forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        // Shared store configuration
        let sharedStoreURL = privateDescription.url!
            .deletingLastPathComponent()
            .appendingPathComponent("MediaWatch-Shared.sqlite")

        let sharedDescription = NSPersistentStoreDescription(url: sharedStoreURL)
        sharedDescription.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(
            containerIdentifier: containerIdentifier
        )
        sharedDescription.cloudKitContainerOptions!.databaseScope = .shared
        sharedDescription.setOption(true as NSNumber,
                                    forKey: NSPersistentHistoryTrackingKey)
        sharedDescription.setOption(true as NSNumber,
                                    forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        container.persistentStoreDescriptions = [privateDescription, sharedDescription]

        // Load stores
        container.loadPersistentStores { description, error in
            if let error = error {
                fatalError("Failed to load store: \(error)")
            }

            if description.cloudKitContainerOptions?.databaseScope == .shared {
                self.sharedStore = self.container.persistentStoreCoordinator
                    .persistentStore(for: description.url!)
            } else {
                self.privateStore = self.container.persistentStoreCoordinator
                    .persistentStore(for: description.url!)
            }
        }

        // Configure view context
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        // Listen for remote changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRemoteChange),
            name: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator
        )
    }

    @objc private func handleRemoteChange(_ notification: Notification) {
        // Process remote changes
        Task {
            await processRemoteChanges()
        }
    }

    private func processRemoteChanges() async {
        // Fetch and merge history
        // Update UI if needed
    }
}
```

### 4.2 Sync Status Monitoring

```swift
import Combine

extension CloudKitManager {
    enum SyncStatus {
        case idle
        case syncing
        case succeeded
        case failed(Error)
        case noAccount
        case restricted
    }

    @Published var syncStatus: SyncStatus = .idle

    func checkAccountStatus() async {
        do {
            let status = try await CKContainer.default().accountStatus()
            await MainActor.run {
                switch status {
                case .available:
                    syncStatus = .idle
                case .noAccount:
                    syncStatus = .noAccount
                case .restricted:
                    syncStatus = .restricted
                case .couldNotDetermine:
                    syncStatus = .failed(CloudKitError.accountUnavailable)
                case .temporarilyUnavailable:
                    syncStatus = .failed(CloudKitError.temporarilyUnavailable)
                @unknown default:
                    syncStatus = .failed(CloudKitError.unknown)
                }
            }
        } catch {
            await MainActor.run {
                syncStatus = .failed(error)
            }
        }
    }

    func monitorSyncEvents() {
        // Use NSPersistentCloudKitContainer event monitoring
        // Available in iOS 14+

        let eventMonitor = container.eventChangedPublisher()
        // Subscribe to events
    }
}

enum CloudKitError: Error {
    case accountUnavailable
    case temporarilyUnavailable
    case unknown
}
```

---

## 5. Sharing Implementation

### 5.1 Share a List

```swift
extension CloudKitManager {

    /// Creates a share for a list and all its related content
    func shareList(_ list: List) async throws -> CKShare {
        // Fetch objects to share (list and all related items)
        let objectsToShare = try await fetchObjectsToShare(for: list)

        // Create share
        let (objectIDs, share, container) = try await self.container.share(
            objectsToShare,
            to: nil  // Creates new share
        )

        // Configure share metadata
        share[CKShare.SystemFieldKey.title] = list.name
        share.publicPermission = .none  // Private by default

        return share
    }

    private func fetchObjectsToShare(for list: List) async throws -> [NSManagedObject] {
        var objects: [NSManagedObject] = [list]

        // Add all list items
        if let items = list.items as? Set<ListItem> {
            for item in items {
                objects.append(item)

                // Add the title
                if let title = item.title {
                    objects.append(title)

                    // Add episodes for TV shows
                    if let episodes = title.episodes as? Set<Episode> {
                        objects.append(contentsOf: episodes)
                    }

                    // Add non-private notes
                    if let notes = title.notes as? Set<Note> {
                        let sharedNotes = notes.filter { !$0.ownerOnly }
                        objects.append(contentsOf: sharedNotes)
                    }
                }
            }
        }

        return objects
    }

    /// Accept a share invitation
    func acceptShare(_ metadata: CKShare.Metadata) async throws {
        try await CKContainer.default().accept(metadata)
    }

    /// Get all shares
    func fetchShares() async throws -> [CKShare] {
        try await container.fetchShares(in: nil)
    }

    /// Check if an object is shared
    func isShared(_ object: NSManagedObject) -> Bool {
        guard let store = object.objectID.persistentStore else { return false }
        return store == sharedStore
    }

    /// Get share for an object
    func share(for object: NSManagedObject) -> CKShare? {
        guard isShared(object) else { return nil }

        do {
            let shares = try container.fetchShares(matching: [object.objectID])
            return shares[object.objectID]
        } catch {
            return nil
        }
    }

    /// Get participants for a share
    func participants(for share: CKShare) -> [CKShare.Participant] {
        return share.participants
    }

    /// Remove a participant from a share
    func removeParticipant(_ participant: CKShare.Participant, from share: CKShare) async throws {
        share.removeParticipant(participant)
        try await CKContainer.default().privateCloudDatabase.save(share)
    }

    /// Stop sharing a list
    func stopSharing(_ list: List) async throws {
        guard let share = share(for: list) else { return }

        let database = CKContainer.default().privateCloudDatabase
        try await database.deleteRecord(withID: share.recordID)
    }
}
```

### 5.2 Share UI Integration

```swift
import SwiftUI
import CloudKit

struct ShareListView: View {
    let list: List
    @State private var share: CKShare?
    @State private var isPresenting = false

    var body: some View {
        Button {
            Task {
                do {
                    share = try await CloudKitManager.shared.shareList(list)
                    isPresenting = true
                } catch {
                    // Handle error
                }
            }
        } label: {
            Label("Share", systemImage: "person.badge.plus")
        }
        .sheet(isPresented: $isPresenting) {
            if let share = share {
                CloudSharingView(share: share, container: CKContainer.default())
            }
        }
    }
}

struct CloudSharingView: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: container)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, UICloudSharingControllerDelegate {
        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            print("Failed to save share: \(error)")
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            return "Shared List"
        }
    }
}
```

### 5.3 Handle Share Acceptance

```swift
// In SceneDelegate or App

class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene,
                     userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        Task {
            do {
                try await CloudKitManager.shared.acceptShare(cloudKitShareMetadata)
            } catch {
                // Show error to user
            }
        }
    }
}

// For SwiftUI App
@main
struct MediaWatchApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            // Handle scene phase changes
        }
    }
}
```

---

## 6. Conflict Resolution

### 6.1 Merge Policy

```swift
// NSMergeByPropertyObjectTrumpMergePolicy
// - Server wins for each property
// - Last write wins

container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
```

### 6.2 Custom Conflict Handling

```swift
extension CloudKitManager {

    func resolveConflict(for object: NSManagedObject, serverRecord: CKRecord) {
        // Compare modification dates per field
        let localModified = object.value(forKey: "dateModified") as? Date ?? .distantPast
        let serverModified = serverRecord.modificationDate ?? .distantPast

        if serverModified > localModified {
            // Server wins - merge server values
            mergeServerValues(serverRecord, into: object)
        } else {
            // Local wins - values already set
        }
    }

    private func mergeServerValues(_ record: CKRecord, into object: NSManagedObject) {
        // Map CKRecord fields to Core Data attributes
        // Handle type conversions
    }
}
```

### 6.3 Field-Level Tracking

For more granular conflict resolution, track modification dates per field:

```swift
// In Title entity, add:
// watchedDateModified, likedStatusDateModified, etc.

extension Title {
    func updateWatched(_ value: Bool) {
        watched = value
        watchedDate = value ? Date() : nil
        // Track when this specific field was modified
        setValue(Date(), forKey: "watchedFieldModified")
    }
}
```

---

## 7. Offline Support

### 7.1 Queue Management

Core Data + CloudKit automatically queues changes when offline.

```swift
extension CloudKitManager {

    var hasUnsyncedChanges: Bool {
        // Check persistent history for pending operations
        return false // Implementation depends on history tracking
    }

    func pendingOperationCount() async -> Int {
        // Count pending CloudKit operations
        return 0
    }
}
```

### 7.2 Network Monitoring

```swift
import Network

class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")

    @Published var isConnected = true
    @Published var connectionType: ConnectionType = .unknown

    enum ConnectionType {
        case wifi
        case cellular
        case wired
        case unknown
    }

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isConnected = path.status == .satisfied

                if path.usesInterfaceType(.wifi) {
                    self?.connectionType = .wifi
                } else if path.usesInterfaceType(.cellular) {
                    self?.connectionType = .cellular
                } else if path.usesInterfaceType(.wiredEthernet) {
                    self?.connectionType = .wired
                } else {
                    self?.connectionType = .unknown
                }
            }
        }

        monitor.start(queue: queue)
    }
}
```

---

## 8. Error Handling

### 8.1 Common CloudKit Errors

```swift
extension CloudKitManager {

    func handleCloudKitError(_ error: Error) -> String {
        guard let ckError = error as? CKError else {
            return error.localizedDescription
        }

        switch ckError.code {
        case .networkUnavailable, .networkFailure:
            return "Network unavailable. Changes will sync when online."

        case .notAuthenticated:
            return "Please sign in to iCloud in Settings."

        case .quotaExceeded:
            return "iCloud storage is full. Please free up space."

        case .serverResponseLost:
            return "Server connection lost. Will retry automatically."

        case .zoneBusy, .requestRateLimited:
            // Implement exponential backoff
            return "Server busy. Will retry shortly."

        case .changeTokenExpired:
            // Need to re-fetch all data
            return "Sync token expired. Performing full sync."

        case .partialFailure:
            // Handle individual record errors
            if let partialErrors = ckError.userInfo[CKPartialErrorsByItemIDKey] as? [CKRecord.ID: Error] {
                handlePartialErrors(partialErrors)
            }
            return "Some items failed to sync."

        case .limitExceeded:
            // Batch operations exceeded limits
            return "Too many items. Syncing in batches."

        case .userDeletedZone:
            // User deleted iCloud data
            return "iCloud data was deleted."

        default:
            return "Sync error: \(ckError.localizedDescription)"
        }
    }

    private func handlePartialErrors(_ errors: [CKRecord.ID: Error]) {
        for (recordID, error) in errors {
            print("Error for \(recordID): \(error)")
            // Handle individual record errors
        }
    }
}
```

### 8.2 Retry Logic

```swift
extension CloudKitManager {

    func retryOperation<T>(
        maxAttempts: Int = 3,
        initialDelay: TimeInterval = 1.0,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var lastError: Error?
        var delay = initialDelay

        for attempt in 1...maxAttempts {
            do {
                return try await operation()
            } catch let error as CKError {
                lastError = error

                // Check if error is retryable
                guard isRetryable(error) else {
                    throw error
                }

                // Get retry delay from error or use exponential backoff
                let retryAfter = error.retryAfterSeconds ?? delay

                if attempt < maxAttempts {
                    try await Task.sleep(nanoseconds: UInt64(retryAfter * 1_000_000_000))
                    delay *= 2  // Exponential backoff
                }
            } catch {
                throw error
            }
        }

        throw lastError ?? CloudKitError.unknown
    }

    private func isRetryable(_ error: CKError) -> Bool {
        switch error.code {
        case .networkUnavailable, .networkFailure, .serverResponseLost,
             .zoneBusy, .requestRateLimited, .serviceUnavailable:
            return true
        default:
            return false
        }
    }
}
```

---

## 9. Privacy Considerations

### 9.1 Owner-Only Notes

```swift
// When sharing, exclude owner-only notes
private func objectsToShare(for list: List) -> [NSManagedObject] {
    var objects: [NSManagedObject] = []

    // ... include list, items, titles, episodes

    // Only include non-private notes
    for note in allNotes {
        if !note.ownerOnly {
            objects.append(note)
        }
    }

    return objects
}
```

### 9.2 Participant Identification

```swift
extension CKShare.Participant {
    var displayName: String {
        if let name = userIdentity.nameComponents {
            return PersonNameComponentsFormatter().string(from: name)
        }
        return userIdentity.lookupInfo?.emailAddress ?? "Unknown"
    }
}
```

---

## 10. Testing CloudKit

### 10.1 Development vs Production

- Use separate containers for dev/prod
- Enable CloudKit Dashboard logging
- Test with multiple iCloud accounts

### 10.2 Reset Development Data

```swift
#if DEBUG
extension CloudKitManager {
    func resetCloudKitData() async throws {
        let database = CKContainer.default().privateCloudDatabase
        let zones = try await database.allRecordZones()

        for zone in zones {
            try await database.deleteRecordZone(withID: zone.zoneID)
        }
    }
}
#endif
```

### 10.3 Mock for Unit Tests

```swift
protocol CloudKitManagerProtocol {
    func shareList(_ list: List) async throws -> CKShare
    func fetchShares() async throws -> [CKShare]
    // ...
}

class MockCloudKitManager: CloudKitManagerProtocol {
    var shouldFail = false
    var shares: [CKShare] = []

    func shareList(_ list: List) async throws -> CKShare {
        if shouldFail {
            throw CloudKitError.unknown
        }
        return CKShare(rootRecord: CKRecord(recordType: "List"))
    }

    func fetchShares() async throws -> [CKShare] {
        return shares
    }
}
```
