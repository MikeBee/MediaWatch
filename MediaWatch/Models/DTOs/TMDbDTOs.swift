//
//  TMDbDTOs.swift
//  MediaWatch
//
//  Data Transfer Objects for TMDb API responses
//

import Foundation

// MARK: - Search Results

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
    let adult: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case mediaType = "media_type"
        case title, name
        case originalTitle = "original_title"
        case originalName = "original_name"
        case overview
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case popularity
        case genreIds = "genre_ids"
        case originalLanguage = "original_language"
        case adult
    }

    /// Returns the display title (handles both movies and TV shows)
    var displayTitle: String {
        title ?? name ?? "Unknown"
    }

    /// Returns the display date string
    var displayDate: String? {
        releaseDate ?? firstAirDate
    }

    /// Determines if this is a movie or TV show
    var resolvedMediaType: String {
        if let mediaType = mediaType {
            return mediaType
        }
        // If from movie search endpoint, it's a movie
        // If from TV search endpoint, it's a TV show
        return title != nil ? "movie" : "tv"
    }
}

// MARK: - Movie Details

struct TMDbMovieDetails: Codable {
    let id: Int
    let imdbId: String?
    let title: String
    let originalTitle: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let runtime: Int?
    let status: String?
    let tagline: String?
    let voteAverage: Double?
    let voteCount: Int?
    let popularity: Double?
    let genres: [TMDbGenre]?
    let productionCompanies: [TMDbProductionCompany]?
    let productionCountries: [TMDbProductionCountry]?
    let spokenLanguages: [TMDbSpokenLanguage]?
    let originalLanguage: String?
    let budget: Int?
    let revenue: Int?
    let adult: Bool?
    let video: Bool?
    let homepage: String?

    enum CodingKeys: String, CodingKey {
        case id
        case imdbId = "imdb_id"
        case title
        case originalTitle = "original_title"
        case overview
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case releaseDate = "release_date"
        case runtime, status, tagline
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case popularity, genres
        case productionCompanies = "production_companies"
        case productionCountries = "production_countries"
        case spokenLanguages = "spoken_languages"
        case originalLanguage = "original_language"
        case budget, revenue, adult, video, homepage
    }
}

// MARK: - TV Show Details

struct TMDbTVDetails: Codable {
    let id: Int
    let name: String
    let originalName: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let firstAirDate: String?
    let lastAirDate: String?
    let status: String?
    let tagline: String?
    let type: String?
    let voteAverage: Double?
    let voteCount: Int?
    let popularity: Double?
    let genres: [TMDbGenre]?
    let createdBy: [TMDbCreator]?
    let episodeRunTime: [Int]?
    let homepage: String?
    let inProduction: Bool?
    let languages: [String]?
    let lastEpisodeToAir: TMDbEpisodeBasic?
    let nextEpisodeToAir: TMDbEpisodeBasic?
    let networks: [TMDbNetwork]?
    let numberOfEpisodes: Int?
    let numberOfSeasons: Int?
    let originCountry: [String]?
    let originalLanguage: String?
    let productionCompanies: [TMDbProductionCompany]?
    let productionCountries: [TMDbProductionCountry]?
    let seasons: [TMDbSeasonBasic]?
    let spokenLanguages: [TMDbSpokenLanguage]?

    enum CodingKeys: String, CodingKey {
        case id, name
        case originalName = "original_name"
        case overview
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case firstAirDate = "first_air_date"
        case lastAirDate = "last_air_date"
        case status, tagline, type
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case popularity, genres
        case createdBy = "created_by"
        case episodeRunTime = "episode_run_time"
        case homepage
        case inProduction = "in_production"
        case languages
        case lastEpisodeToAir = "last_episode_to_air"
        case nextEpisodeToAir = "next_episode_to_air"
        case networks
        case numberOfEpisodes = "number_of_episodes"
        case numberOfSeasons = "number_of_seasons"
        case originCountry = "origin_country"
        case originalLanguage = "original_language"
        case productionCompanies = "production_companies"
        case productionCountries = "production_countries"
        case seasons
        case spokenLanguages = "spoken_languages"
    }

    /// Average episode runtime
    var averageRuntime: Int? {
        guard let runtimes = episodeRunTime, !runtimes.isEmpty else { return nil }
        return runtimes.reduce(0, +) / runtimes.count
    }
}

// MARK: - Season Details

