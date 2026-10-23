import Foundation
import CoreFoundation

/// 本地 TXT 小说条目。
struct Novel: Identifiable, Hashable {
    let id: UUID
    var name: String
    var fileURL: URL

    init(id: UUID = UUID(), name: String, fileURL: URL) {
        self.id = id
        self.name = name
        self.fileURL = fileURL
    }
}

/// 本地 TXT 小说来源：扫描 / 导入 Documents/Novels 目录，并按常见编码读取文本。
struct LocalNovelSource {

    /// 支持的文本格式（统一按多编码解码后阅读）
    private static let textExtensions: Set<String> = [
        "txt", "md", "text", "log", "srt", "lrc", "sub", "rtf", "csv"
    ]

    static var libraryURL: URL {
        LocalLibrarySource.documentsURL.appendingPathComponent("Novels", isDirectory: true)
    }

    /// 扫描本地 TXT 小说
    static func scan() -> [Novel] {
        try? FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: libraryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return files
            .filter { textExtensions.contains($0.pathExtension.lowercased()) }
            .map { Novel(name: $0.deletingPathExtension().lastPathComponent, fileURL: $0) }
            .sorted { $0.name < $1.name }
    }

    /// 从文件 App 导入文本（security-scoped），返回新增 Novel 列表
    static func importFiles(from urls: [URL]) -> [Novel] {
        try? FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true)
        var added: [Novel] = []
        for src in urls {
            let accessed = src.startAccessingSecurityScopedResource()
            defer { if accessed { src.stopAccessingSecurityScopedResource() } }
            guard textExtensions.contains(src.pathExtension.lowercased()) else { continue }
            let dest = libraryURL.appendingPathComponent(src.lastPathComponent)
            do {
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.copyItem(at: src, to: dest)
                added.append(Novel(name: dest.deletingPathExtension().lastPathComponent, fileURL: dest))
            } catch {
                print("导入文本失败 \(src.lastPathComponent): \(error)")
            }
        }
        return added
    }

    /// 删除某本本地 TXT 小说（App 内滑动删除用）。
    static func delete(_ novel: Novel) {
        try? FileManager.default.removeItem(at: novel.fileURL)
    }

    /// 读取 TXT 文本：依次尝试 UTF-8 / UTF-16 / GBK(GB18030)，兼容中文常见编码。
    static func readText(from url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else { return "" }
        return decode(data)
    }

    /// 分块读取 + 进度回调：用于大文件，后台调用，避免一次性读入阻塞。
    /// - Parameters:
    ///   - onProgress: 已读字节占比（0…1），在主线程外调用，调用方需自行切回主线程更新 UI。
    static func readTextChunked(from url: URL, onProgress: @escaping (Double) -> Void) -> String {
        let fm = FileManager.default
        let fileSize = (try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?
            .doubleValue ?? 0
        guard fileSize > 0 else { return readText(from: url) }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return readText(from: url) }
        defer { try? handle.close() }
        let chunk = 1_048_576   // 每次 1MB
        var data = Data()
        data.reserveCapacity(Int(fileSize))
        while true {
            let d = handle.readData(ofLength: chunk)
            if d.isEmpty { break }
            data.append(d)
            onProgress(min(1.0, Double(data.count) / fileSize))
        }
        return decode(data)
    }

    /// 只读取文件开头一小部分（最多 2MB）并解码：用于让大文件「先显示开头」，不阻塞。
    static func readTextPreview(from url: URL) -> String {
        let fm = FileManager.default
        let fileSize = (try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?
            .doubleValue ?? 0
        let cap = min(Int(fileSize), 2 * 1_048_576)
        guard cap > 0, let handle = try? FileHandle(forReadingFrom: url) else {
            return readText(from: url)
        }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: cap)
        return decode(data)
    }

    /// 统一解码：去 UTF-8 BOM，按 UTF-8 / UTF-16 / GB18030 / ISO-Latin1 依次尝试。
    private static func decode(_ data: Data) -> String {
        let body = data.starts(with: [0xEF, 0xBB, 0xBF]) ? data.dropFirst(3) : data[...]
        if let s = String(data: body, encoding: .utf8) { return s }
        if let s = String(data: data, encoding: .utf16) { return s }
        let gbk = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        if let s = String(data: data, encoding: gbk) { return s }
        return String(data: data, encoding: .isoLatin1) ?? ""
    }
}
