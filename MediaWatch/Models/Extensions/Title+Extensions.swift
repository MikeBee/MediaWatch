//
//  Title+Extensions.swift
//  MediaWatch
//
//  Extensions for the Title Core Data entity
//

import Foundation
import CoreData

// MARK: - Liked Status Enum

enum LikedStatus: Int, CaseIterable {
    case disliked = -1
    case neutral = 0
    case liked = 1

    var displayName: String {
        switch self {
        case .disliked: return "Disliked"
        case .neutral: return "Neutral"
        case .liked: return "Liked"
        }
    }

    var systemImage: String {
        switch self {
        case .disliked: return "hand.thumbsdown.fill"
        case .neutral: return "minus.circle"
        case .liked: return "hand.thumbsup.fill"
        }
    }
}

// MARK: - Title Extensions

extension Title {

    // MARK: - Type Checks

    var isMovie: Bool {
        mediaType == "movie"
    }

    var isTVShow: Bool {
        mediaType == "tv"
    }

    // MARK: - Display Properties

    var displayTitle: String {
        title ?? "Unknown Title"
    }

    var displayYear: String {
        year > 0 ? String(year) : ""
    }

    var displayRuntime: String {
        guard runtime > 0 else { return "" }
        let hours = runtime / 60
        let minutes = runtime % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    var displayGenres: String {
        (genres as? [String])?.joined(separator: ", ") ?? ""
    }

    var displayType: String {
        isMovie ? "Movie" : "TV Show"
    }

    var displayStatus: String {
        if isMovie {
            return watched ? "Watched" : "Not Watched"
        } else {
            let progress = watchProgress
            if progress >= 1.0 {
                return "Completed"
            } else if progress > 0 {
                return "In Progress"
            } else {
                return "Not Started"
            }
        }
    }

    // MARK: - Liked Status

    var likedStatusEnum: LikedStatus {
        get {
            LikedStatus(rawValue: Int(likedStatus)) ?? .neutral
        }
        set {
            likedStatus = Int16(newValue.rawValue)
        }
    }

    // MARK: - Watch Progress

    /// Returns watch progress as a value between 0.0 and 1.0
    var watchProgress: Double {
        if isMovie {
            return watched ? 1.0 : 0.0
        }

        guard let episodeSet = episodes as? Set<Episode> else {
            return 0.0
        }

        let total = episodeSet.count
        guard total > 0 else { return 0.0 }

        let watchedCount = episodeSet.filter { $0.watched }.count
        return Double(watchedCount) / Double(total)
    }

    /// Returns the number of watched episodes
    var watchedEpisodeCount: Int {
        guard let episodeSet = episodes as? Set<Episode> else { return 0 }
        return episodeSet.filter { $0.watched }.count
    }

    /// Returns total episode count
    var totalEpisodeCount: Int {
        (episodes as? Set<Episode>)?.count ?? 0
    }

    /// Returns progress as a formatted string
    var watchProgressText: String {
        if isMovie {
            return watched ? "Watched" : "Not Watched"
        }
        return "\(watchedEpisodeCount)/\(totalEpisodeCount)"
    }

    // MARK: - Episodes by Season

    /// Returns episodes grouped by season number
    var episodesBySeason: [Int16: [Episode]] {
        guard let episodeSet = episodes as? Set<Episode> else { return [:] }

        var grouped: [Int16: [Episode]] = [:]
        for episode in episodeSet {
            grouped[episode.seasonNumber, default: []].append(episode)
        }

        // Sort episodes within each season
        for (season, eps) in grouped {
            grouped[season] = eps.sorted { $0.episodeNumber < $1.episodeNumber }
        }

        return grouped
    }

    /// Returns sorted season numbers
    var seasonNumbers: [Int16] {
        Array(episodesBySeason.keys).sorted()
    }

    // MARK: - List Membership

    /// Returns all lists this title belongs to
    var lists: [MediaList] {
        guard let itemSet = listItems as? Set<ListItem> else { return [] }
        return itemSet.compactMap { $0.list }
    }

    /// Checks if the title is in a specific list
    func isInList(_ list: MediaList) -> Bool {
        lists.contains { $0.objectID == list.objectID }
    }

    // MARK: - Notes

    /// Returns all notes sorted by creation date
    var sortedNotes: [Note] {
        guard let noteSet = notes as? Set<Note> else { return [] }
        return noteSet.sorted { ($0.dateCreated ?? .distantPast) > ($1.dateCreated ?? .distantPast) }
    }

    // MARK: - Image URLs

    /// Returns the TMDb poster URL for a given size
    func posterURL(size: String = "w500") -> URL? {
        guard let path = posterPath, !path.isEmpty else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/\(size)\(path)")
    }

    /// Returns the TMDb backdrop URL for a given size
    func backdropURL(size: String = "w780") -> URL? {
        guard let path = backdropPath, !path.isEmpty else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/\(size)\(path)")
    }

    // MARK: - Actions

    /// Toggles watched status for the title
    func toggleWatched() {
        watched.toggle()
        watchedDate = watched ? Date() : nil
        dateModified = Date()
    }

    /// Marks all episodes as watched or unwatched
    func markAllEpisodes(watched: Bool) {
        guard let episodeSet = episodes as? Set<Episode> else { return }

        for episode in episodeSet {
            episode.watched = watched
            episode.watchedDate = watched ? Date() : nil
        }

        dateModified = Date()
    }

    /// Marks a specific season as watched or unwatched
    func markSeason(_ seasonNumber: Int16, watched: Bool) {
        guard let episodeSet = episodes as? Set<Episode> else { return }

        for episode in episodeSet where episode.seasonNumber == seasonNumber {
            episode.watched = watched
            episode.watchedDate = watched ? Date() : nil
        }

        dateModified = Date()
    }
}

// MARK: - Fetch Requests

extension Title {

    /// Fetch request for all titles
    static func fetchAll() -> NSFetchRequest<Title> {
        let request = NSFetchRequest<Title>(entityName: "Title")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Title.dateAdded, ascending: false)]
        return request
    }

    /// Fetch request for titles by media type
    static func fetchByType(_ mediaType: String) -> NSFetchRequest<Title> {
        let request = NSFetchRequest<Title>(entityName: "Title")
        request.predicate = NSPredicate(format: "mediaType == %@", mediaType)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Title.dateAdded, ascending: false)]
        return request
    }

    /// Fetch request for a title by TMDb ID
    static func fetchByTmdbId(_ tmdbId: Int64, mediaType: String) -> NSFetchRequest<Title> {
        let request = NSFetchRequest<Title>(entityName: "Title")
        request.predicate = NSPredicate(format: "tmdbId == %lld AND mediaType == %@", tmdbId, mediaType)
        request.fetchLimit = 1
        return request
    }
}
