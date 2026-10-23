import SwiftUI

/// 设置页
struct SettingsView: View {
    @Environment(LibraryStore.self) private var library
    @State private var aboutPresented = false

    var body: some View {
        @Bindable var library = library
        List {
            Section("曲库") {
                Button {
                    Task { await library.rescan() }
                } label: {
                    HStack {
                        Label("重新扫描本地曲库", systemImage: "arrow.clockwise")
                        Spacer()
                        if library.isScanning { ProgressView() }
                    }
                }
            }

            Section {
                LabeledContent("本地歌曲", value: "\(library.songs.count) 首")
                LabeledContent("在线歌曲", value: "\(library.onlineSongs.count) 首")
                HStack {
                    Label("音乐来源", systemImage: "externaldrive")
                    Spacer()
                    Text("\(library.source.kind.displayName) / \(library.streamingSource.kind.displayName)")
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("曲库统计")
            }

            Section {
                TextField("https://…/playlist.json", text: feedBinding)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Text("填写自定义在线歌单 JSON 地址后，音乐库「在线歌单」将改用该地址。\n格式：数组 [{ title, artist?, url }]，url 为可直接播放的音频地址。\n留空则使用内置默认歌单（Internet Archive 公版名曲）。")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            } header: {
                Text("在线歌单（自定义地址，可选）")
            }

            Section("关于") {
                NavigationLink {
                    CacheManagementView()
                } label: {
                    Label("缓存管理", systemImage: "internaldrive")
                }
                Button {
                    aboutPresented = true
                } label: {
                    Label("关于聆乐", systemImage: "music.note")
                }
            }

            Section("说明") {
                Text("聆乐支持本地播放与在线歌单两种来源。在线源通过 MusicSource 协议接入，以后可替换为任意平台。")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("设置")
        .alert("聆乐", isPresented: $aboutPresented) {
            Button("好的", role: .cancel) {}
        } message: {
            Text("一款支持本地播放与在线歌单的 iOS 音乐播放器。")
        }
    }

    private var feedBinding: Binding<String> {
        Binding(
            get: { library.feedURL ?? "" },
            set: { library.feedURL = $0.isEmpty ? nil : $0 }
        )
    }
}
