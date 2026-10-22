import Foundation

/// 专辑分组模型（供库视图与导航目的地使用）
struct AlbumGroup: Identifiable, Hashable {
    let id: String          // album|artist，用于稳定身份
    let album: String
    let artist: String
    let songs: [Song]

    init(album: String, artist: String, songs: [Song]) {
        self.id = "\(album)|\(artist)"
        self.album = album
        self.artist = artist
        self.songs = songs
    }
}
