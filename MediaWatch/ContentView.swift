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
                                        NavigationLink {
                                            TitleDetailView(title: show)
                                        } label: {
                                            ContinueWatchingCard(title: show)
                                        }
                                        .buttonStyle(.plain)
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
                                    NavigationLink {
                                        TitleDetailView(title: title)
                                    } label: {
                                        RecentlyWatchedRow(title: title)
                                    }
                                    .buttonStyle(.plain)
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
                                NavigationLink {
                                    TitleDetailView(title: title)
                                } label: {
                                    TitleGridItem(title: title)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(list.sortedTitles, id: \.objectID) { title in
                                NavigationLink {
                                    TitleDetailView(title: title)
                                } label: {
                                    TitleListRow(title: title)
                                }
                                .buttonStyle(.plain)
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

// MARK: - Title Detail View

struct TitleDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var title: Title

    @State private var showingNotesEditor = false
    @State private var showingListManager = false
    @State private var expandedSynopsis = false
    @State private var expandedSeasons: Set<Int> = []

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // MARK: - Header with Poster
                headerSection

                // MARK: - Content
                VStack(alignment: .leading, spacing: 24) {
                    // Liked Status Toggle
                    likedStatusSection

                    // Basic Info
                    basicInfoSection

                    // Synopsis
                    synopsisSection

                    // Notes
                    notesSection

                    // Progress Section
                    progressSection

                    // Lists Section
                    listsSection

                    // External Links
                    externalLinksSection

                    Spacer(minLength: 100)
                }
                .padding()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        showingNotesEditor = true
                    } label: {
                        Label("Edit Notes", systemImage: "note.text")
                    }
                    Button {
                        showingListManager = true
                    } label: {
                        Label("Manage Lists", systemImage: "list.bullet")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingNotesEditor) {
            NotesEditorSheet(title: title)
        }
        .sheet(isPresented: $showingListManager) {
            ListManagerSheet(title: title)
                .environment(\.managedObjectContext, viewContext)
        }
        .safeAreaInset(edge: .bottom) {
            actionBar
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        ZStack(alignment: .bottom) {
            // Backdrop
            if let backdropPath = title.backdropPath {
                BackdropImageView(backdropPath: backdropPath, size: Constants.TMDb.ImageSize.backdropLarge)
                    .frame(height: 250)
                    .clipped()
                    .overlay {
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 250)
            }

            // Title Info
            HStack(alignment: .bottom, spacing: 16) {
                // Poster
                PosterImageView(posterPath: title.posterPath, size: Constants.TMDb.ImageSize.posterMedium)
                    .frame(width: 100, height: 150)
                    .cornerRadius(8)
                    .shadow(radius: 10)

                // Title and Year
                VStack(alignment: .leading, spacing: 4) {
                    Text(title.title ?? "Unknown")
                        .font(.title2)
                        .fontWeight(.bold)
                        .lineLimit(3)

                    if title.year > 0 {
                        Text("\(title.year)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    // Type badge
                    Text(title.mediaType == "movie" ? "Movie" : "TV Show")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.3))
                        .cornerRadius(4)
                }

                Spacer()
            }
            .padding()
        }
    }

    // MARK: - Liked Status Section

    private var likedStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rating")
                .font(.headline)

            HStack(spacing: 16) {
                LikeButton(
                    icon: "hand.thumbsup.fill",
                    label: "Liked",
                    isSelected: title.likedStatus == 1,
                    color: .green
                ) {
                    title.likedStatus = title.likedStatus == 1 ? 0 : 1
                    try? viewContext.save()
                }

                LikeButton(
                    icon: "minus",
                    label: "Neutral",
                    isSelected: title.likedStatus == 0,
                    color: .gray
                ) {
                    title.likedStatus = 0
                    try? viewContext.save()
                }

                LikeButton(
                    icon: "hand.thumbsdown.fill",
                    label: "Disliked",
                    isSelected: title.likedStatus == -1,
                    color: .red
                ) {
                    title.likedStatus = title.likedStatus == -1 ? 0 : -1
                    try? viewContext.save()
                }
            }
        }
    }

    // MARK: - Basic Info Section

    private var basicInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Info")
                .font(.headline)

            VStack(spacing: 8) {
                // Genres
                if let genres = title.genres, !genres.isEmpty {
                    InfoRow(label: "Genres", value: genres.joined(separator: ", "))
                }

                // Runtime or Seasons
                if title.mediaType == "movie" {
                    if title.runtime > 0 {
                        InfoRow(label: "Runtime", value: "\(title.runtime) min")
                    }
                } else {
                    if title.numberOfSeasons > 0 {
                        InfoRow(label: "Seasons", value: "\(title.numberOfSeasons)")
                    }
                    if title.numberOfEpisodes > 0 {
                        InfoRow(label: "Episodes", value: "\(title.numberOfEpisodes)")
                    }
                }

                // Status
                if let status = title.status, !status.isEmpty {
                    InfoRow(label: "Status", value: status)
                }

                // Last Watched
                if let watchedDate = title.watchedDate {
                    InfoRow(label: "Last Watched", value: watchedDate.formatted(date: .abbreviated, time: .omitted))
                }

                // Vote Average
                if title.voteAverage > 0 {
                    HStack {
                        Text("TMDb Rating")
                            .foregroundStyle(.secondary)
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                            Text(String(format: "%.1f", title.voteAverage))
                        }
                    }
                    .font(.subheadline)
                }
            }
        }
    }

    // MARK: - Synopsis Section

    private var synopsisSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Synopsis")
                .font(.headline)

            if let overview = title.overview, !overview.isEmpty {
                Text(overview)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(expandedSynopsis ? nil : 4)

                if overview.count > 200 {
                    Button {
                        withAnimation {
                            expandedSynopsis.toggle()
                        }
                    } label: {
                        Text(expandedSynopsis ? "Show Less" : "Read More")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    }
                }
            } else {
                Text("No synopsis available")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .italic()
            }
        }
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("My Notes")
                    .font(.headline)
                Spacer()
                Button("Edit") {
                    showingNotesEditor = true
                }
                .font(.subheadline)
            }

            let notesArray = (title.notes as? Set<Note>)?.sorted { $0.dateModified ?? Date() > $1.dateModified ?? Date() } ?? []

            if notesArray.isEmpty {
                Button {
                    showingNotesEditor = true
                } label: {
                    HStack {
                        Image(systemName: "note.text.badge.plus")
                        Text("Add a note...")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGray6).opacity(0.5))
                    .cornerRadius(8)
                }
                .buttonStyle(.plain)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(notesArray.prefix(3), id: \.objectID) { note in
                        Text(note.text ?? "")
                            .font(.body)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(.systemGray6).opacity(0.5))
                            .cornerRadius(8)
                    }
                }
            }
        }
    }

    // MARK: - Progress Section

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Progress")
                .font(.headline)

            if title.mediaType == "movie" {
                // Movie: Simple watched toggle
                movieProgressSection
            } else {
                // TV Show: Episode tracking
                tvShowProgressSection
            }
        }
    }

    private var movieProgressSection: some View {
        VStack(spacing: 12) {
            Button {
                title.watched.toggle()
                if title.watched {
                    title.watchedDate = Date()
                }
                try? viewContext.save()
            } label: {
                HStack {
                    Image(systemName: title.watched ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                    Text(title.watched ? "Watched" : "Mark as Watched")
                        .font(.headline)
                    Spacer()
                    if title.watched, let date = title.watchedDate {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(title.watched ? Color.green.opacity(0.2) : Color(.systemGray6).opacity(0.5))
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .foregroundStyle(title.watched ? .green : .primary)
        }
    }

    private var tvShowProgressSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Episode count
            let episodes = (title.episodes as? Set<Episode>) ?? []
            let watchedCount = episodes.filter { $0.watched }.count
            let totalCount = episodes.count

            if totalCount > 0 {
                HStack {
                    Text("\(watchedCount) of \(totalCount) episodes watched")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(Double(watchedCount) / Double(totalCount) * 100))%")
                        .font(.caption)
                        .fontWeight(.bold)
                }

                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 4)
                            .cornerRadius(2)

                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: geometry.size.width * CGFloat(watchedCount) / CGFloat(totalCount), height: 4)
                            .cornerRadius(2)
                    }
                }
                .frame(height: 4)
            }

            // Seasons list
            let seasons = Dictionary(grouping: episodes) { $0.seasonNumber }
                .sorted { $0.key < $1.key }

            if !seasons.isEmpty {
                ForEach(seasons, id: \.key) { seasonNumber, seasonEpisodes in
                    SeasonSection(
                        seasonNumber: Int(seasonNumber),
                        episodes: seasonEpisodes.sorted { $0.episodeNumber < $1.episodeNumber },
                        isExpanded: expandedSeasons.contains(Int(seasonNumber))
                    ) {
                        if expandedSeasons.contains(Int(seasonNumber)) {
                            expandedSeasons.remove(Int(seasonNumber))
                        } else {
                            expandedSeasons.insert(Int(seasonNumber))
                        }
                    }
                }
            } else {
                Text("No episodes loaded yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .italic()
            }
        }
    }

    // MARK: - Lists Section

    private var listsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("In Lists")
                    .font(.headline)
                Spacer()
                Button("Manage") {
                    showingListManager = true
                }
                .font(.subheadline)
            }

            let listItems = (title.listItems as? Set<ListItem>) ?? []
            let lists = listItems.compactMap { $0.list }

            if lists.isEmpty {
                Text("Not in any list")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(lists, id: \.objectID) { list in
                        HStack(spacing: 4) {
                            Image(systemName: list.displayIcon)
                                .foregroundStyle(list.displayColor)
                            Text(list.displayName)
                        }
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(.systemGray6).opacity(0.5))
                        .cornerRadius(16)
                    }
                }
            }
        }
    }

    // MARK: - External Links Section

    private var externalLinksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("External Links")
                .font(.headline)

            HStack(spacing: 12) {
                // TMDb
                Link(destination: URL(string: "https://www.themoviedb.org/\(title.mediaType ?? "movie")/\(title.tmdbId)")!) {
                    LinkButton(icon: "film", label: "TMDb")
                }

                // IMDb
                if let imdbId = title.imdbId, !imdbId.isEmpty {
                    Link(destination: URL(string: "https://www.imdb.com/title/\(imdbId)")!) {
                        LinkButton(icon: "star", label: "IMDb")
                    }
                }
            }
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 16) {
            // Mark Watched / Next Episode
            Button {
                if title.mediaType == "movie" {
                    title.watched.toggle()
                    if title.watched {
                        title.watchedDate = Date()
                    }
                    try? viewContext.save()
                }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: title.watched ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(.title2)
                    Text(title.mediaType == "movie" ? "Watched" : "Progress")
                        .font(.caption2)
                }
            }
            .foregroundStyle(title.watched ? .green : .primary)

            Spacer()

            // Lists
            Button {
                showingListManager = true
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "list.bullet")
                        .font(.title2)
                    Text("Lists")
                        .font(.caption2)
                }
            }

            Spacer()

            // Notes
            Button {
                showingNotesEditor = true
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "note.text")
                        .font(.title2)
                    Text("Notes")
                        .font(.caption2)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }
}

