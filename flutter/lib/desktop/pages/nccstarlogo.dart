// nccstarlogo.dart
import 'package:flutter/material.dart';

class NccstarLogo extends StatelessWidget {
  /// 网络图片加载组件
  /// 支持加载状态和错误处理
  const NccstarLogo({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Image.network(
      'http://nccstar.top:9494/rustdesk/nccstar.png',
      fit: BoxFit.contain, // 保持图片原始比例
      alignment: Alignment.center,
      loadingBuilder: (context, child, progress) {
        if (progress != null) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(),
            ),
          );
        }
        return child;
      },
      errorBuilder: (context, error, stackTrace) {
        return Center(
          child: Container(
            padding: EdgeInsets.all(16.0),
            child: Text(
              '亿芯电子 远程服务客户端 图片加载失败',
              style: TextStyle(
                color: Colors.red,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        );
      },
    );
  }
}

 Widget _buildNetworkImageContent() {
    return Image.network(
      'http://nccstar.top:9494/rustdesk/nccstar.png', // 示例图片地址
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) {
        return progress == null 
            ? child 
            : const Center(child: CircularProgressIndicator());
      },
      errorBuilder: (context, error, stackTrace) {
        return const Center(child: Icon(Icons.error_outline, color: Colors.red));
      },
    );
  }