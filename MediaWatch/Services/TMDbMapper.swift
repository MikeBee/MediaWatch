//
//  TMDbMapper.swift
//  MediaWatch
//
//  Maps TMDb API responses to Core Data entities
//

import Foundation
import CoreData

// MARK: - TMDb Mapper

struct TMDbMapper {

    // MARK: - Date Parsing

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()

    private static func parseDate(_ dateString: String?) -> Date? {
        guard let dateString = dateString, !dateString.isEmpty else { return nil }
        return dateFormatter.date(from: dateString)
    }

    private static func parseYear(_ dateString: String?) -> Int16? {
        guard let dateString = dateString, dateString.count >= 4 else { return nil }
        return Int16(String(dateString.prefix(4)))
    }

    // MARK: - Title Mapping

    /// Create or update a Title from search result
    @discardableResult
    static func mapSearchResult(
        _ result: TMDbSearchResult,
        context: NSManagedObjectContext
    ) -> Title {
        // Check if title already exists
        let fetchRequest: NSFetchRequest<Title> = Title.fetchRequest()
        fetchRequest.predicate = NSPredicate(
            format: "tmdbId == %lld AND mediaType == %@",
            Int64(result.id),
            result.resolvedMediaType
        )

        let existingTitle = try? context.fetch(fetchRequest).first

        let title = existingTitle ?? Title(context: context)

        // Set basic properties
        if title.id == nil {
            title.id = UUID()
        }
        title.tmdbId = Int64(result.id)
        title.mediaType = result.resolvedMediaType
        title.title = result.displayTitle
        title.originalTitle = result.originalTitle ?? result.originalName
        title.overview = result.overview
        title.posterPath = result.posterPath
        title.backdropPath = result.backdropPath
        title.voteAverage = result.voteAverage ?? 0
        title.voteCount = Int32(result.voteCount ?? 0)
        title.popularity = result.popularity ?? 0
        title.originalLanguage = result.originalLanguage

        // Set dates
        if result.resolvedMediaType == "movie" {
            title.releaseDate = parseDate(result.releaseDate)
            title.year = parseYear(result.releaseDate) ?? 0
        } else {
            title.firstAirDate = parseDate(result.firstAirDate)
            title.year = parseYear(result.firstAirDate) ?? 0
        }

        // Set timestamps for new entities
        if existingTitle == nil {
            title.dateAdded = Date()
        }
        title.dateModified = Date()

        return title
    }

    /// Update a Title with movie details
    @discardableResult
    static func mapMovieDetails(
        _ details: TMDbMovieDetails,
        to title: Title
    ) -> Title {
        title.imdbId = details.imdbId
        title.title = details.title
        title.originalTitle = details.originalTitle
        title.overview = details.overview
        title.posterPath = details.posterPath
        title.backdropPath = details.backdropPath
        title.releaseDate = parseDate(details.releaseDate)
        title.year = parseYear(details.releaseDate) ?? 0
        title.runtime = Int16(details.runtime ?? 0)
        title.status = details.status
        title.voteAverage = details.voteAverage ?? 0
        title.voteCount = Int32(details.voteCount ?? 0)
        title.popularity = details.popularity ?? 0
        title.originalLanguage = details.originalLanguage
        title.genres = details.genreNames
        title.dateModified = Date()

        return title
    }

    /// Update a Title with TV show details
    @discardableResult
    static func mapTVDetails(
        _ details: TMDbTVDetails,
        to title: Title
    ) -> Title {
        title.title = details.name
        title.originalTitle = details.originalName
        title.overview = details.overview
        title.posterPath = details.posterPath
        title.backdropPath = details.backdropPath
        title.firstAirDate = parseDate(details.firstAirDate)
        title.lastAirDate = parseDate(details.lastAirDate)
        title.year = parseYear(details.firstAirDate) ?? 0
        title.runtime = Int16(details.averageRuntime ?? 0)
        title.status = details.status
        title.numberOfSeasons = Int16(details.numberOfSeasons ?? 0)
        title.numberOfEpisodes = Int16(details.numberOfEpisodes ?? 0)
        title.voteAverage = details.voteAverage ?? 0
        title.voteCount = Int32(details.voteCount ?? 0)
        title.popularity = details.popularity ?? 0
        title.originalLanguage = details.originalLanguage
        title.genres = details.genreNames
        title.dateModified = Date()

        return title
    }

