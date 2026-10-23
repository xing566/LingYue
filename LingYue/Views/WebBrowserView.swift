import SwiftUI
import WebKit

/// 内置网页浏览器（用于「网页搜索」）。SwiftUI 包装 WKWebView。
/// 使用持久化数据存储：缓存与 Cookie 保存在 App 本地容器，跨启动保留，页面再次访问更快。
struct WebBrowserView: UIViewRepresentable {
    let url: URL

    /// 共享的持久化数据存储（缓存 + Cookie 本地保留）
    private static let dataStore = WKWebsiteDataStore.default()

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WebBrowserView.dataStore
        configuration.suppressesIncrementalRendering = false
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        let key = url.absoluteString
        guard context.coordinator.loadedURL != key else { return }
        context.coordinator.loadedURL = key
        uiView.load(URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedURL: String?
        func webView(_ webView: WKWebView,
                     didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            // 页面加载失败时由 WKWebView 显示默认错误，这里不做额外处理
        }
    }
}
