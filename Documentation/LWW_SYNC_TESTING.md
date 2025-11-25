# LWW Sync Testing Guide

This document covers comprehensive testing of the Last Writer Wins (LWW) sync implementation, especially for Cross-Apple ID scenarios.

## 🧪 Test Environment Setup

### Required Test Devices/Accounts

1. **Device A**: iPhone with Apple ID A
2. **Device B**: iPad with Apple ID B  
3. **Device C**: iPhone with Apple ID A (same as Device A)
4. **Device D**: Mac with Apple ID C

### Pre-Test Setup

```bash
# For each device:
1. Delete MediaWatch app completely
2. Clear iCloud data for the app
3. Install fresh build from TestFlight
4. Verify fresh install initialization
```

---

## 📋 Critical Field Sync Tests

### Test 1: Watch Status Sync

**Scenario**: Mark episodes as watched on different devices

```
Device A (Apple ID A):
1. Add TV Show "Breaking Bad"
2. Mark S1E1 as watched
3. Set current episode to S1E2
4. Sync

Device B (Apple ID B): 
1. Sync
2. Verify S1E1 shows as watched
3. Verify current episode is S1E2
4. Mark S1E2 as watched
5. Sync

Device A:
1. Sync
2. Verify S1E2 shows as watched
```

**Expected Result**: ✅ All watched statuses sync correctly across Apple IDs

### Test 2: Rating Sync

**Scenario**: Rate content on different devices

```
Device A:
1. Add movie "Inception"
2. Set userRating = 4.5
3. Set mikeRating = 4.0
4. Sync

Device B:
1. Sync  
2. Verify userRating = 4.5
3. Verify mikeRating = 4.0
4. Set lauraRating = 5.0
5. Sync

Device A:
1. Sync
2. Verify lauraRating = 5.0
3. Verify other ratings unchanged
```

**Expected Result**: ✅ All rating fields sync independently

### Test 3: Episode Starred Status

**Scenario**: Star episodes on different devices

```
Device A:
1. Add TV Show with episodes
2. Star S1E5 (isStarred = true)
3. Sync

Device B:
1. Sync
2. Verify S1E5 is starred
3. Star S2E3
4. Sync

Device C (same Apple ID as A):
1. Sync
2. Verify both S1E5 and S2E3 are starred
```

**Expected Result**: ✅ Episode starred status syncs across all devices

### Test 4: Notes Sync (Cross-Apple ID)

**Scenario**: Share notes across different Apple IDs

```
Device A:
1. Add note to movie (ownerOnly = false)
2. Note text: "Great cinematography"
3. Sync

Device B (different Apple ID):
1. Sync
2. Verify note appears
3. Add note: "Amazing sound design"
4. Sync

Device A:
1. Sync
2. Verify both notes visible
```

**Expected Result**: ✅ Non-private notes sync across Apple IDs

### Test 5: Private Notes (No Cross-Apple ID)

**Scenario**: Private notes stay private

```
Device A:
1. Add note to movie (ownerOnly = true)
2. Note text: "Personal reminder"
3. Sync

Device B (different Apple ID):
1. Sync
2. Verify private note does NOT appear
```

**Expected Result**: ✅ Private notes don't sync across Apple IDs

---

## 🔄 Conflict Resolution Tests

### Test 6: Last Writer Wins - Episodes

**Scenario**: Same episode marked watched on different devices

```
Time 10:00 AM - Device A:
1. Mark S1E3 as watched
2. Set watchedDate = 10:00 AM
3. Go offline (airplane mode)

Time 10:05 AM - Device B:
1. Mark S1E3 as watched  
2. Set watchedDate = 10:05 AM
3. Sync immediately

Time 10:10 AM - Device A:
1. Go online
2. Sync

Expected: Device B wins (later timestamp)
Result: watchedDate should be 10:05 AM
```

### Test 7: Last Writer Wins - Ratings

**Scenario**: Rate same movie on different devices

```
Device A (10:00 AM):
1. Set userRating = 3.0
2. Sync

Device B (10:05 AM):
1. Set userRating = 4.0
2. Sync

Device A:
1. Sync

Expected: userRating = 4.0 (Device B wins)
```

### Test 8: Tombstone Wins Over Modification

