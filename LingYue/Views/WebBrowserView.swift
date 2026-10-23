import SwiftUI
import WebKit

/// 内置网页浏览器（用于「网页搜索」）。SwiftUI 包装 WKWebView。
struct WebBrowserView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.allowsBackForwardNavigationGestures = true
        webView.navigationDelegate = context.coordinator
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        let key = url.absoluteString
        guard context.coordinator.loadedURL != key else { return }
        context.coordinator.loadedURL = key
        uiView.load(URLRequest(url: url))
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
