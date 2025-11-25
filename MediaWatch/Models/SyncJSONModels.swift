//
//  SyncJSONModels.swift
//  MediaWatch
//
//  JSON models for iCloud Drive sync with deterministic conflict resolution
//

import Foundation
import CryptoKit

// MARK: - Protocol for Syncable Items

protocol SyncableItem: Codable {
    var id: String { get }
    var createdAt: Date { get }
    var updatedAt: Date { get }
    var deletedAt: Date? { get }
    var deviceID: String { get }
}

// MARK: - Root Sync Data Structure

struct SyncJSONData: Codable {
    let version: Int
    let lastSyncedAt: Date
    let deviceId: String
    let lists: [SyncListData]
    let checksum: String // SHA256 hash for integrity verification
    
    init(version: Int, lastSyncedAt: Date, deviceId: String, lists: [SyncListData], checksum: String? = nil) {
        self.version = version
        self.lastSyncedAt = lastSyncedAt
        self.deviceId = deviceId
        self.lists = lists
        self.checksum = checksum ?? Self.calculateChecksum(for: lists)
    }
    
    // Custom decoder to handle backward compatibility
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        version = try container.decode(Int.self, forKey: .version)
        lastSyncedAt = try container.decode(Date.self, forKey: .lastSyncedAt)
        deviceId = try container.decode(String.self, forKey: .deviceId)
        lists = try container.decode([SyncListData].self, forKey: .lists)
        
        // Handle missing checksum for backward compatibility
        if container.contains(.checksum) {
            checksum = try container.decode(String.self, forKey: .checksum)
        } else {
            checksum = Self.calculateChecksum(for: lists)
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case version, lastSyncedAt, deviceId, lists, checksum
    }
    
    private static func calculateChecksum(for lists: [SyncListData]) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        
        do {
            let data = try encoder.encode(lists)
            return data.sha256
        } catch {
            return UUID().uuidString // Fallback to ensure we always have a checksum
        }
    }
    
    /// Compare checksums to detect content changes
    func hasContentChanges(comparedTo other: SyncJSONData) -> Bool {
        return self.checksum != other.checksum
    }
}

// MARK: - List Data

struct SyncListData: SyncableItem {
    let id: String
    let name: String
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let deviceID: String
    let order: Double
    let items: [SyncItemData]
    
    init(id: String, name: String, createdAt: Date, updatedAt: Date, deletedAt: Date? = nil, deviceID: String, order: Double = 0, items: [SyncItemData] = []) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.deviceID = deviceID
        self.order = order
        self.items = items
    }
}

// MARK: - Item Data (Movie/TV Show)

struct SyncItemData: SyncableItem {
    let id: String
    let tmdbId: Int
    let mediaType: String
    let title: String
    let year: Int
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let runtime: Int
    
    // Watch Status Fields
    let watched: Bool
    let watchedDate: Date?
    let watchStatus: Int
    let lastWatched: Date?
    
    // Episode Tracking for TV Shows
    let currentSeason: Int
    let currentEpisode: Int
    let numberOfSeasons: Int
    let numberOfEpisodes: Int
    
    // Rating Fields - ALL of them
    let userRating: Double?
    let mikeRating: Double?
    let lauraRating: Double?
    let voteAverage: Double?
    let voteCount: Int
    
    // Status and Preferences
    let isFavorite: Bool
    let likedStatus: Int
    let status: String?
    let streamingService: String?
    let mediaCategory: String?
    
    // Dates
    let releaseDate: Date?
    let firstAirDate: Date?
    let lastAirDate: Date?
    let startDate: Date?
    
    // Additional Metadata
    let originalTitle: String?
    let originalLanguage: String?
    let imdbId: String?
    let popularity: Double?
    let genres: [String]?
    
    // Custom Fields
    let customField1: String?
    let customField2: String?
    
    // LWW Metadata
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let deviceID: String
    let order: Double
    
    // Related Data
    let episodes: [SyncEpisodeData]
    let notes: [SyncNoteData]
    
