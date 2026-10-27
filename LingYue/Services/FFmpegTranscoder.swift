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

    /// 把 inputURL 解码成 WAV 数据，直接交给内存播放器（不落盘）。成功返回内存中的 WAV Data。
    static func decodeToWavData(input inputURL: URL) async -> Data? {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("precache-\(UUID().uuidString)")
            .appendingPathExtension("wav")
        let ok = await Task.detached(priority: .userInitiated) { () -> Bool in
            decode(inputPath: inputURL.path, outputPath: tmp.path)
        }.value
        guard ok else {
            try? FileManager.default.removeItem(at: tmp)
            return nil
        }
        let data = try? Data(contentsOf: tmp)
        try? FileManager.default.removeItem(at: tmp)
        return data
    }

    // MARK: - 底层解码（同步，在后台线程执行）

    private static func decode(inputPath: String, outputPath: String) -> Bool {
        var fmtCtx: UnsafeMutablePointer<AVFormatContext>? = nil
        guard let cPath = inputPath.cString(using: .utf8) else { return false }
        guard avformat_open_input(&fmtCtx, cPath, nil, nil) >= 0, let fmt = fmtCtx else { return false }
        defer { avformat_close_input(&fmtCtx) }

        guard avformat_find_stream_info(fmt, nil) >= 0 else { return false }

        let streamIdx = av_find_best_stream(fmt, AVMEDIA_TYPE_AUDIO, -1, -1, nil, 0)
        guard streamIdx >= 0 else { return false }
        guard let stream = fmt.pointee.streams[Int(streamIdx)] else { return false }
        guard let codecpar = stream.pointee.codecpar else { return false }
        guard let codec = avcodec_find_decoder(codecpar.pointee.codec_id) else { return false }

        var dec = avcodec_alloc_context3(codec)
        guard dec != nil else { return false }
        defer { avcodec_free_context(&dec) }
        guard avcodec_parameters_to_context(dec, codecpar) >= 0 else { return false }
        guard avcodec_open2(dec, codec, nil) >= 0 else { return false }

        let sampleFmt = dec!.pointee.sample_fmt
        let channels = Int(dec!.pointee.ch_layout.nb_channels)
        let rate = Int(dec!.pointee.sample_rate)
        guard channels > 0, rate > 0 else { return false }
        guard let info = wavInfo(for: sampleFmt) else { return false }

        guard let cOut = outputPath.cString(using: .utf8) else { return false }
        guard let fp = fopen(cOut, "wb") else { return false }
        defer { fclose(fp) }

        // 占位 WAV 头（44 字节），写完数据再回头补
        var placeholder = Data(repeating: 0, count: 44)
        _ = placeholder.withUnsafeBytes { fwrite($0.baseAddress, 1, 44, fp) }
        var dataBytes: UInt32 = 0

        var pkt = av_packet_alloc()
        var frame = av_frame_alloc()
        guard pkt != nil, frame != nil else { return false }
        defer { av_packet_free(&pkt); av_frame_free(&frame) }

        while av_read_frame(fmt, pkt) >= 0 {
            defer { av_packet_unref(pkt) }
            if pkt!.pointee.stream_index == streamIdx {
                if avcodec_send_packet(dec, pkt) >= 0 {
                    while avcodec_receive_frame(dec, frame) >= 0 {
                        guard appendFrame(frame!, to: fp, dataBytes: &dataBytes,
                                          fmt: sampleFmt, channels: channels) else {
                            return false
                        }
                        av_frame_unref(frame)
                    }
                }
            }
        }
        avcodec_send_packet(dec, nil)
        while avcodec_receive_frame(dec, frame) >= 0 {
            guard appendFrame(frame!, to: fp, dataBytes: &dataBytes,
                              fmt: sampleFmt, channels: channels) else { return false }
            av_frame_unref(frame)
        }

        // 写 WAV 头
        let blockAlign: UInt16 = UInt16(channels * info.bytes)
        let byteRate: UInt32 = UInt32(rate) * UInt32(blockAlign)
        let bits: UInt16 = UInt16(info.bytes * 8)

        var header = Data()
        header.append(contentsOf: [UInt8]("RIFF".utf8))
        header.append(contentsOf: little32(36 &+ dataBytes))
        header.append(contentsOf: [UInt8]("WAVE".utf8))
        header.append(contentsOf: [UInt8]("fmt ".utf8))
        header.append(contentsOf: little32(16))
        header.append(contentsOf: little16(info.tag))
        header.append(contentsOf: little16(UInt16(channels)))
        header.append(contentsOf: little32(UInt32(rate)))
        header.append(contentsOf: little32(byteRate))
        header.append(contentsOf: little16(blockAlign))
        header.append(contentsOf: little16(bits))
        header.append(contentsOf: [UInt8]("data".utf8))
        header.append(contentsOf: little32(dataBytes))
        fseek(fp, 0, SEEK_SET)
        _ = header.withUnsafeBytes { fwrite($0.baseAddress, 1, header.count, fp) }
        fflush(fp)

        return dataBytes > 0
    }

    /// 把一个解码帧按原生格式交错写入 WAV。
    private static func appendFrame(
        _ frame: UnsafeMutablePointer<AVFrame>,
        to fp: UnsafeMutablePointer<FILE>,
        dataBytes: inout UInt32,
        fmt: AVSampleFormat, channels: Int
    ) -> Bool {
        let samples = Int(frame.pointee.nb_samples)
        guard samples > 0 else { return true }
        guard let info = wavInfo(for: fmt) else { return false }

        // frame.data 在 Swift 中被导入为元组，转成平面指针数组
        let d = frame.pointee.data
        let planes: [UnsafeMutablePointer<UInt8>?] = [d.0, d.1, d.2, d.3, d.4, d.5, d.6, d.7]

        if info.planar {
            let outCount = samples * channels
            let outBytes = outCount * info.bytes
            guard outBytes > 0 else { return true }
            let outBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: outBytes)
            defer { outBuf.deallocate() }
            for i in 0..<samples {
                for c in 0..<channels {
                    guard let src = planes[c] else { return false }
                    switch fmt {
                    case AV_SAMPLE_FMT_FLTP:
                        let v = UnsafeRawPointer(src).advanced(by: i * 4).load(as: Float.self)
                        UnsafeMutableRawPointer(outBuf).advanced(by: (i * channels + c) * 4)
                            .storeBytes(of: v, as: Float.self)
                    case AV_SAMPLE_FMT_S16P:
                        let v = UnsafeRawPointer(src).advanced(by: i * 2).load(as: Int16.self)
                        UnsafeMutableRawPointer(outBuf).advanced(by: (i * channels + c) * 2)
                            .storeBytes(of: v, as: Int16.self)
                    case AV_SAMPLE_FMT_S32P:
                        let v = UnsafeRawPointer(src).advanced(by: i * 4).load(as: Int32.self)
                        UnsafeMutableRawPointer(outBuf).advanced(by: (i * channels + c) * 4)
                            .storeBytes(of: v, as: Int32.self)
                    case AV_SAMPLE_FMT_U8P:
                        outBuf.advanced(by: i * channels + c).pointee = src.advanced(by: i).pointee
                    default:
                        return false
                    }
                }
            }
            let written = fwrite(outBuf, 1, outBytes, fp)
            dataBytes += UInt32(written)
            return written == outBytes
        } else {
            // 已是交错
            guard let first = planes[0] else { return false }
            let outBytes = samples * channels * info.bytes
            let written = fwrite(first, 1, outBytes, fp)
            dataBytes += UInt32(written)
            return written == outBytes
        }
    }

    /// 把 AVSampleFormat 映射到 WAV 参数：fmt tag（1=PCM int，3=IEEE float）、每样本字节、是否平面。
    private static func wavInfo(for fmt: AVSampleFormat) -> (tag: UInt16, bytes: Int, planar: Bool)? {
        switch fmt {
        case AV_SAMPLE_FMT_U8:    return (1, 1, false)
        case AV_SAMPLE_FMT_U8P:   return (1, 1, true)
        case AV_SAMPLE_FMT_S16:   return (1, 2, false)
        case AV_SAMPLE_FMT_S16P:  return (1, 2, true)
        case AV_SAMPLE_FMT_S32:   return (1, 4, false)
        case AV_SAMPLE_FMT_S32P:  return (1, 4, true)
        case AV_SAMPLE_FMT_FLT:   return (3, 4, false)
        case AV_SAMPLE_FMT_FLTP:  return (3, 4, true)
        default:                  return nil
        }
    }

    private static func little16(_ v: UInt16) -> [UInt8] {
        [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)]
    }
    private static func little32(_ v: UInt32) -> [UInt8] {
        [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]
    }
}
