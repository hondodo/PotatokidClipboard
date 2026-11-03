import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:potatokid_screen/core/di/injection.dart';
import 'package:potatokid_screen/core/router/app_router.dart';
import 'package:potatokid_screen/core/router/route_params.dart';
import 'package:potatokid_screen/features/parental/presentation/widgets/parental_local_config_editor.dart';

/// 设置弹层：以底部 Sheet 形式滑入，通过 [SettingsSheetParams] 接收参数。
///
/// 阶段 1 在此承载儿童模式**本地临时配置调试入口**（[ParentalLocalConfigEditor]）：
/// 由「我的」页长按「版本」行打开（见 `profile_page._openParentalDebug`）。
/// 复用本占位页与既有路由（原先无调用方），不新增页面/路由文件；编辑区
/// 限高 0.72 屏并内部滚动，保证遥控器窄可视区内可完整操作。
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
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.72,
                  ),
                  child: const SingleChildScrollView(
                    child: ParentalLocalConfigEditor(),
                  ),
                ),
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
