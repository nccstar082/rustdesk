import 'package:flutter/material.dart';

const sidebarColor = Color(0xFF0C6AF6);
const backgroundStartColor = Color(0xFF0583EA);
const backgroundEndColor = Color(0xFF0697EA);

class DesktopTitleBar extends StatelessWidget {
  final Widget? child;

  const DesktopTitleBar({Key? key, this.child}) : super(key: key);

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
        // 左侧自定义文字（添加此行）
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8.0), // 增加左右间距
          child: Text(
            "1.4.4-1111", // 替换为你的文字
            style: TextStyle(
              color: Colors.white, // 文字颜色（与标题栏背景对比）
              fontSize: 14,
            ),
          ),
        ),
        // 原有内容（保持不变）
          Expanded(
            child: child ?? Offstage(),
          )
        ],
      ),
    );
  }
}