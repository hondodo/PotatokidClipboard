import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pscreen_home/features/remote_control/data/control_settings.dart';
import 'package:pscreen_home/features/remote_control/data/nim_client.dart';
import 'package:pscreen_screen/features/msg/protocol/envelope_builder.dart';

part 'send_state.dart';

/// 发送端 Cubit：管理目标勾选 + 发送（文本/命令）。
class SendCubit extends Cubit<SendState> {
  SendCubit({required this.nim, this.persistTargets = false})
      : super(SendState(
            targets: persistTargets
                ? ControlSettings.instance.selectedTvAccounts
                : const <String>[]));

  final NimClient nim;

  /// 仅管理员勾选目标需要持久化/恢复（spec §4.3）；家人单页不共享该 key。
  final bool persistTargets;

  void toggleTarget(String account) {
    final List<String> next = List<String>.from(state.targets);
    if (next.contains(account)) {
      next.remove(account);
    } else {
      next.add(account);
    }
    emit(state.copyWith(targets: next));
  }

  /// 家人单页：替换为单一台（不支持多选，spec §4.2）。
  void setSingleTarget(String account) {
    emit(state.copyWith(targets: <String>[account]));
  }

  void clearResults() {
    emit(state.copyWith(sendResults: const <String, bool>{}));
  }

  /// 发送纯文本（不加信封）到所有已勾选目标。
  Future<void> sendPlainText(String text) {
    if (text.trim().isEmpty) return Future<void>.value();
    return _sendToTargets(buildPlainText(text));
  }

  /// 发送命令信封到所有已勾选目标。
  Future<void> sendCommand(String name, {Map<String, dynamic>? args}) =>
      _sendToTargets(buildCommandEnvelope(name, args));

  /// 发送已构造好的信封字符串到所有目标（命令面板/快捷入口用）。
  Future<void> sendRaw(String body) => _sendToTargets(body);

  /// 重试指定失败目标（重发 lastBody）。
  Future<void> retryFailed(List<String> accounts) async {
    if (state.isSending) return;
    final String? body = state.lastBody;
    if (body == null) return;
    emit(state.copyWith(isSending: true));
    final Map<String, bool> results = Map<String, bool>.from(state.sendResults);
    for (final String account in accounts) {
      final bool ok = await nim.sendText(toAccount: account, text: body);
      if (isClosed) return;
      results[account] = ok;
      emit(state.copyWith(sendResults: Map<String, bool>.from(results)));
    }
    emit(state.copyWith(isSending: false));
  }

  Future<void> _sendToTargets(String body) async {
    if (state.isSending) return;
    if (state.targets.isEmpty) return;
    if (body.isEmpty) return;
    emit(state.copyWith(isSending: true, lastBody: body));
    final Map<String, bool> results = <String, bool>{};
    for (final String target in state.targets) {
      final bool ok = await nim.sendText(toAccount: target, text: body);
      if (isClosed) return;
      results[target] = ok;
      emit(state.copyWith(sendResults: Map<String, bool>.from(results)));
    }
    emit(state.copyWith(isSending: false)); // 先恢复 isSending
    await _persistTargets(); // 再持久化（此时已无 emit）
  }

  Future<void> _persistTargets() async {
    if (!persistTargets) return;
    try {
      await ControlSettings.instance
          .setSelectedTvAccounts(List<String>.from(state.targets));
    } catch (_) {
      // prefs 未加载/写入失败均非致命
    }
  }
}
