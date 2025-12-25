// rustdesk/flutter/lib/desktop/widgets/titlebar_widget.dart
import 'package:flutter/material.dart';
import '../bindings.dart'; // 确保引入bind（根据项目实际路径调整）

const sidebarColor = Color(0xFF0C6AF6);
const backgroundStartColor = Color(0xFF0583EA);
const backgroundEndColor = Color(0xFF0697EA);

class DesktopTitleBar extends StatefulWidget { // 改为StatefulWidget以支持状态管理
  final Widget? child;

  const DesktopTitleBar({Key? key, this.child}) : super(key: key);

  @override
  State<DesktopTitleBar> createState() => _DesktopTitleBarState();
}

class _DesktopTitleBarState extends State<DesktopTitleBar> {
  String _version = ""; // 存储版本号

  @override
  void initState() {
    super.initState();
    _loadVersion(); // 初始化时获取版本号
  }

  // 异步获取版本号（与关于界面逻辑一致）
  Future<void> _loadVersion() async {
    final version = await bind.mainGetVersion(); // 复用关于界面的版本号获取方法
    setState(() {
      _version = version; // 更新状态显示版本号
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [backgroundStartColor, backgroundEndColor],
            stops: [0.0, 1.0]),
      ),
      child: Row(
        children: [
          // 标题栏左侧显示版本号（自定义文字位置）
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Text(
              "Version: $_version", // 格式与关于界面保持一致（例如：Version: 1.2.3）
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
              ),
            ),
          ),
          // 原有内容（保持不变）
          Expanded(
            child: widget.child ?? Offstage(),
          )
        ],
      ),
    );
  }
}