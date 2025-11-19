//
//  MediaWatchApp.swift
//  MediaWatch
//
//  Created by Mike on 11/19/25.
//

import SwiftUI

@main
struct MediaWatchApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
