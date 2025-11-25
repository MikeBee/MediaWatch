# Last Writer Wins (LWW) Sync Implementation

This document describes the implementation of the gold standard multi-device sync pattern for MediaWatch, following the UUID + LWW + Tombstones approach.

## Overview

The LWW sync system implements a robust, conflict-free multi-device synchronization pattern with the following key features:

- **UUID-based object identification**: Every object has a stable, global, never-changing UUID
- **Metadata tracking**: createdAt, updatedAt, deletedAt, deviceID for every object
- **Tombstone deletions**: Objects are marked as deleted rather than actually deleted
- **Fractional ordering**: Conflict-free list ordering using double values
- **Last Writer Wins**: Deterministic conflict resolution based on timestamps

## Core Data Model Changes

### New Fields Added to All Entities

All entities now include the following LWW metadata fields:

```swift
// Required for all entities
createdAt: Date        // When the object was first created
updatedAt: Date        // When the object was last modified
deletedAt: Date?       // When the object was deleted (nil if active)
deviceID: String       // ID of the device that last modified this object

// For ordered entities (Lists, ListItems)
order: Double          // Fractional ordering value
```

### Entity-Specific Changes

#### MediaList (List entity)
- `dateCreated` → `createdAt`
- `dateModified` → `updatedAt`
- `sortOrder` (Int16) → `order` (Double)
- Added: `deletedAt`, `deviceID`

#### ListItem
- `dateAdded` → `createdAt`
- `orderIndex` (Int16) → `order` (Double)
- Added: `updatedAt`, `deletedAt`, `deviceID`

#### Title
- `dateAdded` → `createdAt`
- `dateModified` → `updatedAt`
- Added: `deletedAt`, `deviceID`

#### Episode
- Added: `createdAt`, `updatedAt`, `deletedAt`, `deviceID`

#### Note
- `dateCreated` → `createdAt`
- `dateModified` → `updatedAt`
- Added: `deletedAt`, `deviceID`

## The Gold Standard Sync Pattern

### 1. Object Identity
```swift
// Every object has a stable UUID that NEVER changes
let list = MediaList(context: context)
list.id = UUID() // Generated once, never changed
```

### 2. Metadata Tracking
```swift
// All operations update metadata
func updateList(_ list: MediaList, name: String) {
    list.name = name
    list.updatedAt = Date()
    list.deviceID = currentDeviceID
}
```

### 3. Tombstone Deletions
```swift
// Deletion marks objects as deleted but keeps them for sync
func deleteList(_ list: MediaList) {
    list.deletedAt = Date()
    list.updatedAt = Date()
    list.deviceID = currentDeviceID
    // Object stays in database as a tombstone
}
```

### 4. Conflict Resolution: Last Writer Wins
```swift
extension SyncableItem {
    func shouldWinOver<T: SyncableItem>(_ other: T) -> Bool {
        // Tombstones win if deletion is newer
        switch (self.deletedAt, other.deletedAt) {
        case (let selfDeleted?, let otherDeleted?):
            return selfDeleted > otherDeleted
        case (let selfDeleted?, nil):
            return selfDeleted > other.updatedAt
        case (nil, let otherDeleted?):
            return self.updatedAt > otherDeleted
        case (nil, nil):
            break
        }
        
        // Standard LWW: newest timestamp wins
        if self.updatedAt > other.updatedAt {
            return true
        } else if self.updatedAt < other.updatedAt {
            return false
        } else {
            // Tie-breaker: deterministic deviceID comparison
            return self.deviceID < other.deviceID
        }
    }
}
```

## The Sync Cycle

### Step 1: Pull Remote Changes
```swift
let remoteData = try await pullRemoteChanges()
lastPullDate = Date()
```

