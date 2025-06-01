import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';
import 'package:window_manager/window_manager.dart';

enum TrayIconVisibility {
  visible,
  hidden,
}

class TrayIconController extends GetxController with WindowListener {
  static TrayIconController get to => Get.find();
  
  // 托盘图标可见性状态
  final Rx<TrayIconVisibility> _visibility = TrayIconVisibility.visible.obs;
  TrayIconVisibility get visibility => _visibility.value;
  
  // 控制托盘图标显示的设置项
  final RxBool _showTrayIcon = true.obs;
  bool get showTrayIcon => _showTrayIcon.value;
  
  // 单例模式
  static final TrayIconController _instance = TrayIconController._internal();
  factory TrayIconController() => _instance;
  TrayIconController._internal();
  
  @override
  void onInit() {
    super.onInit();
    windowManager.addListener(this);
    _initTrayIcon();
  }
  
  @override
  void onClose() {
    windowManager.removeListener(this);
    super.onClose();
  }
  
  // 初始化托盘图标设置
  Future<void> _initTrayIcon() async {
    // 从配置中加载托盘图标设置
    _showTrayIcon.value = await _loadTrayIconSetting();
    
    // 应用初始设置
    await _updateTrayIconVisibility();
  }
  
  // 从配置或本地存储加载托盘图标设置
  Future<bool> _loadTrayIconSetting() async {
    // 实际应用中应从配置文件或本地存储读取
    // 这里使用示例代码
    try {
      final setting = await bind.mainGetBoolOption('show-tray-icon');
      return setting ?? true; // 默认显示托盘图标
    } catch (e) {
      print("Failed to load tray icon setting: $e");
      return true;
    }
  }
  
  // 保存托盘图标设置
  Future<void> _saveTrayIconSetting(bool value) async {
    try {
      await bind.mainSetBoolOption('show-tray-icon', value);
    } catch (e) {
      print("Failed to save tray icon setting: $e");
    }
  }
  
  // 更新托盘图标可见性
  Future<void> _updateTrayIconVisibility() async {
    try {
      if (_showTrayIcon.value) {
        // 显示托盘图标
        await bind.mainShowTrayIcon();
        _visibility.value = TrayIconVisibility.visible;
      } else {
        // 隐藏托盘图标
        await bind.mainHideTrayIcon();
        _visibility.value = TrayIconVisibility.hidden;
      }
    } catch (e) {
      print("Failed to update tray icon visibility: $e");
    }
  }
  
  // 切换托盘图标显示状态
  Future<void> toggleTrayIconVisibility() async {
    _showTrayIcon.value = !_showTrayIcon.value;
    await _saveTrayIconSetting(_showTrayIcon.value);
    await _updateTrayIconVisibility();
    update(); // 通知所有观察者状态已更新
  }
  
  // 显示托盘图标
  Future<void> showTrayIcon() async {
    if (!_showTrayIcon.value) {
      _showTrayIcon.value = true;
      await _saveTrayIconSetting(true);
      await _updateTrayIconVisibility();
      update();
    }
  }
  
  // 隐藏托盘图标
  Future<void> hideTrayIcon() async {
    if (_showTrayIcon.value) {
      _showTrayIcon.value = false;
      await _saveTrayIconSetting(false);
      await _updateTrayIconVisibility();
      update();
    }
  }
  
  // 窗口状态变化监听
  @override
  void onWindowMinimize() async {
    // 窗口最小化时，可以选择是否自动隐藏托盘图标
    // 这里使用配置来决定行为
    if (await _shouldHideOnMinimize()) {
      await hideTrayIcon();
    }
  }
  
  @override
  void onWindowRestore() async {
    // 窗口恢复时，可以选择是否自动显示托盘图标
    if (visibility == TrayIconVisibility.hidden) {
      await showTrayIcon();
    }
  }
  
  // 判断窗口最小化时是否应该隐藏托盘图标
  Future<bool> _shouldHideOnMinimize() async {
    try {
      return await bind.mainGetBoolOption('hide-tray-on-minimize') ?? false;
    } catch (e) {
      return false;
    }
  }
}

// 托盘图标控制按钮组件
class TrayIconControlButton extends StatelessWidget {
  final IconData? icon;
  final String? tooltip;
  final double? size;
  
  const TrayIconControlButton({
    Key? key,
    this.icon = Icons.desktop_windows,
    this.tooltip = 'Toggle Tray Icon',
    this.size = 24,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final controller = TrayIconController.to;
      final isVisible = controller.visibility == TrayIconVisibility.visible;
      
      return Tooltip(
        message: tooltip ?? (isVisible ? 'Hide Tray Icon' : 'Show Tray Icon'),
        child: IconButton(
          icon: Icon(icon),
          color: isVisible ? Colors.green : Colors.grey,
          iconSize: size,
          onPressed: () async {
            await controller.toggleTrayIconVisibility();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  isVisible ? 'Tray icon hidden' : 'Tray icon shown',
                ),
                duration: Duration(seconds: 1),
              ),
            );
          },
        ),
      );
    });
  }
}

// 托盘图标状态指示器
class TrayIconStatusIndicator extends StatelessWidget {
  final double? size;
  
  const TrayIconStatusIndicator({
    Key? key,
    this.size = 16,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final controller = TrayIconController.to;
      final isVisible = controller.visibility == TrayIconVisibility.visible;
      
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isVisible ? Colors.green : Colors.grey,
        ),
      );
    });
  }
}  