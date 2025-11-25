# MediaWatch LWW Sync Deployment Guide

This guide covers deploying the new Last Writer Wins (LWW) sync system to TestFlight and Production environments.

## 🚨 CRITICAL: Breaking Changes

The new LWW sync implementation includes **breaking changes** to the Core Data model. This requires special handling for deployment.

### Core Data Model Changes

1. **New required fields added to ALL entities:**
   - `createdAt: Date`
   - `updatedAt: Date` 
   - `deletedAt: Date?`
   - `deviceID: String`

2. **Field changes:**
   - `sortOrder` → `order` (Int16 → Double)
   - `orderIndex` → `order` (Int16 → Double)
   - `dateCreated` → `createdAt`
   - `dateModified` → `updatedAt`

3. **New sync behavior:**
   - Tombstone deletions instead of hard deletes
   - UUID-based object identification
   - Fractional ordering for lists

## Deployment Strategy Options

### Option 1: Fresh Start (RECOMMENDED)
Since you're planning to delete and reinstall on all devices, this is the cleanest approach.

### Option 2: Automatic Migration (if you change your mind)
For users with existing data who want to keep it.

---

## 🔄 Option 1: Fresh Start Deployment

### Step 1: Prepare the Release

1. **Update app version** in `Info.plist`:
```xml
<key>CFBundleShortVersionString</key>
<string>2.0.0</string>
<key>CFBundleVersion</key>
<string>1</string>
```

2. **Add version check** in `MediaWatchApp.swift`:
```swift
struct MediaWatchApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .onAppear {
                    // Initialize LWW sync for fresh installs
                    LWWSyncService.shared.initializeForFreshInstall()
                }
        }
    }
}
```

3. **Update CloudKit schema** (if using CloudKit):
   - Delete existing records in CloudKit Dashboard
   - Update record types to match new JSON structure
   - Test with development environment first

### Step 2: TestFlight Deployment

1. **Create new build** with version 2.0.0
2. **Upload to TestFlight**
3. **Add release notes** explaining the fresh start:
```
Version 2.0.0 - Major Sync Upgrade

🚨 IMPORTANT: This update includes a complete rewrite of the sync system for better reliability and cross-device support.

⚠️ You will need to:
1. Delete the app from ALL your devices
2. Reinstall from TestFlight
3. Re-add your lists and shows

This ensures you get the new sync system without any data conflicts.

New Features:
✅ Improved multi-device sync
✅ Cross-Apple ID sharing support
✅ Better conflict resolution
✅ Enhanced episode tracking
✅ Sync all ratings and notes
```

### Step 3: Production Release

1. **Test thoroughly** in TestFlight with multiple devices
2. **Verify sync works** across different Apple IDs
3. **Submit to App Store** with same version and release notes
4. **Monitor** for any issues after release

---

## 🔄 Option 2: Migration Deployment (if needed)

If you decide to preserve user data, here's how to handle migration:

### Core Data Migration

1. **Create new Core Data model version:**
```bash
# In Xcode:
# 1. Select MediaShows.xcdatamodeld
# 2. Editor → Add Model Version
# 3. Name it "MediaShows 2"
# 4. Set as current version
```

2. **Add migration mapping:**
```swift
// In PersistenceController
lazy var persistentContainer: NSPersistentContainer = {
    let container = NSPersistentContainer(name: "MediaShows")
    
    // Add migration options
    let storeDescription = container.persistentStoreDescriptions.first
    storeDescription?.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
    storeDescription?.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
    
    container.loadPersistentStores { _, error in
        if let error = error {
            fatalError("Core Data migration failed: \(error)")
        }
        
        // Perform LWW migration after Core Data migration
        LWWMigrationUtility(context: container.viewContext).performMigrationIfNeeded()
    }
    
    return container
}()
```

---

## 📱 Environment Configuration

### Development Environment

```swift
// In LWWSyncService.swift - Development configuration
#if DEBUG
private let syncInterval: TimeInterval = 30.0  // 30 seconds for testing
private let enableDetailedLogging = true
#else
private let syncInterval: TimeInterval = 300.0 // 5 minutes for production
private let enableDetailedLogging = false
#endif
```

### TestFlight Environment

1. **Enable beta features:**
```swift
// Add to build configurations
#if TESTFLIGHT
private let enableAdvancedSync = true
private let allowCrossiCloudSync = true
#endif
```

2. **Add TestFlight detection:**
```swift
extension Bundle {
    var isTestFlight: Bool {
        return appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }
}
```

### Production Environment

```swift
// Production-safe defaults
private let maxSyncRetries = 3
private let syncTimeout: TimeInterval = 30.0
private let tombstoneCleanupInterval: TimeInterval = 86400 * 30 // 30 days
```

---

## 🔧 Backend Configuration

### CloudKit Setup (if using CloudKit)

1. **Update CloudKit schema:**
```javascript
// New record type: MediaShowsDataV2
{
    "recordType": "MediaShowsDataV2",
    "fields": {
        "jsonData": "String",
        "version": "Int(64)",
        "deviceID": "String", 
        "lastModified": "DateTime",
        "schemaVersion": "String"
    }
}
```

