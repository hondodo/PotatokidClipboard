part of 'send_cubit.dart';

class SendState extends Equatable {
  const SendState({
    this.targets = const <String>[],
    this.sendResults = const <String, bool>{},
    this.isSending = false,
    this.lastBody,
  });

  /// 已勾选的目标账号。
  final List<String> targets;

  /// 逐台发送结果（最新一次发送）。
  final Map<String, bool> sendResults;

  /// 是否正在发送。
  final bool isSending;

  /// 最近一次发送的 body（重试用）。
  final String? lastBody;

  SendState copyWith({
    List<String>? targets,
    Map<String, bool>? sendResults,
    bool? isSending,
    String? lastBody,
  }) =>
      SendState(
        targets: targets ?? this.targets,
        sendResults: sendResults ?? this.sendResults,
        isSending: isSending ?? this.isSending,
        lastBody: lastBody ?? this.lastBody,
      );

  @override
  List<Object?> get props =>
      <Object?>[targets, sendResults, isSending, lastBody];
}
