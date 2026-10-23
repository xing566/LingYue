import SwiftUI
import WebKit

/// 本地缓存页条目。
struct SavedPage: Identifiable, Codable {
    var id: UUID = UUID()
    var title: String
    var urlString: String
}

/// 单个浏览器标签页：各自持有 WKWebView、标题与导航状态。
final class BrowserTab: NSObject, ObservableObject, WKNavigationDelegate {
    let id = UUID()
    @Published var title = ""
    @Published var canGoBack = false
    @Published var canGoForward = false
    let webView: WKWebView

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()   // 持久化，缓存本地保留
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
    }

    func installAdBlocker(_ list: WKContentRuleList?) {
        guard let list else { return }
        webView.configuration.userContentController.add(list)
    }

    func load(_ url: URL) {
        webView.load(URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30))
    }
    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        title = webView.title ?? title
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }
}

/// 浏览器标签管理器：管理多个标签页、当前激活标签与导航控制。
final class BrowserModel: ObservableObject {
    @Published var tabs: [BrowserTab] = []
    @Published var activeIndex = 0

    var activeTab: BrowserTab? { tabs.indices.contains(activeIndex) ? tabs[activeIndex] : nil }
    var pageTitle: String { activeTab?.title ?? "" }
    var canGoBack: Bool { activeTab?.canGoBack ?? false }
    var canGoForward: Bool { activeTab?.canGoForward ?? false }
    var activeURL: URL? { activeTab?.webView.url }

    /// 广告屏蔽开关（存在本地，设置页可改）
    static let adEnabledKey = "adBlockerEnabled"
    static var isAdEnabled: Bool {
        UserDefaults.standard.object(forKey: adEnabledKey) as? Bool ?? true
    }
    private static var adList: WKContentRuleList?

    init() {
        addTab(initialURL: nil)
        if Self.isAdEnabled {
            WKContentRuleListStore.default().compileContentRuleList(
                forIdentifier: "LingYueAdBlock",
                encodedContentRuleList: Self.adRuleJSON
            ) { [weak self] list, _ in
                guard let list else { return }
                Self.adList = list
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    for tab in self.tabs { tab.installAdBlocker(list) }
                }
            }
        }
    }

    @discardableResult
    func addTab(initialURL: URL?) -> BrowserTab {
        let tab = BrowserTab()
        if let list = Self.adList { tab.installAdBlocker(list) }
        if let url = initialURL { tab.load(url) }
        tabs.append(tab)
        activeIndex = tabs.count - 1
        return tab
    }

    func switchTo(_ tab: BrowserTab) {
        if let i = tabs.firstIndex(where: { $0.id == tab.id }) { activeIndex = i }
    }

    func closeTab(_ tab: BrowserTab) {
        guard let i = tabs.firstIndex(where: { $0.id == tab.id }), tabs.count > 1 else { return }
        tabs.remove(at: i)
        if activeIndex >= tabs.count { activeIndex = max(0, tabs.count - 1) }
        else if activeIndex == i { activeIndex = min(i, tabs.count - 1) }
    }

    // 导航控制（作用于当前标签）
    func load(_ url: URL) { activeTab?.load(url) }
    func goBack() { activeTab?.goBack() }
    func goForward() { activeTab?.goForward() }
    func reload() { activeTab?.reload() }

    /// 常见广告网络 / 广告脚本的屏蔽规则。
    private static let adRuleJSON = """
    [
      {"action":{"type":"block"},
       "trigger":{"url-filter":".*","resource-type":["script","image","media"],
         "if-domain":["doubleclick.net","googlesyndication.com","googleadservices.com","adnxs.com","adservice.google.com","adsystem.com","advertising.com","scorecardresearch.com","moatads.com","outbrain.com","taboola.com","amazon-adsystem.com","zedo.com","pubmatic.com","rubiconproject.com","criteo.com","adform.net","openx.net","smartadserver.com","adtechus.com"]}},
      {"action":{"type":"block"},
       "trigger":{"url-filter":"(doubleclick|googlesyndication|googleadservices|adnxs|adservice|advertising|scorecardresearch|moatads|outbrain|taboola|pubmatic|rubiconproject|criteo|adform|openx|smartadserver|zedo)\\.(net|com|org)","resource-type":["script","image","media"]}},
      {"action":{"type":"block"},
       "trigger":{"url-filter":"^https?://[^/]*(/|\\.)(ads?|adserver|advertising|adsystem|sponsor|promo)[^/]*/","resource-type":["script","image"]}}
    ]
    """
}

/// 把当前激活标签的 WKWebView 挂到 SwiftUI（切换标签时只显示激活的那个）。
struct BrowserContainer: UIViewRepresentable {
    @ObservedObject var model: BrowserModel
    func makeUIView(context: Context) -> UIView { UIView() }
    func updateUIView(_ uiView: UIView, context: Context) {
        uiView.subviews.forEach { $0.removeFromSuperview() }
        guard let tab = model.activeTab else { return }
        let wv = tab.webView
        wv.translatesAutoresizingMaskIntoConstraints = false
        uiView.addSubview(wv)
        NSLayoutConstraint.activate([
            wv.leadingAnchor.constraint(equalTo: uiView.leadingAnchor),
            wv.trailingAnchor.constraint(equalTo: uiView.trailingAnchor),
            wv.topAnchor.constraint(equalTo: uiView.topAnchor),
            wv.bottomAnchor.constraint(equalTo: uiView.bottomAnchor)
        ])
    }
}

/// 内置浏览器界面：多标签 / 地址栏 / 前进 / 后退 / 刷新，
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
            tabStrip
            addressBar
            ZStack {
                BrowserContainer(model: model)
                if model.activeURL == nil && model.pageTitle.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "safari").font(.system(size: 44)).foregroundColor(.secondary)
                        Text("输入网址，或点「+」新开标签页，从「缓存列表」打开已保存页面").font(.system(size: 13)).foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
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
                        urlString: model.activeURL?.absoluteString ?? initialURL?.absoluteString ?? ""))
                    savedPages = BrowserStore.load()
                } label: {
                    Image(systemName: "bookmark")
                }
                .disabled(model.activeURL == nil && initialURL == nil)
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
            if model.activeURL == nil, let initialURL {
                model.load(initialURL); address = initialURL.absoluteString
            }
        }
        .onChange(of: model.activeIndex) { syncAddress() }
        .onChange(of: model.pageTitle) {
            if let u = model.activeURL { address = u.absoluteString }
        }
    }

    /// 顶部标签栏：可切换 / 关闭标签，末尾「+」新建标签。
    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.tabs) { tab in
                    HStack(spacing: 4) {
                        Button {
                            model.switchTo(tab)
                        } label: {
                            Text(tab.title.isEmpty ? "新标签页" : tab.title)
                                .font(.system(size: 12))
                                .lineLimit(1)
                                .foregroundColor(model.activeTab?.id == tab.id ? .white : .primary)
                        }
                        Button {
                            model.closeTab(tab)
                        } label: {
                            Image(systemName: "xmark").font(.system(size: 9))
                                .foregroundColor(model.activeTab?.id == tab.id ? .white : .secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(model.activeTab?.id == tab.id ? Color.accentColor : Color(.systemGray5))
                    .clipShape(Capsule())
                }
                Button {
                    model.addTab(initialURL: nil)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.accentColor)
                        .padding(6)
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.vertical, 6)
        .background(Color(.systemBackground))
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

    private func syncAddress() {
        address = model.activeURL?.absoluteString ?? ""
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
