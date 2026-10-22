import SwiftUI

/// 歌曲封面/默认占位图
struct ArtworkView: View {
    let data: Data?
    var size: CGFloat

    var body: some View {
        Group {
            if let data, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
            } else {
                // 无封面时的渐变占位 + 音符图标
                ZStack {
                    LinearGradient(
                        colors: [Color(red: 0.35, green: 0.42, blue: 0.65),
                                 Color(red: 0.16, green: 0.18, blue: 0.28)],
                        startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.3, weight: .semibold))
                        .foregroundColor(.white.opacity(0.85))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.12, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 5, x: 0, y: 2)
    }
}

/// 列表中的单行歌曲
struct SongRowView: View {
    @Environment(PlayerManager.self) private var player
    let song: Song
    var showIndex: Int? = nil
    var trailing: AnyView? = nil

    var body: some View {
        HStack(spacing: 12) {
            if let idx = showIndex {
                Text("\(idx + 1)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(player.currentSong?.id == song.id ? .accentColor : .secondary)
                    .frame(width: 22)
            } else {
                ArtworkView(data: song.artworkData, size: 44)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(song.displayTitle)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(player.currentSong?.id == song.id ? .accentColor : .primary)
                    .lineLimit(1)
                Text(song.artist)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            trailing ?? AnyView(
                Text(song.formattedDuration)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundColor(.secondary)
            )
        }
        .contentShape(Rectangle())
        .onTapGesture {
            player.play(song)
        }
    }
}
