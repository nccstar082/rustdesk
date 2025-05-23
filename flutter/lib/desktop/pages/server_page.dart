import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:flutter_hbb/models/chat_model.dart';
import 'package:flutter_hbb/models/cm_file_model.dart';
import 'package:flutter_hbb/models/server_model.dart'; // 新增导入
import 'package:flutter_hbb/utils/platform_channel.dart';
import 'package:get/get.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../common.dart';
import '../../models/global.dart'; // 假设gFFI在此定义

class DesktopServerPage extends StatefulWidget {
  final bool hideWindow;
  const DesktopServerPage({Key? key, this.hideWindow = true}) : super(key: key);

  @override
  State<DesktopServerPage> createState() => _DesktopServerPageState();
}

class _DesktopServerPageState extends State<DesktopServerPage>
    with AutomaticKeepAliveClientMixin {
  final tabController = gFFI.serverModel.tabController;

  @override
  void initState() {
    windowManager.addListener(this);
    if (widget.hideWindow) {
      _initBackgroundWindow();
    }
    super.initState();
  }

  Future<void> _initBackgroundWindow() async {
    await windowManager.ensureInitialized();
    
    if (Platform.isWindows) {
      await windowManager.setSkipTaskbar(true);
    }
    
    await windowManager.setOpacity(0.0);
    await windowManager.setAsFrameless();
    await windowManager.hide();
    await windowManager.setResizable(false);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() async {
    if (!widget.hideWindow) {
      await gFFI.serverModel.closeAll();
      await gFFI.close();
      
      if (Platform.isMacOS) {
        RdPlatformChannel.instance.terminate();
      } else {
        await windowManager.setPreventClose(false);
        windowManager.close();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.hideWindow) {
      return Container(color: Colors.transparent);
    }
    
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: gFFI.serverModel),
        ChangeNotifierProvider.value(value: gFFI.chatModel),
      ],
      child: Consumer<ServerModel>(
        builder: (context, serverModel, child) {
          final body = Scaffold(
            backgroundColor: Theme.of(context).colorScheme.background,
            body: ConnectionManager(hideCM: widget.hideWindow),
          );
          
          return isLinux
              ? buildVirtualWindowFrame(context, body)
              : workaroundWindowBorder(context, body);
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

class ConnectionManagerState extends State<ConnectionManager>
    with WidgetsBindingObserver {
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
          windowManager.setTitle(getWindowNameWithId(client.peerId));
          gFFI.cmFileModel.updateCurrentClientId(client.id);
        }
      }
    };
    gFFI.chatModel.isConnManager = true;
    super.initState();
  }

  String getWindowNameWithId(String peerId) {
    return "RustDesk - $peerId";
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
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
              showMaximize: false,
              showMinimize: true,
              showClose: true,
              onWindowCloseButton: handleWindowCloseButton,
              controller: serverModel.tabController,
              selectedBorderColor: MyTheme.accent,
              maxLabelWidth: 100,
              tail: null,
              tabBuilder: (key, icon, label, themeConf) {
                final client = serverModel.clients.firstWhereOrNull((c) => c.id.toString() == key);
                return client == null
                    ? Offstage()
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Tooltip(
                            message: key,
                            waitDuration: Duration(seconds: 1),
                            child: label,
                          ),
                          unreadMessageCountBuilder(client.unreadChatMessageCount)
                              .marginOnly(left: 4),
                        ],
                      );
              },
              pageViewBuilder: (pageView) => LayoutBuilder(
                builder: (context, constraints) {
                  if (widget.hideCM) return Offstage();
                  
                  var borderWidth = 0.0;
                  if (constraints.maxWidth > kConnectionManagerWindowSizeClosedChat.width) {
                    borderWidth = kConnectionManagerWindowSizeOpenChat.width - constraints.maxWidth;
                  } else {
                    borderWidth = kConnectionManagerWindowSizeClosedChat.width - constraints.maxWidth;
                  }
                  if (borderWidth < 0 || borderWidth > 50) {
                    borderWidth = 0;
                  }
                  
                  final realClosedWidth = kConnectionManagerWindowSizeClosedChat.width - borderWidth;
                  final realChatPageWidth = constraints.maxWidth - realClosedWidth;
                  
                  return Container(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    child: Row(children: [
                      if (constraints.maxWidth > kConnectionManagerWindowSizeClosedChat.width)
                        Consumer<ChatModel>(
                          builder: (_, model, child) => SizedBox(
                            width: realChatPageWidth,
                            child: buildSidePage(),
                          ),
                        ),
                      SizedBox(
                        width: realClosedWidth,
                        child: pageView,
                      ),
                    ]),
                  );
                },
              ),
            ),
          );
  }

  Widget buildSidePage() {
    final selected = gFFI.serverModel.tabController.state.value.selected;
    if (selected < 0 || selected >= gFFI.serverModel.clients.length) {
      return Offstage();
    }
    
    final client = gFFI.serverModel.clients[selected];
    final clientType = client.type_();
    
    return clientType == ClientType.file
        ? _FileTransferLogPage(hideFileLog: true)
        : ChatPage(type: ChatPageType.desktopCM);
  }

  Future<bool> handleWindowCloseButton() async {
    return widget.hideCM;
  }
}

// 其他组件和工具方法
Widget unreadMessageCountBuilder(RxInt? count) {
  return count == null || count.value == 0
      ? Container()
      : Container(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: Colors.red,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            count.value.toString(),
            style: TextStyle(color: Colors.white, fontSize: 10),
          ),
        );
}

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
    
    return ListView(
      children: [
        Text("文件传输日志"),
      ],
    );
  }
}
