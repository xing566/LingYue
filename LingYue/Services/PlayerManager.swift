import Foundation
import AVFoundation
import Observation

/// 播放器管理器：基于 AVPlayer 实现本地播放，含播放队列、进度、锁屏与远程控制。
@Observable
final class PlayerManager {

    enum RepeatMode: Int { case off = 0, all = 1, one = 2 }

    private(set) var currentSong: Song?
    private(set) var isPlaying = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0

    var volume: Float = 0.8 { didSet { player?.volume = volume } }
    var shuffle = false
    var repeatMode: RepeatMode = .off

    /// 当前播放队列（曲目顺序）
    private(set) var queue: [Song] = []

    private var player: AVPlayer?

    /// 供视频播放界面使用的 AVPlayer（与音频播放同一实例；仅在有视频文件时显示画面）。
    var avPlayer: AVPlayer? { player }
    private var timeObserver: Any?
    private let source: MusicSource
    private let nowPlaying = NowPlayingCenter()

    init(source: MusicSource) {
        self.source = source
        configureAudioSession()
        nowPlaying.setup(handlers: NowPlayingCenter.Handlers(
            onPlayPause: { [weak self] in self?.togglePlayPause() },
            onNext: { [weak self] in self?.playNext(manual: true) },
            onPrevious: { [weak self] in self?.playPrevious() },
            onSeek: { [weak self] offset in self?.seek(to: offset) }
        ))
    }

    // MARK: - 播放控制

    func play(_ song: Song, in queue: [Song]? = nil) {
        if let q = queue, !q.isEmpty {
            self.queue = q
        } else if !self.queue.contains(where: { $0.id == song.id }) {
            self.queue = songsByAdding(song)
        }
        currentSong = song
        duration = song.duration
        attachPlayer(to: song)
        resume()
        updateNowPlaying()
    }

    func togglePlayPause() {
        guard currentSong != nil else { return }
        isPlaying ? pause() : resume()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        updateNowPlaying()
        // 暂停后释放音频会话，避免空转耗电
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    func resume() {
        try? AVAudioSession.sharedInstance().setActive(true)
        player?.play()
        isPlaying = true
        updateNowPlaying()
    }

    func seek(to time: TimeInterval) {
        let t = min(max(time, 0), duration)
        currentTime = t
        player?.seek(to: CMTime(seconds: t, preferredTimescale: 600))
        updateNowPlaying()
    }

    /// 播放列表内相对位置；找不到则视为首尾。
    private var currentIndex: Int {
        guard let cur = currentSong else { return -1 }
        return queue.firstIndex { $0.id == cur.id } ?? -1
    }

    func playNext(manual: Bool = true) {
        guard !queue.isEmpty else { return }
        if repeatMode == .one && manual {
            restartCurrent()
            return
        }
        let nextIndex: Int
        if repeatMode == .off && currentIndex == queue.count - 1 {
            // 播放到末尾则停止
            pause()
            return
        }
        if repeatMode == .one { nextIndex = currentIndex }
        else { nextIndex = (currentIndex + 1) % queue.count }
        let song = queue[nextIndex]
        play(song, in: queue)
    }

    func playPrevious() {
        guard !queue.isEmpty else { return }
        // 播放超过 3 秒则回到开头
        if currentTime > 3 {
            seek(to: 0)
            return
        }
        let prevIndex = (currentIndex - 1 + queue.count) % queue.count
        play(queue[prevIndex], in: queue)
    }

    private func restartCurrent() {
        seek(to: 0)
        resume()
    }

    func shuffleQueue() {
        guard let cur = currentSong else { return }
        var rest = queue.filter { $0.id != cur.id }
        rest.shuffle()
        queue = [cur] + rest
        shuffle = true
    }

    func restoreOrder(_ order: [Song]) {
        guard let cur = currentSong else { return }
        let rest = order.filter { $0.id != cur.id }
        queue = [cur] + rest
        shuffle = false
    }

    /// 当前歌曲入队（插到队列末尾并设为当前）
    private func songsByAdding(_ song: Song) -> [Song] {
        var q = queue
        q.append(song)
        return q
    }

    // MARK: - AVPlayer

    private func attachPlayer(to song: Song) {
        if let observer = timeObserver { player?.removeTimeObserver(observer); timeObserver = nil }
        let url = source.resolveURL(for: song)
        player = AVPlayer(url: url)
        player?.volume = volume
        // 始终尝试从真实媒体读取时长（纠正存储值错误/为 0 的情况）
        let currentPlayer = player
        Task { [weak self] in
            guard let item = currentPlayer?.currentItem,
                  let dur = try? await item.asset.load(.duration), dur.isNumeric,
                  dur.seconds.isFinite, dur.seconds > 0 else { return }
            await MainActor.run {
                self?.duration = dur.seconds
                self?.updateNowPlaying()
            }
        }
        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            // 时长在 attach 时已按歌曲元数据设置；这里只更新播放进度
            self.currentTime = time.seconds.isFinite ? time.seconds : 0
            self.updateNowPlaying()
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(didPlayToEnd),
            name: .AVPlayerItemDidPlayToEndTime, object: player?.currentItem
        )
    }

    @objc private func didPlayToEnd() {
        switch repeatMode {
        case .one: restartCurrent()
        case .off:
            if currentIndex < queue.count - 1 { playNext(manual: true) }
            else { pause() }
        case .all: playNext(manual: true)
        }
    }

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [])
        try? session.setActive(true)
    }

    // MARK: - 锁屏 / 远程控制

    private func updateNowPlaying() {
        guard let song = currentSong else { return }
        nowPlaying.update(
            title: song.displayTitle,
            artist: song.artist,
            album: song.album,
            artworkData: song.artworkData,
            currentTime: currentTime,
            duration: duration,
            isPlaying: isPlaying
        )
    }
}
