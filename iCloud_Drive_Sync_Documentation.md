# iCloud Drive JSON Sync Documentation

## Overview

The MediaWatch app now includes a robust iCloud Drive JSON sync system that automatically syncs your lists, movies, TV shows, episodes, and notes across all your devices using iCloud Drive. This system does NOT use CloudKit, making it compatible with TestFlight distributions across different Apple IDs.

## Key Features

### ✅ Automatic Sync
- Changes sync automatically across devices within ~30 seconds
- Works in background with no manual user actions required
- Real-time UI updates when remote changes are merged

### ✅ Deterministic Conflict Resolution
- Last-writer-wins conflict resolution using timestamps
- Deterministic tie-breaking using device UUID ordering
- Tombstone handling for deleted items
- No user prompts for conflict resolution

### ✅ Robust Offline Support
- Changes are queued locally when offline
- Automatic retry when connectivity returns
- Background sync using UIBackgroundTaskIdentifier

### ✅ Migration Path
- One-time migration from existing Core Data to JSON
- Safe, idempotent migration process
- Migration status tracking and user controls

## How It Works

### Data Storage
- Single JSON file per account: `Documents/MediaShowsSync/MediaShowsData.json`
- Stored in iCloud Drive ubiquity container: `iCloud.reasonality.MediaShows`
- Atomic writes using temporary files and file coordination
- NSFileCoordinator/NSFilePresenter for change detection

### JSON Schema
```json
{
  "version": 1,
  "lastSyncedAt": "2025-11-23T20:00:00Z",
  "deviceId": "UUID-of-device",
  "lists": [
    {
      "id": "list-uuid",
      "name": "Weekend Movies",
      "createdAt": "2025-11-01T12:00:00Z",
      "updatedAt": "2025-11-20T14:30:00Z",
      "deleted": false,
      "items": [
        {
          "id": "item-uuid",
          "tmdbId": 12345,
          "mediaType": "movie",
          "title": "The Great Movie",
          "year": 2023,
          "overview": "An amazing film...",
          "posterPath": "/path.jpg",
          "runtime": 120,
          "watched": false,
          "watchedDate": null,
          "rating": null,
          "createdAt": "2025-11-01T12:00:00Z",
          "updatedAt": "2025-11-20T14:31:00Z",
          "deleted": false,
          "episodes": [],
          "notes": []
        }
      ]
    }
  ]
}
```

### Conflict Resolution Algorithm
1. **Per-item comparison**: Each list, movie, episode is compared individually
2. **Timestamp-based**: Later `updatedAt` timestamp wins
3. **Tie-breaking**: If timestamps are identical, lexicographic device UUID comparison
4. **Tombstones**: Deleted items (marked `deleted: true`) are preserved and beat older creates/edits
5. **Logging**: All conflicts are logged for diagnostics

## Usage

### For Users

#### First-time Setup
1. Ensure iCloud Drive is enabled on your device
2. Open MediaWatch settings
3. Navigate to "iCloud Drive Sync"
4. Enable sync (will automatically migrate existing data)

#### Managing Sync
- View sync status and last sync time in settings
- Force manual sync if needed
- View diagnostics log for troubleshooting
- Disable sync to revert to local-only mode

#### Troubleshooting
- Check iCloud Drive storage space
- Verify iCloud Drive is enabled in Settings > [Your Name] > iCloud
- View diagnostics log for specific error messages
- Force sync to retry failed operations

### For Developers

#### Integration Points
```swift
// Access sync service
let syncService = ICloudDriveJSONSyncService.shared

// Check if sync is enabled
if syncService.isEnabled {
    print("Sync is active")
}

// Monitor sync status
syncService.$syncStatus
    .sink { status in
        switch status {
        case .syncing:
            print("Sync in progress")
        case .success(let message):
            print("Sync completed: \(message)")
        case .error(let error):
            print("Sync error: \(error)")
        }
    }
```

#### Testing

##### Unit Tests
```bash
# Run sync-specific tests
xcodebuild test -scheme MediaWatch -destination 'platform=iOS Simulator,name=iPhone 15' -only-testing:MediaWatchTests/ICloudDriveJSONSyncTests
```

##### Manual Testing on Two Devices
1. **Setup**: Install app on two devices with same Apple ID
2. **Initial sync**: Add items on Device A, verify they appear on Device B
3. **Conflict testing**: 
   - Turn off WiFi on both devices
   - Make different changes to same list on both
   - Turn WiFi back on
   - Verify conflicts resolve deterministically
4. **Offline testing**: Make changes offline, verify sync when online

