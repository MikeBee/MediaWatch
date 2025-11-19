//
//  TMDbService.swift
//  MediaWatch
//
//  Service for interacting with The Movie Database (TMDb) API
//

import Foundation

// MARK: - TMDb Service

actor TMDbService {

    // MARK: - Singleton

    static let shared = TMDbService()

    // MARK: - Properties

    private let baseURL = Constants.TMDb.baseURL
    private let session: URLSession
    private var apiKey: String?

    // Genre cache
    private var movieGenres: [Int: String] = [:]
    private var tvGenres: [Int: String] = [:]
    private var genresLoaded = false

    // MARK: - Initialization

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)
    }

    // MARK: - Configuration

    /// Set the TMDb API key
    func setAPIKey(_ key: String) {
        self.apiKey = key
    }

    /// Check if API key is configured
    var isConfigured: Bool {
        apiKey != nil && !(apiKey?.isEmpty ?? true)
    }

    // MARK: - Search

    /// Search for movies and TV shows
    func searchMulti(query: String, page: Int = 1) async throws -> TMDbSearchResponse {
        guard let apiKey = apiKey else {
            throw MediaWatchError.invalidURL
        }

        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "\(baseURL)/search/multi?api_key=\(apiKey)&query=\(encodedQuery)&page=\(page)&include_adult=false"

        return try await fetch(urlString)
    }

    /// Search for movies only
    func searchMovies(query: String, page: Int = 1, year: Int? = nil) async throws -> TMDbSearchResponse {
        guard let apiKey = apiKey else {
            throw MediaWatchError.invalidURL
        }

        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        var urlString = "\(baseURL)/search/movie?api_key=\(apiKey)&query=\(encodedQuery)&page=\(page)&include_adult=false"

        if let year = year {
            urlString += "&year=\(year)"
        }

        return try await fetch(urlString)
    }

    /// Search for TV shows only
    func searchTV(query: String, page: Int = 1, year: Int? = nil) async throws -> TMDbSearchResponse {
        guard let apiKey = apiKey else {
            throw MediaWatchError.invalidURL
        }

        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        var urlString = "\(baseURL)/search/tv?api_key=\(apiKey)&query=\(encodedQuery)&page=\(page)&include_adult=false"

        if let year = year {
            urlString += "&first_air_date_year=\(year)"
        }

        return try await fetch(urlString)
    }

    // MARK: - Movie Details

    /// Get detailed information about a movie
    func getMovieDetails(id: Int) async throws -> TMDbMovieDetails {
        guard let apiKey = apiKey else {
            throw MediaWatchError.invalidURL
        }

        let urlString = "\(baseURL)/movie/\(id)?api_key=\(apiKey)"
        return try await fetch(urlString)
    }

    // MARK: - TV Show Details

    /// Get detailed information about a TV show
    func getTVDetails(id: Int) async throws -> TMDbTVDetails {
        guard let apiKey = apiKey else {
            throw MediaWatchError.invalidURL
        }

        let urlString = "\(baseURL)/tv/\(id)?api_key=\(apiKey)"
        return try await fetch(urlString)
    }

    /// Get detailed information about a TV season
    func getSeasonDetails(tvId: Int, seasonNumber: Int) async throws -> TMDbSeasonDetails {
        guard let apiKey = apiKey else {
            throw MediaWatchError.invalidURL
        }

        let urlString = "\(baseURL)/tv/\(tvId)/season/\(seasonNumber)?api_key=\(apiKey)"
        return try await fetch(urlString)
    }

    /// Get detailed information about a specific episode
    func getEpisodeDetails(tvId: Int, seasonNumber: Int, episodeNumber: Int) async throws -> TMDbEpisodeDetails {
        guard let apiKey = apiKey else {
            throw MediaWatchError.invalidURL
        }

        let urlString = "\(baseURL)/tv/\(tvId)/season/\(seasonNumber)/episode/\(episodeNumber)?api_key=\(apiKey)"
        return try await fetch(urlString)
    }

    // MARK: - Genres

    /// Load genre mappings from TMDb
    func loadGenres() async throws {
        guard let apiKey = apiKey else {
            throw MediaWatchError.invalidURL
        }

        // Load movie genres
        let movieGenreURL = "\(baseURL)/genre/movie/list?api_key=\(apiKey)"
        let movieGenreResponse: TMDbGenreListResponse = try await fetch(movieGenreURL)
        for genre in movieGenreResponse.genres {
            movieGenres[genre.id] = genre.name
        }

        // Load TV genres
        let tvGenreURL = "\(baseURL)/genre/tv/list?api_key=\(apiKey)"
        let tvGenreResponse: TMDbGenreListResponse = try await fetch(tvGenreURL)
        for genre in tvGenreResponse.genres {
            tvGenres[genre.id] = genre.name
        }

        genresLoaded = true
    }

    /// Get genre names for genre IDs
    func getGenreNames(ids: [Int], mediaType: String) -> [String] {
        let genreMap = mediaType == "movie" ? movieGenres : tvGenres
        return ids.compactMap { genreMap[$0] }
    }

    /// Check if genres are loaded
    var areGenresLoaded: Bool {
        genresLoaded
    }

    // MARK: - Image URLs

    /// Generate full image URL for a poster
    static func posterURL(path: String?, size: String = Constants.TMDb.ImageSize.posterMedium) -> URL? {
        guard let path = path else { return nil }
        return URL(string: "\(Constants.TMDb.imageBaseURL)\(size)\(path)")
    }

    /// Generate full image URL for a backdrop
    static func backdropURL(path: String?, size: String = Constants.TMDb.ImageSize.backdropMedium) -> URL? {
        guard let path = path else { return nil }
        return URL(string: "\(Constants.TMDb.imageBaseURL)\(size)\(path)")
    }

    /// Generate full image URL for an episode still
    static func stillURL(path: String?, size: String = Constants.TMDb.ImageSize.stillMedium) -> URL? {
        guard let path = path else { return nil }
        return URL(string: "\(Constants.TMDb.imageBaseURL)\(size)\(path)")
    }

    // MARK: - Trending & Popular

    /// Get trending movies and TV shows
    func getTrending(mediaType: String = "all", timeWindow: String = "week", page: Int = 1) async throws -> TMDbSearchResponse {
        guard let apiKey = apiKey else {
            throw MediaWatchError.invalidURL
        }

        let urlString = "\(baseURL)/trending/\(mediaType)/\(timeWindow)?api_key=\(apiKey)&page=\(page)"
        return try await fetch(urlString)
    }

    /// Get popular movies
    func getPopularMovies(page: Int = 1) async throws -> TMDbSearchResponse {
        guard let apiKey = apiKey else {
            throw MediaWatchError.invalidURL
        }

        let urlString = "\(baseURL)/movie/popular?api_key=\(apiKey)&page=\(page)"
        return try await fetch(urlString)
    }

    /// Get popular TV shows
    func getPopularTV(page: Int = 1) async throws -> TMDbSearchResponse {
        guard let apiKey = apiKey else {
            throw MediaWatchError.invalidURL
        }

        let urlString = "\(baseURL)/tv/popular?api_key=\(apiKey)&page=\(page)"
        return try await fetch(urlString)
    }

    // MARK: - Network Request

    private func fetch<T: Decodable>(_ urlString: String) async throws -> T {
        guard let url = URL(string: urlString) else {
            throw MediaWatchError.invalidURL
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw MediaWatchError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            break
        case 401:
            throw MediaWatchError.httpError(401)
        case 404:
            throw MediaWatchError.httpError(404)
        case 429:
            throw MediaWatchError.httpError(429)
        default:
            throw MediaWatchError.httpError(httpResponse.statusCode)
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            throw MediaWatchError.decodingError(error)
        }
    }
}

// MARK: - Convenience Extensions

extension TMDbSearchResult {
    /// Get the full poster URL
    var posterURL: URL? {
        TMDbService.posterURL(path: posterPath)
    }

    /// Get the full backdrop URL
    var backdropURL: URL? {
        TMDbService.backdropURL(path: backdropPath)
    }
}

extension TMDbMovieDetails {
    /// Get the full poster URL
    var posterURL: URL? {
        TMDbService.posterURL(path: posterPath)
    }

    /// Get the full backdrop URL
    var backdropURL: URL? {
        TMDbService.backdropURL(path: backdropPath)
    }

    /// Get genre names as array
    var genreNames: [String] {
        genres?.map { $0.name } ?? []
    }
}

extension TMDbTVDetails {
    /// Get the full poster URL
    var posterURL: URL? {
        TMDbService.posterURL(path: posterPath)
    }

    /// Get the full backdrop URL
    var backdropURL: URL? {
        TMDbService.backdropURL(path: backdropPath)
    }

    /// Get genre names as array
    var genreNames: [String] {
        genres?.map { $0.name } ?? []
    }
}

extension TMDbEpisodeDetails {
    /// Get the full still URL
    var stillURL: URL? {
        TMDbService.stillURL(path: stillPath)
    }
}
