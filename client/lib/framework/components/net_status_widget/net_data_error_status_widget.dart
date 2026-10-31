import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../framework/components/net_status_widget/base_net_status_widget.dart';

class NetDataErrorStatusWidget extends StatefulWidget {
  /// 解析数据出错时
  const NetDataErrorStatusWidget(
      {super.key,
      required this.onRetry,
      this.boundingColor,
      this.backgroundColor});

  final Function()? onRetry;
  final Color? boundingColor;
  final Color? backgroundColor;

  @override
  State<NetDataErrorStatusWidget> createState() => _NetDataErrorStatusWidget();
}

class _NetDataErrorStatusWidget extends State<NetDataErrorStatusWidget> {
  @override
  Widget build(BuildContext context) {
    return BaseNetStatusWidget(
      imageType: BaseNetStatusImageType.error,
      message: '数据请求失败，请稍后再试'.tr,
      showRetryButton: true,
      onRetry: widget.onRetry,
      boundingColor: widget.boundingColor,
      backgroundColor: widget.backgroundColor,
    );
  }
}
