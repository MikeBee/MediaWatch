//
//  MediaWatchApp.swift
//  MediaWatch
//
//  Main app entry point
//

import SwiftUI
import CloudKit

@main
struct MediaWatchApp: App {

    // MARK: - Properties

    @StateObject private var persistenceController = PersistenceController.shared
    @StateObject private var appSettings = AppSettings.shared
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // MARK: - Body

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.viewContext)
                .environmentObject(persistenceController)
                .environmentObject(appSettings)
                .preferredColorScheme(colorScheme)
                .onOpenURL { url in
                    // Handle CloudKit share URLs
                    handleShareURL(url)
                }
        }
    }

    private var colorScheme: ColorScheme? {
        switch appSettings.theme {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    // MARK: - Share URL Handling

    private func handleShareURL(_ url: URL) {
        // Parse the CloudKit share URL and accept it
        let operation = CKFetchShareMetadataOperation(shareURLs: [url])

        operation.perShareMetadataResultBlock = { url, result in
            switch result {
            case .success(let metadata):
                Task {
                    do {
                        try await persistenceController.acceptShare(metadata)
                        print("Successfully accepted share from URL")
                    } catch {
                        print("Failed to accept share: \(error)")
                    }
                }
            case .failure(let error):
                print("Failed to fetch share metadata: \(error)")
            }
        }

        CKContainer(identifier: "iCloud.com.mediawatch.app").add(operation)
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {

        // Register for remote notifications for CloudKit
        application.registerForRemoteNotifications()

        return true
    }

    // Handle CloudKit share acceptance from notification
    func application(_ application: UIApplication, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        Task {
            do {
                try await PersistenceController.shared.acceptShare(cloudKitShareMetadata)
                print("Successfully accepted CloudKit share invitation")
            } catch {
                print("Failed to accept CloudKit share: \(error)")
            }
        }
    }

    // Handle remote notifications
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        // CloudKit will handle the sync automatically
        completionHandler(.newData)
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // CloudKit uses this automatically
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register for remote notifications: \(error)")
    }
}

