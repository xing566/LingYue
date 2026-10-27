import SwiftUI

@main
struct LingYueApp: App {
    // 单例状态容器，贯穿整个 App 生命周期
    @State private var libraryStore = LibraryStore(source: LocalLibrarySource())
    @State private var player: PlayerManager
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let store = LibraryStore(source: LocalLibrarySource())
        _libraryStore = State(initialValue: store)
        // 播放器与曲库共用同一个 MusicSource，便于日后切换为在线源
        _player = State(initialValue: PlayerManager(source: store.source))
        // 首次启动统一请求通知、蓝牙等系统权限
        PermissionRequester.requestAll()
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(libraryStore)
                .environment(player)
                .preferredColorScheme(.dark)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                // App 退出 / 退到后台：清理音乐转码缓存（保留曲库仍在引用的 WAV）
                clearMusicCacheOnExit()
            }
        }
    }

    /// 清掉转码缓存（AppCache/Transcoded），但保留曲库歌曲仍在引用的 WAV——
    /// 这些是旧版被删掉原文件、靠 WAV 找回来的歌，删了会再次「消失」。
    private func clearMusicCacheOnExit() {
        var referenced = Set<String>()
        referenced.formUnion(libraryStore.songs.compactMap { $0.fileURL.path.lowercased() })
        if let cur = player.currentSong?.fileURL {
            referenced.insert(cur.path.lowercased())
        }
        let transDir = FFmpegTranscoder.transcodedDir
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: transDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]) else { return }
        for item in items {
            if !referenced.contains(item.path.lowercased()) {
                try? FileManager.default.removeItem(at: item)
            }
        }
    }
}
