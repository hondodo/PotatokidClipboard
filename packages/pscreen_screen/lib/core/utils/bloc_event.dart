import 'dart:async';

/// 完成一次性 BLoC 事件：把异步执行结果回传给事件的发起方。
///
/// 约定：需要「等待事件完成」的事件内携带 `final Completer<bool>? completer;`，
/// 处理器末尾调用本方法，调用方 `await completer.future` 即可拿到成败结果。
void completeBlocEvent(Completer<bool>? completer, {required bool success}) {
  if (completer == null || completer.isCompleted) return;
  completer.complete(success);
}
