# MediaWatch - Data Models

## Overview

This document defines the Core Data entities, attributes, relationships, and CloudKit mapping for MediaWatch.

---

## 1. Entity Relationship Diagram

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│    List     │────<│  ListItem   │>────│    Title    │
└─────────────┘     └─────────────┘     └─────────────┘
                                              │
                                              │ (TV Shows only)
                                              ▼
                                        ┌─────────────┐
                                        │   Episode   │
                                        └─────────────┘
                                              │
                    ┌─────────────────────────┼─────────────────────────┐
                    │                         │                         │
                    ▼                         ▼                         ▼
              ┌─────────────┐           ┌─────────────┐           ┌─────────────┐
              │    Note     │           │    Note     │           │    Note     │
              │  (Title)    │           │ (Episode)   │           │             │
              └─────────────┘           └─────────────┘           └─────────────┘
```

---

## 2. Core Data Entities

### 2.1 Title

The main entity representing a Movie or TV Show.

#### Attributes

| Attribute | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `id` | UUID | Yes | Auto | Primary identifier |
| `tmdbId` | Int64 | Yes | - | TMDb unique identifier |
| `imdbId` | String | No | nil | IMDb identifier (tt...) |
| `mediaType` | String | Yes | - | "movie" or "tv" |
| `title` | String | Yes | - | Display title |
| `originalTitle` | String | No | nil | Original language title |
| `year` | Int16 | No | 0 | Release/first air year |
| `overview` | String | No | nil | Synopsis/description |
| `genres` | Transformable | No | [] | Array of genre strings |
| `runtime` | Int16 | No | 0 | Minutes (movie) or avg episode |
| `posterPath` | String | No | nil | TMDb poster image path |
| `backdropPath` | String | No | nil | TMDb backdrop image path |
| `originalLanguage` | String | No | nil | ISO 639-1 code |
| `popularity` | Double | No | 0 | TMDb popularity score |
| `voteAverage` | Double | No | 0 | TMDb vote average |
| `voteCount` | Int32 | No | 0 | TMDb vote count |
| `releaseDate` | Date | No | nil | Movie release date |
| `firstAirDate` | Date | No | nil | TV first episode date |
| `lastAirDate` | Date | No | nil | TV last episode date |
| `status` | String | No | nil | TV status (Returning/Ended) |
| `numberOfSeasons` | Int16 | No | 0 | TV total seasons |
| `numberOfEpisodes` | Int16 | No | 0 | TV total episodes |
| `watched` | Bool | Yes | false | User watched status |
| `watchedDate` | Date | No | nil | When marked watched |
| `likedStatus` | Int16 | Yes | 0 | -1=Disliked, 0=Neutral, 1=Liked |
| `dateAdded` | Date | Yes | Now | When added to app |
| `dateModified` | Date | Yes | Now | Last modification |
| `localPosterPath` | String | No | nil | Cached poster file path |
| `localBackdropPath` | String | No | nil | Cached backdrop file path |

#### Relationships

| Relationship | Destination | Type | Delete Rule | Description |
|--------------|-------------|------|-------------|-------------|
| `episodes` | Episode | To-Many | Cascade | TV show episodes |
| `listItems` | ListItem | To-Many | Cascade | List memberships |
| `notes` | Note | To-Many | Cascade | User notes |

#### Constraints
- Unique constraint on `tmdbId` + `mediaType`

#### CloudKit
- Synced to private zone by default
- Included in shared zone when parent List is shared

---

### 2.2 Episode

Individual episode of a TV show.

#### Attributes

| Attribute | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `id` | UUID | Yes | Auto | Primary identifier |
| `tmdbId` | Int64 | No | 0 | TMDb episode ID |
| `seasonNumber` | Int16 | Yes | - | Season number |
| `episodeNumber` | Int16 | Yes | - | Episode number |
| `name` | String | Yes | - | Episode title |
| `overview` | String | No | nil | Episode synopsis |
| `airDate` | Date | No | nil | Air date |
| `runtime` | Int16 | No | 0 | Episode runtime minutes |
| `stillPath` | String | No | nil | TMDb still image path |
| `watched` | Bool | Yes | false | User watched status |
| `watchedDate` | Date | No | nil | When marked watched |
| `dateModified` | Date | Yes | Now | Last modification |
| `localStillPath` | String | No | nil | Cached still file path |

#### Relationships

| Relationship | Destination | Type | Delete Rule | Description |
|--------------|-------------|------|-------------|-------------|
| `show` | Title | To-One | Nullify | Parent TV show |
| `notes` | Note | To-Many | Cascade | Episode notes |

#### Constraints
- Unique constraint on `show` + `seasonNumber` + `episodeNumber`

---

### 2.3 List

User-created collection of titles.

#### Attributes

| Attribute | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `id` | UUID | Yes | Auto | Primary identifier |
| `name` | String | Yes | - | List display name |
| `icon` | String | No | nil | SF Symbol name |
| `colorHex` | String | No | nil | Hex color code |
| `sortOrder` | Int16 | Yes | 0 | Order in list of lists |
| `isDefault` | Bool | Yes | false | Default list for new titles |
| `dateCreated` | Date | Yes | Now | Creation date |
| `dateModified` | Date | Yes | Now | Last modification |

#### Relationships

| Relationship | Destination | Type | Delete Rule | Description |
|--------------|-------------|------|-------------|-------------|
| `items` | ListItem | To-Many | Cascade | Titles in this list |

#### CloudKit Sharing
- Primary shareable entity
- Creates CKShare when shared
- All referenced Titles automatically included

---

### 2.4 ListItem

Junction entity for List-Title many-to-many relationship.

#### Attributes

| Attribute | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `id` | UUID | Yes | Auto | Primary identifier |
| `orderIndex` | Int16 | Yes | 0 | Sort order within list |
| `dateAdded` | Date | Yes | Now | When added to list |

#### Relationships

| Relationship | Destination | Type | Delete Rule | Description |
|--------------|-------------|------|-------------|-------------|
| `list` | List | To-One | Nullify | Parent list |
| `title` | Title | To-One | Nullify | Referenced title |

#### Constraints
- Unique constraint on `list` + `title`

---

### 2.5 Note

User notes attached to titles or episodes.

#### Attributes

| Attribute | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `id` | UUID | Yes | Auto | Primary identifier |
| `text` | String | Yes | "" | Note content (plain/markdown) |
| `ownerOnly` | Bool | Yes | true | Private to creator |
| `dateCreated` | Date | Yes | Now | Creation date |
| `dateModified` | Date | Yes | Now | Last modification |

#### Relationships

| Relationship | Destination | Type | Delete Rule | Description |
|--------------|-------------|------|-------------|-------------|
| `title` | Title | To-One | Nullify | Parent title (optional) |
| `episode` | Episode | To-One | Nullify | Parent episode (optional) |

#### Validation
- Must have either `title` OR `episode` set, not both

#### CloudKit
- `ownerOnly = true`: Stays in private zone only
- `ownerOnly = false`: Synced with shared zone

---

### 2.6 UserPreferences

App-wide user settings (singleton).

#### Attributes

| Attribute | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `id` | UUID | Yes | Auto | Primary identifier |
| `defaultListId` | UUID | No | nil | Default list for new titles |
| `defaultLikedStatus` | Int16 | Yes | 0 | Default liked status |
| `imageQuality` | String | Yes | "w500" | TMDb image size preference |
| `showWatchedInLists` | Bool | Yes | true | Show watched items |
| `sortBy` | String | Yes | "dateAdded" | Default sort field |
| `sortAscending` | Bool | Yes | false | Sort direction |
| `lastSyncDate` | Date | No | nil | Last CloudKit sync |
| `appVersion` | String | No | nil | Last used app version |

#### CloudKit
- Synced to private zone only

---

## 3. CloudKit Configuration

### 3.1 Container Setup

```swift
// Container identifier
let containerIdentifier = "iCloud.com.yourcompany.MediaWatch"

