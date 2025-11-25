//
//  ICloudDriveSyncSettingsView.swift
//  MediaWatch
//
//  Settings and diagnostics view for iCloud Drive JSON sync
//

import SwiftUI
import Foundation

struct ICloudDriveSyncSettingsView: View {
    @StateObject private var syncService = ICloudDriveJSONSyncService.shared
    @State private var showingDiagnostics = false
    @State private var showingMigrationAlert = false
    @State private var migrationStatus = SyncMigrationStatus(isRequired: false, coreDataItemCount: 0, canMigrate: false)
    
    var body: some View {
        NavigationView {
            Form {
                syncStatusSection
                syncControlsSection
                migrationSection
                diagnosticsSection
                advancedSection
            }
            .navigationTitle("iCloud Drive Sync")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                updateMigrationStatus()
            }
            .alert("Migration Required", isPresented: $showingMigrationAlert) {
                Button("Migrate Now") {
                    Task {
                        await syncService.enableSync()
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Would you like to migrate your existing data to iCloud Drive sync?")
            }
        }
    }
    
    // MARK: - Sections
    
    private var syncStatusSection: some View {
        Section(header: Text("Status")) {
            HStack {
                statusIcon
                VStack(alignment: .leading, spacing: 4) {
                    Text(statusText)
                        .font(.headline)
                    if let lastSync = syncService.lastSyncDate {
                        Text("Last sync: \(lastSync, style: .relative) ago")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 4)
        }
    }
    
    private var syncControlsSection: some View {
        Section {
            Toggle("Enable iCloud Drive Sync", isOn: $syncService.isEnabled)
                .disabled(!migrationStatus.canMigrate && migrationStatus.isRequired)
            
            if syncService.isEnabled {
                Button("Force Sync Now") {
                    Task {
                        await syncService.forceSync()
                    }
                }
                .disabled(syncService.syncStatus == .syncing)
            }
        } header: {
            Text("Sync Controls")
        } footer: {
            Text("Automatically syncs your lists and progress across devices using iCloud Drive. Does not use CloudKit.")
        }
    }
    
    private var migrationSection: some View {
        Section(header: Text("Migration")) {
            if migrationStatus.isRequired {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Migration Required", systemImage: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    
                    Text("\(migrationStatus.coreDataItemCount) items ready to migrate")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if migrationStatus.canMigrate {
                        Button("Start Migration") {
                            showingMigrationAlert = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.vertical, 4)
            } else {
                HStack {
                    Image(systemName: "checkmark.circle")
                        .foregroundColor(.green)
                    Text("Migration completed")
                    Spacer()
                    Button("Reset") {
                        syncService.resetMigrationFlag()
                        updateMigrationStatus()
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            }
        }
    }
    
    private var diagnosticsSection: some View {
        Section(header: Text("Diagnostics")) {
            Button("View Sync Log") {
                showingDiagnostics = true
            }
            
            if let conflictDate = syncService.lastConflictDate {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    VStack(alignment: .leading) {
                        Text("Last conflict resolved")
                        Text("\(conflictDate, style: .relative) ago")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
            }
        }
        .sheet(isPresented: $showingDiagnostics) {
            DiagnosticsLogView(diagnosticsLog: syncService.diagnosticsLog)
        }
    }
    
    private var advancedSection: some View {
        Section {
            Button("Clear Sync Cache", role: .destructive) {
                // Implementation would clear local cache
            }
            
            Button("Export Diagnostics") {
                exportDiagnostics()
            }
        } header: {
            Text("Advanced")
        } footer: {
            Text("Advanced options for troubleshooting sync issues.")
        }
    }
    
    // MARK: - Computed Properties
    
    private var statusIcon: some View {
        Group {
            switch syncService.syncStatus {
            case .idle:
                Image(systemName: "pause.circle")
                    .foregroundColor(.secondary)
            case .syncing:
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundColor(.blue)
                    .rotationEffect(.degrees(45))
            case .success:
                Image(systemName: "checkmark.circle")
                    .foregroundColor(.green)
            case .error:
                Image(systemName: "exclamationmark.circle")
                    .foregroundColor(.red)
            case .iCloudUnavailable:
                Image(systemName: "icloud.slash")
                    .foregroundColor(.orange)
            case .migrating:
                Image(systemName: "arrow.up.doc")
                    .foregroundColor(.blue)
            }
        }
    }
    
    private var statusText: String {
        switch syncService.syncStatus {
        case .idle:
            return syncService.isEnabled ? "Ready" : "Disabled"
        case .syncing:
            return "Syncing..."
        case .success(let message):
            return message
        case .error(let error):
            return "Error: \(error)"
        case .iCloudUnavailable:
            return "iCloud Drive Unavailable"
        case .migrating:
            return "Migrating..."
        }
    }
    
    // MARK: - Methods
    
    private func updateMigrationStatus() {
        migrationStatus = syncService.getMigrationStatus()
    }
    
    private func exportDiagnostics() {
        // Implementation would create a shareable diagnostics report
        print("Export diagnostics - not implemented")
    }
}

// MARK: - Diagnostics Log View

struct DiagnosticsLogView: View {
    let diagnosticsLog: [ICloudDriveJSONSyncService.DiagnosticEntry]
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List(diagnosticsLog.reversed()) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(entry.event)
                            .font(.headline)
                        Spacer()
                        if entry.isError {
                            Image(systemName: "exclamationmark.circle")
                                .foregroundColor(.red)
                        }
                    }
                    
                    Text(entry.timestamp, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let details = entry.details {
                        Text(details)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
                    }
                }
                .padding(.vertical, 2)
            }
            .navigationTitle("Sync Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}


#if DEBUG
struct ICloudDriveSyncSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        ICloudDriveSyncSettingsView()
    }
}
#endif