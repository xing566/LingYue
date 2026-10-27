import WidgetKit
import SwiftUI

/// 聆乐监控小组件：显示电量 / 温度 / 剩余内存 / 网速。
/// 支持锁屏（圆形、矩形）与主屏幕/今日（小号）三种形态。
struct MonitorEntry: TimelineEntry {
    let date: Date
    let battery: String        // 纯数字电量
    let charging: Bool
    let thermal: String
    let memoryMB: String
    let net: String
}

struct MonitorProvider: TimelineProvider {
    func placeholder(in context: Context) -> MonitorEntry { makeEntry() }
    func getSnapshot(in context: Context, completion: @escaping (MonitorEntry) -> Void) {
        completion(makeEntry())
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<MonitorEntry>) -> Void) {
        let entry = makeEntry()
        let next = Calendar.current.date(byAdding: .second, value: 30, to: Date())!
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func makeEntry() -> MonitorEntry {
        let lv = MetricsReader.batteryLevel()
        return MonitorEntry(
            date: Date(),
            battery: lv.map { "\($0)" } ?? "—",
            charging: MetricsReader.isCharging(),
            thermal: MetricsReader.thermalText(),
            memoryMB: MetricsReader.availableMemoryMB(),
            net: MetricsReader.netText()
        )
    }
}

struct MonitorEntryView: View {
    var entry: MonitorEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: gaugeFraction, label: { Text("电") }) {
                Text(entry.battery)
            }
            .gaugeStyle(.accessoryCircular)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: entry.charging ? "battery.100percent.bolt" : "battery.75percent")
                    Text("\(entry.battery) · \(entry.thermal)")
                        .font(.system(size: 12, weight: .semibold))
                }
                Text("内存剩 \(entry.memoryMB) MB")
                    .font(.system(size: 11, weight: .medium))
                Text(entry.net)
                    .font(.system(size: 10, weight: .medium))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default: // systemSmall 主屏幕/今日
            VStack(spacing: 5) {
                HStack(spacing: 5) {
                    Image(systemName: entry.charging ? "battery.100percent.bolt" : "battery.75percent")
                        .foregroundColor(.green)
                    Text(entry.battery)
                        .font(.system(size: 16, weight: .bold))
                    Spacer()
                    Text(entry.thermal)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                Divider()
                HStack {
                    Text("内存剩 \(entry.memoryMB) MB")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                HStack {
                    Text(entry.net)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            .padding(8)
        }
    }

    private var gaugeFraction: Double {
        let v = Double(entry.battery) ?? 0
        return min(max(v / 100.0, 0), 1)
    }
}

struct LingYueMonitorWidget: Widget {
    let kind = "LingYueMonitor"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MonitorProvider()) { entry in
            MonitorEntryView(entry: entry)
                .containerBackground(for: .widget) { Color.black.opacity(0.9) }
        }
        .configurationDisplayName("聆乐监控")
        .description("显示电量 / 温度 / 剩余内存 / 网速")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

@main
struct LingYueWidgetBundle: WidgetBundle {
    var body: some Widget {
        LingYueMonitorWidget()
    }
}
