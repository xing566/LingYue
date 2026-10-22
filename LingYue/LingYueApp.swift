import SwiftUI

@main
struct LingYueApp: App {
    // 单例状态容器，贯穿整个 App 生命周期
    @State private var libraryStore = LibraryStore(source: LocalLibrarySource())
    @State private var player: PlayerManager

    init() {
        let store = LibraryStore(source: LocalLibrarySource())
        _libraryStore = State(initialValue: store)
        // 播放器与曲库共用同一个 MusicSource，便于日后切换为在线源
        _player = State(initialValue: PlayerManager(source: store.source))
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(libraryStore)
                .environment(player)
                .preferredColorScheme(.dark)
        }
    }
}
