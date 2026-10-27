import Foundation
import Libavcodec
import Libavformat
import Libavutil

/// 用 FFmpeg（kingslay 音频库）把 iOS 系统无法解码的格式（WMA 等）转成可播的 WAV。
/// 原理：打开文件 → 找到音频流 → 解码 → 按解码器原生格式交错写 WAV（不重采样，保留原采样率/声道）。
enum FFmpegTranscoder {

    /// AVPlayer 原生能播的扩展名（这些不需要转码）
    static let nativelySupported: Set<String> = [
        "mp3", "m4a", "aac", "wav", "aiff", "caf", "alac", "m4b", "mp4", "flac"
    ]

    /// 判断该文件是否需要转码（不在原生支持列表里的就要转，如 wma/ogg/opus/mkv/avi 等）
    static func needsTranscode(_ url: URL) -> Bool {
        !nativelySupported.contains(url.pathExtension.lowercased())
    }

    /// AppCache/Transcoded 目录（转码 WAV 所在处）
    static var transcodedDir: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AppCache", isDirectory: true)
            .appendingPathComponent("Transcoded", isDirectory: true)
    }

    /// 某输入文件对应转码后的 WAV URL（Transcoded/<同名>.wav）
    static func wavURL(for input: URL) -> URL {
        let base = input.deletingPathExtension().lastPathComponent
        return transcodedDir.appendingPathComponent(base).appendingPathExtension("wav")
    }

    /// 清空已转码的 WAV（当前不使用，转由 PlayerManager 按需裁剪）
    static func clearTranscoded() {
        if let items = try? FileManager.default.contentsOfDirectory(at: transcodedDir, includingPropertiesForKeys: nil) {
            for item in items { try? FileManager.default.removeItem(at: item) }
        }
    }

    /// 把 inputURL 解码成 AppCache/Transcoded 下的 .wav。成功返回 wav URL。
    static func decodeToWav(input inputURL: URL) async -> URL? {
        try? FileManager.default.createDirectory(at: transcodedDir, withIntermediateDirectories: true)
        let outputURL = wavURL(for: inputURL)
        let ok = await Task.detached(priority: .userInitiated) { () -> Bool in
            decode(inputPath: inputURL.path, outputPath: outputURL.path)
        }.value
        if ok { return outputURL }
        try? FileManager.default.removeItem(at: outputURL)
        return nil
    }

    private static func little16(_ v: UInt16) -> [UInt8] {
        [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)]
    }
    private static func little32(_ v: UInt32) -> [UInt8] {
        [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]
    }
}