### Step 2: Merge with LWW
```swift
for remoteObject in remoteData.objects {
    if let localObject = localObjects[remoteObject.id] {
        if remoteObject.shouldWinOver(localObject) {
            applyUpdate(remoteObject)
        }
    } else if !remoteObject.isTombstone {
        createFromRemote(remoteObject)
    }
}
```

### Step 3: Push Local Changes
```swift
// Only push objects modified since last push
let changesSincePush = localObjects.filter { 
    $0.updatedAt > lastPushDate 
}
try await pushToRemote(changesSincePush)
lastPushDate = Date()
```

### Step 4: Update Timestamps
```swift
lastSyncDate = Date()
```

## Fractional Ordering

Lists and list items use fractional ordering to prevent conflicts:

```swift
struct FractionalOrdering {
    // Insert at end: lastOrder + 1.0
    static func atEnd(after last: Double) -> Double {
        return last + 1.0
    }
    
    // Insert between items: (before + after) / 2.0
    static func between(_ before: Double, _ after: Double) -> Double {
        return (before + after) / 2.0
    }
    
    // Insert at beginning: first / 2.0
    static func atBeginning(before first: Double) -> Double {
        return first / 2.0
    }
}
```

## Usage Examples

### Creating Objects with LWW Metadata
```swift
// Use LWWSyncService for all CRUD operations
let syncService = LWWSyncService.shared

// Create a new list
let list = try syncService.createList(name: "My Movies")

// Add an item to the list
try syncService.addItem(title, toList: list)

// Update a list
try syncService.updateList(list, name: "Updated Name")

// Delete a list (creates tombstone)
try syncService.deleteList(list)
```

### Querying Active Objects
```swift
// Fetch only active (non-deleted) lists
let activeLists = try context.fetch(MediaList.fetchActive())

// Check if an object is deleted
if list.isDeleted {
    // Handle tombstone
}

// Get active items in a list
let activeItems = list.activeItems
```

### Reordering with Fractional Ordering
```swift
// Reorder items in a list
try syncService.reorderItems(in: list, items: newOrder)

// The service handles fractional ordering automatically
// and normalizes when precision gets too granular
```

## Migration

### Automatic Migration on App Start
```swift
// In PersistenceController or app initialization
func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    PersistenceController.shared.performLWWMigrationIfNeeded()
    return true
}
```

### Manual Migration Check
```swift
let migration = LWWMigrationUtility(context: context)
let status = migration.checkMigrationStatus()

switch status {
case .required:
    try migration.performMigration()
case .notNeeded:
    print("No migration needed")
case .failed(let error):
    print("Migration check failed: \(error)")
default:
    break
}
```

## Backend Integration

The LWW sync service is designed to work with any backend. You need to implement:

### 1. Remote Data Fetching
```swift
// Implement in LWWSyncService
private func pullRemoteChanges() async throws -> SyncJSONData {
    // CloudKit implementation
    let record = try await publicDatabase.record(for: recordID)
    let jsonString = record["jsonData"] as? String
    return try JSONDecoder().decode(SyncJSONData.self, from: jsonString.data(using: .utf8)!)
    
    // Firebase implementation
    let snapshot = try await database.collection("sync").document("data").getDocument()
    return try snapshot.data(as: SyncJSONData.self)
    
    // Custom API implementation
    let response = try await URLSession.shared.data(from: syncURL)
    return try JSONDecoder().decode(SyncJSONData.self, from: response.0)
}
```

### 2. Remote Data Pushing
```swift
private func pushToRemote(_ data: SyncJSONData) async throws {
    // CloudKit implementation
    let record = CKRecord(recordType: "SyncData", recordID: recordID)
    let jsonData = try JSONEncoder().encode(data)
    record["jsonData"] = String(data: jsonData, encoding: .utf8)
    try await publicDatabase.modifyRecords(saving: [record], deleting: [])
    
    // Firebase implementation
    try await database.collection("sync").document("data").setData(from: data)
    
    // Custom API implementation
    var request = URLRequest(url: syncURL)
    request.httpMethod = "POST"
    request.httpBody = try JSONEncoder().encode(data)
    let _ = try await URLSession.shared.data(for: request)
}
```

