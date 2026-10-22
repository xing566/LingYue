import SwiftUI

/// 专辑详情页
struct AlbumDetailView: View {
    @Environment(PlayerManager.self) private var player
    let album: AlbumGroup

    var body: some View {
        List {
            Section {
                HStack(spacing: 16) {
                    ArtworkView(data: album.songs.first?.artworkData, artworkURL: album.songs.first?.artworkURL, size: 120)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(album.album)
                            .font(.title2.weight(.bold))
                            .lineLimit(2)
                        Text(album.artist)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("\(album.songs.count) 首歌曲")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 8)
            }
            Section {
                Button {
                    player.play(album.songs[0], in: album.songs)
                } label: {
                    Label("播放专辑", systemImage: "play.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
            }
            Section {
                ForEach(Array(album.songs.enumerated()), id: \.element.id) { idx, song in
                    SongRowView(song: song, showIndex: idx)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle(album.album)
        .navigationBarTitleDisplayMode(.inline)
    }
}
