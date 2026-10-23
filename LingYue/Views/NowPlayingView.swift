import SwiftUI
import AVKit

/// 全屏播放页（以 sheet 呈现）
struct NowPlayingView: View {
    @Environment(PlayerManager.self) private var player
    @Environment(\.dismiss) private var dismiss
    @State private var draggingTime: Double? = nil

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
                    Spacer()
                    Text("正在播放")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button {} label: {
                        Image(systemName: "ellipsis")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)

                Spacer()

                // 封面 / 视频画面
                if let song = player.currentSong {
                    if isVideo, let av = player.avPlayer {
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

                    // 标题 / 歌手
                    VStack(spacing: 6) {
                        Text(song.displayTitle)
                            .font(.title2.weight(.bold))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                        Text(song.artist)
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)

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
    }

    private var repeatIcon: String {
        switch player.repeatMode {
        case .one: return "repeat.1"
        case .all: return "repeat"
        case .off: return "repeat"
        }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        guard t.isFinite, t > 0 else { return "0:00" }
        let total = Int(t)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
