import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../framework/components/net_status_widget/base_net_status_widget.dart';

class NetErrorStatusWidget extends StatefulWidget {
  /// 访问网络出错时 服务器崩溃、访问超时、code不为200等
  const NetErrorStatusWidget(
      {super.key,
      required this.onRetry,
      this.boundingColor,
      this.backgroundColor});

  final Function()? onRetry;
  final Color? boundingColor;
  final Color? backgroundColor;

  @override
  State<NetErrorStatusWidget> createState() => _NetErrorStatusWidget();
}

class _NetErrorStatusWidget extends State<NetErrorStatusWidget> {
  @override
  Widget build(BuildContext context) {
    return BaseNetStatusWidget(
      imageType: BaseNetStatusImageType.noNetwork,
      message: '很抱歉，服务器当前拥挤，请稍后再试'.tr,
      showRetryButton: true,
      onRetry: widget.onRetry,
      boundingColor: widget.boundingColor,
      backgroundColor: widget.backgroundColor,
    );
  }
}
