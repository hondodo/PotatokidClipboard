import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../framework/components/net_status_widget/base_net_status_widget.dart';

class NetUnkonwnStatusWidget extends StatefulWidget {
  /// 发生未知网络错误时
  const NetUnkonwnStatusWidget(
      {super.key,
      required this.onRetry,
      this.imagePath,
      this.message,
      this.boundingColor,
      this.backgroundColor});
  final String? imagePath;
  final String? message;
  final Function()? onRetry;
  final Color? boundingColor;
  final Color? backgroundColor;
  @override
  State<NetUnkonwnStatusWidget> createState() => _NetUnkonwnStatusWidget();
}

class _NetUnkonwnStatusWidget extends State<NetUnkonwnStatusWidget> {
  @override
  Widget build(BuildContext context) {
    return BaseNetStatusWidget(
      imageType: BaseNetStatusImageType.empty,
      message: widget.message ?? '发生未知网络错误，请稍后重试'.tr,
      showRetryButton: true,
      onRetry: widget.onRetry,
      boundingColor: widget.boundingColor,
      backgroundColor: widget.backgroundColor,
    );
  }
}
