import 'package:flutter/material.dart';

/// 遥控的方向键提示
/// 哪个方向为true时，则闪烁提示
class DirectionWidget extends StatefulWidget {
  const DirectionWidget({
    super.key,
    this.hotLeft = false,
    this.hotRight = false,
    this.hotUp = false,
    this.hotDown = false,
    this.hotOk = false,
  });
  final bool hotLeft;
  final bool hotRight;
  final bool hotUp;
  final bool hotDown;
  final bool hotOk;

  @override
  State<StatefulWidget> createState() => _DirectionWidget();
}

class _DirectionWidget extends State<StatefulWidget> {
  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
