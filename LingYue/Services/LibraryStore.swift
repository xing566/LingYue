import Foundation
import Observation

/// 曲库状态容器：负责导入、扫描、持久化歌曲与播放列表。
@Observable
final class LibraryStore {

    /// 音乐来源（本地）
    let source: MusicSource

    /// 在线歌单源（方案1：内置默认歌单 + 可自定义地址）
    private(set) var streamingSource = RemotePlaylistSource(
        feedURLString: UserDefaults.standard.string(forKey: "feedURL")
    )

    /// 自定义在线歌单地址（设置里可改，持久化）
    var feedURL: String? {
        didSet {
            UserDefaults.standard.set(feedURL, forKey: "feedURL")
            streamingSource.feedURLString = feedURL
        }
    }

    private(set) var onlineSongs: [Song] = []
    var isFetchingOnline = false

    private(set) var songs: [Song] = []
    private(set) var playlists: [Playlist] = []
    var isScanning = false

    private let songsFileURL: URL
    private let playlistsFileURL: URL

    init(source: MusicSource) {
        self.source = source
        let dir = LocalLibrarySource.documentsURL
        self.songsFileURL = dir.appendingPathComponent("songs.json")
        self.playlistsFileURL = dir.appendingPathComponent("playlists.json")
        loadPersistedState()
    }

    // MARK: - 在线曲库（方案1）

    /// 拉取在线歌单（内置默认或自定义地址）
    @MainActor
    func fetchOnlineSongs() async {
        isFetchingOnline = true
        defer { isFetchingOnline = false }
        do {
            onlineSongs = try await streamingSource.fetchSongs()
        } catch {
            onlineSongs = []
            print("在线歌单加载失败: \(error)")
        }
    }

    // MARK: - 导入 / 扫描

    /// 从外部文件导入（UIDocumentPicker 提供 URL 列表）
    @MainActor
    func importFiles(from urls: [URL]) async {
        isScanning = true
        defer { isScanning = false }
        guard let local = source as? LocalLibrarySource else { return }
        do {
            let added = try await local.importFiles(from: urls)
            songs.append(contentsOf: added)
            songs = dedupe(songs)
            persistSongs()
        } catch {
            print("导入失败: \(error)")
        }
    }

    /// 重新扫描沙盒目录（App 启动时调用）
    @MainActor
    func rescan() async {
        isScanning = true
        defer { isScanning = false }
        do {
            let found = try await source.fetchSongs()
            songs = dedupe(found)
            persistSongs()
        } catch {
            print("扫描失败: \(error)")
        }
    }

    // MARK: - 歌曲查询

    func song(withID id: UUID) -> Song? {
        songs.first { $0.id == id }
    }

    /// 按歌手分组的专辑列表
    var albums: [AlbumGroup] {
        let grouped = Dictionary(grouping: songs) { "\($0.album)|\($0.artist)" }
        return grouped.values
            .map { group in
                AlbumGroup(
                    album: group[0].album,
                    artist: group[0].artist,
                    songs: group.sorted { ($0.trackNumber ?? 0) < ($1.trackNumber ?? 0) }
                )
            }
            .sorted { $0.album < $1.album }
    }

    var artists: [(name: String, songs: [Song])] {
        let grouped = Dictionary(grouping: songs) { $0.artist }
        return grouped.map { (name: $0.key, songs: $0.value) }
            .sorted { $0.name < $1.name }
    }

    func search(_ text: String) -> [Song] {
        guard !text.isEmpty else { return [] }
        let t = text.lowercased()
        return songs.filter {
            $0.displayTitle.lowercased().contains(t)
                || $0.artist.lowercased().contains(t)
                || $0.album.lowercased().contains(t)
        }
    }

    // MARK: - 播放列表

    @discardableResult
    func createPlaylist(named name: String) -> Playlist {
        let pl = Playlist(name: name.isEmpty ? "新建播放列表" : name)
        playlists.append(pl)
        persistPlaylists()
        return pl
    }

    func addToPlaylist(_ playlistID: UUID, songIDs: [UUID]) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        var updated = playlists[idx]
        updated.songIDs.append(contentsOf: songIDs)
        playlists[idx] = updated
        persistPlaylists()
    }

    func removeSong(_ songID: UUID, from playlistID: UUID) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        var updated = playlists[idx]
        updated.songIDs.removeAll { $0 == songID }
        playlists[idx] = updated
        persistPlaylists()
    }

    func deletePlaylist(_ playlistID: UUID) {
        playlists.removeAll { $0.id == playlistID }
        persistPlaylists()
    }

    func songs(in playlist: Playlist) -> [Song] {
        playlist.songIDs.compactMap { song(withID: $0) }
    }

    // MARK: - 持久化

    private func loadPersistedState() {
        if let data = try? Data(contentsOf: songsFileURL),
           let decoded = try? JSONDecoder().decode([Song].self, from: data) {
            songs = dedupe(decoded)
        }
        if let data = try? Data(contentsOf: playlistsFileURL),
           let decoded = try? JSONDecoder().decode([Playlist].self, from: data) {
            playlists = decoded
        }
    }

    private func persistSongs() {
        guard let data = try? JSONEncoder().encode(songs) else { return }
        try? data.write(to: songsFileURL, options: .atomic)
    }

    private func persistPlaylists() {
        guard let data = try? JSONEncoder().encode(playlists) else { return }
        try? data.write(to: playlistsFileURL, options: .atomic)
    }

    /// 按文件 URL 去重，保留最新的一条
    private func dedupe(_ list: [Song]) -> [Song] {
        var seen = Set<String>()
        return list.filter { s in
            let key = s.fileURL.lastPathComponent
            return seen.insert(key).inserted
        }
    }
}
