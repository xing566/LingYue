import SwiftUI
import UniformTypeIdentifiers

/// 听小说：在线（Librivox 公版有声书）+ 本地（导入有声书文件）。
struct AudiobookView: View {
    @Environment(PlayerManager.self) private var player
    @State private var segment: Segment = .online
    @State private var query = ""
    @State private var books: [Audiobook] = []
    @State private var localSongs: [Song] = []
    @State private var novels: [Novel] = []
    @State private var isSearching = false
    @State private var errorText: String?
    @State private var importPresented = false
    @State private var importTxtPresented = false

    enum Segment: String, CaseIterable {
        case online = "在线小说"
        case local = "本地有声书"
        case localRead = "本地阅读"
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("来源", selection: $segment) {
                ForEach(Segment.allCases, id: \.self) { seg in
                    Text(seg.rawValue).tag(seg)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 6)

            if segment == .online { onlinePane }
            else if segment == .local { localPane }
            else { localReadPane }
        }
        .navigationTitle("听小说")
        .toolbar {
            if segment == .local {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { importPresented = true } label: {
                        Label("导入有声书", systemImage: "plus.circle")
                    }
                }
            } else if segment == .localRead {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { importTxtPresented = true } label: {
                        Label("导入TXT", systemImage: "plus.circle")
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $importPresented,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                Task {
                    let added = await LocalAudiobookSource.importFiles(from: urls)
                    localSongs = (added + localSongs).sorted { $0.dateAdded > $1.dateAdded }
                }
            }
        }
        .fileImporter(
            isPresented: $importTxtPresented,
            allowedContentTypes: [.plainText, .text],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                let added = LocalNovelSource.importFiles(from: urls)
                novels = (novels + added).sorted { $0.name < $1.name }
            }
        }
        .searchable(text: $query,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "搜索有声书标题 / 作者")
        .onSubmit(of: .search) { search() }
        .task {
            localSongs = await LocalAudiobookSource.scan()
            novels = LocalNovelSource.scan()
        }
        .navigationDestination(for: Audiobook.self) { book in
            BookDetailView(book: book)
        }
        .navigationDestination(for: Novel.self) { novel in
            NovelReaderView(novel: novel)
        }
    }

    private func search() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        isSearching = true
        errorText = nil
        Task {
            do {
                books = try await LibrivoxSource.search(q)
            } catch {
                errorText = "搜索失败：\(error.localizedDescription)"
                books = []
            }
            isSearching = false
        }
    }

    // MARK: 在线小说

    private var onlinePane: some View {
        Group {
            if isSearching {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在搜索…").font(.system(size: 13)).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorText {
                VStack(spacing: 10) {
                    Image(systemName: "wifi.exclamationmark").font(.system(size: 40)).foregroundColor(.secondary)
                    Text(errorText).font(.system(size: 13)).foregroundColor(.secondary).multilineTextAlignment(.center)
                }
                .padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if books.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "book").font(.system(size: 44)).foregroundColor(.secondary)
                    Text("搜索公版有声书（Librivox）\n输入书名或作者开始").font(.system(size: 13)).foregroundColor(.secondary).multilineTextAlignment(.center)
                }
                .padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(books) { book in
                        NavigationLink(value: book) {
                            HStack(spacing: 12) {
                                Image(systemName: "books.vertical.fill")
                                    .font(.system(size: 34))
                                    .foregroundColor(.accentColor)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(book.title).font(.system(size: 15, weight: .medium)).lineLimit(1)
                                    Text("\(book.author) · \(book.sections.count) 章")
                                        .font(.system(size: 12)).foregroundColor(.secondary).lineLimit(1)
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 本地有声书

    private var localPane: some View {
        Group {
            if localSongs.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "headphones").font(.system(size: 44)).foregroundColor(.secondary)
                    Text("还没有本地有声书\n点击右上角「导入有声书」添加音频文件")
                        .font(.system(size: 13)).foregroundColor(.secondary).multilineTextAlignment(.center)
                }
                .padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section {
                        Button {
                            player.play(localSongs[0], in: localSongs)
                        } label: {
                            Label("播放全部", systemImage: "play.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.accentColor)
                        }
                    }
                    ForEach(localSongs) { song in
                        SongRowView(song: song)
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 本地阅读

    private var localReadPane: some View {
        Group {
            if novels.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "text.book.closed").font(.system(size: 44)).foregroundColor(.secondary)
                    Text("还没有本地 TXT 小说\n点击右上角「导入TXT」添加 .txt 文件\n阅读时支持上下滑动、调节字号与明暗主题")
                        .font(.system(size: 13)).foregroundColor(.secondary).multilineTextAlignment(.center)
                }
                .padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(novels) { novel in
                        NavigationLink(value: novel) {
                            HStack(spacing: 12) {
                                Image(systemName: "doc.text").font(.system(size: 26)).foregroundColor(.accentColor)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(novel.name).font(.system(size: 15, weight: .medium)).lineLimit(1)
                                    Text("TXT 小说 · 点击阅读").font(.system(size: 12)).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 单本有声书详情：分章节列表，可播放整本或单章。
struct BookDetailView: View {
    @Environment(PlayerManager.self) private var player
    let book: Audiobook

    var body: some View {
        List {
            Section {
                Button {
                    player.play(book.sections[0], in: book.sections)
                } label: {
                    Label("播放整本（\(book.sections.count) 章）", systemImage: "play.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
            }
            ForEach(Array(book.sections.enumerated()), id: \.element.id) { idx, song in
                SongRowView(song: song, showIndex: idx)
            }
        }
        .listStyle(.plain)
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
