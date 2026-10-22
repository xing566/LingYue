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

            Section("关于") {
                HStack {
                    Label("版本", systemImage: "info.circle")
                    Spacer()
                    Text("1.0.0").foregroundColor(.secondary)
                }
                Button {
                    aboutPresented = true
                } label: {
                    Label("关于聆乐", systemImage: "music.note")
                }
                HStack {
                    Label("音乐来源", systemImage: "externaldrive")
                    Spacer()
                    Text(library.source.kind.displayName).foregroundColor(.secondary)
                }
                HStack {
                    Label("歌曲数量", systemImage: "music.note.list")
                    Spacer()
                    Text("\(library.songs.count) 首").foregroundColor(.secondary)
                }
            }

            Section("说明") {
                Text("聆乐以本地播放为主，架构上预留了在线流媒体扩展点（MusicSource 协议）。以后接入在线源无需改动播放器与界面。")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("设置")
        .alert("聆乐", isPresented: $aboutPresented) {
            Button("好的", role: .cancel) {}
        } message: {
            Text("一款以本地播放为主、预留在线流媒体能力的 iOS 音乐播放器。")
        }
    }
}
