import SwiftUI

/// 应用根视图：底部 Tab 导航 + 迷你播放条 + 全屏播放页。
struct RootTabView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerManager.self) private var player
    @State private var selectedTab: Tab = .library
    @State private var showNowPlaying = false

    enum Tab: Hashable {
        case library, playlists, audiobooks, search, settings, browser
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                NavigationStack { LibraryView() }
                    .tabItem { Label("音乐库", systemImage: "music.note.list") }
                    .tag(Tab.library)

                NavigationStack { PlaylistView() }
                    .tabItem { Label("播放列表", systemImage: "list.bullet") }
                    .tag(Tab.playlists)

                NavigationStack { AudiobookView() }
                    .tabItem { Label("小说", systemImage: "book") }
                    .tag(Tab.audiobooks)

                NavigationStack { SearchView() }
                    .tabItem { Label("搜索", systemImage: "magnifyingglass") }
                    .tag(Tab.search)

                NavigationStack { BrowserView() }
                    .tabItem { Label("浏览器", systemImage: "safari") }
                    .tag(Tab.browser)

                NavigationStack { SettingsView() }
                    .tabItem { Label("设置", systemImage: "gearshape") }
                    .tag(Tab.settings)
            }

            // 迷你播放条（有正在播放的歌曲时才显示）
            if player.currentSong != nil {
                MiniPlayerView { showNowPlaying = true }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 48)
            }
        }
        .sheet(isPresented: $showNowPlaying) {
            NowPlayingView()
        }
        .task {
            // 启动时扫描本地曲库
            await library.rescan()
        }
    }
}
