import Foundation

/// 在线小说 / 有声书来源：Librivox 免费公版有声书 API（无需 Key）。
///
/// 搜索书名/作者返回若干部有声书，每部含分章节音频（url 直链，可播放）。
/// 复用 `FlexString`（在线音乐搜索里定义的宽松解码）与 `RemotePlaylistSource.encode`。
enum LibrivoxSource {

    struct Response: Decodable {
        struct Book: Decodable {
            let title: OnlineSearchSource.FlexString?
            let author: OnlineSearchSource.FlexString?
            let sections: [Section]?
        }
        struct Section: Decodable {
            let title: OnlineSearchSource.FlexString?
            let url: OnlineSearchSource.FlexString?
        }
        let books: [Book]?
    }

    /// 搜索返回有声书列表（每部含章节歌曲）
    static func search(_ query: String, limit: Int = 20) async throws -> [Audiobook] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let q = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        guard let url = URL(string: "https://librivox.org/api/feed/audiobooks?q=\(q)&format=json&limit=\(limit)") else { return [] }

        let (data, _) = try await URLSession.shared.data(from: url)
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let books = decoded.books else { return [] }

        var result: [Audiobook] = []
        for b in books {
            let sections = (b.sections ?? []).compactMap { s -> Song? in
                guard let urlString = s.url?.value, let u = RemotePlaylistSource.encode(urlString) else { return nil }
                return Song(title: s.title?.value ?? "章节",
                            artist: b.author?.value ?? "Librivox",
                            album: b.title?.value ?? "有声书",
                            artworkURL: nil,
                            fileURL: u,
                            duration: 0,
                            source: .streaming)
            }
            guard !sections.isEmpty, let title = b.title?.value, !title.isEmpty else { continue }
            result.append(Audiobook(title: title,
                                    author: b.author?.value ?? "Librivox",
                                    sections: sections))
        }
        return result
    }
}
