import Foundation
import Darwin

/// 系统/App 内存信息（用于「还剩多少内存」显示）。
enum MemoryInfo {

    /// 设备总物理内存（字节）
    static var totalMemory: UInt64 {
        ProcessInfo.processInfo.physicalMemory
    }

    /// 当前可用内存（free + inactive，字节）
    static var availableMemory: UInt64 {
        var vm = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        let page = UInt64(vm_page_size)
        let free = UInt64(vm.free_count) * page
        let inactive = UInt64(vm.inactive_count) * page
        return free + inactive
    }

    /// 当前已用内存（可用内存的补集）
    static var usedMemory: UInt64 {
        let total = totalMemory
        let avail = availableMemory
        return avail < total ? total - avail : 0
    }

    /// 本 App 当前常驻内存（resident set size，字节）
    static var appUsedMemory: UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return info.resident_size
    }

    static func bytes(_ b: UInt64) -> String {
        let v = Double(b)
        if v >= 1_073_741_824 { return String(format: "%.1f GB", v / 1_073_741_824) }
        if v >= 1_048_576 { return String(format: "%.1f MB", v / 1_048_576) }
        if v >= 1024 { return String(format: "%.0f KB", v / 1024) }
        return "\(b) B"
    }
}
