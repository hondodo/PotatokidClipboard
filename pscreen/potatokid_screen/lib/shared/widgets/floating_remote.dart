import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_bloc.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_state.dart';

/// 遥控器按键集合（对应真实遥控器的方向/OK/菜单/返回）。
enum RemoteButton {
  up,
  down,
  left,
  right,
  ok,
  menu,
  back,
}

/// 悬浮遥控器蒙层（手机调试用）：一个可拖动的迷你 D-pad。
///
/// 底层不伪造系统按键事件（当前 Flutter 版本已无 [KeyEventSimulator]），
/// 而是通过 [RemoteButton] 回调到壳层 MainApp，复用与真实遥控器一致的
/// 处理逻辑（焦点移动切 tab/切频道、OK 显隐导航条、上/下切时钟样式）。
/// 显隐由全局 [AppState.showFloatingRemote] 控制（在「我的」页开关）。
class FloatingRemote extends StatefulWidget {
  const FloatingRemote({super.key, required this.onKey});

  /// 遥控器按键回调（由壳层实现与真实遥控器一致的逻辑）。
  final ValueChanged<RemoteButton> onKey;

  @override
  State<FloatingRemote> createState() => _FloatingRemoteState();
}

class _FloatingRemoteState extends State<FloatingRemote> {
  Offset _offset = const Offset(20, 120);

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AppBloc, AppState>(
      buildWhen: (previous, current) =>
          previous.showFloatingRemote != current.showFloatingRemote,
      builder: (context, state) {
        if (!state.showFloatingRemote) return const SizedBox.shrink();
        return Positioned(
          left: _offset.dx,
          top: _offset.dy,
          child: GestureDetector(
            onPanUpdate: (details) => setState(() => _offset += details.delta),
            child: _RemotePad(onKey: widget.onKey),
          ),
        );
      },
    );
  }
}

/// 遥控器按键面板：方向十字 + OK + 菜单/返回。
class _RemotePad extends StatelessWidget {
  const _RemotePad({required this.onKey});

  final ValueChanged<RemoteButton> onKey;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(16),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _dir(Icons.keyboard_arrow_up, RemoteButton.up),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _dir(Icons.keyboard_arrow_left, RemoteButton.left),
                _key(Icons.check, RemoteButton.ok, center: true),
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
    );
  }

  Widget _dir(IconData icon, RemoteButton button) =>
      _key(icon, button, center: false);

  Widget _label(String text, RemoteButton button) {
    return Padding(
      padding: const EdgeInsets.all(2),
      child: InkWell(
        customBorder: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
        onTap: () => onKey(button),
        child: Container(
          width: 52,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white12,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(text,
              style: const TextStyle(color: Colors.white, fontSize: 12)),
        ),
      ),
    );
  }

  Widget _key(IconData icon, RemoteButton button, {required bool center}) {
    return Padding(
      padding: const EdgeInsets.all(2),
      child: InkWell(
        customBorder: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        onTap: () => onKey(button),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: center ? Colors.white : Colors.white24,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            size: 28,
            color: center ? Colors.black : Colors.white,
          ),
        ),
      ),
    );
  }
}