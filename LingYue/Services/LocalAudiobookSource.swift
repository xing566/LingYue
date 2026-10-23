import Foundation
import AVFoundation

/// 本地有声书来源：扫描 Documents/Audiobooks 目录，支持导入音频文件。
struct LocalAudiobookSource {

    /// 支持的音频 / 视频格式（AVFoundation 负责实际解码）
    private static let audioExtensions: Set<String> = [
        "mp3", "m4a", "m4b", "aac", "wav", "flac", "aiff", "caf",
        "mp4", "m4v", "ogg", "opus", "amr", "wma", "aif",
        "mov", "mkv", "avi", "webm", "flv", "ts", "3gp", "mpg", "mpeg", "ogv"
    ]

    static var libraryURL: URL {
        LocalLibrarySource.documentsURL.appendingPathComponent("Audiobooks", isDirectory: true)
    }

    /// 本地有声书库变化通知（下载完成后发出，让列表刷新）
    static let libraryChanged = Notification.Name("LocalAudiobookLibraryChanged")

    /// 扫描本地有声书目录
    static func scan() async -> [Song] {
        try? FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: libraryURL,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        var songs: [Song] = []
        for url in files where audioExtensions.contains(url.pathExtension.lowercased()) {
            if let song = await makeSong(from: url) { songs.append(song) }
        }
        return songs.sorted { $0.dateAdded > $1.dateAdded }
    }

    /// 从文件 App 导入音频（security-scoped），返回新增 Song 列表
    static func importFiles(from urls: [URL]) async -> [Song] {
        try? FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true)
        var added: [Song] = []
        for src in urls {
            let accessed = src.startAccessingSecurityScopedResource()
            defer { if accessed { src.stopAccessingSecurityScopedResource() } }
            guard audioExtensions.contains(src.pathExtension.lowercased()) else { continue }
            let dest = libraryURL.appendingPathComponent(src.lastPathComponent)
            do {
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.copyItem(at: src, to: dest)
                if let song = await makeSong(from: dest) { added.append(song) }
            } catch {
                print("导入有声书失败 \(src.lastPathComponent): \(error)")
            }
        }
        return added
    }

    /// 下载在线有声书整本到本地（Documents/Audiobooks），供离线播放。
    /// progress 回调：已下载数 / 总数。返回下载成功的本地 Song 列表。
    static func download(_ book: Audiobook, progress: ((Int, Int) -> Void)? = nil) async -> [Song] {
        try? FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true)
        let total = book.sections.count
        var downloaded: [Song] = []
        for (i, section) in book.sections.enumerated() {
            let ext = section.fileURL.pathExtension.isEmpty ? "mp3" : section.fileURL.pathExtension
            let dest = libraryURL
                .appendingPathComponent("\(book.title)-第\(i + 1)章.\(ext)")
            do {
                let (data, _) = try await URLSession.shared.data(from: section.fileURL)
                try? FileManager.default.removeItem(at: dest)
                try data.write(to: dest)
                if let song = await makeSong(from: dest) { downloaded.append(song) }
            } catch {
                print("下载章节失败 \(section.title): \(error)")
            }
            progress?(i + 1, total)
        }
        if !downloaded.isEmpty {
            NotificationCenter.default.post(name: libraryChanged, object: nil)
        }
        return downloaded
    }

    /// 删除某个本地有声书文件（App 内滑动删除用），并刷新列表。
    static func delete(_ song: Song) {
        try? FileManager.default.removeItem(at: song.fileURL)
        NotificationCenter.default.post(name: libraryChanged, object: nil)
    }

    private static func makeSong(from url: URL) async -> Song? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let asset = AVURLAsset(url: url)
        var duration: TimeInterval = 0
        if let d = try? await asset.load(.duration), d.isNumeric {
            duration = d.seconds
        }
        let creation = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
        return Song(title: url.deletingPathExtension().lastPathComponent,
                    artist: "本地有声书",
                    album: "本地有声书",
                    fileURL: url,
                    duration: duration,
                    dateAdded: creation,
                    source: .local)
    }
}
