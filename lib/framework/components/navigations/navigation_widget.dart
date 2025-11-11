import 'dart:io';

import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/material.dart';
import 'package:potatokid_clipboard/framework/theme/app_text_theme.dart';

class NavigationWidget extends StatelessWidget implements PreferredSizeWidget {
  const NavigationWidget(
      {super.key,
      required this.title,
      this.actions,
      this.leading,
      this.onBack,
      this.backgroundColor,
      this.foregroundColor,
      this.titleSpacing,
      this.titleWidget,
      this.noBackLeading = false});

  final String title;
  final Widget? titleWidget;
  final List<Widget>? actions;
  final Widget? leading;
  final VoidCallback? onBack;
  final Color? backgroundColor;
  final Color? foregroundColor;

  /// 标题间距(标题和后退箭头之间的间距，和标题和右侧组件actions之间的间距)
  final double? titleSpacing;

  /// 是否不显示后退箭头
  final bool noBackLeading;

  @override
  Widget build(BuildContext context) {
    bool showLeading =
        leading != null || Navigator.canPop(context) || noBackLeading;
    if (Platform.isIOS || Platform.isAndroid) {
      return AppBar(
        title: titleWidget ?? Text(title, style: AppTextTheme.textStyle.title),
        backgroundColor: backgroundColor ?? Colors.blue,
        foregroundColor: foregroundColor ?? Colors.white,
        automaticallyImplyLeading: showLeading, // 去除后退箭头 1
        titleSpacing: titleSpacing ?? (showLeading ? null : 0), // 去除后退箭头 2
        leading: leading ?? (noBackLeading ? null : buildLeading(context)),
        actions: actions,
      );
    } else {
      return
          // WindowTitleBarBox(
          //   child:
          MoveWindow(
        child: AppBar(
          title:
              titleWidget ?? Text(title, style: AppTextTheme.textStyle.title),
          backgroundColor: backgroundColor ?? Colors.blue,
          foregroundColor: foregroundColor ?? Colors.white,
          automaticallyImplyLeading: showLeading, // 去除后退箭头 1
          titleSpacing: titleSpacing ?? (showLeading ? null : 0), // 去除后退箭头 2
          leading: leading ?? (noBackLeading ? null : buildLeading(context)),
          actions: actions,
        ),
        // ),
      );
    }
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  Widget? buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: onBack ?? () => Navigator.pop(context),
    );
  }

  // const NavigationWidget({
  //   super.key,
  //   this.icon = const DefaultBackIcon(
  //     pageStyle: AppPageStyle.light,
  //   ),
  //   VoidCallback? onPressed,
  //   required this.title,
  //   this.textStyle,
  //   this.bgColor = Colors.transparent,
  //   this.bottom,
  //   this.preferredHeight = kToolbarHeight,
  //   this.actions,
  //   this.centerTitle = true,
  //   this.showLeading = true,
  //   this.alwaysShowLeading = false,
  //   this.titleWidget,
  //   this.flexibleSpace,
  //   this.pageStyle = AppPageStyle.light,
  //   this.leadingWidth,
  //   this.titleSpacing,
  // }) : onPressed = onPressed ?? _defaultOnPressed;

  // final Widget? icon; // 返回的icon样式
  // final VoidCallback? onPressed; // 返回点击事件
  // final TextStyle? textStyle; // 标题风格
  // final String title; //< 标题
  // final Color bgColor; //< 背景颜色
  // // final PreferredSizeWidget? bottom; // 底部控件
  // final PreferredSizeWidget? bottom;
  // final double preferredHeight;
  // final bool centerTitle; // 文字居中对齐
  // final List<Widget>? actions; // 右侧组件
  // /// 是否显示后退箭头(默认显示，根据是否可以返回来决定是否显示)
  // final bool showLeading;

  // /// 是否总是显示后退箭头(默认为不总是显示)
  // final bool alwaysShowLeading;

  // /// 如果设置了titleWidget，则不显示title
  // final Widget? titleWidget;

  // /// 自定义的flexibleSpace
  // final Widget? flexibleSpace;

  // final AppPageStyle pageStyle;

  // /// 后退箭头宽度
  // ///
  // /// {@template flutter.material.appbar.leadingWidth}
  // /// Defines the width of [AppBar.leading] widget.
  // ///
  // /// By default, the value of [AppBar.leadingWidth] is 56.0.
  // /// {@endtemplate}
  // final double? leadingWidth;

  // /// 标题间距(标题和后退箭头之间的间距，和标题和右侧组件actions之间的间距)
  // final double? titleSpacing;

  // @override
  // Size get preferredSize => Size.fromHeight(
  //     preferredHeight + (bottom == null ? 0 : bottom!.preferredSize.height));

  // // 新增的公共方法来获取preferredSize
  // Size getPreferredSize() {
  //   return preferredSize;
  // }

  // @override
  // Widget build(BuildContext context) {
  //   // final theme = Get.find<ThemeController>().data;
  //   var bar = AppBar(
  //     systemOverlayStyle: SystemUiOverlayStyle(
  //       statusBarColor: Colors.transparent,
  //       statusBarIconBrightness: pageStyle == AppPageStyle.light
  //           ? Brightness.dark
  //           : Brightness.light,
  //       statusBarBrightness: pageStyle == AppPageStyle.light
  //           ? Brightness.light
  //           : Brightness.dark,
  //     ),
  //     leadingWidth: leadingWidth,
  //     automaticallyImplyLeading: showLeading, // 去除后退箭头 1
  //     titleSpacing: titleSpacing ?? (showLeading ? null : 0), // 去除后退箭头 2
  //     backgroundColor: bgColor,
  //     surfaceTintColor: Colors.transparent,
  //     leading: showLeading == false
  //         ? null // 去除后退箭头 3
  //         : (Navigator.canPop(context) || alwaysShowLeading)
  //             ? IconButton(
  //                 icon: icon ??
  //                     DefaultBackIcon(
  //                       pageStyle: pageStyle,
  //                     ),
  //                 onPressed: onPressed,
  //                 iconSize: 24,
  //                 highlightColor: Colors.transparent,
  //                 splashColor: Colors.transparent,
  //               )
  //             // GestureDetector(
  //             //     onTap: onPressed,
  //             //     child: Container(
  //             //       width: 24.minInW,
  //             //       height: 24.minInW,
  //             //       alignment: Alignment.center,
  //             //       child: icon ?? DefaultBackIcon(pageStyle: pageStyle),
  //             //       // iconSize: 24,
  //             //       // highlightColor: Colors.transparent,
  //             //       // splashColor: Colors.transparent,
  //             //     ),
  //             //   )
  //             : null,
  //     title: titleWidget ??
  //         Text(
  //           title,
  //           style: textStyle ??
  //               (pageStyle == AppPageStyle.light
  //                   ? const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)
  //                   : const TextStyle(
  //                       fontSize: 16, fontWeight: FontWeight.bold)),
  //           textAlign: TextAlign.center,
  //         ),
  //     bottom: bottom,
  //     elevation: 0, //设置AppBar的初始阴影高度为0 - 当滚动ListView时，AppBar的颜色和阴影将保持不变
  //     scrolledUnderElevation:
  //         0, //设置滚动时AppBar的阴影高度也为0 - 当滚动ListView时，AppBar的颜色和阴影将保持不变
  //     centerTitle: centerTitle,
  //     actions: actions,
  //     flexibleSpace: flexibleSpace,
  //     // 不用添加flexibleSpace，需要添加分隔线时使用bottom来实现
  //     // flexibleSpace: Align(alignment: Alignment.bottomCenter, child: Container(height: 1, color: theme.textSubColor,)),
  //   );
  //   return bar;
  // }

  // // 默认为back()
  // static void _defaultOnPressed() {
  //   Get.back();
  // }
}
