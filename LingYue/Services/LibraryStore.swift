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

    /// 向播放列表添加歌曲（直接保存歌曲快照，跨重启始终显示）。
    func addToPlaylist(_ playlistID: UUID, songs newSongs: [Song]) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        var updated = playlists[idx]
        for song in newSongs {
            if !updated.songs.contains(where: { $0.fileURL.path == song.fileURL.path }) {
                updated.songs.append(song)
            }
        }
        playlists[idx] = updated
        persistPlaylists()
    }

    func removeSong(_ song: Song, from playlistID: UUID) {
        guard let idx = playlists.firstIndex(where: { $0.id == playlistID }) else { return }
        var updated = playlists[idx]
        updated.songs.removeAll { $0.fileURL.path == song.fileURL.path }
        playlists[idx] = updated
        persistPlaylists()
    }

    func deletePlaylist(_ playlistID: UUID) {
        playlists.removeAll { $0.id == playlistID }
        persistPlaylists()
    }

    /// 播放列表里的歌曲：返回已保存的快照，并从曲库按路径重新挂回封面/最新元数据。
    func songs(in playlist: Playlist) -> [Song] {
        playlist.songs.map { snapshot in
            if let fresh = songs.first(where: { $0.fileURL.path == snapshot.fileURL.path }) {
                return fresh
            }
            return snapshot
        }
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
        do {
            let clean = songs.map { sanitizedForPersistence($0) }
            let data = try JSONEncoder().encode(clean)
            try data.write(to: songsFileURL, options: .atomic)
        } catch {
            print("保存曲库失败: \(error)")
        }
    }

    private func persistPlaylists() {
        do {
            let clean = playlists.map { pl in
                Playlist(id: pl.id, name: pl.name,
                         songs: pl.songs.map { sanitizedForPersistence($0) },
                         createdAt: pl.createdAt)
            }
            let data = try JSONEncoder().encode(clean)
            try data.write(to: playlistsFileURL, options: .atomic)
        } catch {
            print("保存播放列表失败: \(error)")
        }
    }

    /// 调试用：从磁盘重新加载播放列表（在设置页检查持久化实际内容）。
    func rescanPlaylistsFromDisk() {
        if let data = try? Data(contentsOf: playlistsFileURL),
           let decoded = try? JSONDecoder().decode([Playlist].self, from: data) {
            playlists = decoded
        }
    }

    /// 清洗单曲用于 JSON 持久化：
    /// - 把非有限时长钳制为 0（否则 JSONEncoder 对 NaN/Inf 直接抛错，导致整个保存被跳过）
    /// - 剥离封面图（体积大，且播放在加载时从曲库重新挂回），保证 playlists.json 小而稳定
    private func sanitizedForPersistence(_ song: Song) -> Song {
        var s = song
        if !s.duration.isFinite || s.duration.isNaN || s.duration < 0 { s.duration = 0 }
        s.artworkData = nil
        return s
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
