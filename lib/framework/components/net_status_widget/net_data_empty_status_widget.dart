import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../framework/components/net_status_widget/base_net_status_widget.dart';

/// 数据返回空白时
class NetDataEmptyStatusWidget extends StatefulWidget {
  /// 数据返回空白时
  const NetDataEmptyStatusWidget(
      {super.key,
      required this.onRetry,
      this.boundingColor,
      this.message,
      this.showRetryButton = true,
      this.backgroundColor});

  final Function()? onRetry;
  final Color? boundingColor;
  final String? message;
  final bool showRetryButton;
  final Color? backgroundColor;

  @override
  State<NetDataEmptyStatusWidget> createState() => _NetDataEmptyStatusWidget();
}

class _NetDataEmptyStatusWidget extends State<NetDataEmptyStatusWidget> {
  @override
  Widget build(BuildContext context) {
    return BaseNetStatusWidget(
      imageType: BaseNetStatusImageType.empty,
      message: widget.message ?? '暂无更多数据'.tr,
      showRetryButton: widget.showRetryButton,
      onRetry: widget.onRetry,
      boundingColor: widget.boundingColor,
      backgroundColor: widget.backgroundColor,
    );
  }
}
