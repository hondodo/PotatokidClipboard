import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:potatokid_screen/core/utils/app_settings.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_bloc.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_state.dart';

/// 遥控器按键集合（对应真实遥控器的方向/OK/菜单/返回）。
enum RemoteButton { up, down, left, right, ok, menu, back }

/// 悬浮遥控器蒙层（手机调试用）：一个可拖动的迷你 D-pad。
///
/// 底层不伪造系统按键事件（当前 Flutter 版本已无 [KeyEventSimulator]），
/// 而是通过 [RemoteButton] 回调到壳层 MainApp，复用与真实遥控器一致的
/// 处理逻辑（焦点移动切 tab/切频道、菜单键显隐导航条、上/下切时钟样式）。
/// 显隐由全局 [AppState.showFloatingRemote]（在「我的」页开关）与
/// [AppState.isChromeVisible] 共同决定：开启开关后，遥控器**跟随顶部导航条显隐**
/// （点屏切换 / 10 秒自动收起时一并隐藏）；「我的」页 tabs 恒显示，故遥控器保持显示。
///
/// 上角有一把锁：**锁定**后不再跟随顶部导航条隐藏，始终显示（便于随时操作）；
/// **未锁**时维持跟随显隐的原有行为。锁定状态持久化在 [AppSettings]。
class FloatingRemote extends StatefulWidget {
  const FloatingRemote({super.key, required this.onKey});

  /// 遥控器按键回调（由壳层实现与真实遥控器一致的逻辑）。
  final ValueChanged<RemoteButton> onKey;

  @override
  State<FloatingRemote> createState() => _FloatingRemoteState();
}

class _FloatingRemoteState extends State<FloatingRemote> {
  Offset _offset = const Offset(20, 120);

  /// 是否锁定：锁定后不再跟随顶部导航条隐藏，遥控器始终显示。
  bool _locked = false;

  @override
  void initState() {
    super.initState();
    _restoreLocked();
  }

  /// 恢复持久化的锁定状态（读取失败保持未锁）。
  Future<void> _restoreLocked() async {
    await AppSettings.instance.ensureLoaded();
    final bool locked = AppSettings.instance.floatingRemoteLocked;
    if (!mounted || _locked == locked) return;
    setState(() => _locked = locked);
  }

  /// 切换锁定并写回持久化。
  void _toggleLock() {
    final bool next = !_locked;
    setState(() => _locked = next);
    AppSettings.instance.setFloatingRemoteLocked(next);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppBloc, AppState>(
      buildWhen: (previous, current) =>
          previous.showFloatingRemote != current.showFloatingRemote ||
          previous.isChromeVisible != current.isChromeVisible,
      builder: (context, state) {
        // 开关关闭时一并收起（锁定与否都收起）。
        if (!state.showFloatingRemote) {
          return const SizedBox.shrink();
        }
        // 未锁定时跟随顶部导航条显隐；锁定后不受导航条隐藏影响。
        if (!_locked && !state.isChromeVisible) {
          return const SizedBox.shrink();
        }
        return Positioned(
          left: _offset.dx,
          top: _offset.dy,
          child: GestureDetector(
            onPanUpdate: (details) => setState(() => _offset += details.delta),
            child: _RemotePad(
              onKey: widget.onKey,
              locked: _locked,
              onToggleLock: _toggleLock,
            ),
          ),
        );
      },
    );
  }
}

/// 遥控器按键面板：方向十字 + OK + 菜单/返回，右上角为「锁定」开关。
class _RemotePad extends StatelessWidget {
  const _RemotePad({
    required this.onKey,
    required this.locked,
    required this.onToggleLock,
  });

  final ValueChanged<RemoteButton> onKey;

  /// 是否已锁定（锁定后不跟随顶部导航条隐藏）。
  final bool locked;

  /// 切换锁定状态。
  final VoidCallback onToggleLock;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(16),
      elevation: 4,
      child: Stack(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _dir(Icons.keyboard_arrow_up, RemoteButton.up),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _dir(Icons.keyboard_arrow_left, RemoteButton.left),
                    _key(
                      Icons.check,
                      RemoteButton.ok,
                      center: true,
                      child: Container(
                        color: Colors.transparent,
                        child: Center(
                          child: Text('OK', style: TextStyle(fontSize: 16, color: Colors.black)),
                        ),
                      ),
                    ),
                    _dir(Icons.keyboard_arrow_right, RemoteButton.right),
                  ],
                ),
                _dir(Icons.keyboard_arrow_down, RemoteButton.down),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _label('菜单', RemoteButton.menu),
                    const SizedBox(width: 6),
                    _label('返回', RemoteButton.back),
                  ],
                ),
              ],
            ),
          ),
          // 右上角的锁：锁定后遥控器不随顶部 tabs 隐藏。
          Positioned(top: 3, right: 3, child: _lockButton()),
        ],
      ),
    );
  }

  /// 锁定开关：锁定态用实心锁 + 高亮底色，未锁用开锁图标。
  Widget _lockButton() {
    return InkWell(
      customBorder: const CircleBorder(),
      onTap: onToggleLock,
      child: Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: locked ? Colors.amber : Colors.white12,
          shape: BoxShape.circle,
        ),
        child: Icon(
          locked ? Icons.lock : Icons.lock_open,
          size: 15,
          color: locked ? Colors.black : Colors.white70,
        ),
      ),
    );
  }

  Widget _dir(IconData icon, RemoteButton button) => _key(icon, button, center: false);

  Widget _label(String text, RemoteButton button) {
    return Padding(
      padding: const EdgeInsets.all(2),
      child: InkWell(
        customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        onTap: () => onKey(button),
        child: Container(
          width: 52,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(6)),
          child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ),
      ),
    );
  }

  Widget _key(IconData icon, RemoteButton button, {required bool center, Widget? child}) {
    return Padding(
      padding: const EdgeInsets.all(2),
      child: InkWell(
        customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        onTap: () => onKey(button),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: center ? Colors.white : Colors.white24,
            borderRadius: BorderRadius.circular(10),
          ),
          child: child ?? Icon(icon, size: 28, color: center ? Colors.black : Colors.white),
        ),
      ),
    );
  }
}
