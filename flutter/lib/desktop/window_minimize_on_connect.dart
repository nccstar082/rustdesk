import 'dart:io';
import 'package:window_manager/window_manager.dart';

/// 窗口最小化逻辑封装
class WindowMinimizeOnConnect {
  /// 初始化窗口最小化功能
  /// 在应用启动时调用一次即可
  static Future<void> initialize() async {
    // 确保window_manager已初始化
    await windowManager.ensureInitialized();
  }

  /// 处理连接成功事件并最小化窗口
  /// 仅在Windows平台执行最小化操作
  static Future<void> handleConnectedEvent() async {
    if (Platform.isWindows) {
      await windowManager.minimize();
    }
  }
}