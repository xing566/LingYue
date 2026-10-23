import SwiftUI
import AVFoundation
import AVFAudio
import Combine

/// 语音合成控制器：**唯一持有** AVSpeechSynthesizer（@StateObject 持久，避免 @State 引用被重建导致无声），
/// 负责朗读状态、音频会话激活、播放/暂停/停止。
final class SpeechDelegate: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    let synthesizer = AVSpeechSynthesizer()
    @Published var isSpeaking = false
    @Published var isPaused = false

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// 播放一段文本（先停掉旧的）。激活播放音频会话，让静音键下也能出声。
    func speak(_ text: String, voice: AVSpeechSynthesisVoice?, rate: Float) {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        isPaused = false
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let utt = AVSpeechUtterance(string: trimmed)
        utt.voice = voice
        utt.rate = rate
        synthesizer.speak(utt)
        isSpeaking = true
    }

    /// 播放 / 暂停 / 继续
    func toggle() {
        if synthesizer.isSpeaking {
            synthesizer.pauseSpeaking(at: .immediate)
            isSpeaking = false
            isPaused = true
        } else if synthesizer.isPaused {
            synthesizer.continueSpeaking()
            isPaused = false
            isSpeaking = true
        }
    }

    /// 停止
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        isPaused = false
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isSpeaking = false
        isPaused = false
        try? AVAudioSession.sharedInstance().setActive(false)
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isSpeaking = false
        isPaused = false
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}

/// 目录条目：title 为章节标题，index 为对应正文段落下标。
struct TOCEntry: Identifiable {
    let id: Int
    let index: Int
    let title: String
}

/// TXT 小说阅读器：上下滑动（滚动）阅读，支持调节字号、明暗主题、
/// 目录跳转，以及「朗读」功能（切换声音包 / 语速 / 播放暂停停止 / 点段落从此处开始朗读）。
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

    /// 目录：识别到的章节标题（index 对应正文段落下标）。
    @State private var tocEntries: [TOCEntry] = []
    @State private var showTOC = false
    @State private var scrollTarget: Int?
    /// 无中文语音时的提示文案。
    @State private var voiceHint: String?

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

            // 无中文语音时给出明确提示（根因：iPhone 未下载中文语音包）
            if let voiceHint {
                Text(voiceHint)
                    .font(.system(size: 12))
                    .foregroundColor(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 4)
            }

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

            ScrollViewReader { proxy in
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
                            .id(0)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, para in
                                Text(para)
                                    .font(.system(size: fontSize))
                                    .lineSpacing(6)
                                    .foregroundColor(bodyColor)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                                    .id(index)
                                    .onTapGesture { speak(fromParagraph: index) }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 24)
                    }
                }
                .onChange(of: scrollTarget) { new in
                    if let new { withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(new, anchor: .top) } }
                }
            }
        }
        .background((isDark ? Color(red: 0.06, green: 0.07, blue: 0.10) : Color(red: 0.96, green: 0.94, blue: 0.88))
            .ignoresSafeArea())
        .navigationTitle(novel.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showTOC = true } label: {
                    Image(systemName: "list.bullet")
                }
                .disabled(tocEntries.isEmpty)
            }
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
        .sheet(isPresented: $showTOC) { tocSheet }
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
                self.tocEntries = self.buildTOC(from: self.paragraphs)
                self.isLoading = false
            }
        }
    }

    /// 识别章节标题生成目录（“第X章/回/节/卷”、“卷一”、“Chapter N”等）。
    private func buildTOC(from paragraphs: [String]) -> [TOCEntry] {
        var entries: [TOCEntry] = []
        for (i, para) in paragraphs.enumerated() {
            let t = para.trimmingCharacters(in: .whitespacesAndNewlines)
            if isChapterHeading(t) {
                entries.append(TOCEntry(id: entries.count, index: i, title: String(t.prefix(40))))
            }
        }
        return entries
    }

    private func isChapterHeading(_ s: String) -> Bool {
        guard !s.isEmpty, s.count <= 60 else { return false }
        if s.range(of: #"^第\s*[0-9一二三四五六七八九十百千万零]+\s*[章回节卷部集]"#, options: .regularExpression) != nil { return true }
        if s.range(of: #"^[卷部集]\s*[一二三四五六七八九十]+"#, options: .regularExpression) != nil { return true }
        if s.range(of: #"^(Chapter|CHAPTER|chapter)\s*\d+"#, options: .regularExpression) != nil { return true }
        return false
    }

    /// 目录面板：点条目 → 跳到该章节并从此处开始朗读。
    private var tocSheet: some View {
        NavigationStack {
            List {
                if tocEntries.isEmpty {
                    Text("未识别到章节标题（支持「第X章」「第X回」「第X卷」「卷一」「Chapter N」）")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                } else {
                    ForEach(tocEntries) { entry in
                        Button {
                            scrollTarget = entry.index
                            showTOC = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                speak(fromParagraph: entry.index)
                            }
                        } label: {
                            Text(entry.title)
                                .font(.system(size: 15))
                                .foregroundColor(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("目录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { showTOC = false }
                }
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
                    Text(availableVoices.contains(where: { $0.language.lowercased().hasPrefix("zh") }) ? (selectedVoice?.name ?? "中文") : "无中文语音")
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
        if speech.isSpeaking || speech.isPaused {
            speech.toggle()
        } else {
            startSpeak()
        }
    }

    private func startSpeak() {
        let text = content.isEmpty ? "（没有可朗读的文本）" : content
        doSpeak(text)
    }

    /// 从指定段落开始朗读（点某段正文 / 目录条目触发）。
    private func speak(fromParagraph index: Int) {
        guard index >= 0, index < paragraphs.count else { startSpeak(); return }
        doSpeak(paragraphs[index...].joined(separator: "\n"))
    }

    /// 统一朗读入口：若系统里没有任何中文语音，先明确提示，避免静默无声。
    private func doSpeak(_ text: String) {
        let hasZh = availableVoices.contains { $0.language.lowercased().hasPrefix("zh") }
        if !hasZh {
            voiceHint = "未检测到中文语音：请到 设置→辅助功能→朗读内容→语音 下载「普通话」后重试"
            return
        }
        voiceHint = nil
        speech.speak(text, voice: resolveVoice(), rate: rate)
    }

    /// 声音包解析：优先用户已选，其次中文，最后任选一个可用声音，避免出现无声音包。
    private func resolveVoice() -> AVSpeechSynthesisVoice? {
        if !voiceID.isEmpty, let v = AVSpeechSynthesisVoice(identifier: voiceID) { return v }
        if let v = AVSpeechSynthesisVoice(language: "zh-CN") { return v }
        return AVSpeechSynthesisVoice.speechVoices().first
    }

    private func stopSpeak() {
        speech.stop()
    }
}
