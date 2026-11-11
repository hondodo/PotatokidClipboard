import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:potatokid_screen/shared/widgets/kid_chrome.dart';
import 'package:pscreen_screen/core/update/app_update_controller.dart';

/// 电视端强更页：安装包下载 + sha256 校验通过后才出现，不可关闭。
///
/// 儿童模式下只替换外观与文案（[KidSurface] / 暖黄按钮 / `*_kid` 文案），
/// 安装、重试、错误展示、`PopScope(canPop: false)` 等行为完全不变。
class ForceUpdatePage extends StatelessWidget {
  const ForceUpdatePage({super.key});

  @override
  Widget build(BuildContext context) {
    final bool kid = kidModeOn;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: kid
            ? KidPalette.gradientBottom
            : const Color(0xFF0E1116),
        body: ValueListenableBuilder<AppUpdateState>(
          valueListenable: AppUpdateController.instance,
          builder: (BuildContext context, AppUpdateState state, Widget? _) {
            final String current = state.result?.currentVersion ?? '';
            final String latest = state.result?.latest?.version ?? '';
            final ThemeData theme = ThemeData.dark(useMaterial3: true);
            final Widget content = Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        kid
                            ? Icons.auto_awesome_rounded
                            : Icons.system_update_rounded,
                        size: 88,
                        color: kid
                            ? KidPalette.accent
                            : const Color(0xFF4F8CFF),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        kid ? 'kid_force_update_title'.tr() : '发现新版本',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        current.isEmpty || latest.isEmpty
                            ? (kid
                                  ? 'kid_update_ready_plain'.tr()
                                  : '更新已下载并校验完成')
                            : 'v$current  →  v$latest',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: Colors.white54,
                        ),
                      ),
                      if ((state.result?.latest?.notes ?? '').isNotEmpty) ...<Widget>[
                        const SizedBox(height: 18),
                        Text(
                          state.result!.latest!.notes,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge
                              ?.copyWith(color: Colors.white70),
                        ),
                      ],
                      if (state.error != null) ...<Widget>[
                        const SizedBox(height: 18),
                        Text(
                          state.error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: kid
                                ? const Color(0xFFFF8A72)
                                : Colors.redAccent,
                          ),
                        ),
                      ],
                      if (kid) ...<Widget>[
                        const SizedBox(height: 16),
                        Text(
                          'kid_update_after_install'.tr(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 18,
                          ),
                        ),
                      ],
                      const SizedBox(height: 36),
                      kid
                          ? KidActionButton(
                              label: 'kid_update_install'.tr(),
                              icon: Icons.install_desktop_rounded,
                              autofocus: true,
                              onPressed: () => _install(context),
                            )
                          : FilledButton.icon(
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(260, 56),
                                textStyle: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              onPressed: () => _install(context),
                              icon: const Icon(Icons.install_desktop_rounded),
                              label: const Text('立即安装'),
                            ),
                      const SizedBox(height: 8),
                      kid
                          ? KidOutlineButton(
                              label: 'kid_update_retry'.tr(),
                              onPressed: () => AppUpdateController.instance
                                  .ensureDownloadedNow(),
                            )
                          : TextButton(
                              onPressed: () => AppUpdateController.instance
                                  .ensureDownloadedNow(),
                              child: const Text('重试'),
                            ),
                    ],
                  ),
                ),
              ),
            );
            if (!kid) return content;
            return KidSurface(expand: true, borderRadius: 0, child: content);
          },
        ),
      ),
    );
  }

  /// 安装入口：与原实现一致，仅儿童模式下把失败提示换成温和文案。
  Future<void> _install(BuildContext context) async {
    final bool started = await AppUpdateController.instance.install();
    if (!started && context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        kidModeOn
            ? kidSnackBar('kid_update_install_failed'.tr())
            : const SnackBar(
                content: Text('无法拉起系统安装器，请检查「安装未知应用」权限'),
              ),
      );
    }
  }
}
