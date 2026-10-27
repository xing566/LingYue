import Foundation

/// 歌词行
struct LyricsLine: Identifiable, Equatable {
    let id = UUID()
    let time: TimeInterval
    let text: String
}

/// 歌词服务：按「歌名+歌手」联网匹配歌词（网易云接口），本地缓存，解析 LRC。
enum LyricsService {

    private static var cacheDir: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lyrics", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func cacheFile(title: String, artist: String) -> URL {
        let key = "\(title)|\(artist)".replacingOccurrences(of: "/", with: "_")
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? title
        return cacheDir.appendingPathComponent(key).appendingPathExtension("lrc")
    }

    /// 取歌词行列表；无歌词则返回空数组。优先本地缓存，其次联网拉取并缓存。
    static func fetch(title: String, artist: String, lyricID: Int? = nil) async -> [LyricsLine] {
        let file = cacheFile(title: title, artist: artist)
        // 1) 缓存
        if let lrc = try? String(contentsOf: file, encoding: .utf8), !lrc.isEmpty {
            let lines = parseLRC(lrc)
            if !lines.isEmpty { return lines }
        }
        // 2) 联网
        let raw: String?
        if let id = lyricID {
            raw = await NetEaseService.lyric(songID: id)
        } else {
            if let id = await NetEaseService.findSongID(title: title, artist: artist) {
                raw = await NetEaseService.lyric(songID: id)
            } else {
                raw = nil
            }
        }
        guard let raw, !raw.isEmpty else { return [] }
        try? raw.write(to: file, atomically: true, encoding: .utf8) // 缓存
        return parseLRC(raw)
    }

    /// 解析 LRC：提取带时间戳的歌词行，忽略元信息行。
    static func parseLRC(_ text: String) -> [LyricsLine] {
        var lines: [LyricsLine] = []
        let pattern = "\\[\\s*(\\d{1,3}):(\\d{1,2})(?:[.:](\\d{1,3}))?\\s*\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine as NSString
            let matches = regex.matches(in: rawLine, options: [], range: NSRange(location: 0, length: line.length))
            guard !matches.isEmpty else { continue }
            let contentStart = matches.last!.range.location + matches.last!.range.length
            let lyricTrimmed = (line.substring(from: min(contentStart, line.length))).trimmingCharacters(in: .whitespaces)
            if lyricTrimmed.isEmpty { continue }
            for m in matches {
                let seg = line.substring(with: m.range)
                guard let rm = try? NSRegularExpression(pattern: "(\\d{1,3}):(\\d{1,2})(?:[.:](\\d{1,3}))?"),
                      let r = rm.firstMatch(in: seg, options: [], range: NSRange(location: 0, length: (seg as NSString).length))
                else { continue }
                let min = Double((seg as NSString).substring(with: r.range(at: 1))) ?? 0
                let sec = Double((seg as NSString).substring(with: r.range(at: 2))) ?? 0
                var ms = 0.0
                if r.range(at: 3).location != NSNotFound {
                    let frac = (seg as NSString).substring(with: r.range(at: 3))
                    ms = (Double(frac) ?? 0) / pow(10.0, Double(frac.count))
                }
                let time = min * 60 + sec + ms
                lines.append(LyricsLine(time: time, text: lyricTrimmed))
            }
        }
        return lines.sorted { $0.time < $1.time }
    }
}
