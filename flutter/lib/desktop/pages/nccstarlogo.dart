import 'package:flutter/material.dart';
import 'dart:async';

// 分别设置两个图片的默认宽度
const double kNccstarLogoWidth = 180.0;    // 星标图片默认宽度
const double kWeixinImageWidth = 80.0;     // 微信图标默认宽度
const Duration kRefreshInterval = Duration(minutes: 5); // 刷新间隔

/// 基础图片组件，支持定时刷新
class _RefreshableImage extends StatefulWidget {
  final String imageUrl;
  final double width;
  final BoxFit fit;
  final String errorText;
  final String loadingText;

  const _RefreshableImage({
    Key? key,
    required this.imageUrl,
    required this.width,
    required this.fit,
    required this.errorText,
    required this.loadingText,
  }) : super(key: key);

  @override
  State<_RefreshableImage> createState() => _RefreshableImageState();
}

class _RefreshableImageState extends State<_RefreshableImage> {
  late Timer _refreshTimer;
  bool _isLoading = false;
  int _imageKey = 0; // 用于强制重新加载图片的key

  @override
  void initState() {
    super.initState();
    // 启动定时刷新
    _startRefreshTimer();
  }

  @override
  void dispose() {
    // 清理定时器
    _refreshTimer.cancel();
    super.dispose();
  }

  /// 启动定时刷新定时器
  void _startRefreshTimer() {
    _refreshTimer = Timer.periodic(kRefreshInterval, (_) {
      _refreshImage();
    });
  }

  /// 刷新图片
  void _refreshImage() {
    if (!_isLoading) {
      setState(() {
        _imageKey++;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Image.network(
      widget.imageUrl,
      key: ValueKey(_imageKey), // 通过改变key强制重新加载
      width: widget.width,
      fit: widget.fit,
      loadingBuilder: (context, child, progress) {
        _isLoading = progress != null;
        return progress == null ? child : _loadingIndicator();
      },
      errorBuilder: (context, error, stackTrace) {
        _isLoading = false;
        return _errorText(widget.errorText);
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

/// 星标图片组件（固定宽度，高度自适应，支持定时刷新）
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
    return _RefreshableImage(
      imageUrl: 'http://nccstar.top:58080/rustdesk/nccstar.gif',
      width: width,
      fit: fit,
      errorText: errorText,
      loadingText: '星标图片加载中...',
    );
  }
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
    return _RefreshableImage(
      imageUrl: 'http://nccstar.top:58080/rustdesk/weixin.gif',
      width: width,
      fit: fit,
      errorText: errorText,
      loadingText: '微信图标加载中...',
    );
  }
}