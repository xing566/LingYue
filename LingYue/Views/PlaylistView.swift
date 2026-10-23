import SwiftUI

/// 播放列表管理
struct PlaylistView: View {
    @Environment(LibraryStore.self) private var library
    @State private var newName = ""
    @State private var showCreate = false

    var body: some View {
        @Bindable var library = library
        Group {
            if library.playlists.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(library.playlists) { playlist in
                        NavigationLink(value: playlist) {
                            HStack(spacing: 12) {
                                playlistCover(playlist)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(playlist.name)
                                        .font(.system(size: 16, weight: .medium))
                                    Text("\(playlist.songs.count) 首歌曲")
                                        .font(.system(size: 13))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .onDelete { offsets in
                        for idx in offsets {
                            library.deletePlaylist(library.playlists[idx].id)
                        }
                    }
                }
                .listStyle(.plain)
                .navigationDestination(for: Playlist.self) { pl in
                    PlaylistDetailView(playlistID: pl.id)
                }
            }
        }
        .navigationTitle("播放列表")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCreate = true } label: {
                    Label("新建", systemImage: "plus")
                }
            }
        }
        .alert("新建播放列表", isPresented: $showCreate) {
            TextField("名称", text: $newName)
            Button("创建") {
                library.createPlaylist(named: newName)
                newName = ""
            }
            Button("取消", role: .cancel) {}
        }
    }

    private func playlistCover(_ pl: Playlist) -> some View {
        let songs = library.songs(in: pl)
        let cover = songs.first?.artworkData
        return ArtworkView(data: cover, artworkURL: songs.first?.artworkURL, size: 48)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "list.bullet")
                .font(.system(size: 56))
                .foregroundColor(.secondary)
            Text("还没有播放列表")
                .font(.headline)
            Text("点击右上角「+」创建你的第一个播放列表。")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .padding(40)
    }
}
