import SwiftUI

/// 歌手详情：展示该歌手的全部歌曲，可播放全部 / 单曲播放。
struct ArtistDetailView: View {
    @Environment(PlayerManager.self) private var player
    let name: String
    let songs: [Song]

    var body: some View {
        List {
            if !songs.isEmpty {
                Section {
                    Button {
                        player.play(songs[0], in: songs)
                    } label: {
                        Label("播放全部（\(songs.count) 首）", systemImage: "play.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.accentColor)
                    }
                }
                ForEach(Array(songs.enumerated()), id: \.element.id) { idx, song in
                    SongRowView(song: song, showIndex: idx, queue: songs)
                }
            } else {
                Text("该歌手暂无歌曲").foregroundColor(.secondary)
            }
        }
        .listStyle(.plain)
        .navigationTitle(name.isEmpty ? "歌手" : name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
