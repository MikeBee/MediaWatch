//
//  ContentView.swift
//  MediaWatch
//
//  Main content view with tab navigation
//

import SwiftUI
import CoreData

struct ContentView: View {

    // MARK: - Environment

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    // MARK: - State

    @State private var selectedTab: Tab = .library

    // MARK: - Body

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                // iPad layout
                iPadView
            } else {
                // iPhone layout
                iPhoneView
            }
        }
    }

    // MARK: - iPhone View

    private var iPhoneView: some View {
        TabView(selection: $selectedTab) {
            LibraryPlaceholderView()
                .tabItem {
                    Label("Library", systemImage: "list.bullet")
                }
                .tag(Tab.library)

            SearchPlaceholderView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .tag(Tab.search)

            SettingsPlaceholderView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(Tab.settings)
        }
    }

    // MARK: - iPad View

    private var iPadView: some View {
        NavigationSplitView {
            // Sidebar
            SidebarPlaceholderView()
        } content: {
            // Content
            ContentPlaceholderView()
        } detail: {
            // Detail
            DetailPlaceholderView()
        }
        .navigationSplitViewStyle(.balanced)
    }
}

// MARK: - Tab Enum

enum Tab: Hashable {
    case library
    case search
    case settings
}

// MARK: - Placeholder Views

struct LibraryPlaceholderView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \MediaList.sortOrder, ascending: true)],
        animation: .default
    )
    private var lists: FetchedResults<MediaList>

    var body: some View {
        NavigationStack {
            Group {
                if lists.isEmpty {
                    ContentUnavailableView {
                        Label("No Lists", systemImage: "list.bullet")
                    } description: {
                        Text("Create your first list to start tracking content")
                    } actions: {
                        Button("Create List") {
                            // Will be implemented
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(lists) { list in
                            NavigationLink {
                                ListDetailPlaceholderView(list: list)
                            } label: {
                                ListRowView(list: list)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        // Will be implemented
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }
}

struct ListRowView: View {
    let list: MediaList

    var body: some View {
        HStack {
            Image(systemName: list.displayIcon)
                .foregroundStyle(list.displayColor)
                .frame(width: 30)

            VStack(alignment: .leading) {
                Text(list.displayName)
                    .font(.headline)

                HStack {
                    Text("\(list.titleCount) items")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if list.titleCount > 0 {
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text(list.watchProgressText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Progress indicator
            if list.titleCount > 0 {
                CircularProgressView(progress: list.watchProgress)
                    .frame(width: 30, height: 30)
            }
        }
        .padding(.vertical, 4)
    }
}

struct CircularProgressView: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(lineWidth: 3)
                .opacity(0.3)
                .foregroundStyle(.gray)

            Circle()
                .trim(from: 0.0, to: CGFloat(min(progress, 1.0)))
                .stroke(style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                .foregroundStyle(.green)
                .rotationEffect(Angle(degrees: 270.0))

            if progress >= 1.0 {
                Image(systemName: "checkmark")
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
        }
    }
}

struct ListDetailPlaceholderView: View {
    let list: MediaList

    var body: some View {
        Group {
            if list.sortedTitles.isEmpty {
                ContentUnavailableView {
                    Label("Empty List", systemImage: "film")
                } description: {
                    Text("Search for movies or TV shows to add them here")
                }
            } else {
                List {
                    ForEach(list.sortedTitles, id: \.objectID) { title in
                        TitleRowView(title: title)
                    }
                }
            }
        }
        .navigationTitle(list.displayName)
    }
}

struct TitleRowView: View {
    let title: Title

    var body: some View {
        HStack {
            // Poster placeholder
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 50, height: 75)
                .overlay {
                    Image(systemName: title.isMovie ? "film" : "tv")
                        .foregroundStyle(.gray)
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(title.displayTitle)
                        .font(.headline)
                        .lineLimit(2)

                    if title.likedStatusEnum == .liked {
                        Image(systemName: "hand.thumbsup.fill")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    } else if title.likedStatusEnum == .disliked {
                        Image(systemName: "hand.thumbsdown.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                HStack {
                    Text(title.displayYear)
                    Text("•")
                    Text(title.displayType)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                // Watch status
                HStack {
                    if title.isMovie {
                        Image(systemName: title.watched ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(title.watched ? .green : .gray)
                        Text(title.watched ? "Watched" : "Not watched")
                    } else {
                        Text(title.watchProgressText)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if title.isTVShow && title.watchProgress > 0 && title.watchProgress < 1 {
                CircularProgressView(progress: title.watchProgress)
                    .frame(width: 25, height: 25)
            }
        }
        .padding(.vertical, 4)
    }
}

struct SearchPlaceholderView: View {
    @State private var searchText = ""

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label("Search", systemImage: "magnifyingglass")
            } description: {
                Text("Search for movies and TV shows to add to your library")
            }
            .navigationTitle("Search")
            .searchable(text: $searchText, prompt: "Movies, TV Shows...")
        }
    }
}

struct SettingsPlaceholderView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Library") {
                    HStack {
                        Text("Default List")
                        Spacer()
                        Text("Watchlist")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Sync") {
                    HStack {
                        Text("iCloud Sync")
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }

                    HStack {
                        Text("Last Sync")
                        Spacer()
                        Text("Just now")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Backup") {
                    Text("Export Data")
                    Text("Import Data")
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    Text("Clear Image Cache")
                }
            }
            .navigationTitle("Settings")
        }
    }
}

struct SidebarPlaceholderView: View {
    var body: some View {
        List {
            Section("Lists") {
                Label("Watchlist", systemImage: "list.bullet")
                Label("Favorites", systemImage: "star")
            }
        }
        .navigationTitle("MediaWatch")
    }
}

struct ContentPlaceholderView: View {
    var body: some View {
        ContentUnavailableView("Select a List", systemImage: "list.bullet")
    }
}

struct DetailPlaceholderView: View {
    var body: some View {
        ContentUnavailableView("Select a Title", systemImage: "film")
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
        .environmentObject(PersistenceController.preview)
}
