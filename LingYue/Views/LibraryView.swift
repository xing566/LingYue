import SwiftUI
import UniformTypeIdentifiers

/// 音乐库：歌曲 / 专辑 / 歌手 三个分段，支持导入本地音频。
struct LibraryView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerManager.self) private var player
    @State private var segment: Segment = .songs
    @State private var importPresented = false

    enum Segment: String, CaseIterable {
        case songs = "歌曲", albums = "专辑", artists = "歌手"
    }

    var body: some View {
        @Bindable var library = library
        VStack(spacing: 0) {
            Picker("分类", selection: $segment) {
                ForEach(Segment.allCases, id: \.self) { seg in
                    Text(seg.rawValue).tag(seg)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            Group {
                switch segment {
                case .songs: songsList
                case .albums: albumsList
                case .artists: artistsList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("音乐库")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    importPresented = true
                } label: {
                    Label("导入", systemImage: "plus.circle")
                }
            }
        }
        .fileImporter(
            isPresented: $importPresented,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                Task { await library.importFiles(from: urls) }
            }
        }
        .overlay {
            if library.songs.isEmpty && !library.isScanning {
                emptyState
            }
        }
    }

    // MARK: 歌曲列表

    private var songsList: some View {
        List {
            if !library.songs.isEmpty {
                Section {
                    Button {
                        player.play(library.songs[0], in: library.songs)
                    } label: {
                        Label("播放全部", systemImage: "play.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.accentColor)
                    }
                }
            }
            ForEach(library.songs) { song in
                SongRowView(song: song)
            }
        }
        .listStyle(.plain)
    }

    // MARK: 专辑

    private var albumsList: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 16)], spacing: 20) {
                ForEach(library.albums) { album in
                    NavigationLink(value: album) {
                        VStack(alignment: .leading, spacing: 8) {
                            ArtworkView(data: album.songs.first?.artworkData, size: 160)
                            Text(album.album)
                                .font(.system(size: 14, weight: .medium))
                                .lineLimit(1)
                                .foregroundColor(.primary)
                            Text(album.artist)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationDestination(for: AlbumGroup.self) { album in
            AlbumDetailView(album: album)
        }
    }

    // MARK: 歌手

    private var artistsList: some View {
        List {
            ForEach(library.artists, id: \.name) { artist in
                HStack(spacing: 12) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(artist.name).font(.system(size: 16, weight: .medium))
                        Text("\(artist.songs.count) 首歌曲").font(.system(size: 13)).foregroundColor(.secondary)
                    }
                }
            }
        }
        .listStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "music.note.list")
                .font(.system(size: 56))
                .foregroundColor(.secondary)
            Text("曲库空空如也")
                .font(.headline)
            Text("点击右上角「导入」从“文件”App 添加音频，\n支持 mp3 / m4a / flac / wav 等格式。")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }
}
