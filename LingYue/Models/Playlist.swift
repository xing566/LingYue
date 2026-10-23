import Foundation

/// 播放列表模型
struct Playlist: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    /// 歌曲的稳定标识（本地为文件路径，在线为音频 URL），跨重启不变，用于持久化。
    var songKeys: [String]
    var createdAt: Date

    init(id: UUID = UUID(),
         name: String,
         songKeys: [String] = [],
         createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.songKeys = songKeys
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case id, name, songKeys, createdAt
    }

    /// 兼容旧版本：旧存档只有 songIDs（随机 UUID，重启即失效），读入时置空，用户重新添加即可。
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        songKeys = (try? c.decode([String].self, forKey: .songKeys)) ?? []
        createdAt = (try? c.decode(Date.self, forKey: .createdAt)) ?? Date()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(songKeys, forKey: .songKeys)
        try c.encode(createdAt, forKey: .createdAt)
    }
}
