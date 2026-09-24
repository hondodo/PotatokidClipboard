import 'package:flutter/material.dart';

class NetLoadingStatusWidget extends StatefulWidget {
  /// 加载中
  const NetLoadingStatusWidget({super.key});

  @override
  State<NetLoadingStatusWidget> createState() => _NetLoadingStatusWidget();
}

class _NetLoadingStatusWidget extends State<NetLoadingStatusWidget> {
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(),
    );
  }
}
