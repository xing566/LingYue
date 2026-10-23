import Foundation

/// 在线「网络搜索」源：调用 Internet Archive 免费接口，搜索可播放的公版/公开音乐。
///
/// 无需 API Key，返回的歌曲与内置默认歌单同源（archive.org 直链），可直接用 AVPlayer 播放。
/// 流程：advancedsearch 按关键词搜出 audio 条目 → 逐个取 metadata 找第一个可播放音频文件 → 组装 Song。
enum OnlineSearchSource {

    /// 兼容字符串 / 字符串数组 的宽松解码（IA 返回字段类型不稳定，可能为单值或数组）
    struct FlexString: Decodable {
        let value: String?
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let s = try? c.decode(String.self) { value = s }
            else if let a = try? c.decode([String].self) { value = a.first }
            else { value = nil }
        }
    }

    struct IASearchResponse: Decodable {
        struct Response: Decodable {
            struct Doc: Decodable {
                let identifier: String
                let title: FlexString?
                let creator: FlexString?
                let mediatype: String?
            }
            let docs: [Doc]
        }
        let response: Response
    }

    struct IAMetadataResponse: Decodable {
        struct File: Decodable {
            let name: String
            let format: String?
        }
        let files: [File]
    }

    /// 搜索并返回可播放歌曲列表。
    /// - `limit`: 搜索返回的候选条数
    /// - `resolveLimit`: 最多解析前 N 个条目的音频文件，控制网络请求数
    static func search(_ query: String, limit: Int = 30, resolveLimit: Int = 12) async throws -> [Song] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let q = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        guard let searchURL = URL(
            string: "https://archive.org/advancedsearch.php?q=\(q)&fl%5B%5D=identifier&fl%5B%5D=title&fl%5B%5D=creator&fl%5B%5D=mediatype&rows=\(limit)&page=1&output=json"
        ) else { return [] }

        let (data, _) = try await URLSession.shared.data(from: searchURL)
        let decoded = try JSONDecoder().decode(IASearchResponse.self, from: data)

        var songs: [Song] = []
        var resolved = 0
        for doc in decoded.response.docs {
            if resolved >= resolveLimit { break }
            guard doc.mediatype == "audio" || doc.mediatype == nil else { continue }
            let title = doc.title?.value ?? doc.identifier
            // 单个条目解析失败（如 metadata 请求失败）时跳过，不中断整次搜索
            if let song = try? await makeSong(identifier: doc.identifier,
                                              title: title,
                                              creator: doc.creator?.value) {
                songs.append(song)
                resolved += 1
            }
        }
        return songs
    }

    private static func makeSong(identifier: String, title: String, creator: String?) async throws -> Song? {
        guard let metaURL = URL(string: "https://archive.org/metadata/\(identifier)") else { return nil }
        let (data, _) = try await URLSession.shared.data(from: metaURL)
        let meta = try JSONDecoder().decode(IAMetadataResponse.self, from: data)
        guard let file = meta.files.first(where: { isPlayable($0) }) else { return nil }
        let base = "https://archive.org/download/\(identifier)/"
        guard let url = RemotePlaylistSource.encode(base + file.name) else { return nil }
        return Song(title: title,
                    artist: creator ?? "网络搜索",
                    album: "在线搜索",
                    artworkURL: nil,
                    fileURL: url,
                    duration: 0,
                    source: .streaming)
    }

    private static func isPlayable(_ file: IAMetadataResponse.File) -> Bool {
        let name = file.name.lowercased()
        if name.hasSuffix(".mp3") || name.hasSuffix(".ogg") || name.hasSuffix(".m4a")
            || name.hasSuffix(".aac") || name.hasSuffix(".wav") || name.hasSuffix(".flac") {
            return true
        }
        if let fmt = file.format?.lowercased(),
           fmt.contains("mp3") || fmt.contains("vorbis") || fmt.contains("aac") || fmt.contains("flac") {
            return true
        }
        return false
    }
}
