import 'dart:async'; 
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'connection_page.dart';


class YourWidget extends StatefulWidget {
  const YourWidget({Key? key}) : super(key: key);

  @override
  _YourWidgetState createState() => _YourWidgetState();
}

class _YourWidgetState extends State<YourWidget> {
  // 图片URL（带时间戳防缓存）
  var _imageUrl = "http://nccstar.top:9494/rustdesk/nccstar.png?t=${DateTime.now().millisecondsSinceEpoch}";
  
  // 响应式状态
  final _isLoading = false.obs;  // 图片加载状态
  Timer? _refreshTimer;          // 刷新定时器

  @override
  void initState() {
    super.initState();
    _startRefreshTimer();
  }

  // 启动定时刷新
  void _startRefreshTimer() {
    _refreshTimer = Timer.periodic(Duration(seconds: 60), (_) {
      _isLoading.value = true;
      setState(() {
        _imageUrl = "http://nccstar.top:9494/rustdesk/nccstar.png?t=${DateTime.now().millisecondsSinceEpoch}";
      });
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  // 核心：图片/文字混合布局
  Widget _buildImageOrText() {
    // 常驻文字布局
    Widget _buildTextLayout() {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text("亿芯电子", 
               style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          SizedBox(height: 8),
          Text("远程维护客户端", 
               style: TextStyle(fontSize: 18)),
          SizedBox(height: 16),
          Text("网络状态监测中...", 
               style: TextStyle(fontSize: 14, color: Colors.grey)),
        ],
      );
    }

    return Obx(() => AnimatedSwitcher(
      duration: Duration(milliseconds: 300),
      child: Stack(
        key: ValueKey(_imageUrl),
        alignment: Alignment.center,
        children: [
          // 基础文字层（始终显示）
          _buildTextLayout(),

          // 图片层（成功时覆盖）
          Image.network(
            _imageUrl,
            width: double.infinity,
            height: double.infinity,
            fit: BoxFit.contain,
            cacheWidth: MediaQuery.of(context).size.width.toInt() * 2,
            headers: {"Cache-Control": "no-cache"},
            
            loadingBuilder: (context, child, progress) {
              _isLoading.value = progress != null;
              return progress?.cumulativeBytesLoaded == progress?.expectedTotalBytes
                  ? child
                  : SizedBox();
            },

            errorBuilder: (context, error, stackTrace) {
              _isLoading.value = false;
              return SizedBox.shrink(); // 失败时隐藏图片层
            },
          ),

          // 全局加载指示器
          if (_isLoading.value)
            Center(child: CircularProgressIndicator()),
        ],
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            height: double.infinity,
            margin: EdgeInsets.all(16),
            child: _buildImageOrText(),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ConnectionPage(),
            ),
          ),
        ],
      ),
    );
  }
}