import 'package:flutter/material.dart';
import 'package:pscreen_screen/core/update/app_update_controller.dart';

/// 电视端强更页：安装包下载 + sha256 校验通过后才出现，不可关闭。
class ForceUpdatePage extends StatelessWidget {
  const ForceUpdatePage({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF0E1116),
        body: ValueListenableBuilder<AppUpdateState>(
          valueListenable: AppUpdateController.instance,
          builder: (BuildContext context, AppUpdateState state, Widget? _) {
            final String current = state.result?.currentVersion ?? '';
            final String latest = state.result?.latest?.version ?? '';
            final ThemeData theme = ThemeData.dark(useMaterial3: true);
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.system_update_rounded, size: 88, color: Color(0xFF4F8CFF)),
                      const SizedBox(height: 24),
                      Text('发现新版本', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      Text(
                        current.isEmpty || latest.isEmpty ? '更新已下载并校验完成' : 'v$current  →  v$latest',
                        style: theme.textTheme.titleLarge?.copyWith(color: Colors.white54),
                      ),
                      if ((state.result?.latest?.notes ?? '').isNotEmpty) ...<Widget>[
                        const SizedBox(height: 18),
                        Text(
                          state.result!.latest!.notes,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge,
                        ),
                      ],
                      if (state.error != null) ...<Widget>[
                        const SizedBox(height: 18),
                        Text(state.error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.redAccent)),
                      ],
                      const SizedBox(height: 36),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(260, 56),
                          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                        ),
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
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => AppUpdateController.instance.ensureDownloadedNow(),
                        child: const Text('重试'),
                      ),
                    ],
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
