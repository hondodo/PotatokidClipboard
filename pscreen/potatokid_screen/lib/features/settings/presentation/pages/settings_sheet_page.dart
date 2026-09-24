import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:potatokid_screen/core/di/injection.dart';
import 'package:potatokid_screen/core/router/app_router.dart';
import 'package:potatokid_screen/core/router/route_params.dart';

/// 设置弹层：以底部 Sheet 形式滑入，通过 [SettingsSheetParams] 接收参数。
class SettingsSheetPage extends StatelessWidget {
  const SettingsSheetPage({super.key, required this.params});

  final SettingsSheetParams params;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'settings_title'.tr(),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text('from: ${params.from ?? '-'}'),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => Injection.get<AppRouter>().pop(),
                  child: Text('action_close'.tr()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
