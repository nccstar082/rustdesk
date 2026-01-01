// flutter/lib/desktop/window_minimize_on_connect.dart
// 注册接收来自 Rust 的全局事件（例如 "on_connected"），在 Windows 平台上最小化主窗口。
// 需要在 pubspec.yaml 中添加 window_manager 依赖：window_manager: ^0.4.0（或最新版本）

import 'dart:convert';
import 'dart:io' show Platform;
import 'package:window_manager/window_manager.dart';

/// 将 Rust -> Flutter 的事件流订阅转发给这个函数即可。
/// 参数 streamProvider: 返回一个 Stream<String> 的函数（每条消息通常是 JSON 字符串，含 name 字段）
/// 或者直接传入 Stream<String>。
///
/// 例：setupMinimizeOnConnect(() => gFFI.globalEventStream);
Future<void> setupMinimizeOnConnect(Stream<String> Function() streamProvider,
    {bool requireDefaultConnOnly = true,
    bool useLocalOptionCheck = true,
    String localOptionKey = 'minimize_on_connect'}) async {
  if (!Platform.isWindows) {
    // 只在 Windows 平台执行最小化动作
    return;
  }

  // 确保 window_manager 初始化
  await windowManager.ensureInitialized();

  final Stream<String> stream = streamProvider();

  stream.listen((String raw) {
    try {
      final m = jsonDecode(raw);
      final name = m['name'] as String?;
      if (name != 'on_connected') return;

      final connType = (m['conn_type'] as String?) ?? 'default';

      if (requireDefaultConnOnly && connType != 'default') {
        // 如果只在普通会话时最小化（可调整）
        return;
      }

      // 可选：检查本地设置（示例：仓库中通常有 bind.mainGetLocalOption）
      if (useLocalOptionCheck) {
        try {
          // 下面示例依赖于项目中有一个同步方法读取 local option，例如：
          // bind.mainGetLocalOption(key: localOptionKey)
          // 请在项目中替换为实际读取本地配置的 API；若没有则可跳过这段。
          //
          // final enabledStr = bind.mainGetLocalOption(key: localOptionKey);
          // if (enabledStr != '1' && enabledStr != 'true') return;
        } catch (e) {
          // 读取 local option 失败时继续（默认开启）
        }
      }

      // 触发最小化
      windowManager.minimize();
    } catch (e) {
      // 解析错误忽略
    }
  }, onError: (_) {
    // ignore
  });
}