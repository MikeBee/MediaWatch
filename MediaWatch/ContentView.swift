//
//  ContentView.swift
//  MediaWatch
//
//  Main content view with tab navigation - Letterboxd-inspired design
//

import SwiftUI
import CoreData

struct ContentView: View {

    // MARK: - Environment

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    // MARK: - State

    @State private var selectedTab: Tab = .home

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

            TabView(selection: $selectedTab) {
                HomeView()
                    .tabItem {
                        Label("Home", systemImage: "house.fill")
                    }
                    .tag(Tab.home)

                ListsView()
                    .tabItem {
                        Label("Lists", systemImage: "list.bullet")
                    }
                    .tag(Tab.lists)

                SearchView()
                    .tabItem {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    .tag(Tab.search)

                ProfileView()
                    .tabItem {
                        Label("Profile", systemImage: "person.fill")
                    }
                    .tag(Tab.profile)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            Task {
                await TMDbService.shared.setAPIKey("7f14a43f8de003da44bebf87a8d4d34b")
            }
        }
    }
}

// MARK: - Tab Enum

enum Tab: Hashable {
    case home
    case lists
    case search
    case profile
}

// MARK: - Home View (Dashboard)

struct HomeView: View {
    @Environment(\.managedObjectContext) private var viewContext

    // Fetch recently watched titles
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Title.watchedDate, ascending: false)],
        predicate: NSPredicate(format: "watched == YES"),
        animation: .default
    )
    private var recentlyWatched: FetchedResults<Title>

    // Fetch TV shows in progress
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Title.dateModified, ascending: false)],
        predicate: NSPredicate(format: "mediaType == %@ AND watched == NO", "tv"),
        animation: .default
    )
    private var tvShowsInProgress: FetchedResults<Title>

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // Continue Watching Section
                    if !tvShowsInProgress.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Continue Watching")
                                .font(.title2)
                                .fontWeight(.bold)
                                .padding(.horizontal)

                            ScrollView(.horizontal, showsIndicators: false) {
                                LazyHStack(spacing: 16) {
                                    ForEach(tvShowsInProgress.prefix(10)) { show in
                                        ContinueWatchingCard(title: show)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
                    }

                    // Recently Watched Section
                    if !recentlyWatched.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Recently Watched")
                                .font(.title2)
                                .fontWeight(.bold)
                                .padding(.horizontal)

                            LazyVStack(spacing: 12) {
                                ForEach(recentlyWatched.prefix(5)) { title in
                                    RecentlyWatchedRow(title: title)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    // Empty State
                    if tvShowsInProgress.isEmpty && recentlyWatched.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "film.stack")
                                .font(.system(size: 60))
                                .foregroundStyle(.secondary)

                            Text("Your Dashboard")
                                .font(.title2)
                                .fontWeight(.bold)

                            Text("Start adding movies and TV shows to see your watching progress here.")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    }

                    Spacer(minLength: 100)
                }
                .padding(.top)
            }
            .navigationTitle("Home")
        }
    }
}

// MARK: - Continue Watching Card

struct ContinueWatchingCard: View {
    @ObservedObject var title: Title

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PosterImageView(posterPath: title.posterPath, size: Constants.TMDb.ImageSize.posterMedium)
                .frame(width: 120, height: 180)
                .cornerRadius(8)

