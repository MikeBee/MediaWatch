//
//  ImageCacheService.swift
//  MediaWatch
//
//  Memory and disk caching for images from TMDb
//

import SwiftUI

// MARK: - Image Cache Service

actor ImageCacheService {

    // MARK: - Singleton

    static let shared = ImageCacheService()

    // MARK: - Properties

    private let memoryCache = NSCache<NSString, UIImage>()
    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let maxDiskCacheSizeMB: Int

    // Track disk cache size
    private var currentDiskCacheSize: Int64 = 0
    private var diskCacheSizeCalculated = false

    // MARK: - Initialization

    private init() {
        // Setup memory cache limits
        memoryCache.countLimit = 100
        memoryCache.totalCostLimit = 100 * 1024 * 1024 // 100 MB

        // Setup disk cache directory
        let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = cachesDirectory.appendingPathComponent(Constants.Storage.imageCacheDirectory)

        maxDiskCacheSizeMB = Constants.Storage.maxCacheSizeMB

        // Create cache directory if needed
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Public Interface

    /// Get an image from cache or fetch from URL
    func image(for url: URL) async throws -> UIImage {
        let key = cacheKey(for: url)

        // Check memory cache first
        if let cached = memoryCache.object(forKey: key as NSString) {
            return cached
        }

        // Check disk cache
        if let diskImage = await loadFromDisk(key: key) {
            // Store in memory cache for faster access
            memoryCache.setObject(diskImage, forKey: key as NSString, cost: diskImage.memoryCost)
            return diskImage
        }

        // Fetch from network
        let image = try await fetchImage(from: url)

        // Store in both caches
        memoryCache.setObject(image, forKey: key as NSString, cost: image.memoryCost)
        await saveToDisk(image: image, key: key)

        return image
    }

    /// Get an image if it's already cached (doesn't fetch)
    func cachedImage(for url: URL) async -> UIImage? {
        let key = cacheKey(for: url)

        // Check memory cache
        if let cached = memoryCache.object(forKey: key as NSString) {
            return cached
        }

        // Check disk cache
        if let diskImage = await loadFromDisk(key: key) {
            memoryCache.setObject(diskImage, forKey: key as NSString, cost: diskImage.memoryCost)
            return diskImage
        }

        return nil
    }

    /// Prefetch images for URLs
    func prefetch(urls: [URL]) async {
        await withTaskGroup(of: Void.self) { group in
            for url in urls {
                group.addTask {
                    _ = try? await self.image(for: url)
                }
            }
        }
    }

    /// Clear memory cache
    func clearMemoryCache() {
        memoryCache.removeAllObjects()
    }

    /// Clear disk cache
    func clearDiskCache() async {
        try? fileManager.removeItem(at: cacheDirectory)
        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        currentDiskCacheSize = 0
    }

    /// Clear all caches
    func clearAllCaches() async {
        clearMemoryCache()
        await clearDiskCache()
    }

    /// Get current disk cache size in bytes
    func diskCacheSize() async -> Int64 {
        if !diskCacheSizeCalculated {
            await calculateDiskCacheSize()
        }
        return currentDiskCacheSize
    }

    /// Get formatted disk cache size string
    func formattedDiskCacheSize() async -> String {
        let bytes = await diskCacheSize()
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: - Private Methods

    private func cacheKey(for url: URL) -> String {
        // Use URL path as cache key (remove base URL)
        url.lastPathComponent
    }

    private func diskPath(for key: String) -> URL {
        cacheDirectory.appendingPathComponent(key)
    }

    private func loadFromDisk(key: String) async -> UIImage? {
        let path = diskPath(for: key)

        guard fileManager.fileExists(atPath: path.path) else {
            return nil
        }

        guard let data = try? Data(contentsOf: path),
              let image = UIImage(data: data) else {
            return nil
        }

        return image
    }

    private func saveToDisk(image: UIImage, key: String) async {
        let path = diskPath(for: key)

        guard let data = image.jpegData(compressionQuality: 0.8) else {
            return
        }

        do {
            try data.write(to: path)

            // Update cache size
            currentDiskCacheSize += Int64(data.count)

            // Check if we need to evict old files
            await evictIfNeeded()
        } catch {
            // Silently fail - caching is best effort
        }
    }

    private func fetchImage(from url: URL) async throws -> UIImage {
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw MediaWatchError.imageLoadFailed
        }

        guard let image = UIImage(data: data) else {
            throw MediaWatchError.imageLoadFailed
        }

        return image
    }

    private func calculateDiskCacheSize() async {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: .skipsHiddenFiles
        ) else {
            currentDiskCacheSize = 0
            diskCacheSizeCalculated = true
            return
        }

        var totalSize: Int64 = 0
        for url in contents {
            if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalSize += Int64(size)
            }
        }

        currentDiskCacheSize = totalSize
        diskCacheSizeCalculated = true
    }

    private func evictIfNeeded() async {
        let maxBytes = Int64(maxDiskCacheSizeMB * 1024 * 1024)

        guard currentDiskCacheSize > maxBytes else { return }

        // Get all cached files with modification dates
        guard let contents = try? fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: .skipsHiddenFiles
        ) else {
            return
        }

        // Sort by modification date (oldest first)
        let sortedFiles = contents.compactMap { url -> (URL, Date, Int64)? in
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                  let date = values.contentModificationDate,
                  let size = values.fileSize else {
                return nil
            }
            return (url, date, Int64(size))
        }.sorted { $0.1 < $1.1 }

        // Delete oldest files until we're under 80% of max
        let targetSize = Int64(Double(maxBytes) * 0.8)
        var currentSize = currentDiskCacheSize

        for (url, _, size) in sortedFiles {
            guard currentSize > targetSize else { break }

            try? fileManager.removeItem(at: url)
            currentSize -= size
        }

        currentDiskCacheSize = currentSize
    }
}

