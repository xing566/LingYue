import SwiftUI

/// 可拖动的悬浮监控小窗：显示设备温度状态（系统热状态）与剩余内存，可拖到屏幕任意位置。
/// iOS 不提供公开的设备温度读数，用 ProcessInfo.thermalState 近似（正常/略高/偏热/过热）。
struct FloatingMonitorView: View {
    @AppStorage("floatingMonitorEnabled") private var enabled = true
    @State private var offset = CGSize.zero
    @State private var memText = "—"
    @State private var thermalText = "正常"
    @State private var thermalColor: Color = .green
    @State private var batteryText = "—"
    @State private var batteryIcon = "battery.50percent"
    @State private var batteryColor: Color = .green
    @State private var netText = "↓ — ↑ —"
    @State private var lastRefresh = Date()

    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        if enabled {
            HStack(spacing: 8) {
                Image(systemName: "thermometer.medium")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(thermalColor)
                Text(thermalText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                Image(systemName: batteryIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(batteryColor)
                Text(batteryText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                Text(netText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
                Divider().frame(height: 12)
                Text("剩 \(memText)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.3), lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
            .offset(offset)
            .gesture(
                DragGesture()
                    .onChanged { offset = $0.translation }
            )
            .onReceive(timer) { _ in refresh() }
            .onAppear { refresh() }
        }
    }

    private func refresh() {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:  thermalText = "正常"; thermalColor = .green
        case .fair:     thermalText = "略高"; thermalColor = .yellow
        case .serious:  thermalText = "偏热"; thermalColor = .orange
        case .critical: thermalText = "过热"; thermalColor = .red
        @unknown default: thermalText = "正常"; thermalColor = .green
        }
        // 电池电量与充电状态
        let dev = UIDevice.current
        dev.isBatteryMonitoringEnabled = true
        let level = dev.batteryLevel
        if level < 0 {
            batteryText = "—"
            batteryIcon = "battery.0percent"
        } else {
            let pct = Int((level * 100).rounded())
            batteryText = "\(pct)%"
            switch pct {
            case 80...100: batteryIcon = "battery.100percent"
            case 60..<80:  batteryIcon = "battery.75percent"
            case 40..<60:  batteryIcon = "battery.50percent"
            case 20..<40:  batteryIcon = "battery.25percent"
            default:       batteryIcon = "battery.0percent"
            }
            if dev.batteryState == .charging {
                batteryIcon = "battery.100percent.bolt"
            }
            batteryColor = pct <= 20 ? .red : .green
        }
        memText = MemoryInfo.bytes(MemoryInfo.availableMemory)
        let now = Date()
        let s = NetworkSpeed.sample(elapsedSeconds: now.timeIntervalSince(lastRefresh))
        lastRefresh = now
        netText = "↓\(NetworkSpeed.bytesPerSec(s.down)) ↑\(NetworkSpeed.bytesPerSec(s.up))"
    }
}
