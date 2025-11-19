//
//  MediaWatchError.swift
//  MediaWatch
//
//  App-specific error types
//

import Foundation

/// App-wide error types
enum MediaWatchError: LocalizedError {

    // MARK: - Database Errors

    case coreDataError(Error)
    case entityNotFound(String)
    case saveFailed(Error)
    case fetchFailed(Error)

    // MARK: - Network Errors

    case networkError(Error)
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case decodingError(Error)

    // MARK: - CloudKit Errors

    case cloudKitError(Error)
    case syncFailed(Error)
    case shareError(Error)
    case notAuthenticated

    // MARK: - Validation Errors

    case validationError(String)
    case duplicateEntry(String)

    // MARK: - Import/Export Errors

    case importError(String)
    case exportError(String)
    case invalidFileFormat
    case fileNotFound

    // MARK: - Image Errors

    case imageLoadFailed
    case imageCacheFailed

    // MARK: - LocalizedError

    var errorDescription: String? {
        switch self {
        case .coreDataError(let error):
            return "Database error: \(error.localizedDescription)"

        case .entityNotFound(let entity):
            return "\(entity) not found"

        case .saveFailed(let error):
            return "Failed to save: \(error.localizedDescription)"

        case .fetchFailed(let error):
            return "Failed to fetch data: \(error.localizedDescription)"

        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"

        case .invalidURL:
            return "Invalid URL"

        case .invalidResponse:
            return "Invalid server response"

        case .httpError(let code):
            return "HTTP error: \(code)"

        case .decodingError(let error):
            return "Failed to parse response: \(error.localizedDescription)"

        case .cloudKitError(let error):
            return "iCloud error: \(error.localizedDescription)"

        case .syncFailed(let error):
            return "Sync failed: \(error.localizedDescription)"

        case .shareError(let error):
            return "Sharing failed: \(error.localizedDescription)"

        case .notAuthenticated:
            return "Please sign in to iCloud"

        case .validationError(let message):
            return message

        case .duplicateEntry(let item):
            return "\(item) already exists"

        case .importError(let message):
            return "Import failed: \(message)"

        case .exportError(let message):
            return "Export failed: \(message)"

        case .invalidFileFormat:
            return "Invalid file format"

        case .fileNotFound:
            return "File not found"

        case .imageLoadFailed:
            return "Failed to load image"

        case .imageCacheFailed:
            return "Failed to cache image"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .networkError, .httpError:
            return "Please check your internet connection and try again."

        case .notAuthenticated:
            return "Go to Settings > Apple ID > iCloud to sign in."

        case .syncFailed:
            return "Your changes are saved locally. They will sync when connection is restored."

        case .cloudKitError:
            return "Make sure iCloud is enabled in Settings."

        default:
            return nil
        }
    }
}
