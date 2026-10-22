import SwiftUI

/// 迷你播放条（底部悬浮）
struct MiniPlayerView: View {
    @Environment(PlayerManager.self) private var player
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let song = player.currentSong {
                ArtworkView(song: song, size: 44)
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
                Spacer()
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
        .onTapGesture { onTap() }
        .shadow(color: .black.opacity(0.4), radius: 12, x: 0, y: 4)
    }
}
