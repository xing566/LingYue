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
            .filter { $0.pathExtension.lowercased() == "txt" }
            .map { Novel(name: $0.deletingPathExtension().lastPathComponent, fileURL: $0) }
            .sorted { $0.name < $1.name }
    }

    /// 从文件 App 导入 TXT（security-scoped），返回新增 Novel 列表
    static func importFiles(from urls: [URL]) -> [Novel] {
        try? FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true)
        var added: [Novel] = []
        for src in urls {
            let accessed = src.startAccessingSecurityScopedResource()
            defer { if accessed { src.stopAccessingSecurityScopedResource() } }
            guard src.pathExtension.lowercased() == "txt" else { continue }
            let dest = libraryURL.appendingPathComponent(src.lastPathComponent)
            do {
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.copyItem(at: src, to: dest)
                added.append(Novel(name: dest.deletingPathExtension().lastPathComponent, fileURL: dest))
            } catch {
                print("导入 TXT 失败 \(src.lastPathComponent): \(error)")
            }
        }
        return added
    }

    /// 读取 TXT 文本：依次尝试 UTF-8 / UTF-16 / GBK(GB18030)，兼容中文常见编码。
    static func readText(from url: URL) -> String {
        guard let data = try? Data(contentsOf: url) else { return "" }
        // 去掉 UTF-8 BOM，避免开头出现 \u{FEFF}
        let body = data.starts(with: [0xEF, 0xBB, 0xBF]) ? data.dropFirst(3) : data[...]
        if let s = String(data: body, encoding: .utf8) { return s }
        if let s = String(data: data, encoding: .utf16) { return s }
        let gbk = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        if let s = String(data: data, encoding: gbk) { return s }
        return String(data: data, encoding: .isoLatin1) ?? ""
    }
}