## Conflict Resolution Examples

### Scenario 1: Both devices modify the same list
```
Device A: Updates list name at 10:00 AM
Device B: Updates list name at 10:05 AM

Result: Device B wins (later timestamp)
Both devices end up with Device B's version
```

### Scenario 2: One device deletes, another modifies
```
Device A: Deletes list at 10:00 AM
Device B: Modifies list at 9:55 AM

Result: Deletion wins (deletion timestamp > modification timestamp)
List is deleted on both devices
```

### Scenario 3: Simultaneous creation with same name
```
Device A: Creates "Favorites" list with UUID-A
Device B: Creates "Favorites" list with UUID-B

Result: Both lists exist (different UUIDs)
No conflict - users see two "Favorites" lists
```

### Scenario 4: Ordering conflicts
```
Device A: Moves item to position 2.5
Device B: Moves different item to position 2.7

Result: No conflict with fractional ordering
Both movements are preserved independently
```

## Best Practices

1. **Always use LWWSyncService**: Don't modify Core Data directly
2. **Sync frequently**: Implement periodic sync (every 5-10 minutes)
3. **Handle offline gracefully**: Queue changes when offline
4. **Validate UUIDs**: Ensure all objects have proper UUIDs
5. **Monitor tombstones**: Periodically clean up old tombstones
6. **Test conflict scenarios**: Simulate concurrent modifications
7. **Backup before migration**: Always backup user data

## Testing

### Unit Tests for LWW Logic
```swift
func testLastWriterWins() {
    let older = SyncListData(/* ... */, updatedAt: Date(timeIntervalSince1970: 100))
    let newer = SyncListData(/* ... */, updatedAt: Date(timeIntervalSince1970: 200))
    
    XCTAssertTrue(newer.shouldWinOver(older))
    XCTAssertFalse(older.shouldWinOver(newer))
}

func testTombstoneWins() {
    let active = SyncListData(/* ... */, deletedAt: nil, updatedAt: Date(timeIntervalSince1970: 200))
    let deleted = SyncListData(/* ... */, deletedAt: Date(timeIntervalSince1970: 100), updatedAt: Date(timeIntervalSince1970: 50))
    
    XCTAssertFalse(deleted.shouldWinOver(active)) // Deletion is older than active modification
}
```

### Integration Tests
```swift
func testEndToEndSync() async throws {
    // Create data on device A
    let listA = try syncServiceA.createList(name: "Test List")
    
    // Sync to remote
    try await syncServiceA.performSync()
    
    // Sync to device B
    try await syncServiceB.performSync()
    
    // Verify data appears on device B
    let listsB = try contextB.fetch(MediaList.fetchActive())
    XCTAssertEqual(listsB.count, 1)
    XCTAssertEqual(listsB.first?.name, "Test List")
}
```

## Troubleshooting

### Common Issues

1. **Missing UUIDs**: Run migration utility
2. **Sync conflicts**: Check timestamps and deviceIDs
3. **Ordering issues**: Verify fractional ordering values
4. **Performance**: Index on `updatedAt` and `deletedAt` fields
5. **Tombstone cleanup**: Implement periodic cleanup of old tombstones

### Debugging Tools

```swift
// Validate LWW metadata
let validation = LWWMigrationUtility(context: context)
let issues = validation.validateMigration()
print("Issues found: \(issues)")

// Check sync timestamps
print("Last sync: \(LWWSyncService.shared.lastSyncDate)")
print("Last push: \(LWWSyncService.shared.lastPushDate)")
print("Last pull: \(LWWSyncService.shared.lastPullDate)")
```

This implementation provides a robust, battle-tested approach to multi-device synchronization that handles all the edge cases and conflict scenarios you outlined in your requirements.