import SwiftUI
import AVFoundation
import Combine

/// 语音合成控制器：负责朗读状态与代理回调（播放完成/取消时更新 UI）。
final class SpeechDelegate: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published var isSpeaking = false
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isSpeaking = false
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isSpeaking = false
    }
}

/// TXT 小说阅读器：上下滑动（滚动）阅读，支持调节字号、明暗主题，
/// 以及「朗读」功能（切换声音包 / 语速 / 播放暂停停止）。
struct NovelReaderView: View {
    let novel: Novel
    @State private var content = ""
    @State private var paragraphs: [String] = []
    @State private var isLoading = false
    @State private var loadProgress: Double = 0
    @State private var fontSize: CGFloat = 18
    @State private var isDark = true
    @State private var rate: Float = 0.5
    @State private var voiceID: String = UserDefaults.standard.string(forKey: "ttsVoice") ?? ""
    @StateObject private var speech = SpeechDelegate()
    @State private var synthesizer = AVSpeechSynthesizer()

    /// 可选用的声音包（优先中文，其余按语言归类）
    var availableVoices: [AVSpeechSynthesisVoice] {
        let all = AVSpeechSynthesisVoice.speechVoices().filter { !$0.name.isEmpty }
        let zh = all.filter { $0.language.lowercased().hasPrefix("zh") }
        let other = all.filter { !$0.language.lowercased().hasPrefix("zh") }
        return zh + other
    }

    var selectedVoice: AVSpeechSynthesisVoice? {
        if !voiceID.isEmpty, let v = AVSpeechSynthesisVoice(identifier: voiceID) { return v }
        return AVSpeechSynthesisVoice(language: "zh-CN")
    }

    /// 正文文字颜色（随明暗主题）。
    private var bodyColor: Color {
        isDark ? Color(red: 0.92, green: 0.90, blue: 0.85) : Color(red: 0.15, green: 0.13, blue: 0.11)
    }

    var body: some View {
        VStack(spacing: 0) {
            speakBar

            // 全文仍在后台加载时，顶部显示进度条 + 百分比
            if isLoading {
                VStack(spacing: 4) {
                    ProgressView(value: loadProgress)
                        .tint(.accentColor)
                    Text("正在加载全文… \(Int(loadProgress * 100))%")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
            }

            ScrollView {
                if paragraphs.isEmpty {
                    Text(content.isEmpty ? "（无法读取或文件为空）" : content)
                        .font(.system(size: fontSize))
                        .lineSpacing(6)
                        .foregroundColor(bodyColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 24)
                        .textSelection(.enabled)
                } else {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, para in
                            Text(para)
                                .font(.system(size: fontSize))
                                .lineSpacing(6)
                                .foregroundColor(bodyColor)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 24)
                }
            }
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
        .task { loadText() }
        .onDisappear { stopSpeak() }
    }

    /// 后台加载：先读开头一小部分立刻显示，再分块读取全文并回报百分比。
    private func loadText() {
        let url = novel.fileURL
        isLoading = true
        loadProgress = 0
        Task.detached(priority: .userInitiated) {
            // 1) 先读开头，快速上屏
            let preview = LocalNovelSource.readTextPreview(from: url)
            DispatchQueue.main.async {
                self.content = preview
                self.paragraphs = self.buildParagraphs(preview)
            }
            // 2) 后台继续读全文 + 进度
            let full = LocalNovelSource.readTextChunked(from: url) { p in
                DispatchQueue.main.async {
                    self.loadProgress = p
                }
            }
            DispatchQueue.main.async {
                self.content = full
                self.paragraphs = self.buildParagraphs(full)
                self.isLoading = false
            }
        }
    }

    /// 把整本文本拆成多个短段落，配合 LazyVStack 惰性渲染，避免一个巨型 Text 拖慢界面。
    private func buildParagraphs(_ text: String) -> [String] {
        var result: [String] = []
        for line in text.components(separatedBy: "\n") {
            if line.isEmpty { continue }
            // 超长行（无换行）按固定长度再拆，保证每个段落渲染轻量
            var rest = Substring(line)
            while rest.count > 2500 {
                let idx = rest.index(rest.startIndex, offsetBy: 2500)
                result.append(String(rest[..<idx]))
                rest = rest[idx...]
            }
            result.append(String(rest))
        }
        return result
    }

    // MARK: 朗读控制条

    private var speakBar: some View {
        HStack(spacing: 14) {
            // 播放 / 暂停
            Button { toggleSpeak() } label: {
                Image(systemName: speech.isSpeaking ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 26))
                    .foregroundColor(.accentColor)
            }
            // 停止
            Button { stopSpeak() } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 18))
                    .foregroundColor(.secondary)
            }
            // 声音包切换
            Menu {
                ForEach(availableVoices, id: \.identifier) { v in
                    Button { selectVoice(v) } label: {
                        if v.identifier == selectedVoice?.identifier {
                            Label(voiceName(v), systemImage: "checkmark")
                        } else {
                            Text(voiceName(v))
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "person.wave.2")
                    Text(selectedVoice?.name ?? "中文")
                        .lineLimit(1)
                }
                .font(.system(size: 13))
                .foregroundColor(.primary)
            }

            Spacer()

            // 语速
            Button { rate = max(0.3, rate - 0.1) } label: {
                Image(systemName: "minus.circle")
            }
            Text(String(format: "%.1f", rate))
                .font(.system(size: 12).monospacedDigit())
                .foregroundColor(.secondary)
            Button { rate = min(0.6, rate + 0.1) } label: {
                Image(systemName: "plus.circle")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background((isDark ? Color.black.opacity(0.35) : Color.black.opacity(0.06)))
    }

    // MARK: 朗读控制

    private func selectVoice(_ v: AVSpeechSynthesisVoice) {
        voiceID = v.identifier
        UserDefaults.standard.set(v.identifier, forKey: "ttsVoice")
    }

    private func voiceName(_ v: AVSpeechSynthesisVoice) -> String {
        let lang = Locale(identifier: v.language).localizedString(forIdentifier: v.language) ?? v.language
        return "\(v.name)（\(lang)）"
    }

    private func toggleSpeak() {
        if synthesizer.isSpeaking {
            synthesizer.pauseSpeaking(at: .immediate)
        } else if synthesizer.isPaused {
            synthesizer.continueSpeaking()
        } else {
            startSpeak()
        }
    }

    private func startSpeak() {
        let text = content.isEmpty ? "（没有可朗读的文本）" : content
        let utt = AVSpeechUtterance(string: text)
        utt.voice = selectedVoice
        utt.rate = rate
        synthesizer.delegate = speech
        synthesizer.speak(utt)
        speech.isSpeaking = true
    }

    private func stopSpeak() {
        synthesizer.stopSpeaking(at: .immediate)
        speech.isSpeaking = false
    }
}
