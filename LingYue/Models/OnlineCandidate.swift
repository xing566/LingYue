import Foundation

/// 在线搜索的统一候选（可来自网易云 / iTunes / Jamendo 任一来源）。
/// 不是所有候选都可在线播放（如网易云 VIP 曲目、iTunes 仅预览）。
struct OnlineCandidate: Identifiable {
    let id = UUID()
    let title: String
    let artist: String
    let album: String
    let artworkURL: URL?
    let streamURL: URL?          // nil => 不可在线播放
    let duration: TimeInterval
    let sourceName: String
    let lyricID: Int?            // 网易云歌曲ID（取歌词用）

    var playable: Bool { streamURL != nil }
    var subtitle: String { sourceName }

    /// 转成可加入本地曲库/播放的 Song（仅可播放的候选可转）
    func makeSong() -> Song? {
        guard let streamURL else { return nil }
        return Song(title: title, artist: artist, album: album,
                    artworkURL: artworkURL, fileURL: streamURL,
                    duration: duration, source: .streaming, neteaseID: lyricID)
    }
}
