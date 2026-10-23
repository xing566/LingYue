import SwiftUI
import WebKit

/// 本地缓存页条目。
struct SavedPage: Identifiable, Codable {
    var id: UUID = UUID()
    var title: String
    var urlString: String
}

/// 持有 WKWebView 的浏览器模型：持久化缓存、前进/后退/刷新、标题回调。
final class BrowserModel: NSObject, ObservableObject, WKNavigationDelegate {
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var pageTitle = ""
    let webView: WKWebView
    private var loadedURL: String?

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()   // 持久化，缓存本地保留
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
    }

    func load(_ url: URL) {
        let key = url.absoluteString
        guard loadedURL != key else { return }
        loadedURL = key
        webView.load(URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30))
    }

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        if let t = webView.title, !t.isEmpty { pageTitle = t }
    }
}

/// 把模型里的 WKWebView 挂到 SwiftUI。
struct BrowserRepresentable: UIViewRepresentable {
    @ObservedObject var model: BrowserModel
    func makeUIView(context: Context) -> WKWebView { model.webView }
    func updateUIView(_ uiView: WKWebView, context: Context) { }
}

/// 内置浏览器界面：地址栏 / 前进 / 后退 / 刷新，
/// 网页缓存持久化保存，并提供「缓存列表」查看、重开、删除。
struct BrowserView: View {
    @StateObject private var model = BrowserModel()
    @State private var address = ""
    @State private var savedPages: [SavedPage] = BrowserStore.load()
    @State private var showCache = false
    private let initialURL: URL?

    init(initialURL: URL? = nil) {
        self.initialURL = initialURL
    }

    var body: some View {
        VStack(spacing: 0) {
            addressBar
            ZStack {
                BrowserRepresentable(model: model)
                if address.isEmpty && model.pageTitle.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "safari").font(.system(size: 44)).foregroundColor(.secondary)
                        Text("输入网址，或从「缓存列表」打开已保存页面").font(.system(size: 13)).foregroundColor(.secondary)
                    }
                }
            }
            bottomBar
        }
        .navigationTitle(model.pageTitle.isEmpty ? "浏览器" : model.pageTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    BrowserStore.append(SavedPage(
                        title: model.pageTitle.isEmpty ? (address.isEmpty ? (initialURL?.absoluteString ?? "页面") : address) : model.pageTitle,
                        urlString: model.webView.url?.absoluteString ?? initialURL?.absoluteString ?? ""))
                    savedPages = BrowserStore.load()
                } label: {
                    Image(systemName: "bookmark")
                }
                .disabled(model.webView.url == nil && initialURL == nil)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCache = true } label: {
                    Image(systemName: "clock.arrow.circlepath")
                }
            }
        }
        .sheet(isPresented: $showCache) {
            CacheListView(pages: $savedPages, onOpen: { page in
                if let u = URL(string: page.urlString) {
                    model.load(u); address = u.absoluteString
                }
            })
        }
        .onAppear {
            if model.webView.url == nil, let initialURL {
                model.load(initialURL); address = initialURL.absoluteString
            }
        }
    }

    private var addressBar: some View {
        HStack(spacing: 8) {
            Button { showCache = true } label: {
                Image(systemName: "bookmark").font(.system(size: 15))
            }
            TextField("输入网址", text: $address)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.URL)
                .autocapitalization(.none)
                .onSubmit { go(address) }
            Button { go(address) } label: {
                Image(systemName: "arrow.right.circle.fill").font(.system(size: 18))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    private var bottomBar: some View {
        HStack(spacing: 34) {
            Button { model.goBack() } label: { Image(systemName: "chevron.left").font(.system(size: 18)) }
                .disabled(!model.canGoBack)
            Button { model.goForward() } label: { Image(systemName: "chevron.right").font(.system(size: 18)) }
                .disabled(!model.canGoForward)
            Button { model.reload() } label: { Image(systemName: "arrow.clockwise").font(.system(size: 18)) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    private func go(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var s = trimmed
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") {
            s = "https://" + s
        }
        guard let u = URL(string: s) else { return }
        model.load(u)
    }
}

/// 缓存页列表：本地保留，可重开 / 删除。
struct CacheListView: View {
    @Binding var pages: [SavedPage]
    var onOpen: (SavedPage) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if pages.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath").font(.system(size: 40)).foregroundColor(.secondary)
                        Text("还没有缓存的网页\n浏览时点「书签」即可保存到本地").font(.system(size: 13)).foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(pages) { page in
                            Button {
                                dismiss()
                                onOpen(page)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "globe").foregroundColor(.accentColor)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(page.title).font(.system(size: 15, weight: .medium)).lineLimit(1)
                                        Text(page.urlString).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
                                    }
                                }
                            }
                        }
                        .onDelete { offsets in
                            pages.remove(atOffsets: offsets)
                            BrowserStore.save(pages)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("本地缓存")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Text("完成") }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// 缓存持久化（保存在本地 UserDefaults）
enum BrowserStore {
    private static let key = "browserSavedPages"
    static func load() -> [SavedPage] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let arr = try? JSONDecoder().decode([SavedPage].self, from: data) else { return [] }
        return arr
    }
    static func save(_ pages: [SavedPage]) {
        if let data = try? JSONEncoder().encode(pages) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
    static func append(_ page: SavedPage) {
        var pages = load()
        pages.removeAll { $0.urlString == page.urlString }
        pages.insert(page, at: 0)
        save(pages)
    }
}