##### QA Checklist
- [ ] Fresh install migration works
- [ ] Cross-device sync works (lists, items, watch status)
- [ ] Offline changes sync when online
- [ ] Conflicts resolve without user intervention
- [ ] Large lists sync correctly
- [ ] App doesn't block UI during sync
- [ ] Sync works after app restart
- [ ] Disable/enable sync works correctly

## Implementation Details

### File Structure
```
MediaWatch/
├── Services/
│   ├── ICloudDriveJSONSyncService.swift  # Main sync service
│   └── iCloudSyncService.swift           # Original simple sync (can be deprecated)
├── Models/
│   └── SyncJSONModels.swift              # JSON data structures
├── Views/
│   └── ICloudDriveSyncSettingsView.swift # Settings UI
└── Tests/
    └── ICloudDriveJSONSyncTests.swift    # Unit tests
```

### Key Classes

#### `ICloudDriveJSONSyncService`
- Main sync orchestrator
- Handles file coordination and change detection
- Implements conflict resolution algorithm
- Manages background tasks and offline queue

#### `SyncJSONData` and related models
- Codable structs for JSON serialization
- Each model implements `SyncableItem` protocol
- Built-in timestamp and deletion tracking

#### `ICloudDriveSyncSettingsView`
- SwiftUI settings interface
- Sync status display and controls
- Migration management
- Diagnostics viewer

### Performance Considerations
- **Background queue**: All file operations on utility queue
- **Batched changes**: 2-second delay to batch Core Data changes
- **Atomic writes**: Temp file + replace for crash safety
- **Memory efficient**: Streaming JSON parsing for large files
- **Background sync**: Uses UIBackgroundTaskIdentifier

## Migration Guide

### From Existing System
If you have an existing sync system:

1. **Disable old sync**: Turn off CloudKit sync in existing system
2. **Backup data**: Export current data as backup
3. **Enable new sync**: Follow first-time setup
4. **Verify data**: Check all lists and items transferred correctly
5. **Test cross-device**: Verify sync works between devices

### Rollback Plan
If issues occur:
1. **Disable iCloud Drive sync** in settings
2. **Restore from backup** if needed
3. **Report issues** with diagnostics log
4. **Re-enable CloudKit sync** if reverting completely

## Security & Privacy

### Data Protection
- **No CloudKit**: Avoids CloudKit limitations for TestFlight
- **iCloud Drive encryption**: Benefits from iCloud Drive's end-to-end encryption
- **Private notes**: Notes marked `ownerOnly` are not synced
- **Local diagnostics**: Sync logs stored locally only

### Permissions
- **iCloud Drive access**: Required for sync functionality
- **Background refresh**: Optional, improves sync responsiveness
- **No network requests**: Only uses iCloud Drive APIs

## Troubleshooting

### Common Issues

#### "iCloud Drive Unavailable"
- **Cause**: iCloud Drive not enabled or signed out
- **Solution**: Check Settings > [Your Name] > iCloud > iCloud Drive

#### "Sync Failed"
- **Cause**: Network connectivity or iCloud Drive quota
- **Solution**: Check internet connection and iCloud storage

#### "Migration Required"
- **Cause**: Existing Core Data not yet migrated
- **Solution**: Tap "Start Migration" in sync settings

#### Frequent Conflicts
- **Cause**: Multiple devices editing simultaneously
- **Prevention**: Let previous changes sync before making new ones
- **Impact**: Conflicts resolve automatically, no data loss

### Diagnostics

#### Sync Log
Access detailed sync events:
1. Settings > iCloud Drive Sync
2. Tap "View Sync Log"
3. Look for error messages or unusual patterns

#### Export Diagnostics
For support requests:
1. Settings > iCloud Drive Sync > Advanced
2. Tap "Export Diagnostics"
3. Include in support request

## Version History

### Version 1.12 (Current)
- Initial iCloud Drive JSON sync implementation
- Deterministic conflict resolution
- One-time migration from Core Data
- Comprehensive unit tests
- Settings UI and diagnostics

### Future Enhancements
- **Per-list files**: Shard large datasets across multiple files
- **Encryption**: Optional client-side encryption with Keychain keys
- **Selective sync**: Choose which lists to sync
- **Advanced conflict resolution**: Custom strategies for different data types
- **Sync statistics**: Detailed metrics and performance monitoring

## Support

For issues with iCloud Drive sync:
1. Check troubleshooting section above
2. Enable diagnostics logging
3. Try disabling/re-enabling sync
4. Contact support with diagnostics export

---

*This documentation covers the iCloud Drive JSON sync system for MediaWatch v1.12+*