struct TMDbSeasonDetails: Codable {
    let id: Int
    let airDate: String?
    let episodes: [TMDbEpisodeDetails]?
    let name: String
    let overview: String?
    let posterPath: String?
    let seasonNumber: Int
    let voteAverage: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case airDate = "air_date"
        case episodes, name, overview
        case posterPath = "poster_path"
        case seasonNumber = "season_number"
        case voteAverage = "vote_average"
    }
}

struct TMDbSeasonBasic: Codable {
    let id: Int
    let airDate: String?
    let episodeCount: Int?
    let name: String
    let overview: String?
    let posterPath: String?
    let seasonNumber: Int
    let voteAverage: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case airDate = "air_date"
        case episodeCount = "episode_count"
        case name, overview
        case posterPath = "poster_path"
        case seasonNumber = "season_number"
        case voteAverage = "vote_average"
    }
}

// MARK: - Episode Details

struct TMDbEpisodeDetails: Codable {
    let id: Int
    let airDate: String?
    let episodeNumber: Int
    let name: String
    let overview: String?
    let productionCode: String?
    let runtime: Int?
    let seasonNumber: Int
    let showId: Int?
    let stillPath: String?
    let voteAverage: Double?
    let voteCount: Int?
    let crew: [TMDbCrewMember]?
    let guestStars: [TMDbCastMember]?

    enum CodingKeys: String, CodingKey {
        case id
        case airDate = "air_date"
        case episodeNumber = "episode_number"
        case name, overview
        case productionCode = "production_code"
        case runtime
        case seasonNumber = "season_number"
        case showId = "show_id"
        case stillPath = "still_path"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case crew
        case guestStars = "guest_stars"
    }
}

struct TMDbEpisodeBasic: Codable {
    let id: Int
    let airDate: String?
    let episodeNumber: Int
    let name: String
    let overview: String?
    let runtime: Int?
    let seasonNumber: Int
    let showId: Int?
    let stillPath: String?
    let voteAverage: Double?
    let voteCount: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case airDate = "air_date"
        case episodeNumber = "episode_number"
        case name, overview, runtime
        case seasonNumber = "season_number"
        case showId = "show_id"
        case stillPath = "still_path"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
    }
}

// MARK: - Supporting Types

struct TMDbGenre: Codable, Identifiable {
    let id: Int
    let name: String
}

struct TMDbProductionCompany: Codable, Identifiable {
    let id: Int
    let name: String
    let logoPath: String?
    let originCountry: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case logoPath = "logo_path"
        case originCountry = "origin_country"
    }
}

struct TMDbProductionCountry: Codable {
    let iso3166_1: String
    let name: String

    enum CodingKeys: String, CodingKey {
        case iso3166_1 = "iso_3166_1"
        case name
    }
}

struct TMDbSpokenLanguage: Codable {
    let englishName: String?
    let iso639_1: String
    let name: String

    enum CodingKeys: String, CodingKey {
        case englishName = "english_name"
        case iso639_1 = "iso_639_1"
        case name
    }
}

struct TMDbCreator: Codable, Identifiable {
    let id: Int
    let creditId: String?
    let name: String
    let gender: Int?
    let profilePath: String?

    enum CodingKeys: String, CodingKey {
        case id
        case creditId = "credit_id"
        case name, gender
        case profilePath = "profile_path"
    }
}

struct TMDbNetwork: Codable, Identifiable {
    let id: Int
    let name: String
    let logoPath: String?
    let originCountry: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case logoPath = "logo_path"
        case originCountry = "origin_country"
    }
}

struct TMDbCastMember: Codable, Identifiable {
    let id: Int
    let name: String
    let character: String?
    let creditId: String?
    let order: Int?
    let profilePath: String?
    let gender: Int?
    let knownForDepartment: String?
    let adult: Bool?
    let popularity: Double?
    let originalName: String?

    enum CodingKeys: String, CodingKey {
        case id, name, character
        case creditId = "credit_id"
        case order
        case profilePath = "profile_path"
        case gender
        case knownForDepartment = "known_for_department"
        case adult, popularity
        case originalName = "original_name"
    }
}

struct TMDbCrewMember: Codable, Identifiable {
    let id: Int
    let name: String
    let department: String?
    let job: String?
    let creditId: String?
    let profilePath: String?
    let gender: Int?
    let knownForDepartment: String?
    let adult: Bool?
    let popularity: Double?
    let originalName: String?

    enum CodingKeys: String, CodingKey {
        case id, name, department, job
        case creditId = "credit_id"
        case profilePath = "profile_path"
        case gender
        case knownForDepartment = "known_for_department"
        case adult, popularity
        case originalName = "original_name"
    }
}

