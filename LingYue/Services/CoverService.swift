import Foundation
import UIKit

/// 封面服务：按「歌名+歌手」联网自动找封面（网易云专辑图，兜底 iTunes 缩略图），并下载缓存。
enum CoverService {

    private static var cacheDir: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Covers", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func cacheFile(title: String, artist: String) -> URL {
        let key = "\(title)|\(artist)".replacingOccurrences(of: "/", with: "_")
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? title
        return cacheDir.appendingPathComponent(key).appendingPathExtension("jpg")
    }

    /// 取封面 Data（本地缓存优先，否则联网下载并缓存）
    static func fetch(title: String, artist: String) async -> Data? {
        let file = cacheFile(title: title, artist: artist)
        if let data = try? Data(contentsOf: file) { return data }

        guard let url = await coverURL(title: title, artist: artist) else { return nil }
        guard let data = await downloadData(url) else { return nil }
        try? data.write(to: file, atomically: true)
        return data
    }

    /// 找封面 URL（网易云优先，iTunes 兜底）
    static func coverURL(title: String, artist: String) async -> URL? {
        let artist = artist.isEmpty ? "" : artist
        if let u = await NetEaseService.coverURL(title: title, artist: artist) { return u }
        // iTunes 兜底
        let q = "\(title) \(artist)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? title
        if let url = URL(string: "https://itunes.apple.com/search?term=\(q)&media=music&entity=song&limit=1"),
           let (data, _) = try? await URLSession.shared.data(from: url),
           let dec = try? JSONDecoder().decode(iTunesService.Result.self, from: data),
           let art = dec.results.first?.artworkUrl100,
           let u = URL(string: art) {
            return u
        }
        return nil
    }

    static func downloadData(_ url: URL) async -> Data? {
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
        // 限制尺寸，避免大图占内存
        guard let image = UIImage(data: data) else { return data }
        let target: CGFloat = 400
        let maxSide = max(image.size.width, image.size.height)
        guard maxSide > target else { return data }
        let scale = target / maxSide
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
        return resized.jpegData(compressionQuality: 0.85) ?? data
    }
}