            Text(title.title ?? "Unknown")
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)
                .frame(width: 120, alignment: .leading)

            if title.numberOfSeasons > 0 {
                Text("S\(title.numberOfSeasons)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Recently Watched Row

struct RecentlyWatchedRow: View {
    @ObservedObject var title: Title

    var body: some View {
        HStack(spacing: 12) {
            PosterImageView(posterPath: title.posterPath, size: Constants.TMDb.ImageSize.posterSmall)
                .frame(width: 50, height: 75)
                .cornerRadius(4)

            VStack(alignment: .leading, spacing: 4) {
                Text(title.title ?? "Unknown")
                    .font(.headline)
                    .lineLimit(1)

                HStack {
                    Text(title.mediaType == "movie" ? "Movie" : "TV Show")
                    if title.year > 0 {
                        Text("•")
                        Text("\(title.year)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if let watchedDate = title.watchedDate {
                    Text("Watched \(watchedDate.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.3))
        .cornerRadius(12)
    }
}

// MARK: - Lists View

struct ListsView: View {
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
            ScrollView {
                VStack(spacing: 16) {
                    // New List Button
                    Button {
                        showingNewListSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                            Text("New List")
                                .font(.headline)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                        .background(Color.accentColor.opacity(0.2))
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal)

                    // Lists
                    if lists.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "list.bullet.rectangle")
                                .font(.system(size: 50))
                                .foregroundStyle(.secondary)

                            Text("No Lists Yet")
                                .font(.title3)
                                .fontWeight(.semibold)

                            Text("Create your first list to start organizing your movies and shows.")
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.top, 40)
                        .padding(.horizontal, 40)
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(lists) { list in
                                NavigationLink {
                                    ListDetailView(list: list)
                                } label: {
                                    ListCard(list: list)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.top)
            }
            .navigationTitle("Lists")
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

            if lists.isEmpty {
                list.isDefault = true
            }

            do {
                try viewContext.save()
            } catch {
                print("Error creating list: \(error)")
            }

            newListName = ""
            newListIcon = "list.bullet"
            newListColor = "007AFF"
        }
    }
}

// MARK: - List Card

struct ListCard: View {
    @ObservedObject var list: MediaList

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: list.displayIcon)
                    .foregroundStyle(list.displayColor)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(list.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("\(list.titleCount) items")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }

            // Poster Row Preview
            if list.titleCount > 0 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(list.sortedTitles.prefix(6), id: \.objectID) { title in
                            PosterImageView(posterPath: title.posterPath, size: Constants.TMDb.ImageSize.posterSmall)
                                .frame(width: 60, height: 90)
                                .cornerRadius(6)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.3))
        .cornerRadius(12)
    }
}

// MARK: - List Detail View

struct ListDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var list: MediaList

    @State private var viewMode: ViewMode = .grid

    enum ViewMode {
        case grid, list
    }

    var body: some View {
        Group {
            if list.titleCount == 0 {
                ContentUnavailableView {
                    Label("Empty List", systemImage: "list.bullet")
                } description: {
                    Text("Search for titles to add to this list")
                }
            } else {
                ScrollView {
                    if viewMode == .grid {
                        LazyVGrid(columns: [
                            GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 16)
                        ], spacing: 16) {
                            ForEach(list.sortedTitles, id: \.objectID) { title in
                                TitleGridItem(title: title)
                            }
                        }
                        .padding()
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(list.sortedTitles, id: \.objectID) { title in
                                TitleListRow(title: title)
                            }
                        }
                        .padding()
                    }
                }
            }
        }
        .navigationTitle(list.displayName)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        viewMode = .grid
                    } label: {
                        Label("Grid", systemImage: "square.grid.2x2")
                    }
                    Button {
                        viewMode = .list
                    } label: {
                        Label("List", systemImage: "list.bullet")
                    }
                } label: {
                    Image(systemName: viewMode == .grid ? "square.grid.2x2" : "list.bullet")
                }
            }
        }
    }
}

// MARK: - Title Grid Item

struct TitleGridItem: View {
    @ObservedObject var title: Title

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomTrailing) {
                PosterImageView(posterPath: title.posterPath, size: Constants.TMDb.ImageSize.posterMedium)
                    .aspectRatio(2/3, contentMode: .fit)
                    .cornerRadius(8)

                if title.watched {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .background(Circle().fill(.black.opacity(0.5)))
                        .padding(6)
                }
            }

            Text(title.title ?? "Unknown")
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)
        }
    }
}

// MARK: - Title List Row

struct TitleListRow: View {
    @ObservedObject var title: Title
    @Environment(\.managedObjectContext) private var viewContext

