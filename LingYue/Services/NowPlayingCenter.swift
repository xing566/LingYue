import Foundation
import MediaPlayer
import UIKit

/// 锁屏/控制中心 Now Playing 与远程控制命令封装。
final class NowPlayingCenter {

    struct Handlers {
        var onPlayPause: (() -> Void)?
        var onNext: (() -> Void)?
        var onPrevious: (() -> Void)?
        var onSeek: ((TimeInterval) -> Void)?
    }

    private let infoCenter = MPNowPlayingInfoCenter.default()
    private let commandCenter = MPRemoteCommandCenter.shared()
    private var handlers: Handlers = Handlers()

    func setup(handlers: Handlers) {
        self.handlers = handlers

        commandCenter.playCommand.addTarget { [weak self] _ in
            self?.handlers.onPlayPause?(); return .success
        }
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.handlers.onPlayPause?(); return .success
        }
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.handlers.onPlayPause?(); return .success
        }
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            self?.handlers.onNext?(); return .success
        }
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            self?.handlers.onPrevious?(); return .success
        }
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.handlers.onSeek?(e.positionTime)
            return .success
        }
    }

    func update(title: String,
                artist: String,
                album: String,
                artworkData: Data?,
                currentTime: TimeInterval,
                duration: TimeInterval,
                isPlaying: Bool,
                lyrics: String? = nil) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: artist,
            MPMediaItemPropertyAlbumTitle: album,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0
        ]
        if let lyrics, !lyrics.isEmpty {
            info[MPMediaItemPropertyLyrics] = lyrics
        }
        if let data = artworkData, let image = UIImage(data: data) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        infoCenter.nowPlayingInfo = info
    }
}
