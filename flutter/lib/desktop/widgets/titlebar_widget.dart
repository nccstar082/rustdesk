import 'package:flutter/material.dart';
// 若项目无flutter_screenutil，后续替换marginSymmetric为Padding即可
import 'package:flutter_screenutil/flutter_screenutil.dart'; 

const sidebarColor = Color(0xFF0C6AF6);
const backgroundStartColor = Color(0xFF0583EA);
const backgroundEndColor = Color(0xFF0697EA);

class DesktopTitleBar extends StatelessWidget {
  final Widget? child;
  final String version;

  const DesktopTitleBar({Key? key, this.child, required this.version}) : super(key: key);

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
          // 核心修改：将软件名称+版本放在最左侧，紧贴图标
          SelectionArea(
            child: Text('RustDesk: $version')
                .marginSymmetric(vertical: 4.0, horizontal: 8.0), // 小边距紧贴图标
          ),
          // 原有child（包含软件图标）填充剩余空间，位置后移
          Expanded(
            child: child ?? Offstage(),
          ),
          // 移除右侧的版本信息（已移到左侧）
        ],
      ),
    );
  }
}