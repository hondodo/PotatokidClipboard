import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pscreen_screen/core/utils/device_credentials.dart';

/// 电视端「当前登录账号」小字标签。
///
/// 账号为设备派生号 `<flavor>.<kind>.<设备号>`（如 `tv.tv.0e208908bebea19a`），
/// 用于多台电视时确认正在操作哪一台。只读展示；取不到时明确显示「未登录」，
/// 不显示空白。
class DeviceAccountLabel extends StatefulWidget {
  const DeviceAccountLabel({
    super.key,
    this.color,
    this.fontSize = 12,
    this.textAlign = TextAlign.center,
  });

  final Color? color;
  final double fontSize;
  final TextAlign textAlign;

  @override
  State<DeviceAccountLabel> createState() => _DeviceAccountLabelState();
}

class _DeviceAccountLabelState extends State<DeviceAccountLabel> {
  String? _account;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final String account = (await DeviceCredentials.account()).trim();
    if (!mounted || account == _account) return;
    setState(() => _account = account);
  }

  @override
  Widget build(BuildContext context) {
    final String text = _account == null
        ? '账号：读取中…'
        : (_account!.isEmpty ? '账号：未登录' : '账号：$_account');
    return Text(
      text,
      textAlign: widget.textAlign,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: widget.color ?? Colors.white38,
        fontSize: widget.fontSize,
      ),
    );
  }
}
