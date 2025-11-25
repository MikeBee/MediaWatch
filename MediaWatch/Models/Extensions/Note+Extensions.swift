//
//  Note+Extensions.swift
//  MediaWatch
//
//  Extensions for the Note Core Data entity
//

import Foundation
import CoreData
import UIKit

extension Note {

    // MARK: - Display Properties

    /// Returns a preview of the note text (first 100 characters)
    var previewText: String {
        guard let text = text, !text.isEmpty else { return "Empty note" }
        if text.count <= 100 {
            return text
        }
        return String(text.prefix(100)) + "..."
    }

    /// Returns formatted creation date
    var displayDate: String {
        guard let date = createdAt else { return "" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// Returns the parent type (title or episode)
    var parentType: String {
        if title != nil {
            return "Title"
        } else if episode != nil {
            return "Episode"
        }
        return "Unknown"
    }

    /// Returns the parent name
    var parentName: String {
        if let title = title {
            return title.displayTitle
        } else if let episode = episode {
            return episode.fullName
        }
        return "Unknown"
    }

    // MARK: - Validation

    /// Checks if the note has valid parent (either title or episode, not both)
    var hasValidParent: Bool {
        (title != nil) != (episode != nil) // XOR
    }

    // MARK: - Actions

    /// Updates the note text
    func updateText(_ newText: String) {
        text = newText
        updatedAt = Date()
        deviceID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    }

    /// Toggles the owner-only flag
    func toggleOwnerOnly() {
        ownerOnly.toggle()
        updatedAt = Date()
        deviceID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    }
}

// MARK: - Fetch Requests

extension Note {

    /// Fetch request for all notes
    static func fetchAll() -> NSFetchRequest<Note> {
        let request = NSFetchRequest<Note>(entityName: "Note")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Note.createdAt, ascending: false)]
        return request
    }

    /// Fetch request for notes of a specific title
    static func fetchForTitle(_ title: Title) -> NSFetchRequest<Note> {
        let request = NSFetchRequest<Note>(entityName: "Note")
        request.predicate = NSPredicate(format: "title == %@", title)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Note.createdAt, ascending: false)]
        return request
    }

    /// Fetch request for notes of a specific episode
    static func fetchForEpisode(_ episode: Episode) -> NSFetchRequest<Note> {
        let request = NSFetchRequest<Note>(entityName: "Note")
        request.predicate = NSPredicate(format: "episode == %@", episode)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Note.createdAt, ascending: false)]
        return request
    }
}
