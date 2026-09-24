import 'dart:math';

import 'package:flutter/material.dart';

/// 导航底部工具
/// 注：不要传入widget=null且showSplitLine=false，会返回一个高为max(splitLineHeight, 1)的控件
class NavigationBottomWidget extends StatefulWidget
    implements PreferredSizeWidget {
  const NavigationBottomWidget({
    super.key,
    this.widget,
    this.showSplitLine = true,
    this.preferredHeight = 20,
    this.splitLineColor,
    this.splitLineHeight = 1,
  });
  final Widget? widget;
  final bool showSplitLine;
  final double preferredHeight;
  final Color? splitLineColor;
  final double splitLineHeight;

  double getPreferredHeight() {
    return widget == null
        ? max(splitLineHeight, 1)
        : (showSplitLine
            ? max(splitLineHeight, 1) + preferredHeight
            : preferredHeight);
  }

  Size getPreferredSize() {
    return Size.fromHeight(getPreferredHeight());
  }

  @override
  State<NavigationBottomWidget> createState() => _NavigationBottomWidget();

  @override
  Size get preferredSize {
    return Size.fromHeight(getPreferredHeight());
  }
}

class _NavigationBottomWidget extends State<NavigationBottomWidget> {
  Widget createLineWidget() {
    return Container(
      height: max(widget.splitLineHeight, 1),
      color: widget.splitLineColor ?? Colors.grey.withOpacity(0.12),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.widget == null) {
      return createLineWidget();
    }
    if (widget.showSplitLine) {
      return SizedBox(
          height: widget.getPreferredHeight(),
          child: Column(
            children: [
              Expanded(
                child: Container(
                  color: Colors.transparent,
                ),
              ),
              widget.widget!,
              createLineWidget(),
            ],
          ));
    }
    return SizedBox(
      height: widget.preferredHeight,
      child: widget.widget!,
    );
  }
}
