import Foundation

/// 音乐来源类型。本地播放与在线流媒体。
enum MusicSourceKind: String, Codable, CaseIterable, Identifiable {
    case local
    case streaming

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .local: return "本地曲库"
        case .streaming: return "在线曲库"
        }
    }
}

/// 一首歌的完整模型（可 Codable 持久化）
struct Song: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var artist: String
    var album: String
    var artworkData: Data?          // 缓存的封面图（JPEG/PNG），可为 nil
    var artworkURL: URL?            // 网络封面地址（在线曲库用）
    var fileURL: URL                // 可播放地址：本地为文件 URL，在线为流地址
    var duration: TimeInterval
    var trackNumber: Int?
    var dateAdded: Date
    var source: MusicSourceKind

    init(id: UUID = UUID(),
         title: String,
         artist: String = "未知艺术家",
         album: String = "未知专辑",
         artworkData: Data? = nil,
         artworkURL: URL? = nil,
         fileURL: URL,
         duration: TimeInterval = 0,
         trackNumber: Int? = nil,
         dateAdded: Date = Date(),
         source: MusicSourceKind = .local) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkData = artworkData
        self.artworkURL = artworkURL
        self.fileURL = fileURL
        self.duration = duration
        self.trackNumber = trackNumber
        self.dateAdded = dateAdded
        self.source = source
    }

    /// 标题为空时的兜底显示
    var displayTitle: String {
        title.isEmpty ? fileURL.lastPathComponent : title
    }

    var formattedDuration: String {
        guard duration.isFinite, duration > 0 else { return "--:--" }
        let total = Int(duration)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
