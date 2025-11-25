//
//  DatabaseIntegrityView.swift
//  MediaWatch
//
//  Database integrity maintenance and monitoring UI
//

import SwiftUI

struct DatabaseIntegrityView: View {
    @StateObject private var integrityService = DatabaseIntegrityService.shared
    @State private var showingReport = false
    @State private var showingShareSheet = false
    @State private var reportFileURL: URL?
    @State private var autoFixEnabled = true
    @State private var quickCheckResult: String?
    
    var body: some View {
        List {
            // Status Section
            Section(header: Text("Database Health Status")) {
                HStack {
                    Image(systemName: healthIcon)
                        .foregroundColor(healthColor)
                    
                    VStack(alignment: .leading) {
                        Text(healthStatus)
                            .font(.headline)
                        if let lastScan = integrityService.lastScanDate {
                            Text("Last scan: \(lastScan, style: .relative) ago")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    if case .scanning(let progress) = integrityService.scanStatus {
                        VStack {
                            ProgressView(value: progress)
                                .frame(width: 60)
                            Text("\(Int(progress * 100))%")
                                .font(.caption2)
                        }
                    }
                }
                
                if let report = integrityService.integrityReport {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Total Entities:")
                            Spacer()
                            Text("\(report.totalEntities)")
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Issues Found:")
                            Spacer()
                            Text("\(report.issuesFound.count)")
                                .foregroundColor(report.issuesFound.isEmpty ? .green : .orange)
                        }
                        
                        HStack {
                            Text("Auto-Fixes Applied:")
                            Spacer()
                            Text("\(report.autoFixesApplied.count)")
                                .foregroundColor(.blue)
                        }
                        
                        if !report.manualActionsRequired.isEmpty {
                            HStack {
                                Text("Manual Actions Required:")
                                Spacer()
                                Text("\(report.manualActionsRequired.count)")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    .font(.caption)
                }
                
                if let quickResult = quickCheckResult {
                    Text(quickResult)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            }
            
            // Quick Actions
            Section(header: Text("Quick Actions")) {
                Button("Quick Health Check") {
                    performQuickCheck()
                }
                .disabled(isScanning)
                
                Toggle("Auto-Fix Issues", isOn: $autoFixEnabled)
                
                Button("Full Integrity Scan") {
                    performFullScan()
                }
                .disabled(isScanning)
            }
            
            // Issue Categories
            if let report = integrityService.integrityReport, !report.issuesFound.isEmpty {
                Section(header: Text("Issues by Category")) {
                    let groupedIssues = Dictionary(grouping: report.issuesFound, by: { $0.type })
                    
                    ForEach(groupedIssues.keys.sorted(by: { $0.rawValue < $1.rawValue }), id: \.self) { issueType in
                        let issues = groupedIssues[issueType]!
                        let severityColor = issues.max(by: { $0.severity.rawValue < $1.severity.rawValue })?.severity.emoji ?? "ℹ️"
                        
                        HStack {
                            Text(severityColor)
                            Text(issueType.rawValue)
                            Spacer()
                            Text("\(issues.count)")
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            // Recent Auto-Fixes
            if let report = integrityService.integrityReport, !report.autoFixesApplied.isEmpty {
                Section(header: Text("Recent Auto-Fixes")) {
                    ForEach(report.autoFixesApplied.suffix(5), id: \.timestamp) { fix in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(fix.action)
                                .font(.caption)
                            Text(fix.timestamp, style: .time)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            // Manual Actions Required
            if let report = integrityService.integrityReport, !report.manualActionsRequired.isEmpty {
                Section(header: Text("Manual Actions Required")) {
                    ForEach(report.manualActionsRequired, id: \.id) { issue in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(issue.severity.emoji)
                                Text(issue.description)
                                    .font(.caption)
                                Spacer()
                                Text(issue.entity)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            
                            if let details = issue.details {
                                Text(details)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            
            // Reports & Export
            Section(header: Text("Reports & Export")) {
                if integrityService.integrityReport != nil {
                    Button("View Detailed Report") {
                        showingReport = true
                    }
                    
                    Button("Export Report") {
                        exportReport()
                    }
                }
                
                Button("Clear Report History") {
                    integrityService.integrityReport = nil
                    quickCheckResult = nil
                }
                .foregroundColor(.red)
            }
            
            // Maintenance Tips
            Section(header: Text("Maintenance Tips"), 
                   footer: Text("Regular integrity scans help maintain sync reliability and catch data corruption early.")) {
                
                Label("Run weekly integrity scans", systemImage: "calendar")
                    .font(.caption)
                
                Label("Enable auto-fix for routine issues", systemImage: "wrench.and.screwdriver")
                    .font(.caption)
                
                Label("Export reports for troubleshooting", systemImage: "square.and.arrow.up")
                    .font(.caption)
            }
        }
        .navigationTitle("Database Integrity")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingReport) {
            DatabaseIntegrityReportView()
        }
        .sheet(isPresented: $showingShareSheet) {
            if let fileURL = reportFileURL {
                ShareSheet(activityItems: [fileURL])
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var healthIcon: String {
        switch integrityService.scanStatus {
        case .idle:
            return integrityService.integrityReport?.isHealthy == true ? "checkmark.circle" : "exclamationmark.triangle"
        case .scanning:
            return "magnifyingglass"
        case .completed:
            return integrityService.integrityReport?.isHealthy == true ? "checkmark.circle" : "exclamationmark.triangle"
        case .error:
            return "xmark.circle"
        }
    }
    
    private var healthColor: Color {
        switch integrityService.scanStatus {
        case .idle:
            return integrityService.integrityReport?.isHealthy == true ? .green : .orange
        case .scanning:
            return .blue
        case .completed:
            return integrityService.integrityReport?.isHealthy == true ? .green : .orange
        case .error:
            return .red
        }
    }
    
    private var healthStatus: String {
        switch integrityService.scanStatus {
        case .idle:
            if let report = integrityService.integrityReport {
                return report.summary
            }
            return "Ready to scan"
        case .scanning:
            return "Scanning database..."
        case .completed:
            return integrityService.integrityReport?.summary ?? "Scan completed"
        case .error(let message):
            return "Scan failed: \(message)"
        }
    }
    
    private var isScanning: Bool {
        if case .scanning = integrityService.scanStatus {
            return true
        }
        return false
    }
    
    // MARK: - Actions
    
    private func performQuickCheck() {
        Task {
            do {
                quickCheckResult = try await integrityService.performQuickHealthCheck()
            } catch {
                quickCheckResult = "❌ Quick check failed: \(error.localizedDescription)"
            }
        }
    }
    
    private func performFullScan() {
        Task {
            do {
                try await integrityService.performIntegrityScan(autoFix: autoFixEnabled)
            } catch {
                // Error is already reflected in the scanStatus
            }
        }
    }
    
    private func exportReport() {
        guard let reportText = integrityService.exportIntegrityReport() else { return }
        
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        guard let documentsURL = documentsPath else { return }
        
        let timestamp = Date().formatted(.dateTime.year().month().day().hour().minute())
        let filename = "DatabaseIntegrity_Report_\(timestamp).txt"
        let fileURL = documentsURL.appendingPathComponent(filename)
        
        do {
            try reportText.write(to: fileURL, atomically: true, encoding: .utf8)
            
            // Ensure file is accessible before presenting share sheet
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                print("Failed to create report file")
                return
            }
            
            // Add small delay to ensure file system has processed the new file
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.reportFileURL = fileURL
                self.showingShareSheet = true
            }
        } catch {
            print("Failed to export report: \(error)")
        }
    }
}

struct DatabaseIntegrityReportView: View {
    @StateObject private var integrityService = DatabaseIntegrityService.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                if let report = integrityService.integrityReport {
                    VStack(alignment: .leading, spacing: 16) {
                        // Header
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Database Integrity Report")
                                .font(.title2)
                                .bold()
                            
                            Text("Generated: \(report.scanDate.formatted(.dateTime))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text("Scan Duration: \(String(format: "%.2f", report.scanDuration)) seconds")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Divider()
                        
                        // Summary
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Summary")
                                .font(.headline)
                            
                            Text(report.summary)
                                .padding()
                                .background(report.isHealthy ? Color.green.opacity(0.1) : Color.orange.opacity(0.1))
                                .cornerRadius(8)
                        }
                        
                        // Statistics
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 16) {
                            StatCard(title: "Total Entities", value: "\(report.totalEntities)", color: .blue)
                            StatCard(title: "Issues Found", value: "\(report.issuesFound.count)", color: .orange)
                            StatCard(title: "Auto-Fixed", value: "\(report.autoFixesApplied.count)", color: .green)
                            StatCard(title: "Manual Actions", value: "\(report.manualActionsRequired.count)", color: .red)
                        }
                        
                        // Issues Detail
                        if !report.issuesFound.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Issues Found")
                                    .font(.headline)
                                
                                ForEach(report.issuesFound, id: \.id) { issue in
                                    IssueCard(issue: issue)
                                }
                            }
                        }
                        
                        // Auto-Fixes Applied
                        if !report.autoFixesApplied.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Auto-Fixes Applied")
                                    .font(.headline)
                                
                                ForEach(report.autoFixesApplied, id: \.timestamp) { fix in
                                    FixCard(fix: fix)
                                }
                            }
                        }
                    }
                    .padding()
                } else {
                    Text("No report available")
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Integrity Report")
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

struct StatCard: View {
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack {
            Text(value)
                .font(.title2)
                .bold()
                .foregroundColor(color)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

struct IssueCard: View {
    let issue: DatabaseIntegrityService.IntegrityIssue
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(issue.severity.emoji)
                Text(issue.description)
                    .font(.subheadline)
                    .bold()
                Spacer()
                Text(issue.entity)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(4)
            }
            
            if let details = issue.details {
                Text(details)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text("Auto-fix: \(issue.canAutoFix ? "Yes" : "No")")
                    .font(.caption)
                    .foregroundColor(issue.canAutoFix ? .green : .orange)
                
                Spacer()
                
                if let recordId = issue.recordId {
                    Text("ID: \(recordId.prefix(8))...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

struct FixCard: View {
    let fix: DatabaseIntegrityService.IntegrityFix
    
    var body: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            
            VStack(alignment: .leading) {
                Text(fix.action)
                    .font(.caption)
                Text(fix.timestamp.formatted(.dateTime))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(8)
    }
}

#Preview {
    NavigationView {
        DatabaseIntegrityView()
    }
}