    /// Create or update a Title from movie details
    @discardableResult
    static func createTitle(
        from movieDetails: TMDbMovieDetails,
        context: NSManagedObjectContext
    ) -> Title {
        // Check if title already exists
        let fetchRequest: NSFetchRequest<Title> = Title.fetchRequest()
        fetchRequest.predicate = NSPredicate(
            format: "tmdbId == %lld AND mediaType == %@",
            Int64(movieDetails.id),
            "movie"
        )

        let existingTitle = try? context.fetch(fetchRequest).first
        let title = existingTitle ?? Title(context: context)

        if title.id == nil {
            title.id = UUID()
        }
        title.tmdbId = Int64(movieDetails.id)
        title.mediaType = "movie"

        if existingTitle == nil {
            title.dateAdded = Date()
        }

        return mapMovieDetails(movieDetails, to: title)
    }

    /// Create or update a Title from TV details
    @discardableResult
    static func createTitle(
        from tvDetails: TMDbTVDetails,
        context: NSManagedObjectContext
    ) -> Title {
        // Check if title already exists
        let fetchRequest: NSFetchRequest<Title> = Title.fetchRequest()
        fetchRequest.predicate = NSPredicate(
            format: "tmdbId == %lld AND mediaType == %@",
            Int64(tvDetails.id),
            "tv"
        )

        let existingTitle = try? context.fetch(fetchRequest).first
        let title = existingTitle ?? Title(context: context)

        if title.id == nil {
            title.id = UUID()
        }
        title.tmdbId = Int64(tvDetails.id)
        title.mediaType = "tv"

        if existingTitle == nil {
            title.dateAdded = Date()
        }

        return mapTVDetails(tvDetails, to: title)
    }

    // MARK: - Episode Mapping

    /// Create or update episodes from season details
    @discardableResult
    static func mapSeasonEpisodes(
        _ seasonDetails: TMDbSeasonDetails,
        to title: Title,
        context: NSManagedObjectContext
    ) -> [Episode] {
        guard let episodes = seasonDetails.episodes else { return [] }

        return episodes.map { episodeDetails in
            mapEpisodeDetails(episodeDetails, to: title, context: context)
        }
    }

    /// Create or update an Episode from episode details
    @discardableResult
    static func mapEpisodeDetails(
        _ details: TMDbEpisodeDetails,
        to title: Title,
        context: NSManagedObjectContext
    ) -> Episode {
        // Check if episode already exists
        let fetchRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
        fetchRequest.predicate = NSPredicate(
            format: "show == %@ AND seasonNumber == %d AND episodeNumber == %d",
            title,
            details.seasonNumber,
            details.episodeNumber
        )

        let existingEpisode = try? context.fetch(fetchRequest).first
        let episode = existingEpisode ?? Episode(context: context)

        if episode.id == nil {
            episode.id = UUID()
        }
        episode.tmdbId = Int64(details.id)
        episode.seasonNumber = Int16(details.seasonNumber)
        episode.episodeNumber = Int16(details.episodeNumber)
        episode.name = details.name
        episode.overview = details.overview
        episode.stillPath = details.stillPath
        episode.airDate = parseDate(details.airDate)
        episode.runtime = Int16(details.runtime ?? 0)
        episode.show = title

        return episode
    }

    /// Create or update an Episode from basic episode info
    @discardableResult
    static func mapEpisodeBasic(
        _ basic: TMDbEpisodeBasic,
        to title: Title,
        context: NSManagedObjectContext
    ) -> Episode {
        // Check if episode already exists
        let fetchRequest: NSFetchRequest<Episode> = Episode.fetchRequest()
        fetchRequest.predicate = NSPredicate(
            format: "show == %@ AND seasonNumber == %d AND episodeNumber == %d",
            title,
            basic.seasonNumber,
            basic.episodeNumber
        )

        let existingEpisode = try? context.fetch(fetchRequest).first
        let episode = existingEpisode ?? Episode(context: context)

        if episode.id == nil {
            episode.id = UUID()
        }
        episode.tmdbId = Int64(basic.id)
        episode.seasonNumber = Int16(basic.seasonNumber)
        episode.episodeNumber = Int16(basic.episodeNumber)
        episode.name = basic.name
        episode.overview = basic.overview
        episode.stillPath = basic.stillPath
        episode.airDate = parseDate(basic.airDate)
        episode.runtime = Int16(basic.runtime ?? 0)
        episode.show = title

        return episode
    }

    // MARK: - List Mapping