// MARK: - Supporting Views

struct LikeButton: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title2)
                Text(label)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isSelected ? color.opacity(0.2) : Color(.systemGray6).opacity(0.5))
            .foregroundStyle(isSelected ? color : .secondary)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.subheadline)
    }
}

struct LinkButton: View {
    let icon: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
            Text(label)
                .font(.caption)
        }
        .frame(width: 60, height: 50)
        .background(Color(.systemGray6).opacity(0.5))
        .cornerRadius(8)
    }
}

struct SeasonSection: View {
    @Environment(\.managedObjectContext) private var viewContext
    let seasonNumber: Int
    let episodes: [Episode]
    let isExpanded: Bool
    let onToggle: () -> Void

    var watchedCount: Int {
        episodes.filter { $0.watched }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            // Season header
            Button(action: onToggle) {
                HStack {
                    Text("Season \(seasonNumber)")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Spacer()

                    Text("\(watchedCount)/\(episodes.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color(.systemGray6).opacity(0.3))
                .cornerRadius(isExpanded ? 8 : 8)
            }
            .buttonStyle(.plain)

            // Episodes
            if isExpanded {
                VStack(spacing: 1) {
                    ForEach(episodes, id: \.objectID) { episode in
                        EpisodeRow(episode: episode)
                    }
                }
                .background(Color(.systemGray6).opacity(0.2))
                .cornerRadius(8)
                .padding(.top, 1)
            }
        }
    }
}

struct EpisodeRow: View {
    @Environment(\.managedObjectContext) private var viewContext
    @ObservedObject var episode: Episode

