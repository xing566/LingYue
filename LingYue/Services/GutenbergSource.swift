import Foundation

/// 古登堡计划（Project Gutenberg）中文公版小说源：下载 txt 到本地 Novels/古登堡，
/// 交给 NovelReaderView 阅读（自动分章 / 朗读 / 目录）。
///
/// 说明：受 robots.txt 限制无法程序化全文搜索，故内置一份「编号已核实的精选中文公版经典」，
/// 并支持按古登堡编号自由添加更多公版书目。
enum GutenbergSource {

    struct Book: Identifiable, Hashable {
        let id: Int            // 古登堡 ebook 编号
        var title: String
        var author: String
    }

    /// 精选中文公版经典（编号均已核实，txt 直链可用）。
    static let curated: [Book] = [
        Book(id: 23950, title: "三国演义", author: "罗贯中"),
        Book(id: 23863, title: "水浒传", author: "施耐庵"),
        Book(id: 23962, title: "西游记", author: "吴承恩"),
        Book(id: 24264, title: "红楼梦", author: "曹雪芹"),
        Book(id: 24032, title: "儒林外史", author: "吴敬梓"),
        Book(id: 25124, title: "老残游记", author: "刘鹗"),
        Book(id: 23839, title: "论语", author: "孔子")
    ]

    /// 某编号的 UTF-8 纯文本直链（古登堡 cache 通用格式）。
    static func txtURL(for id: Int) -> URL {
        URL(string: "https://www.gutenberg.org/cache/epub/\(id)/pg\(id).txt")!
    }

    /// 下载 txt 到本地 Novels/古登堡 目录，返回可用于阅读的 Novel。
    static func downloadNovel(_ book: Book) async -> Novel? {
        let dir = LocalNovelSource.libraryURL
            .appendingPathComponent("古登堡", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let url = txtURL(for: book.id)
        let data: Data
        do {
            let (d, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, !d.isEmpty else { return nil }
            data = d
        } catch { return nil }

        let dest = dir.appendingPathComponent("\(book.title).txt")
        do {
            try data.write(to: dest)
        } catch { return nil }
        return Novel(name: book.title, fileURL: dest)
    }
}
