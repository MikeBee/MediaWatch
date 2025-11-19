//
//  BackupService.swift
//  MediaWatch
//
//  Handles backup and restore of app data
//

import Foundation
import CoreData
import UniformTypeIdentifiers

// MARK: - App Settings

class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var theme: AppTheme {
        didSet {
            UserDefaults.standard.set(theme.rawValue, forKey: "appTheme")
        }
    }

    init() {
        let savedTheme = UserDefaults.standard.string(forKey: "appTheme") ?? AppTheme.system.rawValue
        self.theme = AppTheme(rawValue: savedTheme) ?? .system
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system = "system"
    case light = "light"
    case dark = "dark"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max.fill"
        case .dark: return "moon.fill"
        }
    }
}

// MARK: - Backup Service

actor BackupService {
    static let shared = BackupService()

    // MARK: - Backup Data Structure

    struct BackupData: Codable {
        let version: String
        let exportDate: Date
        let lists: [ListBackup]
        let titles: [TitleBackup]
        let episodes: [EpisodeBackup]
        let notes: [NoteBackup]
        let preferences: PreferencesBackup?
    }

    struct ListBackup: Codable {
        let id: String
        let name: String
        let icon: String?
        let colorHex: String?
        let isDefault: Bool
        let isShared: Bool
        let sortOrder: Int
        let dateCreated: Date
        let dateModified: Date
        let titleIds: [String]
    }

    struct TitleBackup: Codable {
        let id: String
        let tmdbId: Int
        let mediaType: String
        let title: String
        let originalTitle: String?
        let overview: String?
        let posterPath: String?
        let backdropPath: String?
        let year: Int
        let runtime: Int
        let status: String?
        let voteAverage: Double
        let voteCount: Int
        let popularity: Double
        let originalLanguage: String?
        let genres: [String]?
        let imdbId: String?
        let numberOfSeasons: Int
        let numberOfEpisodes: Int
        let releaseDate: Date?
        let firstAirDate: Date?
        let lastAirDate: Date?
        let dateAdded: Date
        let dateModified: Date
        let watched: Bool
        let watchedDate: Date?
        let watchStatus: Int
        let likedStatus: Int
        let currentSeason: Int
        let currentEpisode: Int
        let streamingService: String?
    }

    struct EpisodeBackup: Codable {
        let id: String
        let tmdbId: Int
        let showTmdbId: Int
        let seasonNumber: Int
        let episodeNumber: Int
        let name: String?
        let overview: String?
        let stillPath: String?
        let airDate: Date?
        let runtime: Int
        let watched: Bool
        let watchedDate: Date?
    }

    struct NoteBackup: Codable {
        let id: String
        let text: String
        let ownerOnly: Bool
        let titleTmdbId: Int?
        let episodeTmdbId: Int?
        let dateCreated: Date
        let dateModified: Date
    }

    struct PreferencesBackup: Codable {
        let imageQuality: String
        let showWatchedInLists: Bool
        let sortBy: String
        let sortAscending: Bool
        let defaultLikedStatus: Int
    }

    // MARK: - Export

    func createBackup(context: NSManagedObjectContext) async throws -> Data {
        // Fetch all data
        let lists = try await fetchLists(context: context)
        let titles = try await fetchTitles(context: context)
        let episodes = try await fetchEpisodes(context: context)
        let notes = try await fetchNotes(context: context)
        let preferences = try await fetchPreferences(context: context)

        let backup = BackupData(
            version: "1.0",
            exportDate: Date(),
            lists: lists,
            titles: titles,
            episodes: episodes,
            notes: notes,
            preferences: preferences
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        return try encoder.encode(backup)
    }

    private func fetchLists(context: NSManagedObjectContext) async throws -> [ListBackup] {
        try await context.perform {
            let request: NSFetchRequest<MediaList> = MediaList.fetchRequest()
            let lists = try context.fetch(request)

            return lists.map { list in
                let titleIds = (list.items as? Set<ListItem>)?
                    .compactMap { $0.title?.id?.uuidString } ?? []

                return ListBackup(
                    id: list.id?.uuidString ?? UUID().uuidString,
                    name: list.name ?? "",
                    icon: list.icon,
                    colorHex: list.colorHex,
                    isDefault: list.isDefault,
                    isShared: list.isShared,
                    sortOrder: Int(list.sortOrder),
                    dateCreated: list.dateCreated ?? Date(),
                    dateModified: list.dateModified ?? Date(),
                    titleIds: titleIds
                )
            }
        }
    }

    private func fetchTitles(context: NSManagedObjectContext) async throws -> [TitleBackup] {
        try await context.perform {
            let request: NSFetchRequest<Title> = Title.fetchRequest()
            let titles = try context.fetch(request)

            return titles.map { title in
                TitleBackup(
                    id: title.id?.uuidString ?? UUID().uuidString,
                    tmdbId: Int(title.tmdbId),
                    mediaType: title.mediaType ?? "movie",
                    title: title.title ?? "",
                    originalTitle: title.originalTitle,
                    overview: title.overview,
                    posterPath: title.posterPath,
                    backdropPath: title.backdropPath,
                    year: Int(title.year),
                    runtime: Int(title.runtime),
                    status: title.status,
                    voteAverage: title.voteAverage,
                    voteCount: Int(title.voteCount),
                    popularity: title.popularity,
                    originalLanguage: title.originalLanguage,
                    genres: title.genres,
                    imdbId: title.imdbId,
                    numberOfSeasons: Int(title.numberOfSeasons),
                    numberOfEpisodes: Int(title.numberOfEpisodes),
                    releaseDate: title.releaseDate,
                    firstAirDate: title.firstAirDate,
                    lastAirDate: title.lastAirDate,
                    dateAdded: title.dateAdded ?? Date(),
                    dateModified: title.dateModified ?? Date(),
                    watched: title.watched,
                    watchedDate: title.watchedDate,
                    watchStatus: Int(title.watchStatus),
                    likedStatus: Int(title.likedStatus),
                    currentSeason: Int(title.currentSeason),
                    currentEpisode: Int(title.currentEpisode),
                    streamingService: title.streamingService
                )
            }
        }
    }

    private func fetchEpisodes(context: NSManagedObjectContext) async throws -> [EpisodeBackup] {
        try await context.perform {
            let request: NSFetchRequest<Episode> = Episode.fetchRequest()
            let episodes = try context.fetch(request)

            return episodes.map { episode in
                EpisodeBackup(
                    id: episode.id?.uuidString ?? UUID().uuidString,
                    tmdbId: Int(episode.tmdbId),
                    showTmdbId: Int(episode.show?.tmdbId ?? 0),
                    seasonNumber: Int(episode.seasonNumber),
                    episodeNumber: Int(episode.episodeNumber),
                    name: episode.name,
                    overview: episode.overview,
                    stillPath: episode.stillPath,
                    airDate: episode.airDate,
                    runtime: Int(episode.runtime),
                    watched: episode.watched,
                    watchedDate: episode.watchedDate
                )
            }
        }
    }

    private func fetchNotes(context: NSManagedObjectContext) async throws -> [NoteBackup] {
        try await context.perform {
            let request: NSFetchRequest<Note> = Note.fetchRequest()
            let notes = try context.fetch(request)

            return notes.map { note in
                NoteBackup(
                    id: note.id?.uuidString ?? UUID().uuidString,
                    text: note.text ?? "",
                    ownerOnly: note.ownerOnly,
                    titleTmdbId: note.title != nil ? Int(note.title!.tmdbId) : nil,
                    episodeTmdbId: note.episode != nil ? Int(note.episode!.tmdbId) : nil,
                    dateCreated: note.dateCreated ?? Date(),
                    dateModified: note.dateModified ?? Date()
                )
            }
        }
    }

    private func fetchPreferences(context: NSManagedObjectContext) async throws -> PreferencesBackup? {
        try await context.perform {
            let request: NSFetchRequest<UserPreferences> = UserPreferences.fetchRequest()
            request.fetchLimit = 1

            guard let prefs = try context.fetch(request).first else { return nil }

            return PreferencesBackup(
                imageQuality: prefs.imageQuality ?? "w500",
                showWatchedInLists: prefs.showWatchedInLists,
                sortBy: prefs.sortBy ?? "dateAdded",
                sortAscending: prefs.sortAscending,
                defaultLikedStatus: Int(prefs.defaultLikedStatus)
            )
        }
    }

    // MARK: - Restore

    func restoreBackup(from data: Data, context: NSManagedObjectContext) async throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let backup = try decoder.decode(BackupData.self, from: data)

        try await context.perform {
            // Clear existing data first
            try self.clearAllData(context: context)

            // Restore titles first (they're referenced by lists and episodes)
            var titleMap: [Int: Title] = [:]
            for titleBackup in backup.titles {
                let title = Title(context: context)
                title.id = UUID(uuidString: titleBackup.id) ?? UUID()
                title.tmdbId = Int64(titleBackup.tmdbId)
                title.mediaType = titleBackup.mediaType
                title.title = titleBackup.title
                title.originalTitle = titleBackup.originalTitle
                title.overview = titleBackup.overview
                title.posterPath = titleBackup.posterPath
                title.backdropPath = titleBackup.backdropPath
                title.year = Int16(titleBackup.year)
                title.runtime = Int16(titleBackup.runtime)
                title.status = titleBackup.status
                title.voteAverage = titleBackup.voteAverage
                title.voteCount = Int32(titleBackup.voteCount)
                title.popularity = titleBackup.popularity
                title.originalLanguage = titleBackup.originalLanguage
                title.genres = titleBackup.genres
                title.imdbId = titleBackup.imdbId
                title.numberOfSeasons = Int16(titleBackup.numberOfSeasons)
                title.numberOfEpisodes = Int16(titleBackup.numberOfEpisodes)
                title.releaseDate = titleBackup.releaseDate
                title.firstAirDate = titleBackup.firstAirDate
                title.lastAirDate = titleBackup.lastAirDate
                title.dateAdded = titleBackup.dateAdded
                title.dateModified = titleBackup.dateModified
                title.watched = titleBackup.watched
                title.watchedDate = titleBackup.watchedDate
                title.watchStatus = Int16(titleBackup.watchStatus)
                title.likedStatus = Int16(titleBackup.likedStatus)
                title.currentSeason = Int16(titleBackup.currentSeason)
                title.currentEpisode = Int16(titleBackup.currentEpisode)
                title.streamingService = titleBackup.streamingService

                titleMap[titleBackup.tmdbId] = title
            }

            // Restore episodes
            for episodeBackup in backup.episodes {
                let episode = Episode(context: context)
                episode.id = UUID(uuidString: episodeBackup.id) ?? UUID()
                episode.tmdbId = Int64(episodeBackup.tmdbId)
                episode.seasonNumber = Int16(episodeBackup.seasonNumber)
                episode.episodeNumber = Int16(episodeBackup.episodeNumber)
                episode.name = episodeBackup.name
                episode.overview = episodeBackup.overview
                episode.stillPath = episodeBackup.stillPath
                episode.airDate = episodeBackup.airDate
                episode.runtime = Int16(episodeBackup.runtime)
                episode.watched = episodeBackup.watched
                episode.watchedDate = episodeBackup.watchedDate
                episode.show = titleMap[episodeBackup.showTmdbId]
            }

            // Restore lists and list items
            for listBackup in backup.lists {
                let list = MediaList(context: context)
                list.id = UUID(uuidString: listBackup.id) ?? UUID()
                list.name = listBackup.name
                list.icon = listBackup.icon
                list.colorHex = listBackup.colorHex
                list.isDefault = listBackup.isDefault
                list.isShared = listBackup.isShared
                list.sortOrder = Int16(listBackup.sortOrder)
                list.dateCreated = listBackup.dateCreated
                list.dateModified = listBackup.dateModified

                // Create list items for each title
                for (index, titleId) in listBackup.titleIds.enumerated() {
                    if let title = backup.titles.first(where: { $0.id == titleId }),
                       let coreDataTitle = titleMap[title.tmdbId] {
                        let listItem = ListItem(context: context)
                        listItem.id = UUID()
                        listItem.list = list
                        listItem.title = coreDataTitle
                        listItem.orderIndex = Int16(index)
                        listItem.dateAdded = Date()
                    }
                }
            }

            // Restore notes
            for noteBackup in backup.notes {
                let note = Note(context: context)
                note.id = UUID(uuidString: noteBackup.id) ?? UUID()
                note.text = noteBackup.text
                note.ownerOnly = noteBackup.ownerOnly
                note.dateCreated = noteBackup.dateCreated
                note.dateModified = noteBackup.dateModified

                if let titleTmdbId = noteBackup.titleTmdbId {
                    note.title = titleMap[titleTmdbId]
                }
            }

            // Restore preferences
            if let prefsBackup = backup.preferences {
                let prefs = UserPreferences(context: context)
                prefs.id = UUID()
                prefs.imageQuality = prefsBackup.imageQuality
                prefs.showWatchedInLists = prefsBackup.showWatchedInLists
                prefs.sortBy = prefsBackup.sortBy
                prefs.sortAscending = prefsBackup.sortAscending
                prefs.defaultLikedStatus = Int16(prefsBackup.defaultLikedStatus)
            }

            try context.save()
        }
    }

    private func clearAllData(context: NSManagedObjectContext) throws {
        let entityNames = ["Note", "Episode", "ListItem", "Title", "MediaList", "UserPreferences"]

        for entityName in entityNames {
            let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)
            try context.execute(deleteRequest)
        }
    }
}

// MARK: - Backup Document

struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
