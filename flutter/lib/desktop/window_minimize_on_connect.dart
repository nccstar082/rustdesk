// flutter/lib/desktop/window_minimize_on_connect.dart
// 注册接收来自 Rust 的全局事件（例如 "on_connected"），在 Windows 平台上最小化主窗口。
// 需要在 pubspec.yaml 中添加 window_manager 依赖：window_manager: ^0.4.0
//
// 说明：本文件不直接绑定仓库中具体的 Rust->Flutter 事件 API（仓库中可能使用 flutter_rust_bridge 的 stream）。
// 请在 main.dart（或应用初始化处）调用 setupMinimizeOnConnect 并把一个注册函数传入，
// 该注册函数负责把回调绑定到实际的事件流（例如 gFFI 或 bridge 中的流订阅函数）。
//
// 例：如果仓库中有 `gFFI.addPushEventListener((String name, dynamic args) { ... })`，
// 可在 main.dart 中把该订阅转发给 setupMinimizeOnConnect。

import 'dart:io' show Platform;
import 'package:window_manager/window_manager.dart';

typedef EventRegister = void Function(void Function(String name, Map<String, dynamic>? args));

Future<void> setupMinimizeOnConnect(EventRegister register) async {
  if (!Platform.isWindows) {
    // 只在 Windows 平台执行最小化动作
    return;
  }

  // 确保 window_manager 初始化（按插件文档）
  await windowManager.ensureInitialized();

  register((String name, Map<String, dynamic>? args) {
    if (name == 'on_connected') {
      // 可根据 args?['conn_type'] 做更细粒度判断
      windowManager.minimize();
    }
  });
}