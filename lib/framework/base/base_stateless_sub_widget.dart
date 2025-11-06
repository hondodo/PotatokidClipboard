import '../../framework/components/net_status_widget/net_cancelled_status_widget.dart';
import '../../framework/components/net_status_widget/net_data_empty_status_widget.dart';
import '../../framework/components/net_status_widget/net_data_error_status_widget.dart';
import '../../framework/components/net_status_widget/net_error_status_widget.dart';
import '../../framework/components/net_status_widget/net_loading_status_widget.dart';
import '../../framework/components/net_status_widget/net_no_net_status_widget.dart';
import '../../framework/components/net_status_widget/net_unkonwn_status_widget.dart';
import '../../framework/components/shimmer.dart';
import '../../framework/components/shimmer_loading.dart';
import '../../framework/mixin/base_status_mixin.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

abstract class BaseStatelessSubWidget<T extends BaseStatusMixin>
    extends GetView<T> {
  const BaseStatelessSubWidget({
    super.key,
    this.isStatusWidgetCover = false,
    this.isShowShimmer = false,
    this.isSilentRefresh = false,
    this.isShowError = true,
    this.controllerTag = '',
    this.bodyBackgroundColor,
  });

  /// 加载失败后是否覆盖状态组件（默认false,不覆盖）
  final bool isStatusWidgetCover;

  /// 加载中显示modal加载图标还是使用颜色闪烁（默认false,使用加载图标）
  final bool isShowShimmer;

  /// 是否显示错误状态（默认true,显示错误状态）
  final bool isShowError;
  // EdgeInsets get bodyPadding =>
  //     const EdgeInsets.only(left: 0, right: 0, top: 0, bottom: 16);

  /// 是否静默刷新
  final bool isSilentRefresh;

  /// 控制器tag，用于获取不同tag的控制器，默认空，使用默认tag
  /// 如果设置了，请在put时设置tag，否则会报错
  /// 可参考RouterNames.servicerHomePage,RouterNames.categoriesPage的实现
  final String? controllerTag;

  final Color? bodyBackgroundColor;

  @override
  String? get tag => controllerTag;

  /// 闪烁空状态的maskColor, 如果闪屏，可尝试设置成透明或其它颜色
  Color get shimmerEmptyMaskColor => maskColor().withAlpha(50);

  /// 闪烁背景色，如果闪烁，可尝试设置成透明或其它颜色
  Color get shimmerBackgroundColor => Colors.transparent;

  /// 状态组件背景色，如果状态组件背景色，默认透明
  Color statusWidgetBackgroundColor() {
    return Colors.transparent;
  }

  Widget buildMainWidget(BuildContext context) {
    var code = controller.status.value.code;
    var status = controller.status.value.status;

    if (isSilentRefresh && status == Status.loading) {
      var successBody = Container(
        padding: bodyPadding(),
        child: buildBody(context),
      );
      return successBody;
    }

    if (isShowShimmer && status == Status.loading) {
      var successBody = buildBody(context);
      var shimmerLoading = ShimmerLoading(
          isLoading: true,
          emptyMaskColor: shimmerEmptyMaskColor,
          // Colors
          //     .transparent, //maskColor().withAlpha(50), // 改用透明色，避免闪烁 20250625
          child: successBody);
      return Container(
        padding: bodyPadding(), // 20250625 添加和body一样的padding，避免闪烁和尺寸变化
        decoration: BoxDecoration(color: shimmerBackgroundColor),
        child: Shimmer(
          child: shimmerLoading,
        ),
      );
    }

    if (!isShowError) {
      return Container(
        padding: bodyPadding(),
        child: buildBody(context),
      );
    }

    if (isStatusWidgetCover) {
      return Stack(
        children: [
          Container(
            padding: bodyPadding(),
            child: buildBody(context),
          ),
          if (status != Status.success)
            Container(
              color: maskColor(),
              child: Center(
                child: buildStatusWidget(context, status, code),
              ),
            )
        ],
      );
    }
    return buildStatusWidget(context, status, code);
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      return buildMainWidget(context);
    });
  }

  Widget buildBody(BuildContext context);

  Widget? loadingBody(BuildContext context) {
    return null;
  }

  /// 注：dataEmpty 不在此处返回，由createEmptyBody返回
  Widget? errorBody(BuildContext context, StatusErrorCode code) {
    return null;
  }

  Widget? emptyBody(BuildContext context) {
    return null;
  }

  Widget? unknownBody(BuildContext context) {
    return null;
  }

  Widget? cancelBody(BuildContext context) {
    return null;
  }

  Widget createEmptyBody(BuildContext context) {
    Color? boundingColor = isStatusWidgetCover ? Colors.white : null;
    return NetDataEmptyStatusWidget(
      backgroundColor: statusWidgetBackgroundColor(),
      boundingColor: boundingColor,
      onRetry: () {
        retry();
      },
    );
  }

  EdgeInsets bodyPadding() {
    return EdgeInsets.zero;
  }

  Color maskColor() {
    return Colors.black.withAlpha(150);
  }

  Widget buildLoadingBody(BuildContext context) {
    return loadingBody(context) ?? const NetLoadingStatusWidget();
  }

  Widget buildStatusWidget(
      BuildContext context, Status status, StatusErrorCode code) {
    Color? boundingColor = isStatusWidgetCover ? Colors.white : null;
    switch (status) {
      case Status.loading:
        return buildLoadingBody(
            context); // loadingBody(context) ?? const NetLoadingStatusWidget();
      case Status.success:
        return Container(
            padding: bodyPadding(),
            decoration:
                BoxDecoration(color: bodyBackgroundColor ?? Colors.white),
            child: buildBody(context));
      case Status.error:
        if (code == StatusErrorCode.disconnect) {
          return errorBody(context, code) ??
              NetNotNetStatusWidget(
                boundingColor: boundingColor,
                backgroundColor: statusWidgetBackgroundColor(),
                onRetry: () {
                  retry();
                },
              );
        } else if (code == StatusErrorCode.dataEmpty) {
          return createEmptyBody(context);
        } else if (code == StatusErrorCode.cancelled) {
          return errorBody(context, code) ??
              NetCancelledStatusWidget(
                boundingColor: boundingColor,
                backgroundColor: statusWidgetBackgroundColor(),
                onRetry: () {
                  retry();
                },
              );
        } else if (code == StatusErrorCode.assectError) {
          return errorBody(context, code) ??
              NetErrorStatusWidget(
                boundingColor: boundingColor,
                backgroundColor: statusWidgetBackgroundColor(),
                onRetry: () {
                  retry();
                },
              );
        } else if (code == StatusErrorCode.dataError) {
          return errorBody(context, code) ??
              NetDataErrorStatusWidget(
                boundingColor: boundingColor,
                backgroundColor: statusWidgetBackgroundColor(),
                onRetry: () {
                  retry();
                },
              );
        }
        return errorBody(context, code) ??
            NetUnkonwnStatusWidget(
              boundingColor: boundingColor,
              backgroundColor: statusWidgetBackgroundColor(),
              onRetry: () {
                retry();
              },
            );
      case Status.unknown:
        return unknownBody(context) ??
            NetNotNetStatusWidget(
              boundingColor: boundingColor,
              backgroundColor: statusWidgetBackgroundColor(),
              onRetry: () {
                retry();
              },
            );
      default:
        break;
    }
    return Center(
        child: Text(
      'not defined'.tr,
    ));
  }

  void retry() {
    controller.onRetry();
  }

  void cancel() {
    controller.onCancel();
  }

  void close() {
    Get.back();
  }
}
