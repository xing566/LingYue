import WidgetKit
import SwiftUI
import ControlWidget
import AppIntents

/// 点击控制模块时的动作：通过 URL scheme 打开聆乐 App。
struct OpenLingYue: AppIntent {
    static var title: LocalizedStringResource = "打开聆乐"
    func perform() async throws -> some IntentResult {
        .result()
    }
}

/// 控制中心监控模块：显示当前温度与网速（流量）。
struct LingYueControlWidget: ControlWidget {
    var body: some ControlWidgetConfiguration {
        ControlWidgetButton(action: OpenLingYue()) {
            ControlWidgetLabel(
                icon: "thermometer.medium",
                title: LocalizedStringResource(stringLiteral: monitorText())
            )
        }
        .configurationDisplayName("聆乐监控")
        .description("显示温度与网速（流量）")
    }

    private func monitorText() -> String {
        "\(MetricsReader.thermalText()) · \(MetricsReader.netText())"
    }
}
