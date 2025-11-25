//
//  MediaList+Extensions.swift
//  MediaWatch
//
//  Extensions for the MediaList Core Data entity
//

import Foundation
import CoreData
import SwiftUI
import UIKit

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
        return Color(hex: hex)
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
            .sorted { $0.order < $1.order }
            .compactMap { $0.title }
    }

    /// Returns titles filtered by media type
    func titles(ofType mediaType: String) -> [Title] {
        sortedTitles.filter { $0.mediaType == mediaType }
    }

    // MARK: - List Items

    /// Returns sorted list items using fractional ordering
    var sortedItems: [ListItem] {
        guard let itemSet = items as? Set<ListItem> else { return [] }
        return itemSet.sorted { $0.order < $1.order }
    }

    /// Gets the list item for a specific title
    func listItem(for title: Title) -> ListItem? {
        guard let itemSet = items as? Set<ListItem> else { return nil }
        return itemSet.first { $0.title?.objectID == title.objectID }
    }

    // MARK: - Actions

    /// Adds a title to the list with LWW metadata
    @discardableResult
    func addTitle(_ title: Title, context: NSManagedObjectContext) -> ListItem {
        let item = ListItem(context: context)
        let now = Date()
        let deviceID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        
        item.id = UUID()
        item.list = self
        item.title = title
        item.createdAt = now
        item.updatedAt = now
        item.deviceID = deviceID
        
        // Use fractional ordering - place at end
        let lastOrder = sortedItems.last?.order ?? 0
        item.order = lastOrder + 1.0
        
        // Update list metadata
        updatedAt = now
        self.deviceID = deviceID
        
        return item
    }

    /// Removes a title from the list using tombstone pattern
    func removeTitle(_ title: Title, context: NSManagedObjectContext) {
        guard let item = listItem(for: title) else { return }
        let now = Date()
        let deviceID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        
        // Mark as deleted (tombstone) instead of actually deleting
        item.deletedAt = now
        item.updatedAt = now
        item.deviceID = deviceID
        
        // Update list metadata
        updatedAt = now
        self.deviceID = deviceID
    }

    /// Checks if a title is in this list
    func containsTitle(_ title: Title) -> Bool {
        listItem(for: title) != nil
    }

    /// Updates the order of list items using fractional ordering
    func updateOrder(_ titles: [Title]) {
        let now = Date()
        let deviceID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        
        for (index, title) in titles.enumerated() {
            if let item = listItem(for: title) {
                item.order = Double(index + 1)
                item.updatedAt = now
                item.deviceID = deviceID
            }
        }
        
        updatedAt = now
        self.deviceID = deviceID
    }
}

// MARK: - Fetch Requests

extension MediaList {

    /// Fetch request for all lists sorted by order
    static func fetchAll() -> NSFetchRequest<MediaList> {
        let request = NSFetchRequest<MediaList>(entityName: "List")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \MediaList.order, ascending: true)]
        return request
    }

    /// Fetch request for the default list
    static func fetchDefault() -> NSFetchRequest<MediaList> {
        let request = NSFetchRequest<MediaList>(entityName: "List")
        request.predicate = NSPredicate(format: "isDefault == YES AND deletedAt == NULL")
        request.fetchLimit = 1
        return request
    }
    
    /// Fetch request for non-deleted lists only
    static func fetchActive() -> NSFetchRequest<MediaList> {
        let request = NSFetchRequest<MediaList>(entityName: "List")
        request.predicate = NSPredicate(format: "deletedAt == NULL")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \MediaList.order, ascending: true)]
        return request
    }
}

// MARK: - LWW Support

extension MediaList {
    
    /// Returns true if this list is deleted (has a deletedAt timestamp)
    var isListDeleted: Bool {
        return deletedAt != nil
    }
    
    /// Returns true if this list is a tombstone (deleted but kept for sync)
    var isTombstone: Bool {
        return isListDeleted
    }
    
    /// Updates the list's timestamp and device ID to mark it as modified
    func markAsModified() {
        let now = Date()
        let deviceID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        
        updatedAt = now
        self.deviceID = deviceID
    }
    
    /// Returns active (non-deleted) items in this list
    var activeItems: [ListItem] {
        return sortedItems.filter { $0.deletedAt == nil }
    }
    
    /// Returns the actual count of active titles (non-deleted)
    var activeTitleCount: Int {
        return activeItems.count
    }
    
    /// Returns the number of active watched titles
    var activeWatchedCount: Int {
        return activeItems.filter { $0.title?.watched == true }.count
    }
}
