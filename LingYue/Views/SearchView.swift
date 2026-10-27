import SwiftUI

/// 本地搜索
struct SearchView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(PlayerManager.self) private var player
    @State private var query = ""

    private var results: [Song] {
        library.search(query)
    }

    var body: some View {
        Group {
            if query.isEmpty {
                placeholder
            } else if results.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 44)).foregroundColor(.secondary)
                    Text("没有找到“\(query)”").foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section("歌曲 \(results.count)") {
                        ForEach(results) { song in
                            SongRowView(song: song, queue: results)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("搜索")
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "歌名 / 歌手 / 专辑")
    }

    private var placeholder: some View {
        VStack(spacing: 14) {
            Image(systemName: "music.mic")
                .font(.system(size: 56)).foregroundColor(.secondary)
            Text("搜索曲库")
                .font(.headline)
            Text("输入歌名、歌手或专辑名，快速找到想听的歌。")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
        }
        .padding(40)
    }
}