// MARK: - Genre List Response

struct TMDbGenreListResponse: Codable {
    let genres: [TMDbGenre]
}

// MARK: - Configuration

struct TMDbConfiguration: Codable {
    let images: TMDbImageConfiguration
    let changeKeys: [String]

    enum CodingKeys: String, CodingKey {
        case images
        case changeKeys = "change_keys"
    }
}

struct TMDbImageConfiguration: Codable {
    let baseUrl: String
    let secureBaseUrl: String
    let backdropSizes: [String]
    let logoSizes: [String]
    let posterSizes: [String]
    let profileSizes: [String]
    let stillSizes: [String]

    enum CodingKeys: String, CodingKey {
        case baseUrl = "base_url"
        case secureBaseUrl = "secure_base_url"
        case backdropSizes = "backdrop_sizes"
        case logoSizes = "logo_sizes"
        case posterSizes = "poster_sizes"
        case profileSizes = "profile_sizes"
        case stillSizes = "still_sizes"
    }
}

// MARK: - Watch Providers

struct TMDbWatchProvidersResponse: Codable {
    let id: Int
    let results: [String: TMDbWatchProviderRegion]
}

struct TMDbWatchProviderRegion: Codable {
    let link: String?
    let flatrate: [TMDbWatchProvider]?
    let rent: [TMDbWatchProvider]?
    let buy: [TMDbWatchProvider]?
    let ads: [TMDbWatchProvider]?
    let free: [TMDbWatchProvider]?
}

struct TMDbWatchProvider: Codable, Identifiable {
    let providerId: Int
    let providerName: String
    let logoPath: String?
    let displayPriority: Int

    var id: Int { providerId }

    enum CodingKeys: String, CodingKey {
        case providerId = "provider_id"
        case providerName = "provider_name"
        case logoPath = "logo_path"
        case displayPriority = "display_priority"
    }
}

// MARK: - Streaming Service

enum StreamingService: String, CaseIterable, Identifiable {
    case none = ""
    case netflix = "Netflix"
    case amazonPrime = "Amazon Prime Video"
    case disneyPlus = "Disney+"
    case hulu = "Hulu"
    case appleTV = "Apple TV+"
    case hboMax = "Max"
    case paramount = "Paramount+"
    case peacock = "Peacock"
    case other = "Other"

    var id: String { rawValue }

    var displayName: String {
        if self == .none { return "Not Set" }
        return rawValue
    }

    var icon: String {
        switch self {
        case .none: return "tv"
        case .netflix: return "play.tv"
        case .amazonPrime: return "play.tv"
        case .disneyPlus: return "sparkles.tv"
        case .hulu: return "play.tv"
        case .appleTV: return "appletv"
        case .hboMax: return "play.tv"
        case .paramount: return "play.tv"
        case .peacock: return "play.tv"
        case .other: return "tv"
        }
    }

    var color: String {
        switch self {
        case .none: return "666666"
        case .netflix: return "E50914"
        case .amazonPrime: return "00A8E1"
        case .disneyPlus: return "113CCF"
        case .hulu: return "1CE783"
        case .appleTV: return "000000"
        case .hboMax: return "5822B4"
        case .paramount: return "0064FF"
        case .peacock: return "000000"
        case .other: return "666666"
        }
    }

    // Map TMDb provider names to our enum
    static func from(tmdbName: String) -> StreamingService {
        let lowercased = tmdbName.lowercased()
        if lowercased.contains("netflix") { return .netflix }
        if lowercased.contains("amazon") || lowercased.contains("prime video") { return .amazonPrime }
        if lowercased.contains("disney") { return .disneyPlus }
        if lowercased.contains("hulu") { return .hulu }
        if lowercased.contains("apple") { return .appleTV }
        if lowercased.contains("hbo") || lowercased.contains("max") { return .hboMax }
        if lowercased.contains("paramount") { return .paramount }
        if lowercased.contains("peacock") { return .peacock }
        return .other
    }
}

// MARK: - Credits/Cast

struct TMDbCreditsResponse: Codable {
    let id: Int
    let cast: [TMDbCastMember]
    let crew: [TMDbCrewMember]?
}

// Simple struct for storing cast in Core Data
struct CastMember: Codable, Identifiable {
    let id: Int
    let name: String
    let character: String
    let profilePath: String?

    init(from tmdbCast: TMDbCastMember) {
        self.id = tmdbCast.id
        self.name = tmdbCast.name
        self.character = tmdbCast.character ?? ""
        self.profilePath = tmdbCast.profilePath
    }
}