2. **Migration script** for existing CloudKit data:
```swift
func migrateCloudKitData() async throws {
    // Fetch old records
    let oldRecords = try await fetchOldRecords()
    
    // Convert to new format
    for oldRecord in oldRecords {
        let newRecord = convertToLWWFormat(oldRecord)
        try await saveNewRecord(newRecord)
    }
    
    // Clean up old records
    try await deleteOldRecords()
}
```

### Firebase Setup (if using Firebase)

```javascript
// New Firestore structure
{
  "mediawatch_sync_v2": {
    "users": {
      "{userID}": {
        "syncData": {
          "version": 2,
          "lastSyncedAt": "timestamp",
          "deviceId": "string",
          "lists": [...] // Full LWW structure
        }
      }
    }
  }
}
```

---

## 🧪 Testing Strategy

### Pre-Release Testing Checklist

- [ ] **Fresh install** creates proper LWW metadata
- [ ] **Multi-device sync** works correctly
- [ ] **Conflict resolution** handles all scenarios
- [ ] **Episode tracking** syncs watched status
- [ ] **Ratings sync** (userRating, mikeRating, lauraRating)
- [ ] **Notes sync** (non-private only)
- [ ] **Fractional ordering** prevents conflicts
- [ ] **Tombstone deletions** sync properly
- [ ] **Cross-Apple ID** sharing works
- [ ] **Offline changes** sync when online
- [ ] **Performance** acceptable with large datasets

### Test Scenarios

1. **Create list on Device A** → **Sync to Device B**
2. **Add items simultaneously** on both devices
3. **Mark episodes watched** on different devices
4. **Rate content** on multiple devices
5. **Delete lists** and verify tombstones
6. **Reorder items** with fractional ordering
7. **Airplane mode** → make changes → sync when online
8. **Different Apple IDs** can share lists

### Automated Tests

```swift
class LWWSyncTests: XCTestCase {
    func testFreshInstallCreatesMetadata() {
        // Test that new installs create proper LWW metadata
    }
    
    func testConflictResolution() {
        // Test Last Writer Wins scenarios
    }
    
    func testEpisodeSync() {
        // Test episode watched status syncing
    }
    
    func testRatingSync() {
        // Test all rating fields sync
    }
    
    func testTombstoneSync() {
        // Test deletion syncing
    }
}
```

---

## 🚨 Rollback Plan

If issues arise after deployment:

### Emergency Rollback

1. **Prepare rollback build** with previous version
2. **Keep old CloudKit schema** as backup
3. **Document all changes** for quick reversal

### Rollback Steps

1. **Submit emergency update** with old sync system
2. **Restore CloudKit schema** to previous version
3. **Notify users** about temporary sync issues
4. **Fix issues** in development
5. **Re-release** when stable

---

## 📊 Monitoring & Analytics

### Key Metrics to Track

```swift
// Add analytics for sync health
Analytics.track("sync_completed", parameters: [
    "conflicts_resolved": conflictsResolved,
    "sync_duration": duration,
    "device_count": deviceCount,
    "data_size": dataSize
])

Analytics.track("sync_error", parameters: [
    "error_type": error.type,
    "error_message": error.message,
    "retry_count": retryCount
])
```

### CloudWatch/Firebase Monitoring

- Sync success rates
- Conflict resolution frequency
- Average sync duration
- Error rates by type
- User retention after upgrade

---

## 🔐 Security Considerations

### Data Privacy

```swift
// Ensure sensitive data isn't logged
private func sanitizeForLogging(_ data: SyncJSONData) -> String {
    // Remove personal information before logging
    return "Lists: \(data.lists.count), Device: ***"
}
```

### Cross-Apple ID Sharing

```swift
// Only sync non-private notes
let syncableNotes = notes.filter { !$0.ownerOnly }

// Ensure private data stays private
private func filterPrivateData(_ syncData: SyncJSONData) -> SyncJSONData {
    // Remove device-specific or private information
}
```

---

## 🚀 Launch Checklist

### Pre-Launch (1 week before)

- [ ] All tests passing
- [ ] TestFlight feedback addressed
- [ ] Performance testing completed
- [ ] Backend scaling prepared
- [ ] Monitoring dashboards ready
- [ ] Rollback plan tested

### Launch Day

- [ ] Deploy to App Store
- [ ] Monitor crash reports
- [ ] Watch sync success metrics
- [ ] Respond to user feedback
- [ ] Have team ready for emergency fixes

### Post-Launch (1 week after)

- [ ] Analyze sync success rates
- [ ] Review user feedback
- [ ] Identify optimization opportunities
- [ ] Plan next iteration improvements

---

## 🎯 Success Criteria

The deployment is successful when:

✅ **>95% sync success rate** across all devices
✅ **<5 seconds average sync time** for typical datasets
✅ **Zero data loss** reported by users
✅ **Positive user feedback** on sync reliability
✅ **Cross-device experience** works seamlessly
✅ **Episode tracking** syncs accurately
✅ **Ratings and notes** sync properly

---

This comprehensive deployment strategy ensures a smooth transition to the new LWW sync system while minimizing user disruption and maximizing reliability.