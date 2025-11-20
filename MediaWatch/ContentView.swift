//
//  ContentView.swift
//  MediaWatch
//
//  Main content view with tab navigation - Letterboxd-inspired design
//

import SwiftUI
import CoreData
import CloudKit

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

// MARK: - Watch Status Enum

enum WatchStatus: Int16, CaseIterable {
    case current = 0
    case new = 1
    case paused = 2
    case maybe = 3
    case finished = 4

    var label: String {
        switch self {
        case .current: return "Current"
        case .new: return "New"
        case .paused: return "Paused"
        case .maybe: return "Maybe"
        case .finished: return "Finished"
        }
    }

    var icon: String {
        switch self {
        case .current: return "play.circle.fill"
        case .new: return "sparkles"
        case .paused: return "pause.circle.fill"
        case .maybe: return "questionmark.circle"
        case .finished: return "checkmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .current: return .blue
        case .new: return .green
        case .paused: return .orange
        case .maybe: return .purple
        case .finished: return .gray
        }
    }
}

// MARK: - Title Extension for Next Episode

extension Title {
    /// Returns the next unwatched episode (first by season, then by episode number)
    var nextUnwatchedEpisode: (season: Int16, episode: Int16)? {
        guard let episodes = episodes as? Set<Episode>, !episodes.isEmpty else {
            return nil
        }

        // Sort episodes by season then episode number
        let sortedEpisodes = episodes.sorted { first, second in
            if first.seasonNumber != second.seasonNumber {
                return first.seasonNumber < second.seasonNumber
            }
            return first.episodeNumber < second.episodeNumber
        }

        // Find first unwatched episode
        if let nextEpisode = sortedEpisodes.first(where: { !$0.watched }) {
            return (nextEpisode.seasonNumber, nextEpisode.episodeNumber)
        }

        // All episodes watched - return nil or last episode
        return nil
    }

    /// Display string for next episode badge
    var nextEpisodeBadge: String {
        if let next = nextUnwatchedEpisode {
            return "S\(next.season) E\(next.episode)"
        }
        // Fallback to current tracking values if no episodes loaded
        return "S\(currentSeason) E\(currentEpisode)"
    }

    /// Get the streaming service enum value
    var streamingServiceEnum: StreamingService {
        guard let serviceName = streamingService, !serviceName.isEmpty else {
            return .none
        }
        return StreamingService(rawValue: serviceName) ?? .other
    }

    /// Get cast members from stored data
    var castMembers: [CastMember] {
        guard let data = castData else { return [] }
        do {
            return try JSONDecoder().decode([CastMember].self, from: data)
        } catch {
            return []
        }
    }

    /// Set cast members to stored data
    func setCast(_ members: [CastMember]) {
        do {
            castData = try JSONEncoder().encode(members)
        } catch {
            castData = nil
        }
    }

    /// Get cast names for searching
    var castNames: [String] {
        castMembers.map { $0.name }
    }
}

// MARK: - Home View (Dashboard)

enum HomeViewMode: String, CaseIterable {
    case carousel = "carousel"
    case grid = "grid"
    case list = "list"
}

