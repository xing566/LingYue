import SwiftUI

/// 歌曲封面/默认占位图（支持本地数据封面与网络封面）
struct ArtworkView: View {
    let data: Data?
    var artworkURL: URL?
    let size: CGFloat

    init(data: Data?, artworkURL: URL? = nil, size: CGFloat) {
        self.data = data
        self.artworkURL = artworkURL
        self.size = size
    }

    init(song: Song, size: CGFloat) {
        self.data = song.artworkData
        self.artworkURL = song.artworkURL
        self.size = size
    }

    private var placeholder: some View {
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

    var body: some View {
        Group {
            if let url = artworkURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        placeholder
                    case .empty:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else if let data, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
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
                ArtworkView(song: song, size: 44)
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
