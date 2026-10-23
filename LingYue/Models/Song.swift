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

    /// 由字符串（通常是文件路径或在线标识）稳定生成 UUID。
    /// 同一路径每次启动得到相同 ID，保证播放列表等引用在重启后仍有效。
    static func stableID(from key: String) -> UUID {
        // 双 64 位 FNV-1a（偏移量不同），结果稳定、极简、不可能崩溃。
        var h1: UInt64 = 0xcbf29ce484222325
        var h2: UInt64 = 0x84222325cbf29ce4
        for byte in key.utf8 {
            h1 ^= UInt64(byte); h1 &*= 0x100000001b3
            h2 ^= UInt64(byte); h2 &*= 0x100000001b3
        }
        let u = (
            UInt8((h1 >> 56) & 0xff), UInt8((h1 >> 48) & 0xff), UInt8((h1 >> 40) & 0xff), UInt8((h1 >> 32) & 0xff),
            UInt8((h1 >> 24) & 0xff), UInt8((h1 >> 16) & 0xff), UInt8(((h1 >> 8) & 0x0f) | 0x40), UInt8(h1 & 0xff),
            UInt8(((h2 >> 56) & 0x3f) | 0x80), UInt8((h2 >> 48) & 0xff), UInt8((h2 >> 40) & 0xff), UInt8((h2 >> 32) & 0xff),
            UInt8((h2 >> 24) & 0xff), UInt8((h2 >> 16) & 0xff), UInt8((h2 >> 8) & 0xff), UInt8(h2 & 0xff)
        )
        return UUID(uuid: u)
    }

    var formattedDuration: String {
        guard duration.isFinite, duration > 0 else { return "0:00" }
        let total = Int(duration)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
