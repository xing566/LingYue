import SwiftUI

/// 在线搜索：3 个音乐来源切换（网易云 / iTunes / 公版网络）+ 网页搜索。
/// 通过「音乐库 → 在线歌单 → 在线搜索音乐」进入。
struct OnlineSearchView: View {
    @Environment(PlayerManager.self) private var player
    @Environment(\.dismiss) private var dismiss

    enum Mode: String, CaseIterable {
        case music = "音乐搜索"
        case web = "网页搜索"
    }

    enum MusicSource: String, CaseIterable {
        case netease = "网易云"
        case itunes = "iTunes"
        case archive = "公版网络"
    }

    @State private var query = ""
    @State private var submitted = ""
    @State private var mode: Mode = .music
    @State private var musicSource: MusicSource = .netease
    @State private var results: [OnlineCandidate] = []
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var alertMessage: String?

    private var webURL: URL? {
        let q = submitted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return nil }
        let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        return URL(string: "https://www.bing.com/search?q=\(enc)%20mp3")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("模式", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 6)

                if mode == .music {
                    Picker("来源", selection: $musicSource) {
                        ForEach(MusicSource.allCases, id: \.self) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .onChange(of: musicSource) { _, _ in
                        if !submitted.isEmpty { runSearch() }
                    }

                    musicPane
                } else {
                    webPane
                }
            }
            .navigationTitle("在线搜索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Text("完成") }
                }
            }
            .searchable(text: $query,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "输入歌名 / 歌手")
            .onSubmit(of: .search) { submit() }
            .alert("提示", isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text(alertMessage ?? "")
            }
        }
        .preferredColorScheme(.dark)
    }

    private func submit() {
        submitted = query
        if mode == .music { runSearch() }
    }

    private func runSearch() {
        let q = submitted
        guard !q.isEmpty else { return }
        isLoading = true
        errorText = nil
        Task {
            do {
                switch musicSource {
                case .netease:
                    results = try await NetEaseService.search(q)
                case .itunes:
                    results = try await iTunesService.search(q)
                case .archive:
                    let archiveSongs = try await OnlineSearchSource.search(q)
                    results = archiveSongs.map {
                        OnlineCandidate(title: $0.title, artist: $0.artist, album: $0.album,
                                        artworkURL: $0.artworkURL, streamURL: $0.fileURL,
                                        duration: $0.duration, sourceName: "公版网络", lyricID: nil)
                    }
                }
            } catch {
                errorText = "搜索失败：\(error.localizedDescription)"
                results = []
            }
            isLoading = false
        }
    }

    // MARK: - 音乐搜索

    private var musicPane: some View {
        Group {
            if isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在搜索…").font(.system(size: 13)).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorText {
                VStack(spacing: 10) {
                    Image(systemName: "wifi.exclamationmark").font(.system(size: 40)).foregroundColor(.secondary)
                    Text(errorText).font(.system(size: 13)).foregroundColor(.secondary).multilineTextAlignment(.center)
                }
                .padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if results.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "antenna.radiowaves.left.and.right").font(.system(size: 44)).foregroundColor(.secondary)
                    Text(sourceHint).font(.system(size: 13)).foregroundColor(.secondary).multilineTextAlignment(.center)
                }
                .padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section("\(musicSource.rawValue)搜索结果 \(results.count)") {
                        ForEach(results) { cand in
                            OnlineCandidateRow(candidate: cand, isCurrent: player.currentSong?.title == cand.title) {
                                play(cand)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sourceHint: String {
        switch musicSource {
        case .netease: return "搜索国内歌手全量曲库（免费曲目可在线播，VIP曲仅可看歌词）"
        case .itunes: return "国际/港台曲目，免费仅30秒试听"
        case .archive: return "公版音乐（Internet Archive），可完整播放"
        }
    }

    private func play(_ cand: OnlineCandidate) {
        guard cand.playable, let song = cand.makeSong() else {
            alertMessage = "「\(cand.title)」该曲受版权保护或需会员，无法在线播放。\n可查看歌词与封面，或换用公版网络/其他来源。"
            return
        }
        player.play(song)
    }

    // MARK: 网页搜索

    private var webPane: some View {
        Group {
            if let url = webURL {
                BrowserView(initialURL: url)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "safari").font(.system(size: 44)).foregroundColor(.secondary)
                    Text("输入关键词后按搜索，在网页中查找结果\n（打开内置浏览器，可浏览 / 返回 / 缓存到本地）")
                        .font(.system(size: 13)).foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

/// 在线候选单行：封面 / 标题 / 歌手 / 来源 + 可播状态
struct OnlineCandidateRow: View {
    let candidate: OnlineCandidate
    let isCurrent: Bool
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let url = candidate.artworkURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default:
                        LinearGradient(colors: [Color(red: 0.35, green: 0.42, blue: 0.65), Color(red: 0.16, green: 0.18, blue: 0.28)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(LinearGradient(colors: [Color(red: 0.35, green: 0.42, blue: 0.65), Color(red: 0.16, green: 0.18, blue: 0.28)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
                    .overlay(Image(systemName: "music.note").foregroundColor(.white.opacity(0.85)))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(isCurrent ? .accentColor : .primary)
                    .lineLimit(1)
                Text(candidate.artist)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Text(candidate.sourceName)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    if !candidate.playable {
                        Text("VIP/不可播")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.orange)
                    }
                }
            }

            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}
