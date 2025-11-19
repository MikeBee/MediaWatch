//
//  MediaList+Extensions.swift
//  MediaWatch
//
//  Extensions for the MediaList Core Data entity
//

import Foundation
import CoreData
import SwiftUI

extension MediaList {

    // MARK: - Display Properties

    /// Returns the list name or a default
    var displayName: String {
        name ?? "Untitled List"
    }

    /// Returns the icon name or a default
    var displayIcon: String {
        icon ?? "list.bullet"
    }

    /// Returns the color as a SwiftUI Color
    var displayColor: Color {
        guard let hex = colorHex else { return .accentColor }
        return Color(hex: hex) ?? .accentColor
    }

    // MARK: - Counts

    /// Returns the number of titles in the list
    var titleCount: Int {
        (items as? Set<ListItem>)?.count ?? 0
    }

    /// Returns the number of watched titles
    var watchedCount: Int {
        guard let itemSet = items as? Set<ListItem> else { return 0 }
        return itemSet.filter { $0.title?.watched == true }.count
    }

    /// Returns the number of movies in the list
    var movieCount: Int {
        guard let itemSet = items as? Set<ListItem> else { return 0 }
        return itemSet.filter { $0.title?.isMovie == true }.count
    }

    /// Returns the number of TV shows in the list
    var tvShowCount: Int {
        guard let itemSet = items as? Set<ListItem> else { return 0 }
        return itemSet.filter { $0.title?.isTVShow == true }.count
    }

    // MARK: - Progress

    /// Returns overall watch progress as a value between 0.0 and 1.0
    var watchProgress: Double {
        let total = titleCount
        guard total > 0 else { return 0.0 }
        return Double(watchedCount) / Double(total)
    }

    /// Returns progress as a percentage string
    var watchProgressText: String {
        let percentage = Int(watchProgress * 100)
        return "\(percentage)%"
    }

    // MARK: - Titles

    /// Returns all titles in the list sorted by order index
    var sortedTitles: [Title] {
        guard let itemSet = items as? Set<ListItem> else { return [] }
        return itemSet
            .sorted { $0.orderIndex < $1.orderIndex }
            .compactMap { $0.title }
    }

    /// Returns titles filtered by media type
    func titles(ofType mediaType: String) -> [Title] {
        sortedTitles.filter { $0.mediaType == mediaType }
    }

    // MARK: - List Items

    /// Returns sorted list items
    var sortedItems: [ListItem] {
        guard let itemSet = items as? Set<ListItem> else { return [] }
        return itemSet.sorted { $0.orderIndex < $1.orderIndex }
    }

    /// Gets the list item for a specific title
    func listItem(for title: Title) -> ListItem? {
        guard let itemSet = items as? Set<ListItem> else { return nil }
        return itemSet.first { $0.title?.objectID == title.objectID }
    }

    // MARK: - Actions

    /// Adds a title to the list
    @discardableResult
    func addTitle(_ title: Title, context: NSManagedObjectContext) -> ListItem {
        let item = ListItem(context: context)
        item.id = UUID()
        item.list = self
        item.title = title
        item.orderIndex = Int16(titleCount)
        item.dateAdded = Date()
        dateModified = Date()
        return item
    }

    /// Removes a title from the list
    func removeTitle(_ title: Title, context: NSManagedObjectContext) {
        guard let item = listItem(for: title) else { return }
        context.delete(item)
        dateModified = Date()
    }

    /// Checks if a title is in this list
    func containsTitle(_ title: Title) -> Bool {
        listItem(for: title) != nil
    }

    /// Updates the order of list items
    func updateOrder(_ titles: [Title]) {
        for (index, title) in titles.enumerated() {
            if let item = listItem(for: title) {
                item.orderIndex = Int16(index)
            }
        }
        dateModified = Date()
    }
}

// MARK: - Fetch Requests

extension MediaList {

    /// Fetch request for all lists sorted by order
    static func fetchAll() -> NSFetchRequest<MediaList> {
        let request = NSFetchRequest<MediaList>(entityName: "List")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \MediaList.sortOrder, ascending: true)]
        return request
    }

    /// Fetch request for the default list
    static func fetchDefault() -> NSFetchRequest<MediaList> {
        let request = NSFetchRequest<MediaList>(entityName: "List")
        request.predicate = NSPredicate(format: "isDefault == YES")
        request.fetchLimit = 1
        return request
    }
}

// MARK: - Color Extension

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0

        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else {
            return nil
        }

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }
}