**Scenario**: Delete item while another device modifies it

```
Device A (10:00 AM):
1. Delete movie "Inception"
2. Sync (creates tombstone)

Device B (9:55 AM - before deletion):
1. Update rating for "Inception"
2. Sync

Expected: Movie stays deleted (tombstone wins)
```

---

## 📱 Cross-Apple ID Specific Tests

### Test 9: List Sharing Across Apple IDs

**Scenario**: Complete list sharing workflow

```
Device A (Apple ID A):
1. Create list "Family Movies"
2. Add 5 movies
3. Enable Cross-Apple ID sync
4. Share list identifier

Device B (Apple ID B):
1. Enable Cross-Apple ID sync
2. Sync
3. Verify "Family Movies" list appears
4. Verify all 5 movies present
5. Add 2 more movies
6. Sync

Device C (Apple ID A):
1. Sync  
2. Verify all 7 movies present
```

**Expected Result**: ✅ Complete list sharing works across Apple IDs

### Test 10: Simultaneous Cross-Apple ID Updates

**Scenario**: Multiple Apple IDs modify shared data simultaneously

```
Device A (Apple ID A) - 10:00:00 AM:
1. Mark Movie X as watched
2. Sync

Device B (Apple ID B) - 10:00:01 AM:
1. Rate Movie X as 4.5 stars
2. Sync

Device C (Apple ID A) - 10:00:02 AM:
1. Add note to Movie X
2. Sync

All devices sync again:

Expected Result:
- Movie X is watched (from Device A)
- Movie X has 4.5 star rating (from Device B)  
- Movie X has note (from Device C)
```

---

## 🔀 Fractional Ordering Tests

### Test 11: List Item Ordering

**Scenario**: Reorder items on different devices

```
Initial state: [A, B, C, D]

Device 1:
1. Move A between C and D
2. Result: [B, C, A, D]
3. Sync

Device 2 (before sync):
1. Move D to beginning
2. Result: [D, A, B, C]
3. Sync

Expected merged result: [D, B, C, A]
(Both moves preserved due to fractional ordering)
```

### Test 12: Simultaneous List Insertions

**Scenario**: Insert items at same position simultaneously

```
Initial: [A, B, C]

Device 1:
1. Insert X between A and B
2. Result: [A, X, B, C]

Device 2:
1. Insert Y between A and B  
2. Result: [A, Y, B, C]

After sync: [A, X, Y, B, C] or [A, Y, X, B, C]
(Both insertions preserved, order determined by timestamps)
```

---

## 💾 Data Integrity Tests

### Test 13: Complete Field Preservation

**Scenario**: Verify ALL fields sync correctly

```
Device A - Create comprehensive title:
1. Basic info: title, year, overview, runtime
2. Ratings: userRating, mikeRating, lauraRating  
3. Status: watched, watchedDate, lastWatched
4. Progress: currentSeason, currentEpisode
5. Metadata: genres, posterPath, backdropPath
6. Custom: customField1, customField2
7. Preferences: isFavorite, likedStatus
8. Streaming: streamingService, mediaCategory
9. Sync

Device B:
1. Sync
2. Verify EVERY field matches exactly
```

**Expected Result**: ✅ 100% field preservation across devices

### Test 14: Episode Data Completeness

**Scenario**: Verify episode data syncs completely

```
Device A - Add TV show with episodes:
1. 3 seasons, 10 episodes each
2. Mark various episodes as watched
3. Star 5 random episodes
4. Set different watchedDates
5. Add notes to some episodes
6. Sync

Device B:
1. Sync
2. Verify all 30 episodes present
3. Verify watched status matches
4. Verify starred episodes match
5. Verify watchedDates match
6. Verify episode notes sync
```

**Expected Result**: ✅ Complete episode data fidelity

---

## 🌐 Offline/Online Tests

### Test 15: Offline Queue and Sync

**Scenario**: Make changes offline, then sync

```
Device A:
1. Go offline (airplane mode)
2. Add 3 movies
3. Mark 2 shows as watched
4. Rate 5 items
5. Create 2 lists
6. Go online
7. Sync

Device B:
1. Sync
2. Verify all offline changes appear
```

### Test 16: Conflicting Offline Changes

**Scenario**: Both devices offline, conflicting changes

