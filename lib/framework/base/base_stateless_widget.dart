import '../../framework/base/base_stateless_sub_widget.dart';
import '../../framework/components/navigations/navigation_widget.dart';
import '../../framework/mixin/base_status_mixin.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

abstract class BaseStatelessWidget<T extends BaseStatusMixin>
    extends BaseStatelessSubWidget<T> {
  const BaseStatelessWidget({
    super.key,
    this.title = '',
    this.resizeToAvoidBottomInset = true,
    this.hideNavigate = false,
    this.bottomWidget,
    this.decoration,
    this.onBack,
    super.isStatusWidgetCover,
    super.isShowShimmer,
    super.isSilentRefresh,
    super.isShowError,
    super.controllerTag,
    super.bodyBackgroundColor,
    this.barBackgroundColor,
    this.barForegroundColor,
  });

  final String title;
  final bool resizeToAvoidBottomInset;

  /// 是否隐藏导航栏（顶部导航栏，带标题、返回按钮、菜单等）
  final bool hideNavigate;
  final PreferredSizeWidget? bottomWidget;

  /// 正文装饰
  final Decoration? decoration;

  /// 返回按钮点击事件
  final VoidCallback? onBack;

  final Color? barBackgroundColor;
  final Color? barForegroundColor;

  @override
  EdgeInsets bodyPadding() {
    return const EdgeInsets.only(left: 0, right: 0, top: 0, bottom: 0);
  }

  @override
  Widget build(BuildContext context) {
    // return Obx(()
    // {
    //   return buildMainWidget(context);
    // });
    // 注：标题无法覆盖
    var content = Container(
        decoration: decoration ?? const BoxDecoration(color: Colors.white),
        child: Scaffold(
          resizeToAvoidBottomInset: resizeToAvoidBottomInset,
          appBar: hideNavigate ? null : buildAppBar(context),
          drawer: buildDrawer(context),
          backgroundColor: Colors.transparent,
          body: Obx(() {
            return buildMainWidget(context);
          }),
        ));
    return content;
  }

  PreferredSizeWidget? buildAppBar(BuildContext context) {
    // return NavigationWidget(
    //   title: title.tr,
    //   bottom: bottomWidget,
    //   bgColor: Colors.white,
    //   onPressed: onBack,
    // );
    return NavigationWidget(
        title: title,
        onBack: onBack,
        backgroundColor: barBackgroundColor,
        foregroundColor: barForegroundColor);
  }

  Widget? buildDrawer(BuildContext context) {
    return null;
  }
}
