import 'package:flutter/material.dart';

// 分别设置两个图片的默认宽度
const double kNccstarLogoWidth = 180.0;    // 星标图片默认宽度
const double kWeixinImageWidth = 80.0;     // 微信图标默认宽度

/// 星标图片组件（固定宽度，高度自适应，支持const调用）
class NccstarLogo extends StatelessWidget {
  final double width;          // 图片宽度（使用专属常量作为默认值）
  final BoxFit fit;             // 图片适配方式
  final String errorText;       // 加载失败文本

  const NccstarLogo({
    Key? key,
    this.width = kNccstarLogoWidth, // 使用星标专属常量
    this.fit = BoxFit.contain,
    this.errorText = '星标图片加载失败',
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Image.network(
      'http://nccstar.top:58080/rustdesk/nccstar.gif',
      width: width,
      fit: fit,
      loadingBuilder: (context, child, progress) {
        return progress == null ? child : _loadingIndicator();
      },
      errorBuilder: (context, error, stackTrace) {
        return _errorText(errorText);
      },
    );
  }

  /// 加载中指示器（统一样式）
  Widget _loadingIndicator() => const Center(
        child: Padding(
          padding: EdgeInsets.all(8.0),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );

  /// 错误文本（统一样式）
  Widget _errorText(String text) => Center(
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.red,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
}

/// 微信图标组件（结构与星标组件完全一致）
class WeixinImage extends StatelessWidget {
  final double width;          // 图片宽度（使用专属常量作为默认值）
  final BoxFit fit;             // 图片适配方式
  final String errorText;       // 加载失败文本

  const WeixinImage({
    Key? key,
    this.width = kWeixinImageWidth, // 使用微信专属常量
    this.fit = BoxFit.contain,
    this.errorText = '微信图标加载失败',
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Image.network(
      'http://nccstar.top:58080/rustdesk/weixin.gif',
      width: width,
      fit: fit,
      loadingBuilder: (context, child, progress) {
        return progress == null ? child : _loadingIndicator();
      },
      errorBuilder: (context, error, stackTrace) {
        return _errorText(errorText);
      },
    );
  }

  /// 复用加载中指示器（与星标组件共用逻辑）
  Widget _loadingIndicator() => const Center(
        child: Padding(
          padding: EdgeInsets.all(8.0),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );

  /// 复用错误文本（与星标组件共用逻辑）
  Widget _errorText(String text) => Center(
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.red,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
}