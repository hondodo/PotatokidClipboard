import 'package:flutter/material.dart';
import 'package:potatokid_screen/features/parental/presentation/widgets/device_account_label.dart';
import 'package:potatokid_screen/features/parental/presentation/widgets/parental_verification_sheet.dart';
import 'package:potatokid_screen/shared/widgets/kid_chrome.dart';
import 'package:potatokid_screen/features/profile/presentation/pages/profile_page.dart';
import 'package:pscreen_screen/core/media/kid_watch_timer_controller.dart';
import 'package:pscreen_screen/core/parental/parental_state_controller.dart';

/// 「我的」Tab 儿童模式只读页（方案 5.2/5.3，阶段 4）。
///
/// 儿童模式生效（`ParentalStateController.enabled`）时由 `MainApp` 经
/// IndexedStack 翻转整页替换 [ProfilePage]，只展示：
/// - 模式状态（儿童模式已开启）；
/// - 逐人已看时长（与锁屏页同口径的分账展示）；
/// - 「请求解锁」入口（复用阶段 2 的 [ParentalVerificationSheet]，
///   短码与「重新请求」能力由该验证层自带）。
///
/// 不含任何可修改的设置行；判定式不成立时本页不挂载，原页行为不变。
class ProfileReadonlyPage extends StatefulWidget {
  const ProfileReadonlyPage({super.key});

  @override
  State<ProfileReadonlyPage> createState() => _ProfileReadonlyPageState();
}

class _ProfileReadonlyPageState extends State<ProfileReadonlyPage> {
  @override
  void initState() {
    super.initState();
    // 防穿透：模式可能在行内编辑中途开启，原页输入框残留编辑态会先消费
    // 物理键（ProfilePage._handlePageKey 在焦点链上更靠内）——进本页即取消。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ProfilePage.isInlineEditing) {
        ProfilePage.onCancelInlineEdit?.call();
      }
    });
  }

  Future<void> _openVerify() async {
    final bool ok = await ParentalVerificationSheet.show(context);
    // 与锁屏页一致：远程路径由命令执行器解锁，本地（PIN/算术）在此解除；
    // unlock 对未锁状态幂等。
    if (!ok || !mounted) return;
    KidWatchTimerController.instance.unlock();
  }

  @override
  Widget build(BuildContext context) {
    final ParentalStateController parental = ParentalStateController.instance;
    final ThemeData theme = Theme.of(context);
    // 已看时长随计时器通知刷新（镜像锁屏页，本页无自有 ticker）。
    return ListenableBuilder(
      listenable: KidWatchTimerController.instance,
      builder: (BuildContext context, _) {
        final KidWatchTimerController timer = KidWatchTimerController.instance;
        return KidSurface(
          expand: true,
          borderRadius: 0,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(
                    Icons.child_care,
                    size: 72,
                    color: KidPalette.accent,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '儿童模式已开启',
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(color: Colors.white),
                  ),
                  const SizedBox(height: 20),
                  // 逐人已看（分账）：与锁屏页同口径展示单次/当日。
                  for (final String id in timer.activeChildIds)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '${_nameOf(parental, id)}：已看 ${_fmt(timer.sessionSecOf(id))}'
                        '（当日 ${_fmt(timer.dailySecOf(id))}）',
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(color: Colors.white70),
                      ),
                    ),
                  const SizedBox(height: 24),
                  KidOutlineButton(
                    label: '请求解锁',
                    onPressed: _openVerify,
                  ),
                  const SizedBox(height: 20),
                  // 固定显示本机派生账号，多台电视时可确认正在操作哪一台。
                  const DeviceAccountLabel(color: Colors.white54),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 时长展示：`X 分 Y 秒`（与锁屏页同口径，负值按 0 处理）。
  static String _fmt(int sec) {
    final int s = sec < 0 ? 0 : sec;
    return s < 60 ? '$s 秒' : '${s ~/ 60} 分 ${s % 60} 秒';
  }

  static String _nameOf(ParentalStateController parental, String id) =>
      parental.config.childById(id)?.name ?? id;
}
