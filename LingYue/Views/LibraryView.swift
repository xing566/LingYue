import SwiftUI
import UniformTypeIdentifiers

/// 音乐库：本地（歌曲/专辑/歌手）与在线（歌单）。
struct LibraryView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerManager.self) private var player
    @State private var segment: Segment = .songs
    @State private var sourceMode: SourceMode = .local
    @State private var importPresented = false
    @State private var onlineSearchPresented = false

    enum Segment: String, CaseIterable {
        case songs = "歌曲", albums = "专辑", artists = "歌手"
    }

    enum SourceMode: String, CaseIterable {
        case local = "本地曲库", online = "在线歌单"
    }

    var body: some View {
        @Bindable var library = library
        VStack(spacing: 0) {
            // 来源切换：本地 / 在线
            Picker("来源", selection: $sourceMode) {
                ForEach(SourceMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 6)

            if sourceMode == .local {
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
            } else {
                onlineList
            }
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
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                Task { await library.importFiles(from: urls) }
            }
        }
        .sheet(isPresented: $onlineSearchPresented) {
            OnlineSearchView()
        }
        .overlay {
            if sourceMode == .local && library.songs.isEmpty && !library.isScanning {
                emptyState
            }
        }
        .task(id: sourceMode) {
            if sourceMode == .online { await library.fetchOnlineSongs() }
        }
    }

    // MARK: 在线歌单

    private var onlineList: some View {
        Group {
            if library.onlineSongs.isEmpty {
                VStack(spacing: 12) {
                    if library.isFetchingOnline {
                        ProgressView()
                        Text("正在加载在线歌单…")
                            .font(.system(size: 13)).foregroundColor(.secondary)
                    } else {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 44)).foregroundColor(.secondary)
                        Text("在线歌单为空或加载失败")
                            .font(.headline)
                        Text("可在「设置 → 在线歌单」填入你自己的歌单地址，\n否则使用内置默认歌单（公版名曲）。")
                            .font(.system(size: 13)).foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        Button {
                            onlineSearchPresented = true
                        } label: {
                            Label("在线搜索音乐（网络 / 网页）", systemImage: "magnifyingglass")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.accentColor)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(30)
            } else {
                List {
                    Section {
                        Button {
                            player.play(library.onlineSongs[0], in: library.onlineSongs)
                        } label: {
                            Label("播放全部", systemImage: "play.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.accentColor)
                        }
                        Button {
                            Task { await library.fetchOnlineSongs() }
                        } label: {
                            Label("刷新歌单", systemImage: "arrow.clockwise")
                                .foregroundColor(.secondary)
                        }
                        Button {
                            onlineSearchPresented = true
                        } label: {
                            Label("在线搜索音乐（网络 / 网页）", systemImage: "magnifyingglass")
                                .foregroundColor(.secondary)
                        }
                    }
                    ForEach(library.onlineSongs) { song in
                        SongRowView(song: song, trailing: AnyView(
                            Image(systemName: "arrow.down.to.line.compact")
                                .foregroundColor(.secondary)
                        ))
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                            ArtworkView(data: album.songs.first?.artworkData, artworkURL: album.songs.first?.artworkURL, size: 160)
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
                NavigationLink {
                    ArtistDetailView(name: artist.name, songs: artist.songs)
                } label: {
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
