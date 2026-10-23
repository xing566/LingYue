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
            songs = mergePreservingIdentity(found)
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

    /// 向播放列表添加歌曲（存稳定标识 fileURL.path / 在线 absoluteString，跨重启有效）。
    func addToPlaylist(_ playlistID: UUID, songs: [Song]) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        var updated = playlists[idx]
        for song in songs {
            let key = songKey(song)
            if !updated.songKeys.contains(key) { updated.songKeys.append(key) }
        }
        playlists[idx] = updated
        persistPlaylists()
    }

    func removeSong(_ song: Song, from playlistID: UUID) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        var updated = playlists[idx]
        updated.songKeys.removeAll { $0 == songKey(song) }
        playlists[idx] = updated
        persistPlaylists()
    }

    func deletePlaylist(_ playlistID: UUID) {
        playlists.removeAll { $0.id == playlistID }
        persistPlaylists()
    }

    /// 播放列表里的歌曲：按稳定标识在本地曲库 + 在线曲库中解析。
    func songs(in playlist: Playlist) -> [Song] {
        let all = allSongs
        return playlist.songKeys.compactMap { key in
            all.first { songKey($0) == key }
        }
    }

    /// 本地曲库 + 在线曲库合并，供播放列表解析。
    private var allSongs: [Song] {
        songs + onlineSongs
    }

    /// 歌曲的稳定标识：本地用文件路径，在线用绝对 URL 字符串。
    private func songKey(_ song: Song) -> String {
        song.source == .streaming ? song.fileURL.absoluteString : song.fileURL.path
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

    /// 用磁盘上已持久化的歌曲合并新扫描结果：
    /// 同一文件路径的歌曲保留持久化时的 ID，这样播放列表等按 ID 的引用在重启后依然有效。
    /// （纯数据合并，不依赖自定义哈希，不会引入崩溃。）
    private func mergePreservingIdentity(_ found: [Song]) -> [Song] {
        var byPath: [String: Song] = [:]
        for s in songs { byPath[s.fileURL.path] = s }   // 当前 songs 即启动时从磁盘加载的持久化歌曲
        var merged: [Song] = []
        for s in dedupe(found) {
            let path = s.fileURL.path
            if var persisted = byPath[path] {
                // 保留持久化 ID 与封面，标题/歌手/时长用最新扫描结果更新
                persisted.title = s.title.isEmpty ? persisted.title : s.title
                persisted.artist = s.artist
                persisted.album = s.album
                persisted.duration = s.duration
                persisted.trackNumber = s.trackNumber
                merged.append(persisted)
            } else {
                merged.append(s)
            }
        }
        return merged
    }
}