// MARK: - UIImage Memory Cost Extension

private extension UIImage {
    var memoryCost: Int {
        guard let cgImage = cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }
}

// MARK: - SwiftUI Async Image View

/// A view that loads and caches images asynchronously
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder

    @State private var loadedImage: UIImage?
    @State private var isLoading = false

    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.content = content
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image = loadedImage {
                content(Image(uiImage: image))
            } else {
                placeholder()
                    .task {
                        await loadImage()
                    }
            }
        }
    }

    private func loadImage() async {
        guard let url = url, !isLoading else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let image = try await ImageCacheService.shared.image(for: url)
            await MainActor.run {
                self.loadedImage = image
            }
        } catch {
            // Image failed to load - keep showing placeholder
        }
    }
}

// MARK: - Convenience Initializer

extension CachedAsyncImage where Placeholder == ProgressView<EmptyView, EmptyView> {
    init(
        url: URL?,
        @ViewBuilder content: @escaping (Image) -> Content
    ) {
        self.init(url: url, content: content) {
            ProgressView()
        }
    }
}

extension CachedAsyncImage where Content == Image, Placeholder == ProgressView<EmptyView, EmptyView> {
    init(url: URL?) {
        self.init(url: url) { image in
            image
        } placeholder: {
            ProgressView()
        }
    }
}

// MARK: - Poster Image View

/// Specialized view for displaying poster images
struct PosterImageView: View {
    let posterPath: String?
    let size: String

    init(posterPath: String?, size: String = Constants.TMDb.ImageSize.posterMedium) {
        self.posterPath = posterPath
        self.size = size
    }

    var body: some View {
        CachedAsyncImage(url: TMDbService.posterURL(path: posterPath, size: size)) { image in
            image
                .resizable()
                .aspectRatio(2/3, contentMode: .fill)
        } placeholder: {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .aspectRatio(2/3, contentMode: .fill)
                .overlay {
                    Image(systemName: "film")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                }
        }
    }
}

// MARK: - Backdrop Image View

/// Specialized view for displaying backdrop images
struct BackdropImageView: View {
    let backdropPath: String?
    let size: String

    init(backdropPath: String?, size: String = Constants.TMDb.ImageSize.backdropMedium) {
        self.backdropPath = backdropPath
        self.size = size
    }

    var body: some View {
        CachedAsyncImage(url: TMDbService.backdropURL(path: backdropPath, size: size)) { image in
            image
                .resizable()
                .aspectRatio(16/9, contentMode: .fill)
        } placeholder: {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .aspectRatio(16/9, contentMode: .fill)
                .overlay {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundColor(.gray)
                }
        }
    }
}

// MARK: - Still Image View

/// Specialized view for displaying episode still images
struct StillImageView: View {
    let stillPath: String?
    let size: String

    init(stillPath: String?, size: String = Constants.TMDb.ImageSize.stillMedium) {
        self.stillPath = stillPath
        self.size = size
    }

    var body: some View {
        CachedAsyncImage(url: TMDbService.stillURL(path: stillPath, size: size)) { image in
            image
                .resizable()
                .aspectRatio(16/9, contentMode: .fill)
        } placeholder: {
            Rectangle()
                .fill(Color.gray.opacity(0.3))
                .aspectRatio(16/9, contentMode: .fill)
                .overlay {
                    Image(systemName: "tv")
                        .font(.title)
                        .foregroundColor(.gray)
                }
        }
    }
}
