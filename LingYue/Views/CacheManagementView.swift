import SwiftUI
import WebKit

/// 缓存管理：查看网页缓存 / 本地内容占用，一键清缓存（缓存书签保留），并可清理已下载。
struct CacheManagementView: View {
    @State private var webCacheBytes: Int64 = 0
    @State private var webFileBytes: Int64 = 0
    @State private var localBytes: Int64 = 0
    @State private var lyricCoverBytes: Int64 = 0
    @State private var transcodedBytes: Int64 = 0
    @State private var clearing = false
    @State private var clearMessage: String?

    var body: some View {
        List {
            Section {
                HStack {
                    Label("网页缓存占用", systemImage: "internaldrive")
                    Spacer()
                    Text(byteString(webCacheBytes + webFileBytes)).foregroundColor(.secondary)
                }
                if webFileBytes > 0 {
                    HStack {
                        Label("其中：手机文件 AppCache/Web", systemImage: "folder")
                        Spacer()
                        Text(byteString(webFileBytes)).foregroundColor(.secondary)
                    }
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
                Text("清除会同时删掉手机「文件 → 我的 iPhone → 聆乐 → AppCache → Web」里的缓存页；不影响「缓存书签」列表本身。")
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
                    Label("转码文件（WMA等→WAV）", systemImage: "waveform")
                    Spacer()
                    Text(byteString(transcodedBytes)).foregroundColor(.secondary)
                }
            } header: {
                Text("转码文件")
            } footer: {
                Text("当前转码改为「内存方案」：非原生格式（WMA 等）播放时解码到运行内存、不写进本地。此目录仅保留历史旧版残留的 WAV，占用很小可直接在手机「文件 → 我的 iPhone → 聆乐 → AppCache → Transcoded」里删掉。")
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
        // 网页缓存：WebKit 数据 + 系统 Caches + 我们落盘的 AppCache/Web
        let webKit = lib.appendingPathComponent("WebKit", isDirectory: true)
        let caches = lib.appendingPathComponent("Caches", isDirectory: true)
        webCacheBytes = dirSize(webKit) + dirSize(caches)
        // App缓存：AppCache 文件夹（手机「文件」里可见）：Web 网页缓存 / Lyrics 歌词 / Covers 封面 / Transcoded 转码
        let appCache = docs.appendingPathComponent("AppCache", isDirectory: true)
        webFileBytes = dirSize(appCache.appendingPathComponent("Web", isDirectory: true))
        // 本地用户内容：Audiobooks / Novels / Audio
        let audiobooks = docs.appendingPathComponent("Audiobooks", isDirectory: true)
        let novels = docs.appendingPathComponent("Novels", isDirectory: true)
        let audio = docs.appendingPathComponent("Audio", isDirectory: true)
        localBytes = dirSize(audiobooks) + dirSize(novels) + dirSize(audio)
        // 歌词 / 封面 与 转码文件
        lyricCoverBytes = dirSize(appCache.appendingPathComponent("Lyrics", isDirectory: true))
            + dirSize(appCache.appendingPathComponent("Covers", isDirectory: true))
        transcodedBytes = dirSize(appCache.appendingPathComponent("Transcoded", isDirectory: true))
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
        // 1) WebKit / 系统缓存
        WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: Date.distantPast
        ) { [self] in
            Task { @MainActor in
                clearing = false
                compute()
                clearMessage = "已清除网页缓存（\(byteString(webCacheBytes + webFileBytes))）"
            }
        }
        // 2) 同时删掉手机「文件」AppCache/Web 里落盘的缓存页
        let webDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AppCache", isDirectory: true)
            .appendingPathComponent("Web", isDirectory: true)
        if let items = try? FileManager.default.contentsOfDirectory(at: webDir, includingPropertiesForKeys: nil) {
            for item in items { try? FileManager.default.removeItem(at: item) }
        }
    }

    private func clearLyricCoverCache() {
        clearing = true
        clearMessage = nil
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let appCache = docs.appendingPathComponent("AppCache", isDirectory: true)
        // 只清歌词/封面，转码文件（可播放音频）保留
        let targets = [appCache.appendingPathComponent("Lyrics", isDirectory: true),
                       appCache.appendingPathComponent("Covers", isDirectory: true)]
        Task { @MainActor in
            for d in targets {
                if let items = try? FileManager.default.contentsOfDirectory(at: d, includingPropertiesForKeys: nil) {
                    for item in items {
                        try? FileManager.default.removeItem(at: item)
                    }
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
