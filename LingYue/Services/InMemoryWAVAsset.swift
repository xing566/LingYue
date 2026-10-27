import AVFoundation

/// 把一段 WAV 数据**直接从内存**喂给 AVPlayer 播放（用 AVAssetResourceLoader 自定义 scheme，不落盘）。
/// 用于「下一首预缓存交给运行内存」：转码后的 WAV 只存在内存里，切换时秒播且不占可见磁盘。
final class InMemoryWAVAsset: NSObject, AVAssetResourceLoaderDelegate {
    private let data: Data

    init(data: Data) {
        self.data = data
        super.init()
    }

    /// 生成一个可用 AVPlayer 播放的 item（资源由本对象从内存提供）。
    func makeItem() -> AVPlayerItem {
        let url = URL(string: "lingyuemem://memory.wav")!
        let asset = AVURLAsset(url: url)
        asset.resourceLoader.setDelegate(self, queue: .global(qos: .userInitiated))
        return AVPlayerItem(asset: asset)
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        if let info = loadingRequest.contentInformationRequest {
            info.contentType = "com.microsoft.waveform-audio"   // WAV (PCM)
            info.contentLength = Int64(data.count)
            info.isByteRangeAccessSupported = true
        }
        if let dr = loadingRequest.dataRequest {
            let offset = dr.requestedOffset >= 0 ? Int(dr.requestedOffset) : 0
            let length: Int
            if dr.requestsAllDataToEndOfResource {
                length = data.count - offset
            } else {
                length = dr.requestedLength
            }
            let start = max(0, min(offset, data.count))
            let end = max(start, min(start + max(length, 0), data.count))
            if end > start {
                dr.respond(with: data.subdata(in: start..<end))
            }
            loadingRequest.finishLoading()
        } else {
            loadingRequest.finishLoading()
        }
        return true
    }
}
