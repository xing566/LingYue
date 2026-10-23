import Foundation
import AVFoundation

/// 本地有声书来源：扫描 Documents/Audiobooks 目录，支持导入音频文件。
struct LocalAudiobookSource {

    private static let audioExtensions: Set<String> = [
        "mp3", "m4a", "m4b", "aac", "wav", "flac", "aiff", "caf"
    ]

    static var libraryURL: URL {
        LocalLibrarySource.documentsURL.appendingPathComponent("Audiobooks", isDirectory: true)
    }

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

    private static func makeSong(from url: URL) async -> Song? {
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
