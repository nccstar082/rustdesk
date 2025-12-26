import 'package:flutter/material.dart';
import 'package:flutter_hbb/models/platform_model.dart';

const sidebarColor = Color(0xFF0C6AF6);
const backgroundStartColor = Color(0xFF0583EA);
const backgroundEndColor = Color(0xFF0697EA);

class DesktopTitleBar extends StatelessWidget {
  final Widget? child;

  const DesktopTitleBar({Key? key, this.child}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [backgroundStartColor, backgroundEndColor],
            stops: [0.0, 1.0]),
      ),
      child: Row(
        children: [
          Expanded(
            child: child ?? FutureBuilder<String>(
              future: bind.mainGetVersion(),
              builder: (context, snapshot) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Text(
                    snapshot.data ?? '',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                );
              },
            ),
          )
        ],
      ),
    );
  }
}