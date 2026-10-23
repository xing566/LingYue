import Foundation

/// 一部有声书 / 小说：标题、作者、分章节可播放列表。
struct Audiobook: Identifiable, Hashable {
    let id: UUID
    var title: String
    var author: String
    var sections: [Song]

    init(id: UUID = UUID(),
         title: String,
         author: String = "未知作者",
         sections: [Song]) {
        self.id = id
        self.title = title
        self.author = author
        self.sections = sections
    }

    /// 总时长文案（秒→X小时Y分 / Y分钟）
    var durationText: String {
        let total = sections.reduce(0) { $0 + $1.duration }
        guard total > 0 else { return "—" }
        let minutes = Int(total) / 60
        let hours = minutes / 60
        return hours > 0 ? "\(hours)小时\(minutes % 60)分" : "\(minutes)分钟"
    }
}
