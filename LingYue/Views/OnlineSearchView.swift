import SwiftUI

/// 在线搜索：网络搜索（可播放）+ 网页搜索（内置浏览器）。
/// 通过「音乐库 → 在线歌单 → 在线搜索音乐」进入。
struct OnlineSearchView: View {
    @Environment(PlayerManager.self) private var player
    @Environment(\.dismiss) private var dismiss

    enum Mode: String, CaseIterable {
        case network = "网络搜索"
        case web = "网页搜索"
    }

    @State private var query = ""
    @State private var submitted = ""
    @State private var mode: Mode = .network
    @State private var results: [Song] = []
    @State private var isLoading = false
    @State private var errorText: String?

    private var webURL: URL? {
        let q = submitted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return nil }
        let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        return URL(string: "https://www.bing.com/search?q=\(enc)%20mp3")
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("模式", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 6)

                if mode == .network {
                    networkPane
                } else {
                    webPane
                }
            }
            .navigationTitle("在线搜索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Text("完成") }
                }
            }
            .searchable(text: $query,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "输入歌名 / 歌手")
            .onSubmit(of: .search) { submit() }
        }
        .preferredColorScheme(.dark)
    }

    private func submit() {
        submitted = query
        if mode == .network { runNetworkSearch() }
    }

    private func runNetworkSearch() {
        let q = submitted
        guard !q.isEmpty else { return }
        isLoading = true
        errorText = nil
        Task {
            do {
                let found = try await OnlineSearchSource.search(q)
                results = found
            } catch {
                errorText = "搜索失败：\(error.localizedDescription)"
                results = []
            }
            isLoading = false
        }
    }

    // MARK: 网络搜索

    private var networkPane: some View {
        Group {
            if isLoading {
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
            } else if results.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "antenna.radiowaves.left.and.right").font(.system(size: 44)).foregroundColor(.secondary)
                    Text("输入关键词搜索网络公版音乐\n（Internet Archive）").font(.system(size: 13)).foregroundColor(.secondary).multilineTextAlignment(.center)
                }
                .padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section("搜索结果 \(results.count)") {
                        ForEach(results) { song in
                            SongRowView(song: song)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 网页搜索

    private var webPane: some View {
        Group {
            if let url = webURL {
                WebBrowserView(url: url)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "safari").font(.system(size: 44)).foregroundColor(.secondary)
                    Text("输入关键词后按搜索，在网页中查找结果\n（打开内置浏览器，可浏览 / 返回）")
                        .font(.system(size: 13)).foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(30).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
