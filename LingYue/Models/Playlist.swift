import Foundation

/// 播放列表模型
struct Playlist: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var songIDs: [UUID]     // 有序引用曲库中的歌曲
    var createdAt: Date

    init(id: UUID = UUID(),
         name: String,
         songIDs: [UUID] = [],
         createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.songIDs = songIDs
        self.createdAt = createdAt
    }
}
