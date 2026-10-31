import '../../../framework/components/net_status_widget/base_net_status_widget.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// 用户取消时
class NetCancelledStatusWidget extends StatefulWidget {
  /// 用户取消时
  const NetCancelledStatusWidget(
      {super.key,
      required this.onRetry,
      this.boundingColor,
      this.backgroundColor});

  final Function()? onRetry;
  final Color? boundingColor;
  final Color? backgroundColor;

  @override
  State<NetCancelledStatusWidget> createState() => _NetCancelledStatusWidget();
}

class _NetCancelledStatusWidget extends State<NetCancelledStatusWidget> {
  @override
  Widget build(BuildContext context) {
    return BaseNetStatusWidget(
      imageType: BaseNetStatusImageType.cancelled,
      message: '已取消'.tr,
      showRetryButton: true,
      onRetry: widget.onRetry,
      boundingColor: widget.boundingColor,
      backgroundColor: widget.backgroundColor,
    );
  }
}