    init(id: String, tmdbId: Int, mediaType: String, title: String, year: Int,
         overview: String? = nil, posterPath: String? = nil, backdropPath: String? = nil,
         runtime: Int = 0, watched: Bool = false, watchedDate: Date? = nil,
         watchStatus: Int = 1, lastWatched: Date? = nil, currentSeason: Int = 1,
         currentEpisode: Int = 1, numberOfSeasons: Int = 0, numberOfEpisodes: Int = 0,
         userRating: Double? = nil, mikeRating: Double? = nil, lauraRating: Double? = nil,
         voteAverage: Double? = nil, voteCount: Int = 0, isFavorite: Bool = false,
         likedStatus: Int = 0, status: String? = nil, streamingService: String? = nil,
         mediaCategory: String? = nil, releaseDate: Date? = nil, firstAirDate: Date? = nil,
         lastAirDate: Date? = nil, startDate: Date? = nil, originalTitle: String? = nil,
         originalLanguage: String? = nil, imdbId: String? = nil, popularity: Double? = nil,
         genres: [String]? = nil, customField1: String? = nil, customField2: String? = nil,
         createdAt: Date, updatedAt: Date, deletedAt: Date? = nil, deviceID: String,
         order: Double = 0, episodes: [SyncEpisodeData] = [], notes: [SyncNoteData] = []) {
        
        self.id = id
        self.tmdbId = tmdbId
        self.mediaType = mediaType
        self.title = title
        self.year = year
        self.overview = overview
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.runtime = runtime
        self.watched = watched
        self.watchedDate = watchedDate
        self.watchStatus = watchStatus
        self.lastWatched = lastWatched
        self.currentSeason = currentSeason
        self.currentEpisode = currentEpisode
        self.numberOfSeasons = numberOfSeasons
        self.numberOfEpisodes = numberOfEpisodes
        self.userRating = userRating
        self.mikeRating = mikeRating
        self.lauraRating = lauraRating
        self.voteAverage = voteAverage
        self.voteCount = voteCount
        self.isFavorite = isFavorite
        self.likedStatus = likedStatus
        self.status = status
        self.streamingService = streamingService
        self.mediaCategory = mediaCategory
        self.releaseDate = releaseDate
        self.firstAirDate = firstAirDate
        self.lastAirDate = lastAirDate
        self.startDate = startDate
        self.originalTitle = originalTitle
        self.originalLanguage = originalLanguage
        self.imdbId = imdbId
        self.popularity = popularity
        self.genres = genres
        self.customField1 = customField1
        self.customField2 = customField2
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.deviceID = deviceID
        self.order = order
        self.episodes = episodes
        self.notes = notes
    }
}

// MARK: - Episode Data

struct SyncEpisodeData: SyncableItem {
    let id: String
    let tmdbId: Int
    let seasonNumber: Int
    let episodeNumber: Int
    let name: String
    let overview: String?
    let stillPath: String?
    let airDate: Date?
    let runtime: Int
    let watched: Bool
    let watchedDate: Date?
    let isStarred: Bool
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let deviceID: String
    
    init(id: String, tmdbId: Int, seasonNumber: Int, episodeNumber: Int,
         name: String, overview: String? = nil, stillPath: String? = nil,
         airDate: Date? = nil, runtime: Int = 0, watched: Bool = false,
         watchedDate: Date? = nil, isStarred: Bool = false,
         createdAt: Date, updatedAt: Date, deletedAt: Date? = nil, deviceID: String) {
        self.id = id
        self.tmdbId = tmdbId
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.name = name
        self.overview = overview
        self.stillPath = stillPath
        self.airDate = airDate
        self.runtime = runtime
        self.watched = watched
        self.watchedDate = watchedDate
        self.isStarred = isStarred
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.deviceID = deviceID
    }
}

// MARK: - Note Data

struct SyncNoteData: SyncableItem {
    let id: String
    let text: String
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?
    let deviceID: String
    
    init(id: String, text: String, createdAt: Date, updatedAt: Date, deletedAt: Date? = nil, deviceID: String) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
        self.deviceID = deviceID
    }
}

// MARK: - Migration Status

struct SyncMigrationStatus {
    let isRequired: Bool
    let coreDataItemCount: Int
    let canMigrate: Bool
    
    var statusMessage: String {
        if !isRequired {
            return "Migration already completed"
        } else if coreDataItemCount == 0 {
            return "No existing data to migrate"
        } else if canMigrate {
            return "\(coreDataItemCount) items ready to migrate"
        } else {
            return "iCloud Drive not available for migration"
        }
    }
}

// MARK: - Sync Statistics

struct SyncStatistics: Codable {
    let lastSyncDate: Date?
    let totalSyncs: Int
    let totalConflicts: Int
    let totalErrors: Int
    let averageSyncDuration: TimeInterval
    let lastSyncDuration: TimeInterval
    let dataSize: Int // in bytes
    
    init() {
        self.lastSyncDate = nil
        self.totalSyncs = 0
        self.totalConflicts = 0
        self.totalErrors = 0
        self.averageSyncDuration = 0
        self.lastSyncDuration = 0
        self.dataSize = 0
    }
}

// MARK: - Conflict Resolution Result

struct ConflictResolutionResult {
    let resolvedConflicts: Int
    let strategy: ConflictStrategy
    let affectedItems: [String] // Item IDs
    
    enum ConflictStrategy {
        case lastWriterWins
        case deviceIdTiebreaker
        case mergeStrategy
    }
}

// MARK: - Sync Health Status

struct SyncHealthStatus {
    let isHealthy: Bool
    let issues: [SyncIssue]
    let recommendations: [String]
    
    struct SyncIssue {
        let type: IssueType
        let description: String
        let severity: Severity
        
