import Foundation
import AVFoundation

struct Track: Identifiable, Hashable {
    let id: String          // path relative to the library folder
    let url: URL
    var title: String
    var artist: String

    static func == (a: Track, b: Track) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

struct Playlist: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var trackIDs: [String] = []
}

@MainActor
final class Library: ObservableObject {
    @Published private(set) var tracks: [Track] = []
    @Published private(set) var playlists: [Playlist] = []
    @Published private(set) var folderName: String?

    private var root: URL?
    private var timer: Timer?
    private var busy = false
    private var meta: [String: [String]] = [:]   // id -> [title, artist]
    private var index: [String: Track] = [:]
    private var metaTask: Task<Void, Never>?

    nonisolated static let exts: Set<String> =
        ["mp3", "flac", "m4a", "aac", "wav", "aif", "aiff", "caf", "alac", "mp4"]

    init() {
        playlists = Self.load([Playlist].self, "playlists.json") ?? []
        meta = Self.load([String: [String]].self, "meta.json") ?? [:]
        restoreFolder()
    }

    // MARK: Folder

    func setFolder(_ url: URL) {
        tracks = []; index = [:]; meta = [:]
        guard open(url) else { return }
        if let data = try? url.bookmarkData() {
            UserDefaults.standard.set(data, forKey: "folderBookmark")
        }
    }

    private func restoreFolder() {
        guard let data = UserDefaults.standard.data(forKey: "folderBookmark") else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale) else { return }
        open(url)
        if stale, let fresh = try? url.bookmarkData() {
            UserDefaults.standard.set(fresh, forKey: "folderBookmark")
        }
    }

    @discardableResult
    private func open(_ url: URL) -> Bool {
        root?.stopAccessingSecurityScopedResource()
        guard url.startAccessingSecurityScopedResource() else { return false }
        root = url
        folderName = url.lastPathComponent
        rescan()
        return true
    }

    // MARK: Scanning

    func startWatching() {
        rescan()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.rescan() }
        }
    }

    func stopWatching() { timer?.invalidate(); timer = nil }

    func rescan() {
        guard let root, !busy else { return }
        busy = true
        Task.detached(priority: .utility) {
            let found = Library.enumerate(root: root)
            await self.apply(found)
        }
    }

    nonisolated private static func enumerate(root: URL) -> [Track] {
        guard let en = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        let base = root.pathComponents.count
        var out: [Track] = []
        for case let url as URL in en {
            guard exts.contains(url.pathExtension.lowercased()) else { continue }
            let rel = url.pathComponents.dropFirst(base).joined(separator: "/")
            out.append(Track(id: rel, url: url,
                             title: url.deletingPathExtension().lastPathComponent, artist: ""))
        }
        out.sort { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
        return out
    }

    private func apply(_ found: [Track]) {
        busy = false
        guard found.map(\.id) != tracks.map(\.id) else { return }
        tracks = found.map(withMeta)
        reindex()
        loadMetadata()
    }

    private func withMeta(_ t: Track) -> Track {
        guard let m = meta[t.id] else { return t }
        var t = t
        if !m[0].isEmpty { t.title = m[0] }
        t.artist = m[1]
        return t
    }

    private func reindex() {
        index = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private func loadMetadata() {
        metaTask?.cancel()
        let todo = tracks.filter { meta[$0.id] == nil }
        guard !todo.isEmpty else { return }
        metaTask = Task { [weak self] in
            var n = 0
            for t in todo {
                if Task.isCancelled { return }
                let (title, artist) = await Library.readMeta(t.url)
                guard let self else { return }
                self.meta[t.id] = [title ?? "", artist ?? ""]
                n += 1
                if n % 40 == 0 { self.mergeMeta() }
            }
            self?.mergeMeta()
            if let self { Self.save(self.meta, "meta.json") }
        }
    }

    private func mergeMeta() {
        tracks = tracks.map(withMeta)
        reindex()
    }

    nonisolated private static func readMeta(_ url: URL) async -> (String?, String?) {
        let asset = AVURLAsset(url: url)
        guard let items = try? await asset.load(.commonMetadata) else { return (nil, nil) }
        var title: String?, artist: String?
        for item in items {
            guard let key = item.commonKey else { continue }
            if key == .commonKeyTitle { title = try? await item.load(.stringValue) }
            else if key == .commonKeyArtist { artist = try? await item.load(.stringValue) }
        }
        return (title, artist)
    }

    // MARK: Playlists

    func createPlaylist(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        playlists.append(Playlist(name: n.isEmpty ? "New Playlist" : n))
        savePlaylists()
    }

    func deletePlaylists(at offsets: IndexSet) {
        playlists.remove(atOffsets: offsets)
        savePlaylists()
    }

    func add(_ t: Track, to p: Playlist) {
        guard let i = playlists.firstIndex(where: { $0.id == p.id }),
              !playlists[i].trackIDs.contains(t.id) else { return }
        playlists[i].trackIDs.append(t.id)
        savePlaylists()
    }

    func remove(_ ids: [String], from pid: UUID) {
        guard let i = playlists.firstIndex(where: { $0.id == pid }) else { return }
        playlists[i].trackIDs.removeAll { ids.contains($0) }
        savePlaylists()
    }

    func tracks(in p: Playlist) -> [Track] { p.trackIDs.compactMap { index[$0] } }

    private func savePlaylists() { Self.save(playlists, "playlists.json") }

    // MARK: Persistence

    private static func fileURL(_ name: String) -> URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name)
    }

    private static func load<T: Decodable>(_ type: T.Type, _ name: String) -> T? {
        guard let d = try? Data(contentsOf: fileURL(name)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: d)
    }

    private static func save<T: Encodable>(_ value: T, _ name: String) {
        if let d = try? JSONEncoder().encode(value) { try? d.write(to: fileURL(name), options: .atomic) }
    }
}
