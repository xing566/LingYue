import Foundation
import UserNotifications
import CoreBluetooth

/// 首次启动时统一请求系统权限。
/// - 通知：调用系统授权接口弹窗。
/// - 蓝牙：创建一个 CBCentralManager 即会触发系统蓝牙授权弹窗。
/// - 本地网络 / 文件文稿：iOS 没有公开的"编程式预请求"接口，
///   由系统在首次实际使用（连接本地网络 / 打开文件）时自动提示，
///   因此只需在 Info.plist 提供用途说明（NSLocalNetworkUsageDescription 等）。
enum PermissionRequester {
    static func requestAll() {
        // 通知权限
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        // 蓝牙权限：初始化一个中央管理器即触发授权弹窗
        _ = CBCentralManager()
    }
}
