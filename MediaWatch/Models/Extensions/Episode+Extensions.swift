//
//  Episode+Extensions.swift
//  MediaWatch
//
//  Extensions for the Episode Core Data entity
//

import Foundation
import CoreData
import UIKit

extension Episode {

    // MARK: - Display Properties

    /// Returns formatted episode code (e.g., "S01E05")
    var episodeCode: String {
        String(format: "S%02dE%02d", seasonNumber, episodeNumber)
    }

    /// Returns full episode name with code
    var fullName: String {
        "\(episodeCode) - \(name ?? "Unknown")"
    }

    /// Returns display name (episode name or "Episode X")
    var displayName: String {
        if let name = name, !name.isEmpty {
            return name
        }
        return "Episode \(episodeNumber)"
    }

    /// Returns formatted air date
    var displayAirDate: String? {
        guard let date = airDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    /// Returns formatted runtime
    var displayRuntime: String? {
        guard runtime > 0 else { return nil }
        return "\(runtime)m"
    }

    // MARK: - Image URLs

    /// Returns the TMDb still image URL
    func stillURL(size: String = "w300") -> URL? {
        guard let path = stillPath, !path.isEmpty else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/\(size)\(path)")
    }

    // MARK: - Actions

    /// Toggles watched status
    func toggleWatched() {
        watched.toggle()
        watchedDate = watched ? Date() : nil
    }

    // MARK: - Notes

    /// Returns all notes for this episode sorted by creation date
    var sortedNotes: [Note] {
        guard let noteSet = notes as? Set<Note> else { return [] }
        return noteSet.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }
}

// MARK: - Fetch Requests

extension Episode {

    /// Fetch request for episodes of a specific show
    static func fetchForShow(_ show: Title) -> NSFetchRequest<Episode> {
        let request = NSFetchRequest<Episode>(entityName: "Episode")
        request.predicate = NSPredicate(format: "show == %@", show)
        request.sortDescriptors = [
            NSSortDescriptor(keyPath: \Episode.seasonNumber, ascending: true),
            NSSortDescriptor(keyPath: \Episode.episodeNumber, ascending: true)
        ]
        return request
    }

    /// Fetch request for episodes of a specific season
    static func fetchForSeason(_ show: Title, season: Int16) -> NSFetchRequest<Episode> {
        let request = NSFetchRequest<Episode>(entityName: "Episode")
        request.predicate = NSPredicate(format: "show == %@ AND seasonNumber == %d", show, season)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Episode.episodeNumber, ascending: true)]
        return request
    }
}
