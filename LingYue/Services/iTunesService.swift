import Foundation

/// iTunes 搜索源（Apple 官方接口，稳定、无需 Key）。
/// 免费歌曲仅提供 30 秒试听预览；用于补充国际/港台曲目、封面与歌词匹配。
enum iTunesService {

    struct Result: Decodable {
        let resultCount: Int
        let results: [Track]
    }
    struct Track: Decodable {
        let trackName: String?
        let artistName: String?
        let collectionName: String?
        let artworkUrl100: String?
        let previewUrl: String?
        let trackTimeMillis: Int?
    }

    static func search(_ query: String, limit: Int = 30) async throws -> [OnlineCandidate] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let q = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        guard let url = URL(string: "https://itunes.apple.com/search?term=\(q)&media=music&entity=song&limit=\(limit)") else { return [] }
        let (data, _) = try await URLSession.shared.data(from: url)
        let dec = try JSONDecoder().decode(Result.self, from: data)
        return dec.results.map { t in
            let preview = t.previewUrl.flatMap { URL(string: $0) }
            let art = t.artworkUrl100.flatMap { URL(string: $0) }
            return OnlineCandidate(title: t.trackName ?? "未知歌曲",
                                   artist: t.artistName ?? "iTunes",
                                   album: t.collectionName ?? "在线专辑",
                                   artworkURL: art,
                                   streamURL: preview, // 30秒预览，可播放
                                   duration: TimeInterval(t.trackTimeMillis ?? 0) / 1000.0,
                                   sourceName: "iTunes",
                                   lyricID: nil)
        }
    }
}
