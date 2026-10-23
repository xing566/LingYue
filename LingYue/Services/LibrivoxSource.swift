import Foundation

/// 在线小说 / 有声书来源：Librivox 免费公版有声书 API（无需 Key）。
///
/// 书单接口不内嵌章节，需再从每本书的 RSS 抓取章节 mp3 直链（可播放、可下载）。
enum LibrivoxSource {

    struct Author: Decodable {
        let first_name: String?
        let last_name: String?
    }

    struct BookBrief: Decodable {
        let id: String?
        let title: OnlineSearchSource.FlexString?
        let authors: [Author]?
        let url_rss: OnlineSearchSource.FlexString?
    }

    struct Response: Decodable {
        let books: [BookBrief]?
    }

    /// 搜索返回有声书列表（每部从 RSS 解析出章节歌曲）
    static func search(_ query: String, limit: Int = 8) async throws -> [Audiobook] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let q = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        guard let url = URL(string: "https://librivox.org/api/feed/audiobooks?q=\(q)&format=json&limit=\(limit)")
        else { return [] }

        let (data, _) = try await URLSession.shared.data(from: url)
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let books = decoded.books else { return [] }

        var result: [Audiobook] = []
        for b in books {
            let title = b.title?.value ?? ""
            guard !title.isEmpty else { continue }
            let rss = URL(string: b.url_rss?.value ?? "https://librivox.org/rss/\(b.id ?? "")")
            let sections = await (rss.flatMap { await FeedSource.fetchChapters(from: $0) } ?? [])
            guard !sections.isEmpty else { continue }
            result.append(Audiobook(title: title,
                                    author: authorName(b.authors),
                                    sections: sections))
        }
        return result
    }

    private static func authorName(_ authors: [Author]?) -> String {
        guard let authors else { return "Librivox" }
        let names = authors.compactMap { a -> String? in
            let joined = [a.first_name ?? "", a.last_name ?? ""]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            return joined.isEmpty ? nil : joined
        }
        return names.isEmpty ? "Librivox" : names.joined(separator: ", ")
    }
}
