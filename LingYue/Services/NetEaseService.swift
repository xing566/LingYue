import Foundation

/// 网易云音乐非官方接口（多公开实例自动切换）。
///
/// 搜索 / 歌词 / 封面全可用；在线播放地址仅免费曲目可用（VIP 曲目返回空）。
/// 内置多个社区公开实例，按顺序尝试，失败自动切换下一个；用户可在设置页追加自定义实例。
enum NetEaseService {

    /// 社区公开实例（按可用性排序，首个失败自动切换下一个）
    static let defaultBaseURLs: [String] = [
        "https://netease-cloud-music-api-ivory.vercel.app",
        "https://netease-cloud-music-api-six.vercel.app",
        "https://netease-cloud-music-api-sigma.vercel.app",
        "https://netease-cloud-music-api-eta.vercel.app",
        "https://netease-music-api-kappa.vercel.app",
    ]

    private static let customKey = "netease.customBaseURLs"

    /// 用户自定义实例（设置页追加，持久化）
    static var customBaseURLs: [String] {
        UserDefaults.standard.stringArray(forKey: customKey) ?? []
    }
    static func addCustomBaseURL(_ url: String) {
        let t = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        var all = customBaseURLs
        guard !all.contains(t) else { return }
        all.append(t)
        UserDefaults.standard.set(all, forKey: customKey)
    }
    static func resetCustomBaseURLs() {
        UserDefaults.standard.removeObject(forKey: customKey)
    }

    static var allBaseURLs: [String] {
        var list = defaultBaseURLs
        for c in customBaseURLs where !list.contains(c) { list.append(c) }
        return list
    }

    // MARK: - 搜索结果模型

    struct SongResult: Decodable {
        let id: Int
        let name: String
        let duration: Int?
        let artists: [Artist]?
        let album: Album?
        struct Artist: Decodable { let name: String? }
        struct Album: Decodable { let name: String?; let picUrl: String? }

        var displayArtist: String { (artists ?? []).compactMap { $0.name }.joined(separator: "/") }
        var displayAlbum: String { album?.name ?? "未知专辑" }
        var displayDuration: TimeInterval { TimeInterval(duration ?? 0) / 1000.0 }
        var albumCoverURL: URL? {
            guard let p = album?.picUrl, let u = URL(string: p) else { return nil }
            // 转成更小尺寸的封面，省流量
            return URL(string: p.replacingOccurrences(of: "/y300", with: "/y120").replacingOccurrences(of: "/y200", with: "/y120"))
        }
    }

    struct SearchResponse: Decodable {
        let result: ResultBox?
        struct ResultBox: Decodable { let songs: [SongResult]? }
    }

    struct LyricResponse: Decodable {
        let lrc: LRC?
        let nolyric: Bool?
        struct LRC: Decodable { let lyric: String? }
    }

    struct UrlResponse: Decodable {
        let data: [UrlItem]?
        struct UrlItem: Decodable { let url: String? }
    }

    // MARK: - 请求（多实例自动切换，并发 + 总超时兜底）

    /// 并发尝试所有实例，返回第一个 HTTP 200 响应；整个流程最多等 ~8s 即失败。
    /// 这样歌词/封面查找不会因某个实例卡死而无限转圈（此前最长可达 60s+）。
    private static func requestJSON(_ pathAndQuery: String) async throws -> Data {
        let bases = allBaseURLs
        var reqs: [URLRequest] = []
        for base in bases {
            if let url = URL(string: base + pathAndQuery) {
                var r = URLRequest(url: url)
                r.timeoutInterval = 8
                reqs.append(r)
            }
        }
        guard !reqs.isEmpty else { throw URLError(.badURL) }

        return try await withThrowingTaskGroup(of: Data.self, returning: Data.self) { group in
            for r in reqs {
                group.addTask {
                    let (d, resp) = try await URLSession.shared.data(for: r)
                    if let h = resp as? HTTPURLResponse, h.statusCode == 200, !d.isEmpty { return d }
                    throw URLError(.badServerResponse)
                }
            }
            // 兜底超时：最多等 8s，随后整体失败
            group.addTask {
                try await Task.sleep(nanoseconds: 8_000_000_000)
                throw URLError(.timedOut)
            }
            var lastError: Error = URLError(.cannotFindHost)
            while true {
                let result: Data?
                do {
                    result = try await group.next()
                } catch {
                    lastError = error
                    continue
                }
                if let result { return result }
                throw lastError
            }
        }
    }

    // MARK: - 搜索（返回统一在线候选）

    static func search(_ query: String, limit: Int = 30) async throws -> [OnlineCandidate] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let q = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        let data = try await requestJSON("/search?keywords=\(q)&limit=\(limit)")
        let dec = try JSONDecoder().decode(SearchResponse.self, from: data)
        guard let songs = dec.result?.songs else { return [] }
        return songs.map { s in
            OnlineCandidate(title: s.name,
                            artist: s.displayArtist,
                            album: s.displayAlbum,
                            artworkURL: s.albumCoverURL,
                            streamURL: nil, // 播放地址需单独查询
                            duration: s.displayDuration,
                            sourceName: "网易云",
                            lyricID: s.id)
        }
    }

    /// 查询某首歌的在线播放地址（免费曲目可用，VIP 返回 nil）
    static func playURL(songID: Int) async -> URL? {
        do {
            let data = try await requestJSON("/song/url?id=\(songID)&br=128000")
            let dec = try JSONDecoder().decode(UrlResponse.self, from: data)
            guard let url = dec.data?.first?.url, let u = URL(string: url) else { return nil }
            return u
        } catch { return nil }
    }

    /// 取歌词（LRC 纯文本），无则返回 nil
    static func lyric(songID: Int) async -> String? {
        do {
            let data = try await requestJSON("/lyric?id=\(songID)")
            let dec = try JSONDecoder().decode(LyricResponse.self, from: data)
            if let n = dec.nolyric, n { return nil }
            if let l = dec.lrc?.lyric, !l.isEmpty { return l }
            return nil
        } catch { return nil }
    }

    /// 按歌名+歌手搜索，返回第一个匹配结果的歌曲ID（用于取歌词/封面）
    static func findSongID(title: String, artist: String) async -> Int? {
        let q = "\(title) \(artist)".trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return nil }
        do {
            let qq = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
            let data = try await requestJSON("/search?keywords=\(qq)&limit=5")
            let dec = try JSONDecoder().decode(SearchResponse.self, from: data)
            guard let songs = dec.result?.songs else { return nil }
            return songs.first?.id
        } catch { return nil }
    }

    /// 按歌名+歌手查封面
    static func coverURL(title: String, artist: String) async -> URL? {
        let q = "\(title) \(artist)".trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return nil }
        do {
            let qq = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
            let data = try await requestJSON("/search?keywords=\(qq)&limit=5")
            let dec = try JSONDecoder().decode(SearchResponse.self, from: data)
            guard let first = dec.result?.songs?.first else { return nil }
            return first.albumCoverURL
        } catch { return nil }
    }
}
