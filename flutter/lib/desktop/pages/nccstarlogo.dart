// nccstarlogo.dart
import 'package:flutter/material.dart';

// 保持原有的NccstarLogo类不变（如果还需要使用）
class NccstarLogo extends StatelessWidget {
  const NccstarLogo({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Image.network(
      'http://nccstar.top:9494/rustdesk/nccstar.png',
      fit: BoxFit.contain,
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

// 新增：与原_buildNetworkImageContent功能完全一致的实现
Widget buildNccstarLogo() {
  return Image.network(
    'http://nccstar.top:9494/rustdesk/weixin.png',
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

// 新增：与buildNccstarLogo功能相同，但使用原函数名（供connection_page.dart使用）
Widget _buildNetworkImageContent() => buildNccstarLogo();