import Foundation
import Darwin
import UIKit

/// 小组件里读取系统监控数据（电池/温度/内存/网速）。
/// 与 App 内悬浮窗逻辑等价，独立自包含，供 WidgetKit 扩展使用。
enum MetricsReader {

    // MARK: 电池
    static func batteryLevel() -> Int? {
        let dev = UIDevice.current
        dev.isBatteryMonitoringEnabled = true
        let lv = dev.batteryLevel
        guard lv >= 0 else { return nil }
        return Int((lv * 100).rounded())
    }

    static func isCharging() -> Bool {
        UIDevice.current.batteryState == .charging
    }

    // MARK: 温度（系统热状态）
    static func thermalText() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:  return "正常"
        case .fair:     return "略高"
        case .serious:  return "偏热"
        case .critical: return "过热"
        @unknown default: return "正常"
        }
    }

    // MARK: 可用内存（MB）
    static func availableMemoryMB() -> String {
        var vm = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return "—" }
        let page = UInt64(vm_page_size)
        let avail = (UInt64(vm.free_count) + UInt64(vm.inactive_count)) * page
        return String(format: "%.1f", Double(avail) / 1_048_576)
    }

    // MARK: 网速（采样约 1 秒）
    static func netText() -> String {
        let a = interfaceBytes()
        Thread.sleep(forTimeInterval: 1)
        let b = interfaceBytes()
        let down = Double(b.rx >= a.rx ? b.rx - a.rx : 0)
        let up   = Double(b.tx >= a.tx ? b.tx - a.tx : 0)
        return "↓\(kb(down)) ↑\(kb(up))"
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

    private static func kb(_ v: Double) -> String {
        if v >= 1_048_576 { return String(format: "%.1fM", v / 1_048_576) }
        return String(format: "%.0fK", v / 1024)
    }
}
