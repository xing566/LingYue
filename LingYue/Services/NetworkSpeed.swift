import Foundation
import Darwin

/// 实时网速（下载/上传，字节/秒）：用 getifaddrs 周期采样 Wi-Fi/蜂窝接口字节数差值得出。
/// 这是设备级总网速（含本 App 及其它流量），符合「看网速」的直觉。
enum NetworkSpeed {
    private static var lastSample: (rx: UInt64, tx: UInt64)?
    private static var lastTime: Date?

    /// 采样一次，返回每秒下载/上传字节数。elapsedSeconds 为距上次采样经过的秒数。
    static func sample(elapsedSeconds: Double) -> (down: Double, up: Double) {
        let s = interfaceBytes()
        let now = Date()
        var down = 0.0, up = 0.0
        if let last = lastSample, let lt = lastTime {
            let dt = max(elapsedSeconds, 0.5)
            if s.rx >= last.rx { down = Double(s.rx - last.rx) / dt }
            if s.tx >= last.tx { up = Double(s.tx - last.tx) / dt }
        }
        lastSample = s
        lastTime = now
        return (down, up)
    }

    private static func interfaceBytes() -> (rx: UInt64, tx: UInt64) {
        var rx: UInt64 = 0, tx: UInt64 = 0
        var ifap: UnsafeMutablePointer<ifaddrs>? = nil
        guard getifaddrs(&ifap) == 0, let first = ifap else { return (0, 0) }
        defer { freeifaddrs(ifap) }
        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let p = ptr {
            let name = String(cString: p.pointee.ifa_name)
            if name.hasPrefix("en") || name.hasPrefix("pdp_ip") {
                if let data = p.pointee.ifa_data {
                    let ifd = data.assumingMemoryBound(to: if_data.self)
                    rx += UInt64(ifd.pointee.ifi_ibytes)
                    tx += UInt64(ifd.pointee.ifi_obytes)
                }
            }
            ptr = p.pointee.ifa_next
        }
        return (rx, tx)
    }

    /// 把字节/秒格式化成 M/K。
    static func bytesPerSec(_ v: Double) -> String {
        if v >= 1_048_576 { return String(format: "%.1fM", v / 1_048_576) }
        if v >= 1024 { return String(format: "%.0fK", v / 1024) }
        return "\(Int(v))B"
    }

    /// 精确到 KB/s 的数字。
    static func bytesPrecise(_ v: Double) -> String {
        let kb = v / 1024
        return String(format: "%.1f KB/s", kb)
    }
}
