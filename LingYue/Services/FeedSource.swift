import Foundation

/// 通用 RSS / 播客 / 有声书 feed 解析：从任意 feed URL 提取每条章节的标题与 mp3 直链。
/// 供 Librivox 搜索与「自定义源」复用。
struct FeedSource {

    /// 解析 feed 的章节，返回可播放的 Song 列表（fileURL 为远程 mp3）。
    static func fetchChapters(from url: URL) async -> [Song] {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return [] }
        guard let xml = String(data: data, encoding: .utf8) else { return [] }
        var songs: [Song] = []
        let items = xml.components(separatedBy: "<item>").dropFirst()
        for item in items {
            let title = match(item, pattern: "<title>(.*?)</title>")
            let enclosure = match(item, pattern: "<enclosure[^>]*url=\"([^\"]*)\"")
            let mediaURL = match(item, pattern: "<media:content[^>]*url=\"([^\"]*)\"")
            let rawURL = enclosure ?? mediaURL
            guard let rawURL, !rawURL.isEmpty,
                  let u = RemotePlaylistSource.encode(unescape(rawURL)) else { continue }
            songs.append(Song(title: unescape(title ?? "章节"),
                              artist: "有声书",
                              album: "有声书",
                              artworkURL: nil,
                              fileURL: u,
                              duration: 0,
                              source: .streaming))
        }
        return songs
    }

    private static func match(_ text: String, pattern: String) -> String? {
        guard let rx = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
        else { return nil }
        let ns = text as NSString
        guard let m = rx.firstMatch(in: text, options: [], range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1 else { return nil }
        return ns.substring(with: m.range(at: 1))
    }

    private static func unescape(_ s: String) -> String {
        var out = s
        let map: [(String, String)] = [("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"),
                                       ("&quot;", "\""), ("&apos;", "'"), ("&#39;", "'")]
        for (a, b) in map { out = out.replacingOccurrences(of: a, with: b) }
        return out
    }
}