    var body: some View {
        HStack(spacing: 12) {
            PosterImageView(posterPath: title.posterPath, size: Constants.TMDb.ImageSize.posterSmall)
                .frame(width: 60, height: 90)
                .cornerRadius(6)

            VStack(alignment: .leading, spacing: 4) {
                Text(title.title ?? "Unknown")
                    .font(.headline)
                    .lineLimit(1)

                HStack {
                    Text(title.mediaType == "movie" ? "Movie" : "TV Show")
                    if title.year > 0 {
                        Text("•")
                        Text("\(title.year)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                // Progress indicator for TV shows
                if title.mediaType == "tv" && title.numberOfEpisodes > 0 {
                    let watchedEpisodes = (title.episodes as? Set<Episode>)?.filter { $0.watched }.count ?? 0
                    Text("\(watchedEpisodes)/\(title.numberOfEpisodes) episodes")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                // Liked status
                HStack(spacing: 4) {
                    if title.likedStatus == 1 {
                        Image(systemName: "hand.thumbsup.fill")
                            .foregroundStyle(.green)
                    } else if title.likedStatus == -1 {
                        Image(systemName: "hand.thumbsdown.fill")
                            .foregroundStyle(.red)
                    }
                }
                .font(.caption)
            }

            Spacer()

            // Watched indicator
            Button {
                title.watched.toggle()
                if title.watched {
                    title.watchedDate = Date()
                }
                try? viewContext.save()
            } label: {
                Image(systemName: title.watched ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(title.watched ? .green : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.3))
        .cornerRadius(12)
    }
}

// MARK: - Search View

struct SearchView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @State private var searchText = ""
    @State private var searchResults: [TMDbSearchResult] = []
    @State private var trendingResults: [TMDbSearchResult] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var selectedResult: TMDbSearchResult?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if searchText.isEmpty {
                        // Trending Section
                        if !trendingResults.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Trending This Week")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .padding(.horizontal)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    LazyHStack(spacing: 16) {
                                        ForEach(trendingResults) { result in
                                            Button {
                                                selectedResult = result
                                            } label: {
                                                TrendingCard(result: result)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        }

                        // Empty state when no trending
                        if trendingResults.isEmpty && !isSearching {
                            VStack(spacing: 16) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 50))
                                    .foregroundStyle(.secondary)

                                Text("Search for Movies & TV Shows")
                                    .font(.title3)
                                    .fontWeight(.semibold)

                                Text("Find titles to add to your lists")
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                        }
                    } else if isSearching {
                        ProgressView("Searching...")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                    } else if let error = errorMessage {
                        ContentUnavailableView {
                            Label("Error", systemImage: "exclamationmark.triangle")
                        } description: {
                            Text(error)
                        }
                    } else if searchResults.isEmpty {
                        ContentUnavailableView {
                            Label("No Results", systemImage: "magnifyingglass")
                        } description: {
                            Text("No movies or TV shows found for \"\(searchText)\"")
                        }
                    } else {
                        // Search Results
                        LazyVStack(spacing: 12) {
                            ForEach(searchResults) { result in
                                Button {
                                    selectedResult = result
                                } label: {
                                    SearchResultRow(result: result)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.top)
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
            .task {
                await loadTrending()
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

    private func loadTrending() async {
        do {
            let response = try await TMDbService.shared.getTrending()
            await MainActor.run {
                trendingResults = response.results.filter {
                    $0.resolvedMediaType == "movie" || $0.resolvedMediaType == "tv"
                }
            }
        } catch {
            // Silently fail for trending
        }
    }
}

// MARK: - Trending Card

struct TrendingCard: View {
    let result: TMDbSearchResult

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PosterImageView(posterPath: result.posterPath, size: Constants.TMDb.ImageSize.posterMedium)
                .frame(width: 120, height: 180)
                .cornerRadius(8)

            Text(result.displayTitle)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)
                .frame(width: 120, alignment: .leading)

            HStack(spacing: 4) {
                if let voteAverage = result.voteAverage, voteAverage > 0 {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                    Text(String(format: "%.1f", voteAverage))
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Search Result Row

struct SearchResultRow: View {
    let result: TMDbSearchResult

    var body: some View {
        HStack(spacing: 12) {
            PosterImageView(posterPath: result.posterPath, size: Constants.TMDb.ImageSize.posterSmall)
                .frame(width: 60, height: 90)
                .cornerRadius(6)

            VStack(alignment: .leading, spacing: 4) {
                Text(result.displayTitle)
                    .font(.headline)
                    .lineLimit(2)
                    .foregroundStyle(.primary)

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

            Image(systemName: "plus.circle.fill")
                .font(.title2)
                .foregroundStyle(Color.accentColor)
        }
        .padding()
        .background(Color(.systemGray6).opacity(0.3))
        .cornerRadius(12)
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
            fetchLists()
        } catch {
            print("Error creating list: \(error)")
        }
    }

    private func addToList(_ list: MediaList) {
        isAdding = true

        Task {
            let title = TMDbMapper.mapSearchResult(result, context: viewContext)
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

// MARK: - Profile View

struct ProfileView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var cacheSize = "Calculating..."
    @State private var showingClearCacheAlert = false

    var body: some View {
        NavigationStack {
            List {
                // Stats Section
                Section("Your Stats") {
                    StatsRow()
                }

                // Sync Section
                Section("Sync") {
                    HStack {
                        Label("iCloud Sync", systemImage: "icloud")
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }

                    HStack {
                        Label("Last Sync", systemImage: "clock")
                        Spacer()
                        Text("Just now")
                            .foregroundStyle(.secondary)
                    }
                }

                // Storage Section
                Section("Storage") {
                    HStack {
                        Label("Image Cache", systemImage: "photo.stack")
                        Spacer()
                        Text(cacheSize)
                            .foregroundStyle(.secondary)
                    }

                    Button(role: .destructive) {
                        showingClearCacheAlert = true
                    } label: {
                        Label("Clear Cache", systemImage: "trash")
                    }
                }

                // App Section
                Section("App") {
                    HStack {
                        Label("Version", systemImage: "info.circle")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }

                    Link(destination: URL(string: "https://www.themoviedb.org")!) {
                        HStack {
                            Label("Powered by TMDb", systemImage: "film")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Profile")
            .task {
                cacheSize = await ImageCacheService.shared.formattedDiskCacheSize()
            }
            .alert("Clear Cache", isPresented: $showingClearCacheAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Clear", role: .destructive) {
                    Task {
                        await ImageCacheService.shared.clearAllCaches()
                        cacheSize = await ImageCacheService.shared.formattedDiskCacheSize()
                    }
                }
            } message: {
                Text("This will remove all cached images. They will be re-downloaded as needed.")
            }
        }
    }
}

// MARK: - Stats Row

struct StatsRow: View {
    @FetchRequest(
        sortDescriptors: [],
        predicate: NSPredicate(format: "mediaType == %@", "movie")
    )
    private var movies: FetchedResults<Title>

    @FetchRequest(
        sortDescriptors: [],
        predicate: NSPredicate(format: "mediaType == %@", "tv")
    )
    private var tvShows: FetchedResults<Title>

    @FetchRequest(sortDescriptors: [])
    private var lists: FetchedResults<MediaList>

    var body: some View {
        HStack(spacing: 20) {
            StatItem(value: "\(movies.count)", label: "Movies")
            Divider()
            StatItem(value: "\(tvShows.count)", label: "TV Shows")
            Divider()
            StatItem(value: "\(lists.count)", label: "Lists")
        }
        .padding(.vertical, 8)
    }
}

struct StatItem: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - New List Sheet

struct NewListSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var name: String
    @Binding var icon: String
    @Binding var color: String

    let onCreate: () -> Void

    let icons = ["list.bullet", "star.fill", "heart.fill", "film", "tv", "play.fill", "bookmark.fill", "flag.fill"]
    let colors = ["007AFF", "34C759", "FF3B30", "FF9500", "AF52DE", "5856D6", "FF2D55", "00C7BE"]

    var body: some View {
        NavigationStack {
            Form {
                Section("List Name") {
                    TextField("Enter name", text: $name)
                }

                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 16) {
                        ForEach(icons, id: \.self) { iconName in
                            Button {
                                icon = iconName
                            } label: {
                                Image(systemName: iconName)
                                    .font(.title2)
                                    .frame(width: 44, height: 44)
                                    .background(icon == iconName ? Color.accentColor.opacity(0.3) : Color.clear)
                                    .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 16) {
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

// MARK: - Circular Progress View

struct CircularProgressView: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.3), lineWidth: 3)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Text("\(Int(progress * 100))%")
                .font(.system(size: 8))
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
}