        enum IssueType {
            case iCloudUnavailable
            case diskSpaceLow
            case networkConnectivity
            case corruptedData
            case permissionDenied
            case frequentConflicts
        }
        
        enum Severity {
            case low, medium, high, critical
        }
    }
}

// MARK: - LWW (Last Writer Wins) Utilities

extension SyncableItem {
    /// Determines if this item should win over another in LWW conflict resolution
    func shouldWinOver<T: SyncableItem>(_ other: T) -> Bool {
        // Check deletedAt first - if one item is deleted and the other isn't, deleted wins if newer
        switch (self.deletedAt, other.deletedAt) {
        case (let selfDeleted?, let otherDeleted?):
            // Both deleted - use latest deletion timestamp
            return selfDeleted > otherDeleted
        case (let selfDeleted?, nil):
            // Self is deleted, other isn't - deleted wins if deletion is newer than other's last update
            return selfDeleted > other.updatedAt
        case (nil, let otherDeleted?):
            // Other is deleted, self isn't - other wins if deletion is newer than self's last update
            return self.updatedAt > otherDeleted
        case (nil, nil):
            // Neither deleted - use standard LWW rules
            break
        }
        
        // Standard LWW: compare updatedAt timestamps
        if self.updatedAt > other.updatedAt {
            return true
        } else if self.updatedAt < other.updatedAt {
            return false
        } else {
            // Timestamps equal - use deviceID for deterministic tie-breaking
            return self.deviceID < other.deviceID
        }
    }
    
    /// Returns true if this item is deleted (has deletedAt timestamp)
    var isDeleted: Bool {
        return deletedAt != nil
    }
    
    /// Returns true if this item is a tombstone (deleted but kept for sync)
    var isTombstone: Bool {
        return isDeleted
    }
    
    /// Extended LWW comparison that uses deviceID as tie-breaker
    func shouldWinOverExtended<T: SyncableItem>(_ other: T) -> Bool {
        // First check deleted status
        switch (self.deletedAt, other.deletedAt) {
        case (let selfDeleted?, let otherDeleted?):
            // Both deleted - use latest deletion timestamp
            if selfDeleted != otherDeleted {
                return selfDeleted > otherDeleted
            }
            // Same deletion time - use deviceID tie-breaker
            return self.deviceID < other.deviceID
        case (let selfDeleted?, nil):
            // Self is deleted, other isn't - deleted wins if deletion is newer than other's last update
            return selfDeleted > other.updatedAt
        case (nil, let otherDeleted?):
            // Other is deleted, self isn't - other wins if deletion is newer than self's last update
            return self.updatedAt <= otherDeleted
        case (nil, nil):
            // Neither deleted - use standard LWW rules
            break
        }
        
        // Compare timestamps with extended key
        let selfKey = LWWComparisonKey(timestamp: self.updatedAt, deviceID: self.deviceID)
        let otherKey = LWWComparisonKey(timestamp: other.updatedAt, deviceID: other.deviceID)
        
        return selfKey > otherKey
    }
}

// MARK: - LWW Comparison Key

struct LWWComparisonKey: Comparable {
    let timestamp: Date
    let deviceID: String
    
    static func < (lhs: LWWComparisonKey, rhs: LWWComparisonKey) -> Bool {
        if lhs.timestamp != rhs.timestamp {
            return lhs.timestamp < rhs.timestamp
        }
        // Tie breaker: lexicographic device ID comparison
        return lhs.deviceID < rhs.deviceID
    }
    
    static func == (lhs: LWWComparisonKey, rhs: LWWComparisonKey) -> Bool {
        return lhs.timestamp == rhs.timestamp && lhs.deviceID == rhs.deviceID
    }
}

// MARK: - Fractional Ordering Utilities

struct FractionalOrdering {
    /// Generate a new order value between two existing order values
    /// This implements the fractional ordering pattern for conflict-free ordering
    static func between(_ before: Double, _ after: Double) -> Double {
        return (before + after) / 2.0
    }
    
    /// Generate a new order value at the beginning of a sequence
    static func atBeginning(before first: Double) -> Double {
        return first / 2.0
    }
    
    /// Generate a new order value at the end of a sequence
    static func atEnd(after last: Double) -> Double {
        return last + 1.0
    }
    
    /// Generate the first order value for an empty sequence
    static func first() -> Double {
        return 1.0
    }
    
    /// Normalize a sequence of order values to clean up precision issues
    /// Should be called periodically to prevent floating point precision problems
    static func normalize<T>(_ items: [T], orderKeyPath: WritableKeyPath<T, Double>) -> [T] {
        var normalizedItems = items
        for (index, _) in normalizedItems.enumerated() {
            normalizedItems[index][keyPath: orderKeyPath] = Double(index + 1)
        }
        return normalizedItems
    }
}

// MARK: - Data Extensions for Checksum

extension Data {
    var sha256: String {
        let hashed = SHA256.hash(data: self)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
}