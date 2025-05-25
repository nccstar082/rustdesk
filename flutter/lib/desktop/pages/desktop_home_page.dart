import 'dart:async';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cached_network_image/cached_network_image.dart';

class RightPane extends StatefulWidget {
  @override
  _RightPaneState createState() => _RightPaneState();
}

class _RightPaneState extends State<RightPane> {
  final _baseImageUrl = "http://nccstar.top:9494/rustdesk/nccstar.png";
  final imageUrl = "".obs;
  final showImage = false.obs;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _updateImage();
    _startTimer();
  }

  void _updateImage() {
    imageUrl.value = "$_baseImageUrl?t=${DateTime.now().millisecondsSinceEpoch}";
    showImage.value = false; // 重置显示状态
  }

  void _startTimer() {
    _refreshTimer = Timer.periodic(Duration(seconds: 60), (_) => _updateImage());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Widget _buildText() => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Text("亿芯电子", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      SizedBox(height: 8),
      Text("远程维护客户端", style: TextStyle(fontSize: 18)),
      SizedBox(height: 16),
      Obx(() => Text(showImage.isTrue ? "" : "网络可能出现异常，请等待....",
        style: TextStyle(fontSize: 14))),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          Expanded(
            child: Container(
              margin: EdgeInsets.all(16),
              child: Obx(() => Stack(
                alignment: Alignment.center,
                children: [
                  _buildText(),
                  if (showImage.isTrue)
                    CachedNetworkImage(
                      imageUrl: imageUrl.value,
                      fit: BoxFit.contain,
                      placeholder: (_, __) => CircularProgressIndicator(),
                      errorWidget: (_, __, ___) {
                        showImage.value = false;
                        return SizedBox.shrink();
                      },
                      imageBuilder: (_, imageProvider) {
                        showImage.value = true;
                        return Image(image: imageProvider);
                      },
                    ),
                ],
              )),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: ConnectionPage(),
          ),
        ],
      ),
    );
  }
}