import AVFoundation

/// 用 AVAssetResourceLoader 把内存里的 WAV Data 直接喂给 AVPlayer（不落盘、退出即释放）。
final class InMemoryWAVAsset: NSObject, AVAssetResourceLoaderDelegate {
    static let scheme = "lingyuemem"
    private let data: Data

    init(data: Data) {
        self.data = data
        super.init()
    }

    /// 生成一个播放 item，其音频源指向内存里的 WAV Data。
    func makeItem() -> AVPlayerItem {
        var comp = URLComponents()
        comp.scheme = Self.scheme
        comp.host = "memory"
        comp.path = "/memory.wav"
        guard let url = comp.url else {
            return AVPlayerItem(url: URL(string: "memory://memory/memory.wav")!)
        }
        let asset = AVURLAsset(url: url)
        asset.resourceLoader.setDelegate(self, queue: .main)
        return AVPlayerItem(asset: asset)
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader,
                        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        handle(loadingRequest)
        return true
    }

    private func handle(_ request: AVAssetResourceLoadingRequest) {
        // 提供内容信息（WAV），让 AVPlayer 能正确解析
        if let infoReq = request.contentInformationRequest {
            infoReq.contentType = "com.microsoft.waveform-audio"
            infoReq.isByteRangeAccessSupported = true
            infoReq.contentLength = Int64(data.count)
        }
        // 提供请求的字节区间
        if let dataReq = request.dataRequest {
            let start = Int(dataReq.requestedOffset)
            let length = dataReq.requestedLength > 0 ? Int(dataReq.requestedLength) : (data.count - start)
            let end = min(data.count, start + length)
            if start < data.count, end > start {
                dataReq.respond(with: data.subdata(in: start..<end))
            }
            request.finishLoading()
        } else {
            request.finishLoading()
        }
    }
}
