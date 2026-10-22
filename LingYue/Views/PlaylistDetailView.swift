import SwiftUI

/// 播放列表详情：可播放、可从曲库添加歌曲、可移除歌曲
struct PlaylistDetailView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerManager.self) private var player
    let playlistID: UUID
    @State private var showAddPicker = false

    private var playlist: Playlist? {
        library.playlists.first { $0.id == playlistID }
    }

    var body: some View {
        Group {
            if let pl = playlist {
                let songs = library.songs(in: pl)
                List {
                    Section {
                        HStack(spacing: 16) {
                            ArtworkView(data: songs.first?.artworkData, artworkURL: songs.first?.artworkURL, size: 100)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(pl.name).font(.title2.weight(.bold))
                                Text("\(songs.count) 首歌曲").font(.caption).foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    if !songs.isEmpty {
                        Section {
                            Button {
                                player.play(songs[0], in: songs)
                            } label: {
                                Label("播放全部", systemImage: "play.fill")
                                    .foregroundColor(.accentColor)
                            }
                            Button {
                                showAddPicker = true
                            } label: {
                                Label("添加到播放列表", systemImage: "plus.circle")
                            }
                        }
                        Section {
                            ForEach(Array(songs.enumerated()), id: \.element.id) { idx, song in
                                SongRowView(song: song, showIndex: idx, trailing: AnyView(
                                    Button {
                                        library.removeSong(song.id, from: pl.id)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.borderless)
                                ))
                            }
                        }
                    } else {
                        Section {
                            Button {
                                showAddPicker = true
                            } label: {
                                Label("从曲库添加歌曲", systemImage: "plus.circle")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .sheet(isPresented: $showAddPicker) {
                    AddToPlaylistSheet(playlistID: pl.id)
                }
                .navigationTitle(pl.name)
                .navigationBarTitleDisplayMode(.inline)
            } else {
                Text("播放列表不存在")
                    .foregroundColor(.secondary)
            }
        }
    }
}

/// 从曲库挑歌加入播放列表
struct AddToPlaylistSheet: View {
    @Environment(LibraryStore.self) private var library
    @Environment(\.dismiss) private var dismiss
    let playlistID: UUID
    @State private var selected = Set<UUID>()

    var body: some View {
        NavigationStack {
            List(library.songs) { song in
                HStack {
                    ArtworkView(data: song.artworkData, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.displayTitle).font(.system(size: 15, weight: .medium))
                        Text(song.artist).font(.system(size: 13)).foregroundColor(.secondary)
                    }
                    Spacer()
                    if selected.contains(song.id) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.accentColor)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if selected.contains(song.id) { selected.remove(song.id) }
                    else { selected.insert(song.id) }
                }
            }
            .navigationTitle("选择歌曲")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        library.addToPlaylist(playlistID, songIDs: Array(selected))
                        dismiss()
                    }
                    .disabled(selected.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }
}
