import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../framework/components/net_status_widget/base_net_status_widget.dart';

class NetNotNetStatusWidget extends StatefulWidget {
  /// 网络未连接
  const NetNotNetStatusWidget(
      {super.key,
      required this.onRetry,
      this.boundingColor,
      this.backgroundColor});

  final Function()? onRetry;
  final Color? boundingColor;
  final Color? backgroundColor;
  @override
  State<NetNotNetStatusWidget> createState() => _NetNotNetStatusWidget();
}

class _NetNotNetStatusWidget extends State<NetNotNetStatusWidget> {
  @override
  Widget build(BuildContext context) {
    return BaseNetStatusWidget(
      imageType: BaseNetStatusImageType.noNetwork,
      message: '网络异常，请检查你的网络'.tr,
      showRetryButton: true,
      onRetry: widget.onRetry,
      boundingColor: widget.boundingColor,
      backgroundColor: widget.backgroundColor,
    );
  }
}