    var body: some View {
        HStack {
            Button {
                episode.watched.toggle()
                if episode.watched {
                    episode.watchedDate = Date()
                }
                try? viewContext.save()
            } label: {
                Image(systemName: episode.watched ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(episode.watched ? .green : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text("E\(episode.episodeNumber) • \(episode.name ?? "Episode")")
                    .font(.subheadline)
                    .lineLimit(1)

                if let airDate = episode.airDate {
                    Text(airDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if episode.runtime > 0 {
                Text("\(episode.runtime)m")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                      y: bounds.minY + result.positions[index].y),
                         proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in width: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)

                if x + size.width > width && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }

                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
            }

            self.size = CGSize(width: width, height: y + rowHeight)
        }
    }
}

// MARK: - Notes Editor Sheet

struct NotesEditorSheet: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var title: Title

    @State private var noteText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Note") {
                    TextEditor(text: $noteText)
                        .frame(minHeight: 200)
                }
            }
            .navigationTitle("Edit Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveNote()
                        dismiss()
                    }
                }
            }
            .onAppear {
                // Load existing note
                if let notes = title.notes as? Set<Note>,
                   let firstNote = notes.first {
                    noteText = firstNote.text ?? ""
                }
            }
        }
    }

    private func saveNote() {
        // Update or create note
        if let notes = title.notes as? Set<Note>,
           let existingNote = notes.first {
            existingNote.text = noteText
            existingNote.dateModified = Date()
        } else if !noteText.isEmpty {
            _ = TMDbMapper.createNote(text: noteText, for: title, context: viewContext)
        }

        try? viewContext.save()
    }
}

