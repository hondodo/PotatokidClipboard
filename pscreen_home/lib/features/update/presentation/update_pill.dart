import 'package:flutter/material.dart';
import 'package:pscreen_screen/core/update/app_update_controller.dart';

/// AppBar 上的蓝色「更新」胶囊：圆角 + 下载图标 + 进度百分比。
///
/// 非强更：下载完成后显示红点，用户点开才拉起系统安装器，可以一直忽略。
/// 下载中：显示百分比，不阻断任何操作。
class AppUpdatePill extends StatelessWidget {
  const AppUpdatePill({super.key, this.compact = false, this.margin = EdgeInsets.zero});

  final bool compact;
  final EdgeInsets margin;

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
        return Padding(
          padding: margin,
          child: Material(
            color: const Color(0xFF2F6BFF),
            borderRadius: BorderRadius.circular(999),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => handleUpdatePillTap(context, state),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 12, vertical: compact ? 5 : 7),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    if (ready)
                      Icon(Icons.download_rounded, size: compact ? 15 : 17, color: Colors.white)
                    else
                      SizedBox(
                        width: compact ? 13 : 15,
                        height: compact ? 13 : 15,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                          value: progress,
                        ),
                      ),
                    SizedBox(width: compact ? 5 : 6),
                    Text(
                      label,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: compact ? 12 : 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (ready && !state.forceBlocked) ...<Widget>[
                      const SizedBox(width: 6),
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(color: Color(0xFFFF4D4F), shape: BoxShape.circle),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 点击胶囊：已就绪 → 拉起系统安装器；否则确保后台下载并提示。
Future<void> handleUpdatePillTap(BuildContext context, AppUpdateState state) async {
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
