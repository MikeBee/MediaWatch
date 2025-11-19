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
        ZStack {
            // Gradient background
            LinearGradient(
                colors: [Color.black, Color(white: 0.15)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

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
        .preferredColorScheme(.dark)
        .onAppear {
            // Set up TMDb API key
            Task {
                await TMDbService.shared.setAPIKey("7f14a43f8de003da44bebf87a8d4d34b")
            }
        }
    }

    // MARK: - iPhone View

    private var iPhoneView: some View {
        TabView(selection: $selectedTab) {
            LibraryView()
                .tabItem {
                    Label("Library", systemImage: "list.bullet")
                }
                .tag(Tab.library)

            SearchView()
                .tabItem {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .tag(Tab.search)

            SettingsView()
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
            SidebarView()
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

// MARK: - Library View

struct LibraryView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \MediaList.sortOrder, ascending: true)],
        animation: .default
    )
    private var lists: FetchedResults<MediaList>

    @State private var showingNewListSheet = false
    @State private var newListName = ""
    @State private var newListIcon = "list.bullet"
    @State private var newListColor = "007AFF"

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
                            showingNewListSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(lists) { list in
                            NavigationLink {
                                ListDetailView(list: list)
                            } label: {
                                ListRowView(list: list)
                            }
                        }
                        .onDelete(perform: deleteLists)
                    }
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewListSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewListSheet) {
                NewListSheet(
                    name: $newListName,
                    icon: $newListIcon,
                    color: $newListColor,
                    onCreate: createList
                )
            }
        }
    }

    private func createList() {
        withAnimation {
            let list = TMDbMapper.createList(
                name: newListName.isEmpty ? "New List" : newListName,
                icon: newListIcon,
                colorHex: newListColor,
                context: viewContext
            )

            // Make first list the default
            if lists.isEmpty {
                list.isDefault = true
            }

            do {
                try viewContext.save()
            } catch {
                print("Error creating list: \(error)")
            }

            // Reset form
            newListName = ""
            newListIcon = "list.bullet"
            newListColor = "007AFF"
        }
    }

    private func deleteLists(offsets: IndexSet) {
        withAnimation {
            offsets.map { lists[$0] }.forEach(viewContext.delete)

            do {
                try viewContext.save()
            } catch {
                print("Error deleting list: \(error)")
            }
        }
    }
}

// MARK: - New List Sheet

