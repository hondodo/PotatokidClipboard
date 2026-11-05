import 'package:flutter/material.dart';
import 'package:pscreen_screen/core/update/app_update_controller.dart';

/// 强更页：**只在安装包下载完成且 sha256 校验通过后**出现，
/// 没有关闭 / 稍后按钮，只有「立即安装」；安装完成重启后复检通过才回到主页。
class ForceUpdatePage extends StatelessWidget {
  const ForceUpdatePage({super.key});

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: ValueListenableBuilder<AppUpdateState>(
          valueListenable: AppUpdateController.instance,
          builder: (BuildContext context, AppUpdateState state, Widget? _) {
            final String current = state.result?.currentVersion ?? '';
            final String latest = state.result?.latest?.version ?? '';
            final String notes = state.result?.latest?.notes ?? '';
            return SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(Icons.system_update_rounded, size: 64, color: scheme.primary),
                        const SizedBox(height: 20),
                        Text('发现新版本', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 10),
                        Text(
                          current.isEmpty || latest.isEmpty ? '更新已下载并校验完成' : 'v$current  →  v$latest',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(color: scheme.outline),
                        ),
                        if (notes.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 14),
                          Text(notes, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
                        ],
                        if (state.error != null) ...<Widget>[
                          const SizedBox(height: 14),
                          Text(state.error!, textAlign: TextAlign.center, style: TextStyle(color: scheme.error)),
                        ],
                        const SizedBox(height: 26),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: () async {
                              final bool started = await AppUpdateController.instance.install();
                              if (!started && context.mounted) {
                                ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                                  const SnackBar(content: Text('无法拉起系统安装器，请检查「安装未知应用」权限')),
                                );
                              }
                            },
                            icon: const Icon(Icons.install_desktop_rounded),
                            label: const Text('立即安装'),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextButton(
                          onPressed: () => AppUpdateController.instance.ensureDownloadedNow(),
                          child: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
