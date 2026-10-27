import SwiftUI
import AVKit

/// 全屏播放页（以 sheet 呈现）
struct NowPlayingView: View {
    @Environment(PlayerManager.self) private var player
    @Environment(\.dismiss) private var dismiss
    @State private var draggingTime: Double? = nil
    @State private var showLyrics = false
    @State private var lyrics: [LyricsLine] = []
    @State private var lyricsLoading = false

    /// 常见视频扩展名（本地多格式解码）
    private static let videoExtensions: Set<String> = [
        "mp4", "m4v", "mov", "mkv", "avi", "webm", "flv", "ts", "3gp", "mpg", "mpeg", "wmv", "ogv"
    ]

    private var isVideo: Bool {
        guard let url = player.currentSong?.fileURL else { return false }
        return Self.videoExtensions.contains(url.pathExtension.lowercased())
    }

    var body: some View {
        @Bindable var player = player
        ZStack {
            // 背景
            LinearGradient(
                colors: [Color(red: 0.12, green: 0.13, blue: 0.20),
                         Color(red: 0.03, green: 0.03, blue: 0.06)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // 顶部栏
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    .padding(.trailing, 18)   // 左上角往中间收 ~0.5cm
                    Spacer()
                    Text("正在播放")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button {
                        showLyrics.toggle()
                        if showLyrics, lyrics.isEmpty, !lyricsLoading {
                            loadLyrics()
                        }
                    } label: {
                        Image(systemName: showLyrics ? "music.note.list" : "quote.bubble")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(showLyrics ? .accentColor : .secondary)
                    }
                    Button {} label: {
                        Image(systemName: "ellipsis")
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, 18)    // 右上角往中间收 ~0.5cm
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)

                Spacer()

                // 封面 / 视频画面
                if let song = player.currentSong {
                    if showLyrics {
                        lyricsPanel(song: song)
                    } else if isVideo, let av = player.avPlayer {
                        VideoPlayer(player: av)
                            .frame(width: 340, height: 192)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: .black.opacity(0.6), radius: 24, x: 0, y: 10)
                            .padding(.bottom, 30)
                    } else {
                        ArtworkView(song: song, size: 320)
                            .shadow(color: .black.opacity(0.6), radius: 30, x: 0, y: 12)
                            .padding(.bottom, 40)
                    }

                    if !showLyrics {
                        // 标题 / 歌手
                        VStack(spacing: 6) {
                            Text(song.displayTitle)
                                .font(.title2.weight(.bold))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                            Text(song.artist)
                                .font(.system(size: 16))
                                .foregroundColor(.secondary)
                            if player.isTranscoding {
                                Text("格式转换中…")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.orange)
                            }
                        }
                        .padding(.horizontal, 32)
                        .padding(.bottom, 24)
                    }

                    // 进度条
                    VStack(spacing: 6) {
                        Slider(
                            value: Binding(
                                get: { draggingTime ?? player.currentTime },
                                set: { draggingTime = $0 }
                            ),
                            in: 0...(max(player.duration, 1)),
                            onEditingChanged: { editing in
                                if !editing, let t = draggingTime {
                                    player.seek(to: t)
                                    draggingTime = nil
                                }
                            }
                        )
                        .tint(.white)
                        HStack {
                            Text(formatTime(draggingTime ?? player.currentTime))
                            Spacer()
                            Text(formatTime(player.duration))
                        }
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 28)

                    // 控制按钮
                    HStack(spacing: 48) {
                        Button {
                            player.shuffle.toggle()
                            if player.shuffle { player.shuffleQueue() }
                        } label: {
                            Image(systemName: "shuffle")
                                .font(.system(size: 20))
                                .foregroundColor(player.shuffle ? .accentColor : .white.opacity(0.7))
                        }
                        Button {
                            player.playPrevious()
                        } label: {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 34))
                                .foregroundColor(.white)
                        }
                        Button {
                            player.togglePlayPause()
                        } label: {
                            Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 72))
                                .foregroundColor(.white)
                        }
                        Button {
                            player.playNext()
                        } label: {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 34))
                                .foregroundColor(.white)
                        }
                        Button {
                            let next = (player.repeatMode.rawValue + 1) % 3
                            player.repeatMode = PlayerManager.RepeatMode(rawValue: next) ?? .off
                        } label: {
                            Image(systemName: repeatIcon)
                                .font(.system(size: 20))
                                .foregroundColor(player.repeatMode != .off ? .accentColor : .white.opacity(0.7))
                        }
                    }
                    .padding(.top, 28)

                    // 音量
                    HStack(spacing: 12) {
                        Image(systemName: "speaker.fill").foregroundColor(.secondary).font(.system(size: 13))
                        Slider(value: $player.volume, in: 0...1)
                            .tint(.white)
                        Image(systemName: "speaker.wave.3.fill").foregroundColor(.secondary).font(.system(size: 13))
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 24)

                    Spacer()
                    Spacer()
                }
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: player.currentSong?.id) { _, _ in
            if showLyrics {
                lyrics = []
                loadLyrics()
            }
        }
    }

    private var repeatIcon: String {
        switch player.repeatMode {
        case .one: return "repeat.1"
        case .all: return "repeat"
        case .off: return "repeat"
        }
    }

    // MARK: - 歌词面板

    /// 当前高亮的歌词行
    private var activeLyricIndex: Int {
        guard !lyrics.isEmpty else { return 0 }
        let t = player.currentTime
        var idx = 0
        for i in 0..<lyrics.count where lyrics[i].time <= t { idx = i }
        return idx
    }

    private func lyricsPanel(song: Song) -> some View {
        Group {
            if lyricsLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在匹配歌词…").font(.system(size: 13)).foregroundColor(.secondary)
                }
            } else if lyrics.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "quote.bubble").font(.system(size: 40)).foregroundColor(.secondary)
                    Text("未找到歌词\n（联网搜索歌名+歌手匹配）").font(.system(size: 13)).foregroundColor(.secondary).multilineTextAlignment(.center)
                }
                .padding(24)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 14) {
                            // 顶部留白，保证当前行能居中
                            Color.clear.frame(height: 130)
                            ForEach(Array(lyrics.enumerated()), id: \.element.id) { i, line in
                                Text(line.text)
                                    .font(.system(size: i == activeLyricIndex ? 19 : 15, weight: i == activeLyricIndex ? .bold : .regular))
                                    .foregroundColor(i == activeLyricIndex ? .white : .white.opacity(0.45))
                                    .multilineTextAlignment(.center)
                                    .frame(maxWidth: .infinity)
                                    .id(line.id)
                                    .padding(.horizontal, 28)
                            }
                            Color.clear.frame(height: 130)
                        }
                    }
                    .frame(height: 340)
                    .scrollIndicators(.hidden)
                    .onAppear { scrollToCurrent(proxy) }
                    .onChange(of: activeLyricIndex) { _, _ in
                        if !showLyrics { return }
                        scrollToCurrent(proxy)
                    }
                }
            }
        }
        .frame(height: 360)
        .padding(.bottom, 12)
    }

    private func scrollToCurrent(_ proxy: ScrollViewProxy) {
        guard !lyrics.isEmpty, activeLyricIndex < lyrics.count else { return }
        withAnimation(.easeInOut(duration: 0.35)) {
            proxy.scrollTo(lyrics[activeLyricIndex].id, anchor: .center)
        }
    }

    private func loadLyrics() {
        guard let song = player.currentSong else { return }
        lyricsLoading = true
        lyrics = []
        let title = song.title
        let artist = song.artist
        let lyricID = song.neteaseID
        Task {
            let lines = await LyricsService.fetch(title: title, artist: artist, lyricID: lyricID)
            await MainActor.run {
                lyrics = lines
                lyricsLoading = false
            }
        }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        guard t.isFinite, t > 0 else { return "0:00" }
        let total = Int(t)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
