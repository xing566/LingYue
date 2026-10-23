import Foundation

/// 播放列表模型
struct Playlist: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    /// 直接保存歌曲快照，跨重启始终显示（不依赖曲库重扫/ID/路径解析）。
    var songs: [Song]
    var createdAt: Date

    init(id: UUID = UUID(),
         name: String,
         songs: [Song] = [],
         createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.songs = songs
        self.createdAt = createdAt
    }
}
