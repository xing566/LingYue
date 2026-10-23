import SwiftUI

/// TXT 小说阅读器：上下滑动（滚动）阅读，可调字号、切换明暗主题。
struct NovelReaderView: View {
    let novel: Novel
    @State private var content = ""
    @State private var fontSize: CGFloat = 18
    @State private var isDark = true

    var body: some View {
        ScrollView {
            Text(content.isEmpty ? "（无法读取或文件为空）" : content)
                .font(.system(size: fontSize))
                .lineSpacing(6)
                .foregroundColor(isDark ? Color(red: 0.92, green: 0.90, blue: 0.85) : Color(red: 0.15, green: 0.13, blue: 0.11))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .textSelection(.enabled)
        }
        .background((isDark ? Color(red: 0.06, green: 0.07, blue: 0.10) : Color(red: 0.96, green: 0.94, blue: 0.88))
            .ignoresSafeArea())
        .navigationTitle(novel.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button { fontSize = max(13, fontSize - 2) } label: {
                    Image(systemName: "textformat.size.smaller")
                }
                Text("\(Int(fontSize))").font(.subheadline.monospacedDigit()).foregroundColor(.secondary)
                Button { fontSize = min(30, fontSize + 2) } label: {
                    Image(systemName: "textformat.size.larger")
                }
                Spacer()
                Button { withAnimation(.easeInOut(duration: 0.2)) { isDark.toggle() } } label: {
                    Image(systemName: isDark ? "sun.max.fill" : "moon.fill")
                }
            }
        }
        .task { content = LocalNovelSource.readText(from: novel.fileURL) }
    }
}
