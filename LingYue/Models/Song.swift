import Foundation

/// 音乐来源类型。当前只有本地播放；在线流媒体作为预留枚举值，方便后续扩展。
enum MusicSourceKind: String, Codable, CaseIterable, Identifiable {
    case local
    // 预留：case streaming

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .local: return "本地曲库"
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
    var fileURL: URL                // 本地文件绝对路径
    var duration: TimeInterval
    var trackNumber: Int?
    var dateAdded: Date
    var source: MusicSourceKind

    init(id: UUID = UUID(),
         title: String,
         artist: String = "未知艺术家",
         album: String = "未知专辑",
         artworkData: Data? = nil,
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
        guard duration.isFinite, duration > 0 else { return "0:00" }
        let total = Int(duration)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
