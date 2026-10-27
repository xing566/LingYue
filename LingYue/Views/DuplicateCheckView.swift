import SwiftUI

/// 重复歌曲自检：按歌名+歌手分组，展示重复项，一键去重（每组保留最早添加的一条）。
/// 用字典分组计算，不读音频进内存，大曲库也不会爆内存/存储。
struct DuplicateCheckView: View {
    @Environment(LibraryStore.self) private var library
    @State private var groups: [LibraryStore.DuplicateGroup] = []
    @State private var resultMessage: String?

    var body: some View {
        List {
            Section {
                HStack {
                    Label("重复歌曲", systemImage: "rectangle.on.rectangle")
                    Spacer()
                    Text("\(library.songs.count) 首中共 \(library.duplicateCount) 首重复")
                        .foregroundColor(.secondary)
                }
                Button {
                    remove()
                } label: {
                    Label("一键去重（每组保留最早一条）", systemImage: "checkmark.circle")
                        .foregroundColor(.accentColor)
                }
                if let resultMessage {
                    Text(resultMessage).font(.system(size: 13)).foregroundColor(.green)
                }
            } footer: {
                Text("按「歌名+歌手」判定（忽略大小写、空格、全半角括号）。只去重曲库记录，不删除音频文件本身。")
            }

            Section("重复分组") {
                if groups.isEmpty {
                    Text("未发现重复歌曲").foregroundColor(.secondary)
                } else {
                    ForEach(groups) { g in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(g.keep.displayTitle)
                                .font(.system(size: 15, weight: .semibold))
                            Text("保留：\(g.keep.artist) · \(g.keep.formattedDuration)")
                                .font(.system(size: 12)).foregroundColor(.green)
                            ForEach(Array(g.duplicates.enumerated()), id: \.element.id) { _, d in
                                Text("待删：\(d.artist) · \(d.formattedDuration)")
                                    .font(.system(size: 12)).foregroundColor(.red)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("重复歌曲自检")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { refresh() }
    }

    private func refresh() {
        groups = library.duplicateGroups()
    }

    private func remove() {
        let removed = library.removeDuplicates()
        resultMessage = removed > 0 ? "已移除 \(removed) 首重复（保留最早添加的）" : "没有可移除的重复"
        refresh()
    }
}
