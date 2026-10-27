import WidgetKit
import SwiftUI
import AppIntents

/// 点击控制模块时的动作：通过 URL scheme 打开聆乐 App。
@available(iOS 18.0, *)
struct OpenLingYue: AppIntent {
    static var title: LocalizedStringResource = "打开聆乐"
    func perform() async throws -> some IntentResult {
        .result()
    }
}

/// 控制中心监控模块：显示当前温度与网速（流量）。iOS 18+。
@available(iOS 18.0, *)
struct LingYueControlWidget: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "LingYueControl") {
            ControlWidgetButton(action: OpenLingYue()) {
                Label(monitorText(), systemImage: "thermometer.medium")
            }
        }
        .displayName("聆乐监控")
        .description("显示温度与网速（流量）")
    }

    private func monitorText() -> String {
        "\(MetricsReader.thermalText()) · \(MetricsReader.netText())"
    }
}
