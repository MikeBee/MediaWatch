//
//  CloudKitPublicSyncSettingsView.swift
//  MediaWatch
//
//  Settings interface for CloudKit Public Database sync with cross-Apple ID support
//

import SwiftUI

struct CloudKitPublicSyncSettingsView: View {
    @StateObject private var syncService = CloudKitPublicSyncService.shared
    @State private var showingMigrationAlert = false
    @State private var showingClearCacheAlert = false
    @State private var showingDiagnostics = false
    @State private var showingShareSheet = false
    @State private var logFileURL: URL?
    
    var body: some View {
        List {
            // Main sync toggle
            Section(header: Text("CloudKit Public Database Sync")) {
                Toggle("Enable Cross-Apple ID Sync", isOn: $syncService.isEnabled)
                    .disabled(syncService.syncStatus == .syncing)
                
                HStack {
                    Text("Status")
                    Spacer()
                    statusLabel
                }
                
                if let lastSync = syncService.lastSyncDate {
                    HStack {
                        Text("Last Sync")
                        Spacer()
                        Text(lastSync, style: .relative)
                            .foregroundColor(.secondary)
                    }
                }
                
                if let lastConflict = syncService.lastConflictDate {
                    HStack {
                        Text("Last Conflict")
                        Spacer()
                        Text(lastConflict, style: .relative)
                            .foregroundColor(.orange)
                    }
                }
            }
            
            // Migration section
            Section(header: Text("Data Migration"), 
                   footer: Text("Migrate your existing Core Data to CloudKit Public Database for cross-Apple ID sharing.")) {
                
                let migrationStatus = syncService.getMigrationStatus()
                
                HStack {
                    Text("Migration Status")
                    Spacer()
                    Text(migrationStatus.statusMessage)
                        .foregroundColor(migrationStatus.isRequired ? .orange : .green)
                        .font(.caption)
                }
                
                if migrationStatus.isRequired && migrationStatus.canMigrate {
                    Button("Reset Migration Flag") {
                        showingMigrationAlert = true
                    }
                    .foregroundColor(.orange)
                }
            }
            
            // Sync actions
            Section(header: Text("Sync Actions")) {
                Button("Force Sync Now") {
                    Task {
                        await syncService.forceSync()
                    }
                }
                .disabled(!syncService.isEnabled || syncService.syncStatus == .syncing)
                
                if syncService.isInReadOnlyMode {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Read-Only Mode", systemImage: "info.circle")
                            .foregroundColor(.orange)
                            .font(.caption.weight(.medium))
                        
                        Text("This device can read sync data but cannot update CloudKit. Tap below to take ownership and enable full sync.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                
                Button(syncService.isInReadOnlyMode ? "Take Ownership & Enable Full Sync" : "Transfer Record Ownership") {
                    print("🔘 Button pressed: \(syncService.isInReadOnlyMode ? "Take Ownership" : "Transfer Record Ownership")")
                    syncService.logDiagnostic("🔘 Button tapped - isInReadOnlyMode: \(syncService.isInReadOnlyMode)")
                    Task {
                        print("🔄 Starting transferOwnership task")
                        await syncService.transferOwnership()
                        print("✅ transferOwnership task completed")
                    }
                }
                .foregroundColor(syncService.isInReadOnlyMode ? .blue : .orange)
                .disabled(syncService.syncStatus == .syncing)
                
                Button("Clear CloudKit Cache") {
                    showingClearCacheAlert = true
                }
                .foregroundColor(.red)
                .disabled(syncService.syncStatus == .syncing)
                
                Button("Clear Sync Log") {
                    syncService.diagnosticsLog.removeAll()
                }
                .foregroundColor(.red)
            }
            
            // Data Fixes
            Section(header: Text("Data Fixes"), 
                   footer: Text("Tools to fix data issues that can cause sync problems.")) {
                
                let migrationHelper = TimestampMigrationHelper.shared
                
                if !migrationHelper.isTimestampMigrationCompleted {
                    Button("Fix Placeholder Timestamps") {
                        Task {
                            do {
                                try await migrationHelper.fixPlaceholderTimestamps()
                            } catch {
                                print("Migration failed: \(error)")
                            }
                        }
                    }
                    .foregroundColor(.orange)
                } else {
                    HStack {
                        Image(systemName: "checkmark.circle")
                            .foregroundColor(.green)
                        Text("Timestamp Migration Completed")
                        Spacer()
                        Button("Reset") {
                            migrationHelper.resetMigrationFlag()
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                }
                
                Button("Reset Device ID") {
                    #if DEBUG
                    DeviceIdentifier.shared.resetDeviceID()
                    #endif
                }
                .foregroundColor(.orange)
                #if !DEBUG
                .hidden()
                #endif
            }
            
            // Diagnostics
            Section(header: Text("Diagnostics")) {
                NavigationLink("Database Integrity") {
                    DatabaseIntegrityView()
                }
                
                Button("View Sync Logs") {
                    showingDiagnostics = true
                }
                
                Button("Copy Logs to Clipboard") {
                    syncService.copyDiagnosticsToClipboard()
                }
                
                Button("Save & Share Logs") {
                    if let fileURL = syncService.saveDiagnosticsToFile() {
                        logFileURL = fileURL
                        showingShareSheet = true
                    }
                }
                
                HStack {
                    Text("Log Entries")
                    Spacer()
                    Text("\(syncService.diagnosticsLog.count)")
                        .foregroundColor(.secondary)
                }
                
                let errorCount = syncService.diagnosticsLog.filter(\.isError).count
                if errorCount > 0 {
                    HStack {
                        Text("Recent Errors")
                        Spacer()
                        Text("\(errorCount)")
                            .foregroundColor(.red)
                    }
                }
            }
            
            // Information
            Section(header: Text("About CloudKit Public Sync"), 
                   footer: Text("CloudKit Public Database allows syncing across different Apple IDs. All users can access the same shared data. This works in TestFlight and doesn't require App Store publishing.")) {
                
                HStack {
                    Text("Sync Method")
                    Spacer()
                    Text("CloudKit Public Database")
                        .foregroundColor(.blue)
                        .font(.caption)
                }
                
                HStack {
                    Text("Cross-Apple ID")
                    Spacer()
                    Text("✓ Supported")
                        .foregroundColor(.green)
                        .font(.caption)
                }
                
                HStack {
                    Text("TestFlight Compatible")
                    Spacer()
                    Text("✓ Yes")
                        .foregroundColor(.green)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("CloudKit Public Sync")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Reset Migration", isPresented: $showingMigrationAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                syncService.resetMigrationFlag()
            }
        } message: {
            Text("This will force re-migration of your Core Data to CloudKit. Your existing CloudKit data may be overwritten.")
        }
        .alert("Clear CloudKit Cache", isPresented: $showingClearCacheAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Clear", role: .destructive) {
                Task {
                    await syncService.clearSyncCache()
                }
            }
        } message: {
            Text("This will delete the shared sync data from CloudKit Public Database. Other devices will lose access to this data.")
        }
        .sheet(isPresented: $showingDiagnostics) {
            CloudKitPublicSyncDiagnosticsView()
        }
        .sheet(isPresented: $showingShareSheet) {
            if let fileURL = logFileURL {
                ShareSheet(activityItems: [fileURL])
            }
        }
    }
    
    @ViewBuilder
    private var statusLabel: some View {
        switch syncService.syncStatus {
        case .idle:
            Label("Idle", systemImage: "pause.circle")
                .foregroundColor(.secondary)
        case .syncing:
            Label("Syncing", systemImage: "arrow.triangle.2.circlepath")
                .foregroundColor(.blue)
        case .success(let message):
            Label("Success", systemImage: "checkmark.circle")
                .foregroundColor(.green)
        case .error(let message):
            Label("Error", systemImage: "exclamationmark.triangle")
                .foregroundColor(.red)
        case .cloudKitUnavailable:
            Label("CloudKit Unavailable", systemImage: "icloud.slash")
                .foregroundColor(.orange)
        case .migrating:
            Label("Migrating", systemImage: "arrow.up.doc")
                .foregroundColor(.blue)
        case .readOnlyMode(let message):
            Label("Read-Only Mode", systemImage: "eye")
                .foregroundColor(.orange)
        }
    }
}

struct CloudKitPublicSyncDiagnosticsView: View {
    @StateObject private var syncService = CloudKitPublicSyncService.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            List {
                ForEach(syncService.diagnosticsLog.reversed()) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .top) {
                            Text(entry.event)
                                .font(.headline)
                                .foregroundColor(entry.isError ? .red : .primary)
                                .multilineTextAlignment(.leading)
                            
                            Spacer()
                            
                            Text(entry.timestamp, format: .dateTime.hour().minute().second())
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        if let details = entry.details {
                            Text(details)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }
            }
            .listStyle(PlainListStyle())
            .navigationTitle("CloudKit Sync Logs")
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

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        return UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    NavigationView {
        CloudKitPublicSyncSettingsView()
    }
}