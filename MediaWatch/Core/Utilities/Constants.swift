//
//  Constants.swift
//  MediaWatch
//
//  App-wide constants and configuration
//

import Foundation

enum Constants {

    // MARK: - App Info

    enum App {
        static let name = "MediaShows"
        static let bundleIdentifier = "com.mediashows.app"
    }

    // MARK: - CloudKit

    enum CloudKit {
        static let containerIdentifier = "iCloud.com.MediaShows.app" //was mediawatch
    }

    // MARK: - TMDb API

    enum TMDb {
        static let baseURL = "https://api.themoviedb.org/3"
        static let imageBaseURL = "https://image.tmdb.org/t/p/"

        // Image sizes
        enum ImageSize {
            static let posterSmall = "w185"
            static let posterMedium = "w342"
            static let posterLarge = "w500"
            static let posterOriginal = "original"

            static let backdropSmall = "w300"
            static let backdropMedium = "w780"
            static let backdropLarge = "w1280"
            static let backdropOriginal = "original"

            static let stillSmall = "w185"
            static let stillMedium = "w300"
            static let stillOriginal = "original"
        }
    }

    // MARK: - Storage

    enum Storage {
        static let imageCacheDirectory = "ImageCache"
        static let backupDirectory = "Backups"
        static let maxCacheSizeMB = 500
    }

    // MARK: - UI

    enum UI {
        static let defaultListIcon = "list.bullet"
        static let defaultListColor = "007AFF" // System blue

        static let animationDuration: Double = 0.3
        static let debounceInterval: TimeInterval = 0.3
    }

    // MARK: - Limits

    enum Limits {
        static let searchResultsPerPage = 20
        static let noteMaxLength = 10000
        static let listNameMaxLength = 100
    }
}
