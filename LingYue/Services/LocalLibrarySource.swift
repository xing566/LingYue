import Foundation
import AVFoundation

/// 本地文件音乐源：扫描沙盒 Documents/Audio 目录，读取音频元数据（标题/歌手/专辑/封面/时长）。
struct LocalLibrarySource: MusicSource {

    let kind: MusicSourceKind = .local

    /// 支持导入的音频 + 视频扩展名（AVPlayer 负责实际解码）
    private static let audioExtensions: Set<String> = [
        "mp3", "m4a", "aac", "wav", "flac", "aiff", "caf", "alac", "mp4", "m4b",
        "m4v", "mov", "mkv", "avi", "webm", "flv", "ts", "3gp", "mpg", "mpeg", "wmv", "ogv"
    ]

    /// 沙盒 Documents 目录
    static var documentsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// 音频目录
    var libraryURL: URL {
        Self.documentsURL.appendingPathComponent("Audio", isDirectory: true)
    }

    // MARK: - 扫描

    func fetchSongs() async throws -> [Song] {
        try FileManager.default.createDirectory(at: libraryURL,
                                                withIntermediateDirectories: true)
        let files = try FileManager.default.contentsOfDirectory(
            at: libraryURL,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )
        let audioFiles = files.filter {
            Self.audioExtensions.contains($0.pathExtension.lowercased())
        }
        var songs: [Song] = []
        for url in audioFiles {
            if let song = await makeSong(from: url) {
                songs.append(song)
            }
        }
        // 按加入时间倒序
        return songs.sorted { $0.dateAdded > $1.dateAdded }
    }

    /// 从单个文件构建 Song，并提取元数据
    func makeSong(from fileURL: URL) async -> Song? {
        let meta = await extractMetadata(from: fileURL)
        let creation = (try? fileURL.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
        return Song(
            title: meta.title,
            artist: meta.artist,
            album: meta.album,
            artworkData: meta.artwork,
            fileURL: fileURL,
            duration: meta.duration,
            trackNumber: meta.trackNumber,
            dateAdded: creation
        )
    }

    // MARK: - 导入

    /// 把用户选中的外部音频文件拷贝进沙盒，返回新增的 Song 列表。
    ///
    /// 通过 `fileImporter` 选择的文件是 **security-scoped 资源**，必须先调用
    /// `startAccessingSecurityScopedResource()` 获取访问权限，再读取/拷贝；
    /// 否则 `copyItem` 会抛 "Operation not permitted"，导致"本地曲库无法添加"。
    func importFiles(from urls: [URL]) async throws -> [Song] {
        try FileManager.default.createDirectory(at: libraryURL,
                                                withIntermediateDirectories: true)
        var imported: [Song] = []
        for src in urls {
            let accessed = src.startAccessingSecurityScopedResource()
            defer {
                if accessed { src.stopAccessingSecurityScopedResource() }
            }
            do {
                // 已在沙盒内则跳过拷贝
                if src.deletingLastPathComponent().standardizedFileURL == libraryURL.standardizedFileURL {
                    if let song = await makeSong(from: src) { imported.append(song) }
                    continue
                }
                let dest = libraryURL.appendingPathComponent(src.lastPathComponent)
                try? FileManager.default.removeItem(at: dest) // 避免同名冲突
                try FileManager.default.copyItem(at: src, to: dest)
                if let song = await makeSong(from: dest) { imported.append(song) }
            } catch {
                // 单个文件失败不中断其余导入
                print("导入单个文件失败 \(src.lastPathComponent): \(error)")
            }
        }
        return imported
    }

    // MARK: - URL 解析

    func resolveURL(for song: Song) -> URL { song.fileURL }

    // MARK: - 元数据提取

    struct Metadata {
        var title = ""
        var artist = "未知艺术家"
        var album = "未知专辑"
        var artwork: Data?
        var duration: TimeInterval = 0
        var trackNumber: Int?
    }

    func extractMetadata(from url: URL) async -> Metadata {
        let asset = AVURLAsset(url: url)
        var meta = Metadata()
        meta.title = url.deletingPathExtension().lastPathComponent

        if let d = try? await asset.load(.duration), d.isNumeric {
            meta.duration = d.seconds
        }
        let items = (try? await asset.load(.commonMetadata)) ?? []
        for item in items {
            guard let value = item.value as? String else { continue }
            switch item.identifier {
            case .commonIdentifierTitle:
                if meta.title.isEmpty { meta.title = value }
            case .commonIdentifierArtist:
                meta.artist = value
            case .commonIdentifierAlbumName:
                meta.album = value
            default:
                break
            }
        }
        if let art = items.first(where: { $0.identifier == .commonIdentifierArtwork }),
           let data = art.value as? Data {
            meta.artwork = data
        }
        return meta
    }
}