    /// Create a new list
    @discardableResult
    static func createList(
        name: String,
        icon: String? = nil,
        colorHex: String? = nil,
        isDefault: Bool = false,
        context: NSManagedObjectContext
    ) -> MediaList {
        let list = MediaList(context: context)
        list.id = UUID()
        list.name = name
        list.icon = icon ?? Constants.UI.defaultListIcon
        list.colorHex = colorHex ?? Constants.UI.defaultListColor
        list.isDefault = isDefault
        list.dateCreated = Date()
        list.dateModified = Date()

        // Set sort order based on existing lists
        let fetchRequest: NSFetchRequest<MediaList> = MediaList.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(keyPath: \MediaList.sortOrder, ascending: false)]
        fetchRequest.fetchLimit = 1

        if let lastList = try? context.fetch(fetchRequest).first {
            list.sortOrder = lastList.sortOrder + 1
        } else {
            list.sortOrder = 0
        }

        return list
    }

    // MARK: - ListItem Mapping

    /// Add a title to a list
    @discardableResult
    static func addTitle(
        _ title: Title,
        to list: MediaList,
        context: NSManagedObjectContext
    ) -> ListItem? {
        // Check if already in list
        let fetchRequest: NSFetchRequest<ListItem> = ListItem.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "list == %@ AND title == %@", list, title)

        if let existing = try? context.fetch(fetchRequest).first {
            return existing // Already in list
        }

        let item = ListItem(context: context)
        item.id = UUID()
        item.list = list
        item.title = title
        item.dateAdded = Date()

        // Set order index
        if let items = list.items as? Set<ListItem> {
            item.orderIndex = Int16(items.count)
        } else {
            item.orderIndex = 0
        }

        list.dateModified = Date()

        return item
    }

    // MARK: - Note Mapping

    /// Create a note for a title
    @discardableResult
    static func createNote(
        text: String,
        for title: Title,
        ownerOnly: Bool = true,
        context: NSManagedObjectContext
    ) -> Note {
        let note = Note(context: context)
        note.id = UUID()
        note.text = text
        note.ownerOnly = ownerOnly
        note.title = title
        note.dateCreated = Date()
        note.dateModified = Date()

        return note
    }

    /// Create a note for an episode
    @discardableResult
    static func createNote(
        text: String,
        for episode: Episode,
        ownerOnly: Bool = true,
        context: NSManagedObjectContext
    ) -> Note {
        let note = Note(context: context)
        note.id = UUID()
        note.text = text
        note.ownerOnly = ownerOnly
        note.episode = episode
        note.dateCreated = Date()
        note.dateModified = Date()

        return note
    }

    // MARK: - UserPreferences Mapping

    /// Get or create user preferences
    static func getUserPreferences(context: NSManagedObjectContext) -> UserPreferences {
        let fetchRequest: NSFetchRequest<UserPreferences> = UserPreferences.fetchRequest()
        fetchRequest.fetchLimit = 1

        if let existing = try? context.fetch(fetchRequest).first {
            return existing
        }

        let prefs = UserPreferences(context: context)
        prefs.id = UUID()
        prefs.imageQuality = Constants.TMDb.ImageSize.posterMedium
        prefs.showWatchedInLists = true
        prefs.sortBy = "dateAdded"
        prefs.sortAscending = false

        return prefs
    }
}

// MARK: - Batch Operations

extension TMDbMapper {

    /// Map multiple search results
    static func mapSearchResults(
        _ results: [TMDbSearchResult],
        context: NSManagedObjectContext
    ) -> [Title] {
        results.map { mapSearchResult($0, context: context) }
    }

    /// Load all episodes for a TV show
    static func loadAllEpisodes(
        for title: Title,
        using service: TMDbService,
        context: NSManagedObjectContext
    ) async throws {
        guard title.mediaType == "tv" else { return }

        let tvDetails = try await service.getTVDetails(id: Int(title.tmdbId))

        // Update title with full details
        mapTVDetails(tvDetails, to: title)

        // Load each season's episodes
        guard let seasons = tvDetails.seasons else { return }

        for season in seasons {
            // Skip specials (season 0) if desired
            guard season.seasonNumber > 0 else { continue }

            let seasonDetails = try await service.getSeasonDetails(
                tvId: Int(title.tmdbId),
                seasonNumber: season.seasonNumber
            )

            mapSeasonEpisodes(seasonDetails, to: title, context: context)
        }
    }
}