```
Both devices go offline:

Device A:
1. Rate Movie X = 3.0 stars (at 10:00 AM)
2. Mark Episode Y as watched

Device B:  
1. Rate Movie X = 5.0 stars (at 10:05 AM)
2. Mark Episode Z as watched

Both go online and sync:

Expected:
- Movie X rating = 5.0 (Device B wins - later timestamp)
- Episode Y = watched
- Episode Z = watched
```

---

## 🔄 Performance Tests

### Test 17: Large Dataset Sync

**Scenario**: Sync performance with substantial data

```
Device A:
1. Create 50 lists
2. Add 1000 movies/shows total
3. Add 5000 episodes
4. Add 500 notes
5. Sync and measure time

Device B:
1. Sync and measure time
2. Should complete within reasonable time
```

**Acceptance Criteria**: 
- Initial sync: < 30 seconds
- Incremental sync: < 5 seconds

### Test 18: Frequent Sync Performance

**Scenario**: Rapid sync cycles

```
1. Enable auto-sync every 30 seconds
2. Make small changes frequently
3. Monitor performance over 1 hour
4. Check for sync conflicts or issues
```

---

## 🚨 Edge Case Tests

### Test 19: Device ID Changes

**Scenario**: Device identifier changes

```
1. Record initial deviceID
2. Force device ID regeneration
3. Sync
4. Verify no duplicate data
5. Verify LWW logic still works
```

### Test 20: Clock Skew Handling

**Scenario**: Devices with different system times

```
Device A: Set system time -1 hour
Device B: Set system time +1 hour
Device C: Correct system time

1. Make changes on all devices
2. Sync
3. Verify timestamps handle skew correctly
4. Verify conflict resolution works
```

### Test 21: Rapid-Fire Updates

**Scenario**: Very quick successive updates

```
1. Update same field 10 times in 1 second
2. Sync
3. Verify only latest update preserved
4. No duplicate data created
```

---

## ✅ Test Automation Script

```swift
class LWWComprehensiveTests: XCTestCase {
    
    func testWatchStatusSync() async {
        // Implement Test 1
    }
    
    func testRatingSync() async {
        // Implement Test 2  
    }
    
    func testEpisodeStarredSync() async {
        // Implement Test 3
    }
    
    func testNotesSync() async {
        // Implement Test 4
    }
    
    func testPrivateNotesNoSync() async {
        // Implement Test 5
    }
    
    func testLastWriterWinsEpisodes() async {
        // Implement Test 6
    }
    
    func testCrossAppleIDListSharing() async {
        // Implement Test 9
    }
    
    func testCompleteFieldPreservation() async {
        // Implement Test 13
    }
    
    func testOfflineQueueSync() async {
        // Implement Test 15
    }
    
    func testLargeDatasetPerformance() async {
        // Implement Test 17
    }
}
```

---

## 📊 Test Results Template

```markdown
# Test Run Results - [Date]

## Environment
- TestFlight Build: 2.0.0 (1)
- iOS Version: 17.x
- Devices: iPhone 15, iPad Pro, Mac Studio
- Apple IDs: 3 different accounts tested

## Results Summary

| Test | Status | Notes |
|------|--------|-------|
| Watch Status Sync | ✅ | All episode statuses sync correctly |
| Rating Sync | ✅ | All rating fields preserved |
| Episode Starred | ✅ | Starred status syncs across devices |
| Notes Sync | ✅ | Non-private notes share across Apple IDs |
| Private Notes | ✅ | Private notes stay private |
| LWW Episodes | ✅ | Later timestamp wins conflicts |
| Cross-Apple ID | ✅ | Complete list sharing works |
| Field Preservation | ✅ | 100% field fidelity |
| Offline Sync | ✅ | Queued changes sync correctly |
| Performance | ⚠️ | Large datasets take 25s (acceptable) |

## Critical Issues Found
None

## Performance Metrics
- Average sync time: 3.2 seconds
- Large dataset sync: 25 seconds  
- Conflict resolution: < 1 second

## Recommendations
✅ Ready for production deployment
```

This comprehensive testing strategy ensures that ALL critical fields sync correctly, especially for cross-Apple ID scenarios, and that the LWW conflict resolution works properly in all edge cases.