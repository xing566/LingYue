import Foundation

/// 音乐来源抽象协议 —— 这是「预留在线」的核心扩展点。
///
/// 当前实现是 `LocalLibrarySource`（读取沙盒内音频文件）。
/// 将来要接入流媒体时，只需新增一个 `StreamingSource: MusicSource`，
/// 实现 `fetchSongs()` 与 `resolveURL(for:)`（例如返回 CDN / 播放列表地址），
/// 播放器、曲库、UI 完全不需要改动。
protocol MusicSource {
    /// 当前来源支持的类型
    var kind: MusicSourceKind { get }

    /// 拉取来源内的全部歌曲
    func fetchSongs() async throws -> [Song]

    /// 解析某首歌的可播放地址（本地为文件 URL，流媒体为网络地址）
    func resolveURL(for song: Song) -> URL
}

extension MusicSource {
    var kind: MusicSourceKind { .local }
}