// Initialize with CloudKit
lazy var persistentContainer: NSPersistentCloudKitContainer = {
    let container = NSPersistentCloudKitContainer(name: "MediaWatch")

    // Private database store
    let privateStoreDescription = container.persistentStoreDescriptions.first!
    privateStoreDescription.cloudKitContainerOptions =
        NSPersistentCloudKitContainerOptions(containerIdentifier: containerIdentifier)

    // Shared database store
    let sharedStoreURL = privateStoreDescription.url!
        .deletingLastPathComponent()
        .appendingPathComponent("MediaWatch-shared.sqlite")

    let sharedStoreDescription = NSPersistentStoreDescription(url: sharedStoreURL)
    sharedStoreDescription.cloudKitContainerOptions =
        NSPersistentCloudKitContainerOptions(containerIdentifier: containerIdentifier)
    sharedStoreDescription.cloudKitContainerOptions!.databaseScope = .shared

    container.persistentStoreDescriptions = [privateStoreDescription, sharedStoreDescription]

    return container
}()
```

### 3.2 Record Types

Core Data automatically generates CloudKit record types:

| Core Data Entity | CloudKit Record Type |
|------------------|---------------------|
| Title | CD_Title |
| Episode | CD_Episode |
| List | CD_List |
| ListItem | CD_ListItem |
| Note | CD_Note |
| UserPreferences | CD_UserPreferences |

### 3.3 Sharing Configuration

```swift
// Share a list
func shareList(_ list: List) async throws -> CKShare {
    let (_, share, _) = try await persistentContainer.share(
        [list],
        to: nil  // Creates new share
    )

    share[CKShare.SystemFieldKey.title] = list.name
    share[CKShare.SystemFieldKey.thumbnailImageData] = nil

    return share
}
```

---

## 4. Data Validation Rules

### 4.1 Title
- `tmdbId` must be > 0
- `mediaType` must be "movie" or "tv"
- `title` cannot be empty
- Must belong to at least one List

### 4.2 Episode
- `seasonNumber` must be >= 0
- `episodeNumber` must be >= 1
- `name` cannot be empty
- Must have parent `show`

### 4.3 List
- `name` cannot be empty
- `name` max length 100 characters

### 4.4 Note
- Must have either `title` or `episode`, not both, not neither
- `text` max length 10,000 characters

---

## 5. Indexes for Performance

### Title
- `tmdbId` (unique with mediaType)
- `mediaType`
- `dateAdded`
- `title` (for sorting)

### Episode
- `show` + `seasonNumber` + `episodeNumber` (compound unique)
- `seasonNumber`
- `watched`

### ListItem
- `list` + `title` (compound unique)
- `orderIndex`

---

## 6. Migration Strategy

### Version 1.0
- Initial schema as defined above

### Future Migrations
- Use lightweight migrations when possible
- Custom migration for complex changes
- Backup before migration
- Test migration with real data

---

## 7. Swift Model Extensions

### 7.1 Title+Computed

```swift
extension Title {
    var displayYear: String {
        year > 0 ? String(year) : ""
    }

