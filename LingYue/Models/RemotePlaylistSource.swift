import Foundation

/// 方案1：在线歌单源。
/// - 未设置自定义地址时，使用内置默认歌单（Internet Archive 公版名曲直链，已验证可播放）。
/// - 在设置里填入自定义歌单 JSON 地址后，改为从该地址拉取，格式为数组：[{title, artist?, url}]
struct RemotePlaylistSource: MusicSource {
    let kind: MusicSourceKind = .streaming
    var feedURLString: String?

    struct PlaylistItem: Decodable {
        let title: String
        let artist: String?
        let url: String
    }

    func fetchSongs() async throws -> [Song] {
        if let feed = feedURLString, !feed.isEmpty, let url = Self.encode(feed) {
            let (data, _) = try await URLSession.shared.data(from: url)
            let items = try JSONDecoder().decode([PlaylistItem].self, from: data)
            return items.enumerated().compactMap { idx, item in
                guard let u = Self.encode(item.url) else { return nil }
                return Song(
                    id: Song.stableID(from: u.absoluteString),
                    title: item.title,
                    artist: item.artist ?? "未知艺术家",
                    album: "在线歌单",
                    artworkURL: nil,
                    fileURL: u,
                    duration: 0,
                    source: .streaming
                )
            }
        }
        return Self.builtinSongs
    }

    func resolveURL(for song: Song) -> URL { song.fileURL }

    /// 内置默认歌单（Internet Archive 公版名曲直链）
    static var builtinSongs: [Song] {
        let items: [(String, String)] = [
            ("Moonlight Sonata · 贝多芬", "https://archive.org/download/78_8748-Moonlight-Sonata-in-C-sharp-minor-op-27-no-2-1st-movement-og-2nd-movement/8748-Moonlight-Sonata-in-C-sharp-minor-op-27-no-2-1st-movement-og-2nd-movement.mp3"),
            ("Moonlight Sonata (3rd Movement)", "https://archive.org/download/Moonlight_Sonata_3rd_MovementElectric_harpsicord_mix/MoonlightSonata3rdMovement.mp3"),
            ("Für Elise, WoO 59", "https://archive.org/download/WoO59PocoMotoBagatelleInAMinorFurElise/FrEliseWoo59.mp3"),
            ("Für Elise ( Ringtone)", "https://archive.org/download/fureliseringtone/Für Elise (Ringtone).mp3"),
            ("Canon In D Major (Piano/Orchestra)", "https://archive.org/download/canon-in-d-major-piano-orchestra_202603/Canon In D Major (Piano-Orchestra).mp3"),
            ("Canon In D · 婚礼版 (Cello & Piano)", "https://archive.org/download/canon-in-d-pachelbels-canon-cello-piano-best-wedding-version_202607/Canon in D (Pachelbel's Canon) - Cello & Piano [BEST WEDDING VERSION].mp3"),
            ("Ode To Joy · 欢乐颂", "https://archive.org/download/tvtunes_30723/Muppets - Ode To Joy.mp3"),
            ("Ode to joy (Version) · J. Elias Diez", "https://archive.org/download/jamendo-530095/01-2059851-J. Elias Diez-Ode to joy _Version_.mp3"),
            ("Nocturne · 肖邦夜曲 (1924)", "https://archive.org/download/1924-nocturne-chopin-jascha-heifetz-vic-74811/1924 Nocturne - Chopin - Jascha Heifetz - VIC 74811.mp3"),
            ("Nocturne Chopin (Ringtone)", "https://archive.org/download/nocturnechopinringtone/Nocturne - Chopin (Ringtone).mp3"),
            ("Gymnopédie No.1 · Erik Satie", "https://archive.org/download/gymnopedie-1-erik-satie-176573_202506/gymnopedie-1-erik-satie-176573.mp3"),
            ("Gymnopédie No.1 (管弦乐版)", "https://archive.org/download/78_gymnopedie-no-1_boston-symphony-orchestra-satie-debussy-serge-koussevitsky_gbia7003496a/GYMNOPEDIE No. 1 - BOSTON SYMPHONY ORCHESTRA.mp3")
        ]
        return items.compactMap { title, url in
            guard let u = encode(url) else { return nil }
            return Song(id: Song.stableID(from: u.absoluteString),
                        title: title, artist: "公版音乐", album: "在线·默认歌单",
                        artworkURL: nil, fileURL: u, duration: 0, source: .streaming)
        }
    }

    /// 对含空格/特殊字符的 URL 做百分号编码
    static func encode(_ s: String) -> URL? {
        let allowed = CharacterSet.urlQueryAllowed
        let encoded = s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
        return URL(string: encoded)
    }
}
