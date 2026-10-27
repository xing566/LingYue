import SwiftUI
import WebKit

/// 缓存管理：查看网页缓存 / 本地内容占用，一键清缓存（缓存书签保留），并可清理已下载。
struct CacheManagementView: View {
    @State private var webCacheBytes: Int64 = 0
    @State private var localBytes: Int64 = 0
    @State private var lyricCoverBytes: Int64 = 0
    @State private var clearing = false
    @State private var clearMessage: String?

    var body: some View {
        List {
            Section {
                HStack {
                    Label("网页缓存占用", systemImage: "internaldrive")
                    Spacer()
                    Text(byteString(webCacheBytes)).foregroundColor(.secondary)
                }
                Button {
                    clearWebCache()
                } label: {
                    Group {
                        if clearing {
                            HStack { ProgressView(); Text("清除中…") }
                        } else {
                            Label("清除网页缓存", systemImage: "trash").foregroundColor(.red)
                        }
                    }
                }
                .disabled(clearing)
                if let clearMessage {
                    Text(clearMessage).font(.system(size: 12)).foregroundColor(.green)
                }
            } header: {
                Text("网页缓存")
            } footer: {
                Text("清除网页缓存不影响「缓存书签」里保存的页面（书签单独存在本地，会保留）。")
            }

            Section {
                HStack {
                    Label("歌词 / 封面缓存", systemImage: "photo")
                    Spacer()
                    Text(byteString(lyricCoverBytes)).foregroundColor(.secondary)
                }
                Button {
                    clearLyricCoverCache()
                } label: {
                    Label("清除歌词 / 封面缓存", systemImage: "trash").foregroundColor(.red)
                }
                .disabled(clearing)
                if let clearMessage {
                    Text(clearMessage).font(.system(size: 12)).foregroundColor(.green)
                }
            } header: {
                Text("App缓存")
            } footer: {
                Text("清除后下次播放歌曲 / 打开播放页会联网重新拉取歌词和封面。")
            }

            Section {
                HStack {
                    Label("保存的页面", systemImage: "bookmark")
                    Spacer()
                    Text("\(BrowserStore.load().count) 个 · 清除时保留").foregroundColor(.secondary)
                }
            } header: {
                Text("缓存书签")
            }

            Section {
                HStack {
                    Label("本地占用", systemImage: "doc")
                    Spacer()
                    Text(byteString(localBytes)).foregroundColor(.secondary)
                }
            } header: {
                Text("本地内容（下载 / 导入）")
            } footer: {
                Text("本地有声书、文本、视频、音乐可在对应页面滑动删除；下载整本的章节在「小说→本地有声书」里删除。")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("缓存管理")
        .navigationBarTitleDisplayMode(.inline)
        .task { compute() }
    }

    // MARK: 计算占用

    private func compute() {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let lib = docs.deletingLastPathComponent()   // …/Library
        // 网页缓存：WebKit 数据 + 系统 Caches
        let webKit = lib.appendingPathComponent("WebKit", isDirectory: true)
        let caches = lib.appendingPathComponent("Caches", isDirectory: true)
        webCacheBytes = dirSize(webKit) + dirSize(caches)
        // 本地用户内容：Audiobooks / Novels / Audio
        let audiobooks = docs.appendingPathComponent("Audiobooks", isDirectory: true)
        let novels = docs.appendingPathComponent("Novels", isDirectory: true)
        let audio = docs.appendingPathComponent("Audio", isDirectory: true)
        localBytes = dirSize(audiobooks) + dirSize(novels) + dirSize(audio)
        // App缓存：AppCache/Lyrics + AppCache/Covers（手机「文件」里可见的 AppCache 文件夹）
        let appCache = docs.appendingPathComponent("AppCache", isDirectory: true)
        lyricCoverBytes = dirSize(appCache)
    }

    private func dirSize(_ dir: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                                             options: [.skipsHiddenFiles]) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            if let isFile = (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile), isFile == true,
               let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) {
                total += Int64(size)
            }
        }
        return total
    }

    private func clearWebCache() {
        clearing = true
        clearMessage = nil
        WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: Date.distantPast
        ) { [self] in
            Task { @MainActor in
                clearing = false
                compute()
                clearMessage = "已清除网页缓存（\(byteString(webCacheBytes))）"
            }
        }
    }

    private func clearLyricCoverCache() {
        clearing = true
        clearMessage = nil
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let appCache = docs.appendingPathComponent("AppCache", isDirectory: true)
        Task { @MainActor in
            if let items = try? FileManager.default.contentsOfDirectory(at: appCache, includingPropertiesForKeys: nil) {
                for item in items {
                    try? FileManager.default.removeItem(at: item)
                }
            }
            clearing = false
            compute()
            clearMessage = "已清除歌词 / 封面缓存（\(byteString(lyricCoverBytes))）"
        }
    }

    private func byteString(_ bytes: Int64) -> String {
        let b = Double(bytes)
        if b >= 1_073_741_824 { return String(format: "%.1f GB", b / 1_073_741_824) }
        if b >= 1_048_576 { return String(format: "%.1f MB", b / 1_048_576) }
        if b >= 1024 { return String(format: "%.0f KB", b / 1024) }
        return "\(bytes) B"
    }
}
