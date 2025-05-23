import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/global_ffi.dart'; // 假设全局对象定义在此
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:flutter_hbb/models/chat_model.dart'; // 确保继承ChangeNotifier
import 'package:flutter_hbb/models/cm_file_model.dart';
import 'package:flutter_hbb/utils/platform_channel.dart';
import 'package:get/get.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart' as wm;
import 'package:flutter_svg/flutter_svg.dart';

import '../../common.dart' as common;

class DesktopServerPage extends StatefulWidget {
  final bool hideWindow;
  const DesktopServerPage({Key? key, this.hideWindow = true}) : super(key: key);

  @override
  State<DesktopServerPage> createState() => _DesktopServerPageState();
}

class _DesktopServerPageState extends State<DesktopServerPage>
    with AutomaticKeepAliveClientMixin, wm.WindowListenerInterface {
  final gFFI = GlobalFFI.instance; // 假设全局单例对象
  final tabController = gFFI.serverModel.tabController;

  @override
  void initState() {
    wm.WindowManager.instance.addListener(this);
    if (widget.hideWindow) {
      _initBackgroundWindow();
    }
    super.initState();
  }

  @override
  void onWindowReady() {} // 实现WindowListenerInterface接口

  Future<void> _initBackgroundWindow() async {
    await wm.WindowManager.instance.ensureInitialized();
    
    if (Platform.isWindows) {
      await wm.WindowManager.instance.setSkipTaskbar(true); // 隐藏任务栏图标
    }
    
    await wm.WindowManager.instance.setDecorated(false); // 无边框
    await wm.WindowManager.instance.setOpacity(0.0); // 透明
    await wm.WindowManager.instance.hide(); // 隐藏窗口
    await wm.WindowManager.instance.setResizable(false); // 禁止调整大小
  }

  @override
  void dispose() {
    wm.WindowManager.instance.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() {
    if (!widget.hideWindow) {
      Future.wait([
        gFFI.serverModel.closeAll(),
        gFFI.close(),
      ]).then((_) {
        if (Platform.isMacOS) {
          RdPlatformChannel.instance.terminate();
        } else {
          wm.WindowManager.instance.close();
        }
      });
    }
    super.onWindowClose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.hideWindow) return Container(color: Colors.transparent);
    
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<ServerModel>.value(value: gFFI.serverModel),
        ChangeNotifierProvider<ChatModel>.value(value: gFFI.chatModel),
      ],
      child: Consumer<ServerModel>(
        builder: (context, serverModel, child) {
          final body = Scaffold(
            backgroundColor: Theme.of(context).colorScheme.background,
            body: ConnectionManager(hideCM: widget.hideWindow),
          );
          
          return common.buildVirtualWindowFrame(context, body);
        },
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}

class ConnectionManager extends StatefulWidget {
  final bool hideCM;
  const ConnectionManager({Key? key, this.hideCM = true}) : super(key: key);

  @override
  State<StatefulWidget> createState() => ConnectionManagerState();
}

class ConnectionManagerState extends State<ConnectionManager> {
  final RxBool _controlPageBlock = false.obs;
  final RxBool _sidePageBlock = false.obs;

  @override
  void initState() {
    gFFI.serverModel.tabController.onSelected = (client_id_str) {
      final client_id = int.tryParse(client_id_str);
      if (client_id != null) {
        final client = gFFI.serverModel.clients.firstWhereOrNull((e) => e.id == client_id);
        if (client != null) {
          gFFI.chatModel.changeCurrentKey(MessageKey(client.peerId, client.id));
          if (client.unreadChatMessageCount.value > 0) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              client.unreadChatMessageCount.value = 0;
              gFFI.chatModel.showChatPage(MessageKey(client.peerId, client.id));
            });
          }
          wm.WindowManager.instance.setTitle(getWindowNameWithId(client.peerId));
          gFFI.cmFileModel.updateCurrentClientId(client.id);
        }
      }
    };
    gFFI.chatModel.isConnManager = true;
    super.initState();
  }

  String getWindowNameWithId(String peerId) {
    return "远程连接 - $peerId"; // 示例实现，需根据实际逻辑修改
  }

  @override
  Widget build(BuildContext context) {
    if (widget.hideCM) return Offstage();
    
    final serverModel = Provider.of<ServerModel>(context);
    
    void pointerHandler(PointerEvent e) {
      if (serverModel.cmHiddenTimer != null) {
        serverModel.cmHiddenTimer!.cancel();
        serverModel.cmHiddenTimer = null;
      }
    }

    return serverModel.clients.isEmpty
        ? Offstage()
        : Listener(
            onPointerDown: pointerHandler,
            onPointerMove: pointerHandler,
            child: DesktopTab(
              showTitle: false,
              showMinimize: true,
              showClose: true,
              onWindowCloseButton: () => handleWindowCloseButton(),
              controller: serverModel.tabController,
              selectedBorderColor: MyTheme.accent, // 假设MyTheme存在
              maxLabelWidth: 100,
              tabBuilder: (key, icon, label, themeConf) {
                final client = serverModel.clients.firstWhereOrNull((c) => c.id.toString() == key);
                return client == null ? Offstage() : Row(
                  children: [
                    Tooltip(message: key, child: label),
                    unreadMessageCountBuilder(client.unreadChatMessageCount),
                  ],
                );
              },
              pageViewBuilder: (pageView) => LayoutBuilder(
                builder: (context, constraints) {
                  if (widget.hideCM) return Offstage();
                  
                  final realClosedWidth = constraints.maxWidth > kConnectionManagerWindowSizeClosedChat.width
                      ? kConnectionManagerWindowSizeOpenChat.width - (constraints.maxWidth - kConnectionManagerWindowSizeClosedChat.width)
                      : kConnectionManagerWindowSizeClosedChat.width;
                  
                  return Row(
                    children: [
                      if (constraints.maxWidth > kConnectionManagerWindowSizeClosedChat.width)
                        Consumer<ChatModel>(
                          builder: (_, model, child) => SizedBox(
                            width: constraints.maxWidth - realClosedWidth,
                            child: buildSidePage(),
                          ),
                        ),
                      SizedBox(width: realClosedWidth, child: pageView),
                    ],
                  );
                },
              ),
            ),
          );
  }

  Widget buildSidePage() {
    final selected = gFFI.serverModel.tabController.state.value.selected;
    if (selected < 0 || selected >= gFFI.serverModel.clients.length) return Offstage();
    
    final clientType = gFFI.serverModel.clients[selected].type_();
    return clientType == ClientType.file
        ? _FileTransferLogPage(hideFileLog: true)
        : ChatPage(type: ChatPageType.desktopCM);
  }

  Future<bool> handleWindowCloseButton() async {
    return widget.hideCM;
  }
}

// 其他组件（略），需确保继承和方法实现正确

class _FileTransferLogPage extends StatefulWidget {
  final bool hideFileLog;
  const _FileTransferLogPage({Key? key, this.hideFileLog = true}) : super(key: key);

  @override
  State<_FileTransferLogPage> createState() => __FileTransferLogPageState();
}

class __FileTransferLogPageState extends State<_FileTransferLogPage> {
  @override
  Widget build(BuildContext context) {
    if (widget.hideFileLog) return Offstage();
    return ListView(children: [Text("文件传输日志")]);
  }
}
