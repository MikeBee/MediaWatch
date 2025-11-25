//
//  CloudSharingView.swift
//  MediaWatch
//
//  SwiftUI wrapper for UICloudSharingController to share lists via CloudKit
//

import SwiftUI
import CloudKit
import CoreData

// MARK: - Cloud Sharing Controller

struct CloudSharingView: UIViewControllerRepresentable {
    let share: CKShare
    let container: CKContainer
    let list: MediaList

    func makeUIViewController(context: Context) -> UICloudSharingController {
        share[CKShare.SystemFieldKey.title] = list.name ?? "Shared List"

        let controller = UICloudSharingController(share: share, container: container)
        controller.availablePermissions = [.allowReadWrite, .allowPrivate]
        controller.delegate = context.coordinator

        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {
        // No updates needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let parent: CloudSharingView

        init(_ parent: CloudSharingView) {
            self.parent = parent
        }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            print("Failed to save share: \(error.localizedDescription)")
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            parent.list.name ?? "Shared List"
        }

        func itemThumbnailData(for csc: UICloudSharingController) -> Data? {
            // Could return a thumbnail image here
            nil
        }

        func itemType(for csc: UICloudSharingController) -> String? {
            "com.mediashows.list"
        }
    }
}

// MARK: - Share Button View

struct ShareListButton: View {
    @EnvironmentObject var persistenceController: PersistenceController
    @ObservedObject var list: MediaList

    @State private var share: CKShare?
    @State private var showShareSheet = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        Button {
            Task {
                await prepareShare()
            }
        } label: {
            if isLoading {
                ProgressView()
                    .scaleEffect(0.8)
            } else {
                Label(
                    persistenceController.isShared(list) ? "Manage Sharing" : "Share List",
                    systemImage: persistenceController.isShared(list) ? "person.2.fill" : "person.badge.plus"
                )
            }
        }
        .disabled(isLoading)
        .sheet(isPresented: $showShareSheet) {
            if let share = share {
                CloudSharingView(
                    share: share,
                    container: CKContainer(identifier: "iCloud.reasonality.MediaShows"),
                    list: list
                )
            }
        }
        .alert("Sharing Error", isPresented: .constant(errorMessage != nil)) {
            Button("OK") {
                errorMessage = nil
            }
        } message: {
            if let error = errorMessage {
                Text(error)
            }
        }
    }

    private func prepareShare() async {
        isLoading = true

        do {
            // Check if already shared
            if let existingShare = persistenceController.share(for: list) {
                share = existingShare
            } else {
                // Mark list as shared in Core Data
                await MainActor.run {
                    list.isShared = true
                    try? persistenceController.viewContext.save()
                }

                // Create new share
                share = try await persistenceController.shareList(list)
            }

            await MainActor.run {
                isLoading = false
                showShareSheet = true
            }
        } catch {
            await MainActor.run {
                isLoading = false
                errorMessage = "Failed to create share: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Sharing Status View

struct SharingStatusView: View {
    @EnvironmentObject var persistenceController: PersistenceController
    let list: MediaList

    @State private var participants: [CKShare.Participant] = []

    var body: some View {
        if persistenceController.isShared(list) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "person.2.fill")
                        .foregroundStyle(.blue)
                    Text("Shared List")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }

                if !participants.isEmpty {
                    Text("\(participants.count) participant\(participants.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal)
            .task {
                loadParticipants()
            }
        }
    }

    private func loadParticipants() {
        if let share = persistenceController.share(for: list) {
            participants = share.participants.filter { $0.role != .owner }
        }
    }
}
