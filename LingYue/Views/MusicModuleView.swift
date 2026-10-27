import SwiftUI

/// 「音乐」大模块：顶部分段切换 音乐库 / 播放列表 / 搜索，共用一个导航栈。
struct MusicModuleView: View {
    @State private var section: Section = .library

    enum Section: String, CaseIterable, Identifiable {
        case library = "音乐库"
        case playlists = "播放列表"
        case search = "搜索"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("音乐模块", selection: $section) {
                ForEach(Section.allCases) { s in
                    Text(s.rawValue).tag(s)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 6)

            switch section {
            case .library: LibraryView()
            case .playlists: PlaylistView()
            case .search: SearchView()
            }
        }
        .navigationTitle("音乐")
    }
}
