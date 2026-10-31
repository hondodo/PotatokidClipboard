import '../../framework/base/base_stateless_widget.dart';
import '../../framework/components/navigations/navigation_widget.dart';
import '../../framework/mixin/base_status_mixin.dart';
import 'package:flutter/material.dart';

abstract class BaseStatelessUnderlineBarWidget<T extends BaseStatusMixin>
    extends BaseStatelessWidget<T> {
  /// 带导航栏和分割线的基础页面
  ///
  /// [centerTitle] 是否居中显示标题
  /// [splitLineColor] 分割线颜色
  /// [bgColor] 背景颜色
  /// [showLeading] 是否显示返回按钮
  /// [isShowError] 是否显示错误
  /// [decoration] 正文装饰
  /// [hideNavigate] 是否隐藏导航栏
  const BaseStatelessUnderlineBarWidget(
      {super.key,
      super.onBack,
      super.resizeToAvoidBottomInset,
      super.isStatusWidgetCover,
      super.isShowShimmer,
      super.isSilentRefresh,
      this.centerTitle = true,
      this.splitLineColor,
      this.bgColor,
      this.showLeading,
      super.isShowError,
      super.decoration,
      super.hideNavigate,
      super.controllerTag,
      super.bodyBackgroundColor,
      this.showSplitLine = true,
      this.barBackgroundColor,
      this.barForegroundColor});

  /// 是否居中显示标题
  final bool centerTitle;

  /// 获取标题
  String getTitle();

  /// 分割线颜色
  final Color? splitLineColor;

  /// 是否显示分割线
  final bool showSplitLine;

  /// 背景颜色
  final Color? bgColor;

  /// 是否显示返回按钮
  final bool? showLeading;

  List<Widget>? buildActions() {
    return null;
  }

  final Color? barForegroundColor;
  final Color? barBackgroundColor;

  @override
  PreferredSizeWidget? buildAppBar(BuildContext context) {
    return NavigationWidget(
      title: getTitle(),
      onBack: onBack,
      backgroundColor: barBackgroundColor,
      foregroundColor: barForegroundColor,
      actions: buildActions(),
    );
  }
}