struct NewListSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var name: String
    @Binding var icon: String
    @Binding var color: String
    var onCreate: () -> Void

    private let icons = [
        "list.bullet", "star", "heart", "film", "tv",
        "popcorn", "ticket", "sparkles", "flag", "bookmark"
    ]

    private let colors = [
        "007AFF", "FF3B30", "FF9500", "FFCC00", "34C759",
        "5AC8FA", "AF52DE", "FF2D55", "8E8E93", "000000"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("List Name", text: $name)
                }

                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 16) {
                        ForEach(icons, id: \.self) { iconName in
                            Button {
                                icon = iconName
                            } label: {
                                Image(systemName: iconName)
                                    .font(.title2)
                                    .frame(width: 44, height: 44)
                                    .background(icon == iconName ? Color.accentColor.opacity(0.2) : Color.clear)
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 16) {
                        ForEach(colors, id: \.self) { hexColor in
                            Button {
                                color = hexColor
                            } label: {
                                Circle()
                                    .fill(Color(hex: hexColor) ?? Color.accentColor)
                                    .frame(width: 36, height: 36)
                                    .overlay {
                                        if color == hexColor {
                                            Image(systemName: "checkmark")
                                                .font(.caption)
                                                .foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("New List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onCreate()
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - List Row View

struct ListRowView: View {
    @ObservedObject var list: MediaList

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

// MARK: - Circular Progress View

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

// MARK: - List Detail View

struct ListDetailView: View {
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

// MARK: - Title Row View

struct TitleRowView: View {
    let title: Title

    var body: some View {
        HStack {
            // Poster
            PosterImageView(posterPath: title.posterPath, size: Constants.TMDb.ImageSize.posterSmall)
                .frame(width: 50, height: 75)
                .cornerRadius(4)

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

// MARK: - Search View

struct SearchView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @State private var searchText = ""
    @State private var searchResults: [TMDbSearchResult] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var selectedResult: TMDbSearchResult?

    var body: some View {
        NavigationStack {
            Group {
                if searchText.isEmpty && searchResults.isEmpty {
                    ContentUnavailableView {
                        Label("Search", systemImage: "magnifyingglass")
                    } description: {
                        Text("Search for movies and TV shows to add to your library")
                    }
                } else if isSearching {
                    ProgressView("Searching...")
                } else if let error = errorMessage {
                    ContentUnavailableView {
                        Label("Error", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error)
                    }
                } else if searchResults.isEmpty && !searchText.isEmpty {
                    ContentUnavailableView {
                        Label("No Results", systemImage: "magnifyingglass")
                    } description: {
                        Text("No movies or TV shows found for \"\(searchText)\"")
                    }
                } else {
                    List {
                        ForEach(searchResults) { result in
                            Button {
                                selectedResult = result
                            } label: {
                                SearchResultRow(result: result)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Search")
            .searchable(text: $searchText, prompt: "Movies, TV Shows...")
            .onSubmit(of: .search) {
                performSearch()
            }
            .onChange(of: searchText) { oldValue, newValue in
                if newValue.isEmpty {
                    searchResults = []
                    errorMessage = nil
                }
            }
            .sheet(item: $selectedResult) { result in
                AddToListSheet(result: result)
                    .environment(\.managedObjectContext, viewContext)
            }
        }
    }

    private func performSearch() {
        guard !searchText.isEmpty else { return }

        isSearching = true
        errorMessage = nil

        Task {
            do {
                let response = try await TMDbService.shared.searchMulti(query: searchText)
                await MainActor.run {
                    // Filter to only movies and TV shows
                    searchResults = response.results.filter {
                        $0.resolvedMediaType == "movie" || $0.resolvedMediaType == "tv"
                    }
                    isSearching = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isSearching = false
                }
            }
        }
    }
}

// MARK: - Search Result Row

struct SearchResultRow: View {
    let result: TMDbSearchResult

    var body: some View {
        HStack {
            // Poster
            PosterImageView(posterPath: result.posterPath, size: Constants.TMDb.ImageSize.posterSmall)
                .frame(width: 50, height: 75)
                .cornerRadius(4)

            VStack(alignment: .leading, spacing: 4) {
                Text(result.displayTitle)
                    .font(.headline)
                    .lineLimit(2)

                HStack {
                    if let date = result.displayDate, date.count >= 4 {
                        Text(String(date.prefix(4)))
                    }
                    Text("•")
                    Text(result.resolvedMediaType == "movie" ? "Movie" : "TV Show")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let voteAverage = result.voteAverage, voteAverage > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                        Text(String(format: "%.1f", voteAverage))
                    }
                    .font(.caption)
                }
            }

            Spacer()

            Image(systemName: "plus.circle")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Add To List Sheet

struct AddToListSheet: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    let result: TMDbSearchResult

    @State private var lists: [MediaList] = []
    @State private var isAdding = false

    var body: some View {
        NavigationStack {
            Group {
                if lists.isEmpty {
                    ContentUnavailableView {
                        Label("No Lists", systemImage: "list.bullet")
                    } description: {
                        Text("Create a list first to add this title")
                    } actions: {
                        Button("Create List") {
                            createDefaultList()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(lists, id: \.objectID) { list in
                            Button {
                                addToList(list)
                            } label: {
                                HStack {
                                    Image(systemName: list.displayIcon)
                                        .foregroundStyle(list.displayColor)
                                        .frame(width: 30)

                                    Text(list.displayName)
                                        .foregroundStyle(.primary)

                                    Spacer()

                                    if isAdding {
                                        ProgressView()
                                    }
                                }
                            }
                            .disabled(isAdding)
                        }
                    }
                }
            }
            .navigationTitle("Add to List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                if !lists.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            createDefaultList()
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .onAppear {
                fetchLists()
            }
        }
    }

    private func fetchLists() {
        let request: NSFetchRequest<MediaList> = NSFetchRequest(entityName: "List")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \MediaList.sortOrder, ascending: true)]

        do {
            lists = try viewContext.fetch(request)
        } catch {
            print("Error fetching lists: \(error)")
        }
    }

    private func createDefaultList() {
        _ = TMDbMapper.createList(
            name: "Watchlist",
            icon: "list.bullet",
            colorHex: "007AFF",
            isDefault: true,
            context: viewContext
        )

        do {
            try viewContext.save()
            fetchLists() // Refresh the list
        } catch {
            print("Error creating list: \(error)")
        }
    }

    private func addToList(_ list: MediaList) {
        isAdding = true

        Task {
            // Create or get existing title
            let title = TMDbMapper.mapSearchResult(result, context: viewContext)

            // Add to list
            _ = TMDbMapper.addTitle(title, to: list, context: viewContext)

            do {
                try viewContext.save()
                await MainActor.run {
                    dismiss()
                }
            } catch {
                print("Error adding to list: \(error)")
                await MainActor.run {
                    isAdding = false
                }
            }
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @State private var cacheSize = "Calculating..."

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

                Section("Cache") {
                    HStack {
                        Text("Image Cache")
                        Spacer()
                        Text(cacheSize)
                            .foregroundStyle(.secondary)
                    }

                    Button("Clear Image Cache") {
                        Task {
                            await ImageCacheService.shared.clearAllCaches()
                            cacheSize = await ImageCacheService.shared.formattedDiskCacheSize()
                        }
                    }
                    .foregroundStyle(.red)
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                Task {
                    cacheSize = await ImageCacheService.shared.formattedDiskCacheSize()
                }
            }
        }
    }
}

// MARK: - iPad Views

struct SidebarView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \MediaList.sortOrder, ascending: true)],
        animation: .default
    )
    private var lists: FetchedResults<MediaList>

    var body: some View {
        List {
            Section("Lists") {
                ForEach(lists) { list in
                    Label(list.displayName, systemImage: list.displayIcon)
                }
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
}