struct HomeView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @State private var viewMode: HomeViewMode = .carousel

    // Fetch Current titles
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Title.dateModified, ascending: false)],
        predicate: NSPredicate(format: "watchStatus == %d", WatchStatus.current.rawValue),
        animation: .default
    )
    private var currentTitles: FetchedResults<Title>

    // Fetch New titles
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Title.dateModified, ascending: false)],
        predicate: NSPredicate(format: "watchStatus == %d", WatchStatus.new.rawValue),
        animation: .default
    )
    private var newTitles: FetchedResults<Title>

    // Fetch Paused titles
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Title.dateModified, ascending: false)],
        predicate: NSPredicate(format: "watchStatus == %d", WatchStatus.paused.rawValue),
        animation: .default
    )
    private var pausedTitles: FetchedResults<Title>

    // Fetch Maybe titles
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Title.dateModified, ascending: false)],
        predicate: NSPredicate(format: "watchStatus == %d", WatchStatus.maybe.rawValue),
        animation: .default
    )
    private var maybeTitles: FetchedResults<Title>

    // Fetch Finished titles
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \Title.dateModified, ascending: false)],
        predicate: NSPredicate(format: "watchStatus == %d", WatchStatus.finished.rawValue),
        animation: .default
    )
    private var finishedTitles: FetchedResults<Title>

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {

                    // Current Section
                    if !currentTitles.isEmpty {
                        statusSection(
                            status: .current,
                            titles: Array(currentTitles)
                        )
                    }

                    // New Section
                    if !newTitles.isEmpty {
                        statusSection(
                            status: .new,
                            titles: Array(newTitles)
                        )
                    }

                    // Paused Section
                    if !pausedTitles.isEmpty {
                        statusSection(
                            status: .paused,
                            titles: Array(pausedTitles)
                        )
                    }

                    // Maybe Section
                    if !maybeTitles.isEmpty {
                        statusSection(
                            status: .maybe,
                            titles: Array(maybeTitles)
                        )
                    }

                    // Finished Section
                    if !finishedTitles.isEmpty {
                        statusSection(
                            status: .finished,
                            titles: Array(finishedTitles)
                        )
                    }

                    // Empty State
                    if currentTitles.isEmpty && newTitles.isEmpty && pausedTitles.isEmpty && maybeTitles.isEmpty && finishedTitles.isEmpty {
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            viewMode = .carousel
                        } label: {
                            Label("Carousel", systemImage: "rectangle.split.1x2")
                            if viewMode == .carousel {
                                Image(systemName: "checkmark")
                            }
                        }
                        Button {
                            viewMode = .grid
                        } label: {
                            Label("Grid", systemImage: "square.grid.2x2")
                            if viewMode == .grid {
                                Image(systemName: "checkmark")
                            }
                        }
                        Button {
                            viewMode = .list
                        } label: {
                            Label("List", systemImage: "list.bullet")
                            if viewMode == .list {
                                Image(systemName: "checkmark")
                            }
                        }
                    } label: {
                        Image(systemName: viewMode == .carousel ? "rectangle.split.1x2" : (viewMode == .grid ? "square.grid.2x2" : "list.bullet"))
                    }
                }
            }
        }
    }

    private func statusSection(status: WatchStatus, titles: [Title]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: status.icon)
                    .foregroundStyle(status.color)
                Text(status.label)
                    .font(.title2)
                    .fontWeight(.bold)
            }
            .padding(.horizontal)

            switch viewMode {
            case .carousel:
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 16) {
                        ForEach(titles.prefix(10)) { title in
                            NavigationLink {
                                TitleDetailView(title: title)
                            } label: {
                                ContinueWatchingCard(title: title)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal)
                }

            case .grid:
                LazyVGrid(columns: [
                    GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 16)
                ], alignment: .leading, spacing: 16) {
                    ForEach(titles) { title in
                        NavigationLink {
                            TitleDetailView(title: title)
                        } label: {
                            VStack(alignment: .leading) {
                                PosterImageView(posterPath: title.posterPath, size: Constants.TMDb.ImageSize.posterMedium)
                                    .frame(height: 150)
                                    .cornerRadius(8)

                                Text(title.title ?? "Unknown")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .lineLimit(2)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)

            case .list:
                VStack(spacing: 0) {
                    ForEach(titles) { title in
                        NavigationLink {
                            TitleDetailView(title: title)
                        } label: {
                            HStack(spacing: 12) {
                                PosterImageView(posterPath: title.posterPath, size: Constants.TMDb.ImageSize.posterSmall)
                                    .frame(width: 50, height: 75)
                                    .cornerRadius(4)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(title.title ?? "Unknown")
                                        .font(.headline)
                                        .lineLimit(1)

                                    if title.mediaType == "tv" {
                                        Text(title.nextEpisodeBadge)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    if let genres = title.genres, !genres.isEmpty {
                                        Text(genres.prefix(2).joined(separator: ", "))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }

                                Spacer()

                                if title.streamingServiceEnum != .none {
                                    Text(title.streamingServiceEnum.displayName)
                                        .font(.caption2)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                        .background(Color(hex: title.streamingServiceEnum.color))
                                        .foregroundStyle(.white)
                                        .cornerRadius(3)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
                .padding(.horizontal)
            }
        }
    }
}

// MARK: - Continue Watching Card

struct ContinueWatchingCard: View {
    @ObservedObject var title: Title

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                PosterImageView(posterPath: title.posterPath, size: Constants.TMDb.ImageSize.posterMedium)
                    .frame(width: 120, height: 180)
                    .cornerRadius(8)

                VStack {
                    // Streaming service badge at top
                    if title.streamingServiceEnum != .none {
                        HStack {
                            Spacer()
                            Text(title.streamingServiceEnum.displayName)
                                .font(.system(size: 8, weight: .bold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color(hex: title.streamingServiceEnum.color))
                                .foregroundStyle(.white)
                                .cornerRadius(3)
                                .padding(4)
                        }
                    }
                    Spacer()
                    // Season/Episode badge for TV shows - next unwatched
                    if title.mediaType == "tv" {
                        HStack {
                            Text(title.nextEpisodeBadge)
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(.ultraThinMaterial)
                                .cornerRadius(4)
                                .padding(6)
                            Spacer()
                        }
                    }
                }
            }

            Text(title.title ?? "Unknown")
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)
                .frame(width: 120, alignment: .leading)
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
                        Text(String(title.year))
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

                // Shared/Private indicator
                Image(systemName: list.isShared ? "person.2.fill" : "lock.fill")
                    .font(.caption)
                    .foregroundStyle(list.isShared ? .blue : .secondary)

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

// Sort and Group Options
enum ListSortOption: String, CaseIterable {
    case added = "added"
    case updated = "updated"
    case alpha = "alpha"
    case started = "started"
    case lastWatched = "lastWatched"
    case stars = "stars"

    var label: String {
        switch self {
        case .added: return "Date Added"
        case .updated: return "Date Updated"
        case .alpha: return "Alphabetical"
        case .started: return "Started"
        case .lastWatched: return "Last Watched"
        case .stars: return "Rating"
        }
    }

    var icon: String {
        switch self {
        case .added: return "plus.circle"
        case .updated: return "clock.arrow.circlepath"
        case .alpha: return "textformat.abc"
        case .started: return "calendar"
        case .lastWatched: return "eye"
        case .stars: return "star"
        }
    }
}

enum ListGroupOption: String, CaseIterable {
    case none = "none"
    case watchStatus = "watchStatus"
    case provider = "provider"

    var label: String {
        switch self {
        case .none: return "None"
        case .watchStatus: return "Watch Status"
        case .provider: return "Provider"
        }
    }

    var icon: String {
        switch self {
        case .none: return "rectangle.grid.1x2"
        case .watchStatus: return "eye"
        case .provider: return "play.tv"
        }
    }
}

struct ListDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var persistenceController: PersistenceController
    @ObservedObject var list: MediaList

    @State private var viewMode: ViewMode = .grid
    @State private var showShareSheet = false
    @State private var share: CKShare?
    @State private var isPreparingShare = false
    @State private var shareError: String?

    // Sort, Group, Filter
    @State private var sortOption: ListSortOption = .added
    @State private var sortAscending = false
    @State private var groupOption: ListGroupOption = .none
    @State private var selectedWatchFilters: Set<Int16> = []
    @State private var showFilterSheet = false
    @State private var showSortMenu = false
    @State private var showGroupMenu = false

    // Rename and Delete
    @State private var showRenameAlert = false
    @State private var newListName = ""
    @State private var showDeleteConfirmation = false

    enum ViewMode {
        case grid, list
    }

    // Filtered and sorted titles
    private var processedTitles: [Title] {
        var titles = list.sortedTitles

        // Apply filters
        if !selectedWatchFilters.isEmpty {
            titles = titles.filter { selectedWatchFilters.contains($0.watchStatus) }
        }

        // Apply sorting
        titles = titles.sorted { first, second in
            let result: Bool
            switch sortOption {
            case .added:
                result = (first.dateAdded ?? Date.distantPast) > (second.dateAdded ?? Date.distantPast)
            case .updated:
                result = (first.dateModified ?? Date.distantPast) > (second.dateModified ?? Date.distantPast)
            case .alpha:
                result = (first.title ?? "") < (second.title ?? "")
            case .started:
                result = (first.startDate ?? Date.distantPast) > (second.startDate ?? Date.distantPast)
            case .lastWatched:
                result = (first.lastWatched ?? Date.distantPast) > (second.lastWatched ?? Date.distantPast)
            case .stars:
                let firstAvg = (first.lauraRating + first.mikeRating) / 2.0
                let secondAvg = (second.lauraRating + second.mikeRating) / 2.0
                result = firstAvg > secondAvg
            }
            return sortAscending ? !result : result
        }

        return titles
    }

    // Grouped titles
    private var groupedTitles: [(key: String, titles: [Title])] {
        let titles = processedTitles

        switch groupOption {
        case .none:
            return [("", titles)]
        case .watchStatus:
            let grouped = Dictionary(grouping: titles) { title in
                WatchStatus(rawValue: title.watchStatus)?.label ?? "Unknown"
            }
            // Sort groups by watch status order
            let order = ["Current", "New", "Paused", "Maybe", "Finished"]
            return grouped.sorted { first, second in
                let firstIndex = order.firstIndex(of: first.key) ?? 99
                let secondIndex = order.firstIndex(of: second.key) ?? 99
                return firstIndex < secondIndex
            }.map { (key: $0.key, titles: $0.value) }
        case .provider:
            let grouped = Dictionary(grouping: titles) { title in
                title.streamingService ?? "None"
            }
            return grouped.sorted { $0.key < $1.key }.map { (key: $0.key, titles: $0.value) }
        }
    }

    // Active filter count
    private var activeFilterCount: Int {
        selectedWatchFilters.count
    }

    var body: some View {
        Group {
            if list.titleCount == 0 {
                ContentUnavailableView {
                    Label("Empty List", systemImage: "list.bullet")
                } description: {
                    Text("Search for titles to add to this list")
                }
            } else if processedTitles.isEmpty {
                ContentUnavailableView {
                    Label("No Results", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("No titles match your current filters")
                } actions: {
                    Button("Clear Filters") {
                        selectedWatchFilters.removeAll()
                    }
                }
            } else {
                ScrollView {
                    if viewMode == .grid {
                        LazyVStack(alignment: .leading, spacing: 20) {
                            ForEach(groupedTitles, id: \.key) { group in
                                VStack(alignment: .leading, spacing: 12) {
                                    // Group header
                                    if !group.key.isEmpty {
                                        Text(group.key)
                                            .font(.headline)
                                            .fontWeight(.bold)
                                            .padding(.horizontal)
                                    }

                                    LazyVGrid(columns: [
                                        GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 16)
                                    ], spacing: 16) {
                                        ForEach(group.titles, id: \.objectID) { title in
                                            NavigationLink {
                                                TitleDetailView(title: title)
                                            } label: {
                                                TitleGridItem(title: title)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        }
                        .padding(.vertical)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(groupedTitles, id: \.key) { group in
                                VStack(alignment: .leading, spacing: 8) {
                                    // Group header
                                    if !group.key.isEmpty {
                                        Text(group.key)
                                            .font(.headline)
                                            .fontWeight(.bold)
                                            .padding(.horizontal)
                                            .padding(.top, 8)
                                    }

                                    ForEach(group.titles, id: \.objectID) { title in
                                        NavigationLink {
                                            TitleDetailView(title: title)
                                        } label: {
                                            TitleListRow(title: title)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
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
            ToolbarItemGroup(placement: .primaryAction) {
                // Sort menu
                Menu {
                    Picker("Sort", selection: $sortOption) {
                        ForEach(ListSortOption.allCases, id: \.self) { option in
                            Label(option.label, systemImage: option.icon)
                                .tag(option)
                        }
                    }

                    Divider()

                    Button {
                        sortAscending.toggle()
                    } label: {
                        Label(
                            sortAscending ? "Ascending" : "Descending",
                            systemImage: sortAscending ? "arrow.up" : "arrow.down"
                        )
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }

                // Group menu
                Menu {
                    Picker("Group", selection: $groupOption) {
                        ForEach(ListGroupOption.allCases, id: \.self) { option in
                            Label(option.label, systemImage: option.icon)
                                .tag(option)
                        }
                    }
                } label: {
                    Image(systemName: groupOption == .none ? "rectangle.3.group" : "rectangle.3.group.fill")
                }

                // Filter button
                Button {
                    showFilterSheet = true
                } label: {
                    Image(systemName: activeFilterCount > 0 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }

                // More options menu
                Menu {
                    // View mode
                    Button {
                        viewMode = viewMode == .grid ? .list : .grid
                    } label: {
                        Label(
                            viewMode == .grid ? "List View" : "Grid View",
                            systemImage: viewMode == .grid ? "list.bullet" : "square.grid.2x2"
                        )
                    }

                    Divider()

                    // Rename
                    Button {
                        newListName = list.name ?? ""
                        showRenameAlert = true
                    } label: {
                        Label("Rename List", systemImage: "pencil")
                    }

                    // Share
                    Button {
                        Task {
                            await prepareShare()
                        }
                    } label: {
                        if isPreparingShare {
                            Label("Preparing...", systemImage: "hourglass")
                        } else {
                            Label(
                                persistenceController.isShared(list) ? "Manage Sharing" : "Share List",
                                systemImage: persistenceController.isShared(list) ? "person.2.fill" : "person.badge.plus"
                            )
                        }
                    }
                    .disabled(isPreparingShare)

                    Divider()

                    // Delete
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete List", systemImage: "trash")
                    }
                    .disabled(list.isDefault)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let share = share {
                CloudSharingView(
                    share: share,
                    container: CKContainer(identifier: "iCloud.com.mediawatch.app"),
                    list: list
                )
            }
        }
        .alert("Sharing Error", isPresented: .constant(shareError != nil)) {
            Button("OK") {
                shareError = nil
            }
        } message: {
            if let error = shareError {
                Text(error)
            }
        }
        .sheet(isPresented: $showFilterSheet) {
            FilterSheetView(
                selectedWatchFilters: $selectedWatchFilters
            )
        }
        .alert("Rename List", isPresented: $showRenameAlert) {
            TextField("List name", text: $newListName)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                if !newListName.isEmpty {
                    list.name = newListName
                    list.dateModified = Date()
                    try? viewContext.save()
                }
            }
        } message: {
            Text("Enter a new name for this list")
        }
        .alert("Delete List", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                viewContext.delete(list)
                try? viewContext.save()
                dismiss()
            }
        } message: {
            Text("Are you sure you want to delete \"\(list.name ?? "this list")\"? This action cannot be undone.")
        }
    }

    private func prepareShare() async {
        isPreparingShare = true

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
                isPreparingShare = false
                showShareSheet = true
            }
        } catch {
            await MainActor.run {
                isPreparingShare = false
                shareError = "Failed to create share: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Filter Sheet View

struct FilterSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedWatchFilters: Set<Int16>

    var body: some View {
        NavigationStack {
            List {
                // Watch Status Filters
                Section("Watch Status") {
                    ForEach(WatchStatus.allCases, id: \.rawValue) { status in
                        WatchFilterRow(status: status, selectedFilters: $selectedWatchFilters)
                    }
                }
            }
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear All") {
                        selectedWatchFilters.removeAll()
                    }
                    .disabled(selectedWatchFilters.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

struct WatchFilterRow: View {
    let status: WatchStatus
    @Binding var selectedFilters: Set<Int16>

    var body: some View {
        Button {
            if selectedFilters.contains(status.rawValue) {
                selectedFilters.remove(status.rawValue)
            } else {
                selectedFilters.insert(status.rawValue)
            }
        } label: {
            HStack {
                Image(systemName: status.icon)
                    .foregroundStyle(status.color)
                Text(status.label)
                    .foregroundStyle(.primary)
                Spacer()
                if selectedFilters.contains(status.rawValue) {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
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
            ZStack {
                PosterImageView(posterPath: title.posterPath, size: Constants.TMDb.ImageSize.posterMedium)
                    .aspectRatio(2/3, contentMode: .fit)
                    .cornerRadius(8)

                VStack {
                    HStack {
                        // Streaming service badge at top left
                        if title.streamingServiceEnum != .none {
                            Text(title.streamingServiceEnum.displayName)
                                .font(.system(size: 7, weight: .bold))
                                .padding(.horizontal, 3)
                                .padding(.vertical, 2)
                                .background(Color(hex: title.streamingServiceEnum.color))
                                .foregroundStyle(.white)
                                .cornerRadius(3)
                                .padding(4)
                        }
                        Spacer()
                        // Watch status icon at top right
                        let status = WatchStatus(rawValue: title.watchStatus) ?? .new
                        Image(systemName: status.icon)
                            .font(.caption)
                            .foregroundStyle(status.color)
                            .padding(4)
                            .background(Circle().fill(.ultraThinMaterial))
                            .padding(4)
                    }
                    Spacer()
                    // Season/Episode badge for TV shows - next unwatched
                    if title.mediaType == "tv" {
                        HStack {
                            Text(title.nextEpisodeBadge)
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(.ultraThinMaterial)
                                .cornerRadius(4)
                                .padding(6)
                            Spacer()
                        }
                    }
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
                        Text(String(title.year))
                    }
                    // Show next unwatched episode for TV shows
                    if title.mediaType == "tv" {
                        Text("•")
                        Text(title.nextEpisodeBadge)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                // Streaming service and liked status
                HStack(spacing: 4) {
                    if title.streamingServiceEnum != .none {
                        Text(title.streamingServiceEnum.displayName)
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color(hex: title.streamingServiceEnum.color))
                            .foregroundStyle(.white)
                            .cornerRadius(3)
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
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var title: Title

    @State private var showingNotesEditor = false
    @State private var showingListManager = false
    @State private var expandedSynopsis = false
    @State private var expandedSeasons: Set<Int> = []
    @State private var allSeasonsHidden = true
    @State private var isLoadingEpisodes = false
    @State private var episodeLoadError: String?
    @State private var showingDeleteConfirmation = false
    @State private var episodeRefreshTrigger = false
    @State private var availableProviders: [TMDbWatchProvider] = []
    @State private var isLoadingProviders = false
    @State private var showingStreamingPicker = false
    @State private var isLoadingCast = false
    @State private var expandedCast = false

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    // MARK: - Header with Poster
                    headerSection
                        .frame(width: geometry.size.width)

                    // MARK: - Content
                    VStack(alignment: .leading, spacing: 24) {
                        // Watch Status
                        watchStatusSection

                        // Dates Section (Started and Last Watched)
                        datesSection

                        // Ratings
                        ratingsSection

                        // Basic Info
                        basicInfoSection

                        // Streaming Service
                        streamingServiceSection

                        // Synopsis
                        synopsisSection

                        // Cast
                        castSection

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
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .frame(width: geometry.size.width)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
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

                    Divider()

                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .alert("Delete Title", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                deleteTitle()
            }
        } message: {
            Text("Are you sure you want to delete \"\(title.title ?? "this title")\"? This will remove it from all lists and delete all associated notes and episode data.")
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
                    HStack(alignment: .top) {
                        Text(title.title ?? "Unknown")
                            .font(.title2)
                            .fontWeight(.bold)
                            .lineLimit(3)

                        Spacer()

                        // Favorite star
                        Button {
                            title.isFavorite.toggle()
                            try? viewContext.save()
                        } label: {
                            Image(systemName: title.isFavorite ? "star.fill" : "star")
                                .font(.title2)
                                .foregroundStyle(title.isFavorite ? .yellow : .secondary)
                        }
                    }

                    if title.year > 0 {
                        Text(String(title.year))
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
            }
            .padding()
        }
    }

    // MARK: - Watch Status Section

    private var watchStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Watch Status")
                .font(.headline)

            HStack(spacing: 12) {
                ForEach(WatchStatus.allCases, id: \.rawValue) { status in
                    Button {
                        title.watchStatus = status.rawValue
                        title.dateModified = Date()
                        try? viewContext.save()
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: status.icon)
                                .font(.title2)
                            Text(status.label)
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(title.watchStatus == status.rawValue ? status.color.opacity(0.2) : Color(.systemGray6).opacity(0.5))
                        .foregroundStyle(title.watchStatus == status.rawValue ? status.color : .secondary)
                        .cornerRadius(12)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Dates Section

    private var datesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Started date
            HStack {
                Text("Started")
                    .foregroundStyle(.secondary)
                Spacer()
                if title.startDate != nil {
                    DatePicker("", selection: Binding(
                        get: { title.startDate ?? Date() },
                        set: { newValue in
                            title.startDate = newValue
                            try? viewContext.save()
                        }
                    ), displayedComponents: .date)
                    .labelsHidden()

                    Button {
                        title.startDate = nil
                        try? viewContext.save()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button("Set") {
                        title.startDate = Date()
                        try? viewContext.save()
                    }
                    .font(.subheadline)
                }
            }
            .font(.subheadline)

            // Last Watched date
            HStack {
                Text("Last Watched")
                    .foregroundStyle(.secondary)
                Spacer()
                if title.lastWatched != nil {
                    DatePicker("", selection: Binding(
                        get: { title.lastWatched ?? Date() },
                        set: { newValue in
                            title.lastWatched = newValue
                            try? viewContext.save()
                        }
                    ), displayedComponents: .date)
                    .labelsHidden()

                    Button {
                        title.lastWatched = nil
                        try? viewContext.save()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button("Set") {
                        title.lastWatched = Date()
                        try? viewContext.save()
                    }
                    .font(.subheadline)
                }
            }
            .font(.subheadline)
        }
    }

    // MARK: - Ratings Section

    private var ratingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ratings")
                .font(.headline)

                // Laura Rating
                HStack {
                    Text("Laura")
                        .frame(width: 50, alignment: .leading)
                    StarRatingView(rating: Binding(
                        get: { title.lauraRating },
                        set: { newValue in
                            title.lauraRating = newValue
                            try? viewContext.save()
                        }
                    ))
                    Spacer()
                    if title.lauraRating > 0 {
                        Text(String(format: "%.1f", title.lauraRating))
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                }

                // Mike Rating
                HStack {
                    Text("Mike")
                        .frame(width: 50, alignment: .leading)
                    StarRatingView(rating: Binding(
                        get: { title.mikeRating },
                        set: { newValue in
                            title.mikeRating = newValue
                            try? viewContext.save()
                        }
                    ))
                    Spacer()
                    if title.mikeRating > 0 {
                        Text(String(format: "%.1f", title.mikeRating))
                            .font(.title2)
                            .fontWeight(.bold)
                    }
                }

                // Average Rating
                if title.lauraRating > 0 || title.mikeRating > 0 {
                    HStack {
                        Text("Avg")
                            .frame(width: 50, alignment: .leading)
                        let avgRating = (title.lauraRating > 0 && title.mikeRating > 0)
                            ? (title.lauraRating + title.mikeRating) / 2.0
                            : (title.lauraRating > 0 ? title.lauraRating : title.mikeRating)
                        ForEach(1...5, id: \.self) { star in
                            Image(systemName: Double(star) <= avgRating ? "star.fill" : (Double(star) - 0.5 <= avgRating ? "star.leadinghalf.filled" : "star"))
                                .font(.title2)
                                .foregroundStyle(.yellow)
                        }
                        Spacer()
                        Text(String(format: "%.1f", avgRating))
                            .font(.title2)
                            .fontWeight(.bold)
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
                // Media Category (for TV) - at top with bold styling
                if title.mediaType == "tv" {
                    HStack {
                        Text("Category")
                            .fontWeight(.bold)
                            .foregroundStyle(colorScheme == .dark ? Color.orange : Color.blue)
                        Spacer()
                        Menu {
                            Button("None") {
                                title.mediaCategory = nil
                                try? viewContext.save()
                            }
                            Button("Series") {
                                title.mediaCategory = "Series"
                                try? viewContext.save()
                            }
                            Button("Limited Series") {
                                title.mediaCategory = "Limited Series"
                                try? viewContext.save()
                            }
                            Button("TV Show") {
                                title.mediaCategory = "TV Show"
                                try? viewContext.save()
                            }
                            Button("TV Movie") {
                                title.mediaCategory = "TV Movie"
                                try? viewContext.save()
                            }
                        } label: {
                            Text(title.mediaCategory ?? "Select")
                                .fontWeight(.bold)
                                .foregroundColor(title.mediaCategory == nil ? .secondary : (colorScheme == .dark ? Color.orange : Color.blue))
                        }
                    }
                    .font(.subheadline)
                }

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

    // MARK: - Streaming Service Section

    private var streamingServiceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Where to Watch")
                .font(.headline)

            HStack {
                // Current streaming service
                Button {
                    showingStreamingPicker = true
                } label: {
                    HStack {
                        let service = title.streamingServiceEnum
                        if service != .none {
                            Text(service.displayName)
                                .font(.subheadline)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(hex: service.color))
                                .foregroundStyle(.white)
                                .cornerRadius(6)
                        } else {
                            Label("Select Service", systemImage: "tv")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }

            // TMDb providers
            if !availableProviders.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Available on")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(availableProviders) { provider in
                                Button {
                                    let service = StreamingService.from(tmdbName: provider.providerName)
                                    title.streamingService = service.rawValue
                                    try? viewContext.save()
                                } label: {
                                    Text(provider.providerName)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color(.systemGray5))
                                        .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            } else if isLoadingProviders {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading providers...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .sheet(isPresented: $showingStreamingPicker) {
            StreamingServicePicker(selectedService: Binding(
                get: { title.streamingService ?? "" },
                set: { newValue in
                    title.streamingService = newValue
                    try? viewContext.save()
                }
            ))
        }
        .task {
            await loadWatchProviders()
        }
    }

    private func loadWatchProviders() async {
        isLoadingProviders = true
        do {
            let response: TMDbWatchProvidersResponse
            if title.mediaType == "movie" {
                response = try await TMDbService.shared.getMovieWatchProviders(id: Int(title.tmdbId))
            } else {
                response = try await TMDbService.shared.getTVWatchProviders(id: Int(title.tmdbId))
            }

            // Get US providers (or first available region)
            if let usProviders = response.results["US"] {
                var providers: [TMDbWatchProvider] = []
                if let flatrate = usProviders.flatrate {
                    providers.append(contentsOf: flatrate)
                }
                if let free = usProviders.free {
                    providers.append(contentsOf: free)
                }
                if let ads = usProviders.ads {
                    providers.append(contentsOf: ads)
                }
                // Remove duplicates by provider ID
                var seen = Set<Int>()
                providers = providers.filter { seen.insert($0.providerId).inserted }
                // Sort by priority
                providers.sort { $0.displayPriority < $1.displayPriority }
                await MainActor.run {
                    availableProviders = providers
                }
            }
        } catch {
            // Silently fail - providers are optional
            print("Failed to load watch providers: \(error)")
        }
        await MainActor.run {
            isLoadingProviders = false
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

    // MARK: - Cast Section

    private var castSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation {
                    expandedCast.toggle()
                }
            } label: {
                HStack {
                    Text("Cast")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    if isLoadingCast {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: expandedCast ? "chevron.up" : "chevron.down")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)

            if expandedCast {
                let cast = title.castMembers
                if cast.isEmpty {
                    if !isLoadingCast {
                        Button("Load Cast") {
                            Task {
                                await loadCast()
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(Color.accentColor)
                    }
                } else {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(cast.prefix(20)) { member in
                            HStack(spacing: 12) {
                                // Profile image placeholder
                                if let profilePath = member.profilePath {
                                    AsyncImage(url: TMDbService.profileURL(path: profilePath)) { image in
                                        image
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                    } placeholder: {
                                        Color.gray.opacity(0.3)
                                    }
                                    .frame(width: 40, height: 40)
                                    .clipShape(Circle())
                                } else {
                                    Image(systemName: "person.circle.fill")
                                        .font(.title)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 40, height: 40)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(member.name)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    if !member.character.isEmpty {
                                        Text(member.character)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .task {
            if title.castMembers.isEmpty {
                await loadCast()
            }
        }
    }

    private func loadCast() async {
        isLoadingCast = true
        do {
            let credits: TMDbCreditsResponse
            if title.mediaType == "movie" {
                credits = try await TMDbService.shared.getMovieCredits(id: Int(title.tmdbId))
            } else {
                credits = try await TMDbService.shared.getTVCredits(id: Int(title.tmdbId))
            }

            let castMembers = credits.cast.prefix(20).map { CastMember(from: $0) }
            await MainActor.run {
                title.setCast(Array(castMembers))
                try? viewContext.save()
                isLoadingCast = false
            }
        } catch {
            await MainActor.run {
                isLoadingCast = false
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
        let episodes = (title.episodes as? Set<Episode>) ?? []
        let sortedEpisodes = episodes.sorted {
            $0.seasonNumber == $1.seasonNumber
                ? $0.episodeNumber < $1.episodeNumber
                : $0.seasonNumber < $1.seasonNumber
        }
        let seasons = Dictionary(grouping: sortedEpisodes) { Int($0.seasonNumber) }
            .sorted { $0.key < $1.key }
        let watchedCount = episodes.filter { $0.watched }.count
        let totalCount = episodes.count

        return VStack(alignment: .leading, spacing: 12) {
            // Episode progress summary
            if totalCount > 0 {
                HStack {
                    Text("\(watchedCount) of \(totalCount) episodes")
                        .font(.subheadline)
                    Spacer()
                    Text("\(Int(Double(watchedCount) / Double(totalCount) * 100))%")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(watchedCount == totalCount ? .green : .primary)
                }

                // Progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 4)
                            .cornerRadius(2)

                        Rectangle()
                            .fill(watchedCount == totalCount ? Color.green : Color.accentColor)
                            .frame(width: geometry.size.width * CGFloat(watchedCount) / CGFloat(max(totalCount, 1)), height: 4)
                            .cornerRadius(2)
                    }
                }
                .frame(height: 4)
            }

            // Load/Refresh Episodes Button
            Button {
                loadEpisodes()
            } label: {
                HStack {
                    if isLoadingEpisodes {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: episodes.isEmpty ? "arrow.down.circle" : "arrow.clockwise")
                    }
                    Text(episodes.isEmpty ? "Load Episodes" : "Refresh Episodes")
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color(.systemGray6).opacity(0.5))
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .disabled(isLoadingEpisodes)

            // Error message
            if let error = episodeLoadError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            // Seasons list with episodes
            if !seasons.isEmpty {
                // Expand/Collapse All buttons
                HStack {
                    Button {
                        withAnimation {
                            allSeasonsHidden = false
                            expandedSeasons = Set(seasons.map { $0.key })
                        }
                    } label: {
                        Label("Expand All", systemImage: "chevron.down.2")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)

                    Button {
                        withAnimation {
                            allSeasonsHidden = true
                            expandedSeasons.removeAll()
                        }
                    } label: {
                        Label("Collapse All", systemImage: "chevron.up.2")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)

                    Spacer()
                }
                .padding(.bottom, 4)

                if !allSeasonsHidden {
                    ForEach(seasons, id: \.key) { seasonNumber, seasonEpisodes in
                    VStack(spacing: 0) {
                        // Season header
                        Button {
                            withAnimation {
                                if expandedSeasons.contains(seasonNumber) {
                                    expandedSeasons.remove(seasonNumber)
                                } else {
                                    expandedSeasons.insert(seasonNumber)
                                }
                            }
                        } label: {
                            HStack {
                                Image(systemName: expandedSeasons.contains(seasonNumber) ? "chevron.down" : "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 20)

                                Text("Season \(seasonNumber)")
                                    .font(.subheadline)
                                    .fontWeight(.medium)

                                Spacer()

                                let seasonWatched = seasonEpisodes.filter { $0.watched }.count
                                Text("\(seasonWatched)/\(seasonEpisodes.count)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                // Mark all button
                                Button {
                                    let allWatched = seasonEpisodes.allSatisfy { $0.watched }
                                    for ep in seasonEpisodes {
                                        ep.watched = !allWatched
                                        if !allWatched {
                                            ep.watchedDate = Date()
                                        }
                                    }
                                    // Update date tracking
                                    if !allWatched {
                                        title.lastWatched = Date()
                                        if title.startDate == nil {
                                            title.startDate = Date()
                                        }
                                    }
                                    // Update title to trigger UI refresh
                                    title.dateModified = Date()
                                    title.objectWillChange.send()
                                    try? viewContext.save()
                                    episodeRefreshTrigger.toggle()
                                } label: {
                                    Image(systemName: seasonEpisodes.allSatisfy { $0.watched } ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(seasonEpisodes.allSatisfy { $0.watched } ? .green : .secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)

                        // Episodes list (when expanded)
                        if expandedSeasons.contains(seasonNumber) {
                            VStack(spacing: 0) {
                                ForEach(seasonEpisodes.sorted { $0.episodeNumber < $1.episodeNumber }) { episode in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Button {
                                                episode.watched.toggle()
                                                if episode.watched {
                                                    episode.watchedDate = Date()
                                                    // Update lastWatched
                                                    title.lastWatched = Date()
                                                    // Set startDate if not already set
                                                    if title.startDate == nil {
                                                        title.startDate = Date()
                                                    }
                                                }
                                                // Update title to trigger UI refresh
                                                title.dateModified = Date()
                                                title.objectWillChange.send()
                                                try? viewContext.save()
                                                episodeRefreshTrigger.toggle()
                                            } label: {
                                                Image(systemName: episode.watched ? "checkmark.circle.fill" : "circle")
                                                    .foregroundStyle(episode.watched ? .green : .secondary)
                                            }
                                            .buttonStyle(.plain)

                                            // Episode star
                                            Button {
                                                episode.isStarred.toggle()
                                                try? viewContext.save()
                                                episodeRefreshTrigger.toggle()
                                            } label: {
                                                Image(systemName: episode.isStarred ? "star.fill" : "star")
                                                    .font(.caption)
                                                    .foregroundStyle(episode.isStarred ? .yellow : .secondary)
                                            }
                                            .buttonStyle(.plain)

                                            Text("\(episode.episodeNumber).")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .frame(width: 25, alignment: .leading)

                                            Text(episode.name ?? "Episode \(episode.episodeNumber)")
                                                .font(.subheadline)
                                                .lineLimit(1)

                                            Spacer()

                                            if episode.runtime > 0 {
                                                Text("\(episode.runtime)m")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }

                                        // Episode description
                                        if let overview = episode.overview, !overview.isEmpty {
                                            Text(overview)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(3)
                                                .padding(.leading, 53)
                                        }
                                    }
                                    .padding(.vertical, 6)
                                    .padding(.leading, 28)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color(.systemGray6).opacity(0.3))
                    .cornerRadius(8)
                    }
                }
            }

            // Show total seasons if known and no episodes loaded
            if episodes.isEmpty && title.numberOfSeasons > 0 {
                Text("Total: \(title.numberOfSeasons) seasons")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .id(episodeRefreshTrigger)
    }

    private func loadEpisodes() {
        isLoadingEpisodes = true
        episodeLoadError = nil

        Task {
            do {
                try await TMDbMapper.loadAllEpisodes(
                    for: title,
                    using: TMDbService.shared,
                    context: viewContext
                )
                try viewContext.save()
                await MainActor.run {
                    isLoadingEpisodes = false
                }
            } catch {
                await MainActor.run {
                    isLoadingEpisodes = false
                    episodeLoadError = "Failed to load episodes: \(error.localizedDescription)"
                }
            }
        }
    }

    private func deleteTitle() {
        viewContext.delete(title)
        do {
            try viewContext.save()
            dismiss()
        } catch {
            print("Failed to delete title: \(error)")
        }
    }

    // MARK: - Lists Section

    private var listsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Lists")
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

                // Wikipedia
                if let titleName = title.title,
                   let encodedTitle = titleName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                   let wikiURL = URL(string: "https://en.wikipedia.org/wiki/Special:Search?search=\(encodedTitle)") {
                    Link(destination: wikiURL) {
                        LinkButton(icon: "book.closed", label: "Wiki")
                    }
                }
            }
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        let currentStatus = WatchStatus(rawValue: title.watchStatus) ?? .new

        return HStack(spacing: 0) {
            // Watch Status - cycles through statuses
            Button {
                let nextStatus: WatchStatus
                switch currentStatus {
                case .current:
                    nextStatus = .new
                case .new:
                    nextStatus = .paused
                case .paused:
                    nextStatus = .maybe
                case .maybe:
                    nextStatus = .finished
                case .finished:
                    nextStatus = .current
                }
                title.watchStatus = nextStatus.rawValue
                title.dateModified = Date()
                try? viewContext.save()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: currentStatus.icon)
                        .font(.title3)
                    Text(currentStatus.label)
                        .font(.caption2)
                }
                .frame(maxWidth: .infinity)
            }
            .foregroundStyle(currentStatus.color)

            // Lists
            Button {
                showingListManager = true
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "list.bullet")
                        .font(.title3)
                    Text("Lists")
                        .font(.caption2)
                }
                .frame(maxWidth: .infinity)
            }

            // Notes
            Button {
                showingNotesEditor = true
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "note.text")
                        .font(.title3)
                    Text("Notes")
                        .font(.caption2)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Supporting Views

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
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

enum SearchMode: String, CaseIterable {
    case tmdb = "TMDb"
    case library = "My Library"
}

enum MediaTypeFilter: String, CaseIterable {
    case all = "All"
    case movie = "Movies"
    case tv = "TV Shows"
}

enum MediaCategoryFilter: String, CaseIterable {
    case all = "All"
    case series = "Series"
    case limitedSeries = "Limited Series"
    case tvShow = "TV Show"
    case tvMovie = "TV Movie"
}

struct SearchView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        entity: Title.entity(),
        sortDescriptors: [NSSortDescriptor(keyPath: \Title.dateAdded, ascending: false)]
    ) private var allTitles: FetchedResults<Title>

    @State private var searchText = ""
    @State private var searchResults: [TMDbSearchResult] = []
    @State private var trendingResults: [TMDbSearchResult] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var selectedResult: TMDbSearchResult?
    @State private var selectedTitle: Title?

    // Library search filters
    @State private var searchMode: SearchMode = .tmdb
    @State private var mediaTypeFilter: MediaTypeFilter = .all
    @State private var mediaCategoryFilter: MediaCategoryFilter = .all

    // Filtered library results
    private var filteredLibraryResults: [Title] {
        var results = Array(allTitles)

        // Apply media type filter
        if mediaTypeFilter != .all {
            let filterValue = mediaTypeFilter == .movie ? "movie" : "tv"
            results = results.filter { $0.mediaType == filterValue }
        }

        // Apply media category filter
        if mediaCategoryFilter != .all {
            results = results.filter { $0.mediaCategory == mediaCategoryFilter.rawValue }
        }

        // Apply search text
        if !searchText.isEmpty {
            let searchLower = searchText.lowercased()
            results = results.filter { title in
                // Search in title
                if title.title?.lowercased().contains(searchLower) == true {
                    return true
                }
                // Search in overview
                if title.overview?.lowercased().contains(searchLower) == true {
                    return true
                }
                // Search in genres
                if let genres = title.genres as? [String] {
                    if genres.contains(where: { $0.lowercased().contains(searchLower) }) {
                        return true
                    }
                }
                // Search in cast names
                if title.castNames.contains(where: { $0.lowercased().contains(searchLower) }) {
                    return true
                }
                return false
            }
        }

        return results
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search mode picker
                Picker("Search Mode", selection: $searchMode) {
                    ForEach(SearchMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                // Library filters (only show in library mode)
                if searchMode == .library {
                    VStack(spacing: 8) {
                        HStack {
                            Menu {
                                ForEach(MediaTypeFilter.allCases, id: \.self) { filter in
                                    Button {
                                        mediaTypeFilter = filter
                                    } label: {
                                        HStack {
                                            Text(filter.rawValue)
                                            if mediaTypeFilter == filter {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "film")
                                    Text(mediaTypeFilter.rawValue)
                                    Image(systemName: "chevron.down")
                                }
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color(.systemGray5))
                                .cornerRadius(8)
                            }

                            Menu {
                                ForEach(MediaCategoryFilter.allCases, id: \.self) { filter in
                                    Button {
                                        mediaCategoryFilter = filter
                                    } label: {
                                        HStack {
                                            Text(filter.rawValue)
                                            if mediaCategoryFilter == filter {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "tv")
                                    Text(mediaCategoryFilter.rawValue)
                                    Image(systemName: "chevron.down")
                                }
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color(.systemGray5))
                                .cornerRadius(8)
                            }

                            Spacer()
                        }
                        .padding(.horizontal)
                    }
                    .padding(.bottom, 8)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if searchMode == .tmdb {
                            // TMDb Search Mode
                            tmdbSearchContent
                        } else {
                            // Library Search Mode
                            librarySearchContent
                        }
                    }
                    .padding(.top)
                }
            }
            .navigationTitle("Search")
            .searchable(text: $searchText, prompt: searchMode == .tmdb ? "Movies, TV Shows..." : "Title, actor, genre...")
            .onSubmit(of: .search) {
                if searchMode == .tmdb {
                    performSearch()
                }
            }
            .onChange(of: searchText) { oldValue, newValue in
                if newValue.isEmpty && searchMode == .tmdb {
                    searchResults = []
                    errorMessage = nil
                }
            }
            .onChange(of: searchMode) { oldValue, newValue in
                // Clear TMDb results when switching to library
                if newValue == .library {
                    searchResults = []
                    errorMessage = nil
                }
            }
            .sheet(item: $selectedResult) { result in
                SearchResultDetailView(result: result)
                    .environment(\.managedObjectContext, viewContext)
            }
            .sheet(item: $selectedTitle) { title in
                TitleDetailView(title: title)
                    .environment(\.managedObjectContext, viewContext)
            }
            .task {
                await loadTrending()
            }
        }
    }

    // MARK: - TMDb Search Content

    @ViewBuilder
    private var tmdbSearchContent: some View {
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

    // MARK: - Library Search Content

    @ViewBuilder
    private var librarySearchContent: some View {
        if filteredLibraryResults.isEmpty {
            ContentUnavailableView {
                Label(searchText.isEmpty ? "No Titles" : "No Results", systemImage: searchText.isEmpty ? "tray" : "magnifyingglass")
            } description: {
                if searchText.isEmpty {
                    Text("Add movies and TV shows to see them here")
                } else {
                    Text("No titles found matching \"\(searchText)\"")
                }
            }
            .padding(.top, 40)
        } else {
            LazyVStack(spacing: 12) {
                ForEach(filteredLibraryResults) { title in
                    Button {
                        selectedTitle = title
                    } label: {
                        LibrarySearchRow(title: title)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
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

// MARK: - Library Search Row

struct LibrarySearchRow: View {
    @ObservedObject var title: Title

    var body: some View {
        HStack(spacing: 12) {
            PosterImageView(posterPath: title.posterPath, size: Constants.TMDb.ImageSize.posterSmall)
                .frame(width: 60, height: 90)
                .cornerRadius(6)

            VStack(alignment: .leading, spacing: 4) {
                Text(title.title ?? "Unknown")
                    .font(.headline)
                    .lineLimit(2)
                    .foregroundStyle(.primary)

                HStack(spacing: 6) {
                    Text(title.mediaType == "movie" ? "Movie" : "TV")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.systemGray5))
                        .cornerRadius(4)

                    if title.year > 0 {
                        Text(String(title.year))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Show genres if available
                if let genres = title.genres as? [String], !genres.isEmpty {
                    Text(genres.prefix(3).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                // Show cast if available
                if !title.castNames.isEmpty {
                    Text(title.castNames.prefix(2).joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
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
    @StateObject private var appSettings = AppSettings.shared
    @State private var cacheSize = "Calculating..."
    @State private var showingClearCacheAlert = false
    @State private var showingBackupExporter = false
    @State private var showingRestoreImporter = false
    @State private var backupData: Data?
    @State private var isBackingUp = false
    @State private var isRestoring = false
    @State private var backupError: String?
    @State private var restoreError: String?
    @State private var showingRestoreSuccess = false
    @State private var showingRestoreConfirmation = false
    @State private var pendingRestoreData: Data?

    var body: some View {
        NavigationStack {
            List {
                // Stats Section
                Section("Your Stats") {
                    StatsRow()
                }

                // Appearance Section
                Section("Appearance") {
                    Picker("Theme", selection: $appSettings.theme) {
                        ForEach(AppTheme.allCases) { theme in
                            Label(theme.displayName, systemImage: theme.icon)
                                .tag(theme)
                        }
                    }
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

                // Data Section
                Section("Data") {
                    Button {
                        Task {
                            await createBackup()
                        }
                    } label: {
                        HStack {
                            Label("Export to JSON", systemImage: "square.and.arrow.up")
                            Spacer()
                            if isBackingUp {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    }
                    .disabled(isBackingUp || isRestoring)

                    Button {
                        showingRestoreImporter = true
                    } label: {
                        HStack {
                            Label("Import from JSON", systemImage: "square.and.arrow.down")
                            Spacer()
                            if isRestoring {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    }
                    .disabled(isBackingUp || isRestoring)
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
            .fileExporter(
                isPresented: $showingBackupExporter,
                document: BackupDocument(data: backupData ?? Data()),
                contentType: .json,
                defaultFilename: "MediaWatch-Backup-\(formatDateForFilename()).json"
            ) { result in
                switch result {
                case .success:
                    break
                case .failure(let error):
                    backupError = error.localizedDescription
                }
            }
            .fileImporter(
                isPresented: $showingRestoreImporter,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    Task {
                        await importBackup(from: url)
                    }
                case .failure(let error):
                    restoreError = error.localizedDescription
                }
            }
            .alert("Backup Error", isPresented: .constant(backupError != nil)) {
                Button("OK") { backupError = nil }
            } message: {
                if let error = backupError {
                    Text(error)
                }
            }
            .alert("Restore Error", isPresented: .constant(restoreError != nil)) {
                Button("OK") { restoreError = nil }
            } message: {
                if let error = restoreError {
                    Text(error)
                }
            }
            .alert("Restore Backup", isPresented: $showingRestoreConfirmation) {
                Button("Cancel", role: .cancel) {
                    pendingRestoreData = nil
                }
                Button("Restore", role: .destructive) {
                    Task {
                        await performRestore()
                    }
                }
            } message: {
                Text("This will replace all your current data with the backup. This action cannot be undone.")
            }
            .alert("Restore Complete", isPresented: $showingRestoreSuccess) {
                Button("OK") { }
            } message: {
                Text("Your data has been successfully restored from the backup.")
            }
        }
    }

    private func formatDateForFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private func createBackup() async {
        isBackingUp = true
        do {
            backupData = try await BackupService.shared.createBackup(context: viewContext)
            await MainActor.run {
                isBackingUp = false
                showingBackupExporter = true
            }
        } catch {
            await MainActor.run {
                isBackingUp = false
                backupError = "Failed to create backup: \(error.localizedDescription)"
            }
        }
    }

    private func importBackup(from url: URL) async {
        guard url.startAccessingSecurityScopedResource() else {
            await MainActor.run {
                restoreError = "Unable to access the selected file."
            }
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            let data = try Data(contentsOf: url)
            await MainActor.run {
                pendingRestoreData = data
                showingRestoreConfirmation = true
            }
        } catch {
            await MainActor.run {
                restoreError = "Failed to read backup file: \(error.localizedDescription)"
            }
        }
    }

    private func performRestore() async {
        guard let data = pendingRestoreData else { return }
        isRestoring = true

        do {
            try await BackupService.shared.restoreBackup(from: data, context: viewContext)
            await MainActor.run {
                isRestoring = false
                pendingRestoreData = nil
                showingRestoreSuccess = true
            }
        } catch {
            await MainActor.run {
                isRestoring = false
                pendingRestoreData = nil
                restoreError = "Failed to restore backup: \(error.localizedDescription)"
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

// MARK: - Streaming Service Picker

struct StreamingServicePicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedService: String

    var body: some View {
        NavigationStack {
            List {
                ForEach(StreamingService.allCases) { service in
                    Button {
                        selectedService = service.rawValue
                        dismiss()
                    } label: {
                        HStack {
                            if service != .none {
                                Text(service.displayName)
                                    .font(.subheadline)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color(hex: service.color))
                                    .foregroundStyle(.white)
                                    .cornerRadius(6)
                            } else {
                                Text("None")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selectedService == service.rawValue {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Select Service")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Star Rating View

struct StarRatingView: View {
    @Binding var rating: Double
    let maxRating: Int = 5

    var body: some View {
        HStack(spacing: 4) {
            ForEach(1...maxRating, id: \.self) { star in
                starImage(for: star)
                    .foregroundStyle(.yellow)
                    .onTapGesture {
                        let starValue = Double(star)
                        if rating == starValue {
                            // Second click on full star -> half star
                            rating = starValue - 0.5
                        } else if rating == starValue - 0.5 {
                            // Third click on half star -> clear
                            rating = 0
                        } else {
                            // First click -> full star
                            rating = starValue
                        }
                    }
            }

            if rating > 0 {
                Text(String(format: "%.1f", rating))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
        }
        .font(.title2)
    }

    private func starImage(for star: Int) -> Image {
        let starValue = Double(star)
        if rating >= starValue {
            return Image(systemName: "star.fill")
        } else if rating >= starValue - 0.5 {
            return Image(systemName: "star.leadinghalf.filled")
        } else {
            return Image(systemName: "star")
        }
    }
}

// MARK: - Color Extension

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Preview

#Preview {
    ContentView()
        .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
}
