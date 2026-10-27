import WidgetKit
import SwiftUI
import AppIntents

/// 组件外观配置：可编辑的文本颜色。
/// 注意：iOS 的 AppIntents 不支持 `Color` 作为可编辑参数（编译会报
/// `Color` 不遵循 `_IntentValue`），因此用十六进制字符串表示，
/// 长按组件 → 编辑小组件 → 填颜色值（如 #FFFFFF），支持 #RRGGBB。
struct MonitorConfig: AppIntent, WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "外观"
    static var description = IntentDescription("设置监控小组件的文字颜色（#RRGGBB）")

    @Parameter(title: "文字颜色（如 #FFFFFF）")
    var textColorHex: String

    init() { textColorHex = "#FFFFFF" }
    init(textColorHex: String) { self.textColorHex = textColorHex }

    func perform() async throws -> some IntentResult {
        .result()
    }
}

/// 时间线条目：携带配置 + 监控数据。
struct MonitorEntry: TimelineEntry {
    let date: Date
    let configuration: MonitorConfig
    let battery: String
    let charging: Bool
    let thermal: String
    let memoryMB: String
    let net: String
}

struct MonitorProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> MonitorEntry {
        makeEntry(config: MonitorConfig())
    }
    func snapshot(for config: MonitorConfig, in context: Context) async -> MonitorEntry {
        makeEntry(config: config)
    }
    func timeline(for config: MonitorConfig, in context: Context) async -> Timeline<MonitorEntry> {
        let entry = makeEntry(config: config)
        let next = Calendar.current.date(byAdding: .second, value: 30, to: Date())!
        return Timeline(entries: [entry], policy: .after(next))
    }

    private func makeEntry(config: MonitorConfig) -> MonitorEntry {
        let lv = MetricsReader.batteryLevel()
        return MonitorEntry(
            date: Date(),
            configuration: config,
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

    private var c: Color { hexColor(entry.configuration.textColorHex) }

    private func hexColor(_ hex: String) -> Color {
        var h = hex.trimmingCharacters(in: .whitespaces).uppercased()
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt64(h, radix: 16) else { return .white }
        return Color(
            red: Double((v >> 16) & 0xFF) / 255.0,
            green: Double((v >> 8) & 0xFF) / 255.0,
            blue: Double(v & 0xFF) / 255.0
        )
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: gaugeFraction, label: { Text("电") }) {
                Text(entry.battery).foregroundColor(c)
            }
            .gaugeStyle(.accessoryCircular)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Image(systemName: entry.charging ? "battery.100percent.bolt" : "battery.75percent")
                        .foregroundColor(c)
                    Text("\(entry.battery) · \(entry.thermal)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(c)
                }
                Text("内存剩 \(entry.memoryMB) MB")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(c.opacity(0.85))
                Text(entry.net)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(c.opacity(0.85))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        default: // systemSmall 主屏幕/今日
            VStack(spacing: 5) {
                HStack(spacing: 5) {
                    Image(systemName: entry.charging ? "battery.100percent.bolt" : "battery.75percent")
                        .foregroundColor(c)
                    Text(entry.battery)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(c)
                    Spacer()
                    Text(entry.thermal)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(c.opacity(0.8))
                }
                Divider().overlay(c.opacity(0.4))
                HStack {
                    Text("内存剩 \(entry.memoryMB) MB")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(c.opacity(0.85))
                    Spacer()
                }
                HStack {
                    Text(entry.net)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(c.opacity(0.85))
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
        AppIntentConfiguration(
            kind: kind,
            intent: MonitorConfig.self,
            provider: MonitorProvider()
        ) { entry in
            MonitorEntryView(entry: entry)
                .containerBackground(for: .widget) { Color.black.opacity(0.9) }
        }
        .configurationDisplayName("聆乐监控")
        .description("显示电量 / 温度 / 剩余内存 / 网速，可编辑文字颜色")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

@main
struct LingYueWidgetBundle: WidgetBundle {
    var body: some Widget {
        LingYueMonitorWidget()
    }
}
