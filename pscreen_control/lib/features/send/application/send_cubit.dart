import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pscreen_control/core/nim_client.dart';
import 'package:pscreen_control/features/protocol/envelope_builder.dart';

part 'send_state.dart';

/// 发送端 Cubit：管理目标勾选 + 发送（文本/命令）。
class SendCubit extends Cubit<SendState> {
  SendCubit({required this.nim}) : super(const SendState());

  final NimClient nim;

  void toggleTarget(String account) {
    final List<String> next = List<String>.from(state.targets);
    if (next.contains(account)) {
      next.remove(account);
    } else {
      next.add(account);
    }
    emit(state.copyWith(targets: next));
  }

  void clearResults() {
    emit(state.copyWith(sendResults: const <String, bool>{}));
  }

  /// 发送纯文本（不加信封）到所有已勾选目标。
  Future<void> sendPlainText(String text) =>
      _sendToTargets(buildPlainText(text));

  /// 发送命令信封到所有已勾选目标。
  Future<void> sendCommand(String name, {Map<String, dynamic>? args}) =>
      _sendToTargets(buildCommandEnvelope(name, args));

  Future<void> _sendToTargets(String body) async {
    if (state.isSending) return;
    if (state.targets.isEmpty) return;
    emit(state.copyWith(isSending: true));
    final Map<String, bool> results = <String, bool>{};
    for (final String target in state.targets) {
      final bool ok = await nim.sendText(toAccount: target, text: body);
      results[target] = ok;
      emit(state.copyWith(sendResults: Map<String, bool>.from(results)));
    }
    emit(state.copyWith(isSending: false));
  }
}