// MARK: - List Manager Sheet

struct ListManagerSheet: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var title: Title

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \MediaList.sortOrder, ascending: true)],
        animation: .default
    )
    private var allLists: FetchedResults<MediaList>

    var body: some View {
        NavigationStack {
            List {
                ForEach(allLists) { list in
                    let isInList = titleIsInList(list)

                    Button {
                        toggleList(list)
                    } label: {
                        HStack {
                            Image(systemName: list.displayIcon)
                                .foregroundStyle(list.displayColor)
                                .frame(width: 30)

                            Text(list.displayName)
                                .foregroundStyle(.primary)

                            Spacer()

                            if isInList {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Manage Lists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func titleIsInList(_ list: MediaList) -> Bool {
        guard let listItems = title.listItems as? Set<ListItem> else { return false }
        return listItems.contains { $0.list?.objectID == list.objectID }
    }

    private func toggleList(_ list: MediaList) {
        if titleIsInList(list) {
            // Remove from list
            if let listItems = title.listItems as? Set<ListItem>,
               let item = listItems.first(where: { $0.list?.objectID == list.objectID }) {
                viewContext.delete(item)
            }
        } else {
            // Add to list
            _ = TMDbMapper.addTitle(title, to: list, context: viewContext)
        }

        try? viewContext.save()
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
                SearchResultDetailView(result: result)
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

// MARK: - Search Result Detail View

struct SearchResultDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    let result: TMDbSearchResult

    @State private var showingAddToList = false
    @State private var expandedSynopsis = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Header with backdrop/poster
                    headerSection

                    // Content
                    VStack(alignment: .leading, spacing: 20) {
                        // Basic Info
                        infoSection

                        // Synopsis
                        synopsisSection

                        // TMDb Rating
                        if let voteAverage = result.voteAverage, voteAverage > 0 {
                            ratingSection(voteAverage: voteAverage)
                        }

                        Spacer(minLength: 100)
                    }
                    .padding()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        showingAddToList = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .sheet(isPresented: $showingAddToList) {
                AddToListSheet(result: result)
                    .environment(\.managedObjectContext, viewContext)
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        ZStack(alignment: .bottom) {
            // Backdrop
            if let backdropPath = result.backdropPath {
                BackdropImageView(backdropPath: backdropPath, size: Constants.TMDb.ImageSize.backdropLarge)
                    .frame(height: 220)
                    .clipped()
                    .overlay {
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.8)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 220)
            }

            // Title Info
            HStack(alignment: .bottom, spacing: 16) {
                // Poster
                PosterImageView(posterPath: result.posterPath, size: Constants.TMDb.ImageSize.posterMedium)
                    .frame(width: 100, height: 150)
                    .cornerRadius(8)
                    .shadow(radius: 10)

                // Title and Year
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.displayTitle)
                        .font(.title2)
                        .fontWeight(.bold)
                        .lineLimit(3)

                    if let date = result.displayDate, date.count >= 4 {
                        Text(String(date.prefix(4)))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    // Type badge
                    Text(result.resolvedMediaType == "movie" ? "Movie" : "TV Show")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.3))
                        .cornerRadius(4)
                }

                Spacer()
            }
            .padding()
        }
    }

    // MARK: - Info Section

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Info")
                .font(.headline)

            HStack {
                Text("Type")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(result.resolvedMediaType == "movie" ? "Movie" : "TV Show")
            }
            .font(.subheadline)

            if let date = result.displayDate {
                HStack {
                    Text(result.resolvedMediaType == "movie" ? "Release Date" : "First Aired")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(date)
                }
                .font(.subheadline)
            }

            if let language = result.originalLanguage {
                HStack {
                    Text("Language")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(language.uppercased())
                }
                .font(.subheadline)
            }
        }
    }

    // MARK: - Synopsis Section

    private var synopsisSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Synopsis")
                .font(.headline)

            if let overview = result.overview, !overview.isEmpty {
                Text(overview)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(expandedSynopsis ? nil : 5)

                if overview.count > 200 {
                    Button {
                        withAnimation {
                            expandedSynopsis.toggle()
                        }
                    } label: {
                        Text(expandedSynopsis ? "Show Less" : "Read More")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    }
                }
            } else {
                Text("No synopsis available")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .italic()
            }
        }
    }

    // MARK: - Rating Section

    private func ratingSection(voteAverage: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TMDb Rating")
                .font(.headline)

            HStack(spacing: 8) {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .font(.title2)

                Text(String(format: "%.1f", voteAverage))
                    .font(.title2)
                    .fontWeight(.bold)

                Text("/ 10")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let voteCount = result.voteCount, voteCount > 0 {
                    Text("(\(voteCount) votes)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
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
