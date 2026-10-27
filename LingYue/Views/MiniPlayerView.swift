import SwiftUI

/// 迷你播放条（底部悬浮）
struct MiniPlayerView: View {
    @Environment(PlayerManager.self) private var player
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let song = player.currentSong {
                ArtworkView(song: song, size: 44)
                    .onTapGesture { onTap() }
                VStack(alignment: .leading, spacing: 2) {
                    Text(song.displayTitle)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(song.artist)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
                .onTapGesture { onTap() }
                Spacer()
                Button {
                    let next = (player.repeatMode.rawValue + 1) % 3
                    player.repeatMode = PlayerManager.RepeatMode(rawValue: next) ?? .off
                } label: {
                    Image(systemName: repeatIcon)
                        .font(.system(size: 17))
                        .foregroundColor(player.repeatMode != .off ? .accentColor : .secondary)
                }
                Button {
                    player.playPrevious()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                }
                Button {
                    player.togglePlayPause()
                } label: {
                    Image(systemName: player.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 34))
                        .foregroundColor(.primary)
                }
                Button {
                    player.playNext()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 4)
    }

    private var repeatIcon: String {
        switch player.repeatMode {
        case .one: return "repeat.1"
        default: return "repeat"
        }
    }
}
