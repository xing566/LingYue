import SwiftUI
import UniformTypeIdentifiers

/// 听小说：在线（Librivox 公版有声书）+ 本地（导入有声书文件）。
struct AudiobookView: View {
    @Environment(PlayerManager.self) private var player
    @State private var segment: Segment = .online
    @State private var onlineMode: OnlineMode = .network
    @State private var query = ""
    @State private var webQuery = ""
    @State private var customURL = UserDefaults.standard.string(forKey: "novelFeedURL") ?? ""
    @State private var customBook: Audiobook?
    @State private var isCustomLoading = false
    @State private var customError: String?
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

    enum OnlineMode: String, CaseIterable {
        case network = "网络搜索"
        case web = "网页搜索"
        case custom = "自定义源"
    }

    /// 网页搜索：把关键词带去内置浏览器，找在线有声书/小说资源。
    private var webURL: URL? {
        let q = webQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return nil }
        let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        return URL(string: "https://www.bing.com/search?q=\(enc)%20%E6%9C%89%E5%A3%B0%E4%B9%A6")
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
                        Label("导入文本", systemImage: "plus.circle")
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
            allowedContentTypes: [.item],
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
        .onReceive(NotificationCenter.default.publisher(for: LocalAudiobookSource.libraryChanged)) { _ in
            Task { localSongs = await LocalAudiobookSource.scan() }
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
        if onlineMode == .network {
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
        } else if onlineMode == .web {
            webQuery = q
        }
    }

    // MARK: 在线小说

    private var onlinePane: some View {
        VStack(spacing: 0) {
            Picker("模式", selection: $onlineMode) {
                ForEach(OnlineMode.allCases, id: \.self) { m in
                    Text(m.rawValue).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 6)

            if onlineMode == .network {
                networkOnlinePane
            } else if onlineMode == .web {
                webOnlinePane
            } else {
                customOnlinePane
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var networkOnlinePane: some View {
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
                                    Text("\(book.author) · \(book.sections.count) 章 · 可下载")
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

    private var webOnlinePane: some View {
        Group {
            if let url = webURL {
                BrowserView(initialURL: url)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "safari").font(.system(size: 44)).foregroundColor(.secondary)
                    Text("输入关键词后按搜索，在网页中找可下载的有声书/小说资源\n（内置浏览器，可浏览 / 返回 / 缓存到本地）")
                        .font(.system(size: 13)).foregroundColor(.secondary).multilineTextAlignment(.center)
                }
                .padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var customOnlinePane: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                TextField("粘贴 RSS / 有声书 feed 网址", text: $customURL)
                    .textFieldStyle(.roundedBorder)
                    .autocapitalization(.none)
                    .keyboardType(.URL)
                Button {
                    loadCustom()
                } label: {
                    Text("加载").fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
                .disabled(customURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCustomLoading)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            Group {
                if isCustomLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("正在加载章节…").font(.system(size: 13)).foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let customError {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle").font(.system(size: 40)).foregroundColor(.secondary)
                        Text(customError).font(.system(size: 13)).foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let customBook {
                    List {
                        NavigationLink(value: customBook) {
                            HStack(spacing: 12) {
                                Image(systemName: "books.vertical.fill")
                                    .font(.system(size: 30)).foregroundColor(.accentColor)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(customBook.title).font(.system(size: 15, weight: .medium)).lineLimit(1)
                                    Text("\(customBook.sections.count) 章 · 可下载")
                                        .font(.system(size: 12)).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "link.circle").font(.system(size: 44)).foregroundColor(.secondary)
                        Text("粘贴你常听的有声书 / 播客 RSS 地址\n加载后即可在线播放，并可在详情页「下载整本」\n（地址会保存在本机）")
                            .font(.system(size: 13)).foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func loadCustom() {
        let raw = customURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, let url = URL(string: raw) else {
            customError = "网址格式不正确"
            return
        }
        UserDefaults.standard.set(raw, forKey: "novelFeedURL")
        isCustomLoading = true
        customError = nil
        Task {
            let chapters = await FeedSource.fetchChapters(from: url)
            await MainActor.run {
                if chapters.isEmpty {
                    customError = "未能从该地址解析到章节（请确认是 RSS/播客 feed 或 mp3 链接）"
                    customBook = nil
                } else {
                    let name = url.host ?? "自定义源"
                    customBook = Audiobook(title: name, author: "自定义源", sections: chapters)
                }
                isCustomLoading = false
            }
        }
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
                        SongRowView(song: song, queue: localSongs)
                    }
                    .onDelete { offsets in
                        for i in offsets { LocalAudiobookSource.delete(localSongs[i]) }
                        localSongs.remove(atOffsets: offsets)
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
                    Text("还没有本地文本\n点击右上角「导入文本」添加 .txt / .md / .srt 等文件\n阅读时支持上下滑动、调节字号、明暗主题与朗读")
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
                                    Text("本地文本 · 点击阅读").font(.system(size: 12)).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .onDelete { offsets in
                        for i in offsets { LocalNovelSource.delete(novels[i]) }
                        novels.remove(atOffsets: offsets)
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// 单本有声书详情：分章节列表，可播放整本或单章，并可「下载整本」到本地离线听。
struct BookDetailView: View {
    @Environment(PlayerManager.self) private var player
    let book: Audiobook
    @State private var isDownloading = false
    @State private var downloaded = 0
    @State private var doneMessage: String?

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
            if isDownloading {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("正在下载… \(downloaded)/\(book.sections.count)").font(.system(size: 13)).foregroundColor(.secondary)
                    }
                }
            }
            ForEach(Array(book.sections.enumerated()), id: \.element.id) { idx, song in
                SongRowView(song: song, showIndex: idx, queue: book.sections)
                    .simultaneousGesture(TapGesture().onEnded { _ in cacheChapter(idx) })
            }
        }
        .listStyle(.plain)
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let doneMessage {
                    Text(doneMessage).font(.system(size: 12)).foregroundColor(.green)
                } else if isDownloading {
                    ProgressView()
                } else {
                    Button {
                        downloadBook()
                    } label: {
                        Label("下载整本", systemImage: "arrow.down.circle")
                    }
                }
            }
        }
    }

    /// 播放在线章节时自动缓存该章到本地（永久保留，可在「本地有声书」手动删除）。
    private func cacheChapter(_ idx: Int) {
        guard idx >= 0, idx < book.sections.count else { return }
        let section = book.sections[idx]
        LocalAudiobookSource.cacheChapter(from: section.fileURL, name: "\(book.title)-第\(idx + 1)章")
    }

    private func downloadBook() {
        isDownloading = true
        downloaded = 0
        Task {
            let saved = await LocalAudiobookSource.download(book) { cur, total in
                Task { @MainActor in downloaded = cur }
            }
            isDownloading = false
            if saved.isEmpty {
                doneMessage = "下载失败"
            } else {
                doneMessage = "已下载 \(saved.count) 章"
            }
            // 几秒后清掉提示文字
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                doneMessage = nil
            }
        }
    }
}
