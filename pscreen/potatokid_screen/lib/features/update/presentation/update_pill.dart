import 'package:flutter/material.dart';
import 'package:pscreen_screen/core/update/app_update_controller.dart';

/// 电视端右上角的蓝色「更新」胶囊（圆角 + 下载图标 + 百分比）。
///
/// 电视端没有 AppBar，这里作为首页播放器上的悬浮层；下载中只展示进度，
/// 不拦截播放/操作。下载校验完成后点按才拉起系统安装器。
class TvUpdatePill extends StatelessWidget {
  const TvUpdatePill({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppUpdateState>(
      valueListenable: AppUpdateController.instance,
      builder: (BuildContext context, AppUpdateState state, Widget? _) {
        if (!state.showPill) return const SizedBox.shrink();
        final bool ready = state.phase == AppUpdatePhase.ready || state.phase == AppUpdatePhase.installing;
        final double? progress = state.progress;
        final String label = ready
            ? '更新'
            : progress == null
                ? '更新中'
                : '${(progress * 100).round()}%';
        return Material(
          color: const Color(0xFF2F6BFF),
          borderRadius: BorderRadius.circular(999),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => handleTvUpdateTap(context, state),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (ready)
                    const Icon(Icons.download_rounded, size: 20, color: Colors.white)
                  else
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white, value: progress),
                    ),
                  const SizedBox(width: 8),
                  Text(label, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                  if (ready && !state.forceBlocked) ...<Widget>[
                    const SizedBox(width: 8),
                    Container(
                      width: 9,
                      height: 9,
                      decoration: const BoxDecoration(color: Color(0xFFFF4D4F), shape: BoxShape.circle),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

Future<void> handleTvUpdateTap(BuildContext context, AppUpdateState state) async {
  final AppUpdateController controller = AppUpdateController.instance;
  final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(context);
  if (state.phase != AppUpdatePhase.ready && state.phase != AppUpdatePhase.installing) {
    messenger?.showSnackBar(
      const SnackBar(content: Text('正在后台下载更新，完成后可从这里安装'), behavior: SnackBarBehavior.floating),
    );
    await controller.ensureDownloadedNow();
    return;
  }
  final bool started = await controller.install();
  if (!started) {
    messenger?.showSnackBar(
      const SnackBar(content: Text('无法拉起系统安装器，请检查「安装未知应用」权限'), behavior: SnackBarBehavior.floating),
    );
  }
}
