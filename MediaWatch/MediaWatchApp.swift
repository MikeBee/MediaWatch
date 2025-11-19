//
//  MediaWatchApp.swift
//  MediaWatch
//
//  Main app entry point
//

import SwiftUI

@main
struct MediaWatchApp: App {

    // MARK: - Properties

    @StateObject private var persistenceController = PersistenceController.shared

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.viewContext)
                .environmentObject(persistenceController)
        }
    }
}
