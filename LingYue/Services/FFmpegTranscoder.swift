import Foundation
import Libavcodec
import Libavformat
import Libavutil
import Libswresample

/// 用 FFmpeg（kingslay 音频库）把 iOS 系统无法解码的格式（WMA 等）转成可播的 WAV。
/// 原理：打开文件 → 找到音频流 → 解码 → 重采样为 44.1kHz/立体声/s16 → 写 WAV。
enum FFmpegTranscoder {

    /// AVPlayer 原生能播的扩展名（这些不需要转码）
    static let nativelySupported: Set<String> = [
        "mp3", "m4a", "aac", "wav", "aiff", "caf", "alac", "m4b", "mp4", "flac"
    ]

    /// 判断该文件是否需要转码（不在原生支持列表里的就要转，如 wma/ogg/opus/mkv/avi 等）
    static func needsTranscode(_ url: URL) -> Bool {
        !nativelySupported.contains(url.pathExtension.lowercased())
    }

    /// 把 inputURL 解码成同目录的 .wav（44.1kHz / 立体声 / 16bit）。成功返回 wav URL。
    static func decodeToWav(input inputURL: URL) async -> URL? {
        let outputURL = inputURL.deletingPathExtension().appendingPathExtension("wav")
        let ok = await Task.detached(priority: .userInitiated) { () -> Bool in
            decode(inputPath: inputURL.path, outputPath: outputURL.path)
        }.value
        if ok { return outputURL }
        try? FileManager.default.removeItem(at: outputURL)
        return nil
    }

    // MARK: - 底层解码（同步，在后台线程执行）

    private static func decode(inputPath: String, outputPath: String) -> Bool {
        var fmtCtx: UnsafeMutablePointer<AVFormatContext>? = nil
        guard let cPath = inputPath.cString(using: .utf8) else { return false }
        guard avformat_open_input(&fmtCtx, cPath, nil, nil) >= 0, let fmt = fmtCtx else { return false }
        defer { avformat_close_input(&fmtCtx) }

        guard avformat_find_stream_info(fmt, nil) >= 0 else { return false }

        // 找最佳音频流
        let streamIdx = av_find_best_stream(fmt, AVMEDIA_TYPE_AUDIO, -1, -1, nil, 0)
        guard streamIdx >= 0 else { return false }
        guard let stream = fmt.pointee.streams[Int(streamIdx)] else { return false }
        guard let codecpar = stream.pointee.codecpar else { return false }
        guard let codec = avcodec_find_decoder(codecpar.pointee.codec_id) else { return false }
        guard let dec = avcodec_alloc_context3(codec) else { return false }
        defer { avcodec_free_context(&dec) }
        guard avcodec_parameters_to_context(dec, codecpar) >= 0 else { return false }
        guard avcodec_open2(dec, codec, nil) >= 0 else { return false }

        // 输出格式
        let outRate: Int32 = 44100
        let outCh: Int32 = 2
        let outFmt = AVSampleFormat_S16

        var inLayout = AVChannelLayout()
        av_channel_layout_default(&inLayout, dec.pointee.ch_layout.nb_channels)
        var outLayout = AVChannelLayout()
        av_channel_layout_default(&outLayout, outCh)

        // 重采样器
        var swr: UnsafeMutablePointer<SwrContext>? = swr_alloc()
        guard let swr else { return false }
        defer { swr_free(&swr) }
        let swrOK = swr_alloc_set_opts2(
            &swr,
            &outLayout, outFmt, outRate,
            &inLayout, dec.pointee.sample_fmt, dec.pointee.sample_rate,
            0, nil)
        guard swrOK >= 0, swr_init(swr) >= 0 else { return false }

        // 打开输出文件
        guard let cOut = outputPath.cString(using: .utf8) else { return false }
        guard let fp = fopen(cOut, "wb") else { return false }
        defer { fclose(fp) }

        // 先写占位 WAV 头（44 字节），全部写完再回头补大小
        var placeholder = Data(repeating: 0, count: 44)
        _ = placeholder.withUnsafeBytes { fwrite($0.baseAddress, 1, 44, fp) }
        var dataBytes: UInt32 = 0

        let pkt = av_packet_alloc()
        let frame = av_frame_alloc()
        guard let pkt, let frame else { return false }
        defer { av_packet_free(&pkt); av_frame_free(&frame) }

        while av_read_frame(fmt, pkt) >= 0 {
            defer { av_packet_unref(pkt) }
            if pkt.pointee.stream_index == streamIdx {
                if avcodec_send_packet(dec, pkt) >= 0 {
                    while avcodec_receive_frame(dec, frame) >= 0 {
                        guard writeFrame(swr, frame, to: fp, outFmt: outFmt,
                                         outCh: outCh, outRate: outRate,
                                         dataBytes: &dataBytes) else {
                            return false
                        }
                        av_frame_unref(frame)
                    }
                }
            }
        }
        // 冲刷解码器剩余帧
        avcodec_send_packet(dec, nil)
        while avcodec_receive_frame(dec, frame) >= 0 {
            guard writeFrame(swr, frame, to: fp, outFmt: outFmt,
                             outCh: outCh, outRate: outRate,
                             dataBytes: &dataBytes) else { return false }
            av_frame_unref(frame)
        }

        // 补写 WAV 头大小
        fseek(fp, 4, SEEK_SET)
        var riffSize: UInt32 = 36 &+ dataBytes
        withUnsafePointer(to: &riffSize) { fwrite($0, 1, 4, fp) }
        fseek(fp, 40, SEEK_SET)
        withUnsafePointer(to: &dataBytes) { fwrite($0, 1, 4, fp) }
        fflush(fp)

        return dataBytes > 0
    }

    /// 把一个解码帧重采样并写入 WAV（小端 s16 交错）。
    private static func writeFrame(
        _ swr: UnsafeMutablePointer<SwrContext>?,
        _ frame: UnsafeMutablePointer<AVFrame>?,
        to fp: UnsafeMutablePointer<FILE>?,
        outFmt: AVSampleFormat, outCh: Int32, outRate: Int32,
        dataBytes: inout UInt32
    ) -> Bool {
        let inSamples = frame.pointee.nb_samples
        guard inSamples > 0 else { return true }

        // 估算输出样本数
        let inRate = frame.pointee.sample_rate
        let estOut = (Int(inSamples) * Int(outRate) / max(1, Int(inRate))) + 256
        let capacity = estOut * Int(outCh) * 2  // s16
        guard capacity > 0 else { return true }

        let outBuf = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { outBuf.deallocate() }

        // 构造输入平面指针数组
        let dataPtr = frame.pointee.data
        var inPointers: [UnsafePointer<UInt8>?] = []
        for i in 0..<8 { inPointers.append(dataPtr?[i]) }
        var inData: [UnsafePointer<UInt8>?] = inPointers

        var outData: UnsafeMutablePointer<UInt8>? = outBuf
        let converted = swr_convert(swr, &outData, Int32(estOut),
                                    &inData, inSamples)
        guard converted > 0 else { return true }
        let bytes = Int(converted) * Int(outCh) * 2
        let written = fwrite(outBuf, 1, bytes, fp)
        dataBytes += UInt32(written)
        return true
    }
}