    var isMovie: Bool {
        mediaType == "movie"
    }

    var isTVShow: Bool {
        mediaType == "tv"
    }

    var watchProgress: Double {
        guard isTVShow, let episodes = episodes as? Set<Episode> else {
            return watched ? 1.0 : 0.0
        }
        let total = episodes.count
        guard total > 0 else { return 0.0 }
        let watchedCount = episodes.filter { $0.watched }.count
        return Double(watchedCount) / Double(total)
    }

    var likedStatusEnum: LikedStatus {
        LikedStatus(rawValue: Int(likedStatus)) ?? .neutral
    }
}

enum LikedStatus: Int {
    case disliked = -1
    case neutral = 0
    case liked = 1
}
```

### 7.2 Episode+Computed

```swift
extension Episode {
    var episodeCode: String {
        String(format: "S%02dE%02d", seasonNumber, episodeNumber)
    }

    var fullName: String {
        "\(episodeCode) - \(name ?? "Unknown")"
    }
}
```

### 7.3 List+Computed

```swift
extension List {
    var titleCount: Int {
        items?.count ?? 0
    }

    var watchedCount: Int {
        guard let items = items as? Set<ListItem> else { return 0 }
        return items.filter { $0.title?.watched == true }.count
    }

    var watchProgress: Double {
        let total = titleCount
        guard total > 0 else { return 0.0 }
        return Double(watchedCount) / Double(total)
    }
}
```

---

## 8. Data Transfer Objects (DTOs)

### 8.1 TMDb API Response Models

```swift
struct TMDbSearchResponse: Codable {
    let page: Int
    let results: [TMDbSearchResult]
    let totalPages: Int
    let totalResults: Int

    enum CodingKeys: String, CodingKey {
        case page, results
        case totalPages = "total_pages"
        case totalResults = "total_results"
    }
}

struct TMDbSearchResult: Codable, Identifiable {
    let id: Int
    let mediaType: String?
    let title: String?
    let name: String?
    let originalTitle: String?
    let originalName: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let firstAirDate: String?
    let voteAverage: Double?
    let voteCount: Int?
    let popularity: Double?
    let genreIds: [Int]?
    let originalLanguage: String?

    var displayTitle: String {
        title ?? name ?? "Unknown"
    }

    var displayYear: String {
        let date = releaseDate ?? firstAirDate ?? ""
        return String(date.prefix(4))
    }
}
```

### 8.2 Export/Import Models

```swift
struct ExportData: Codable {
    let version: String
    let exportDate: Date
    let lists: [ExportList]
    let titles: [ExportTitle]
    let episodes: [ExportEpisode]
    let notes: [ExportNote]
}

struct ExportList: Codable {
    let id: String
    let name: String
    let icon: String?
    let colorHex: String?
    let sortOrder: Int
    let titleIds: [String]
}

struct ExportTitle: Codable {
    let id: String
    let tmdbId: Int
    let imdbId: String?
    let mediaType: String
    let title: String
    let year: Int
    let overview: String?
    let genres: [String]
    let runtime: Int
    let posterPath: String?
    let backdropPath: String?
    let watched: Bool
    let watchedDate: Date?
    let likedStatus: Int
    let dateAdded: Date
}

struct ExportEpisode: Codable {
    let id: String
    let showId: String
    let seasonNumber: Int
    let episodeNumber: Int
    let name: String
    let overview: String?
    let watched: Bool
    let watchedDate: Date?
}

struct ExportNote: Codable {
    let id: String
    let parentId: String
    let parentType: String  // "title" or "episode"
    let text: String
    let ownerOnly: Bool
    let dateCreated: Date
}
```
