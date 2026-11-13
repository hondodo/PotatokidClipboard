import 'package:flutter/foundation.dart';

/// 家长端最小埋点（3.7）：统一结构化日志，覆盖保存结果、冲突选择、
/// 关联视图刷新失败、账号恢复、题库授权 / 副本导入与答题空题库降级。
///
/// 不引入第三方统计 SDK：先以 `[parental-metric] {json}` 形式落到日志，
/// 后续接统计通道时只替换本类实现。
class ParentalTelemetry {
  const ParentalTelemetry._();

  static void record(String event, {Map<String, Object?>? data}) {
    final StringBuffer buffer = StringBuffer('[parental-metric] $event');
    if (data != null && data.isNotEmpty) {
      buffer.write(' ');
      buffer.write(
        data.entries
            .map((MapEntry<String, Object?> e) => '${e.key}=${e.value}')
            .join(' '),
      );
    }
    debugPrint(buffer.toString());
  }

  /// 实体保存结果：`entity` 取 `familyChild / assignment / quiz / deviceLocal`。
  static void saveResult(
    String entity, {
    required bool ok,
    String? reason,
    int? revision,
  }) {
    record(ok ? 'save_success' : 'save_failure', data: <String, Object?>{
      'entity': entity,
      'reason': ?reason,
      'revision': ?revision,
    });
  }

  /// 冲突发生与用户选择：`choice` 取 `viewDiff / overwrite / discard`。
  static void conflict(String entity, String choice) {
    record('conflict', data: <String, Object?>{'entity': entity, 'choice': choice});
  }

  /// 关联视图刷新失败（保存后回读 / 列表刷新）。
  static void refreshFailure(String entity, Object error) {
    record('refresh_failure', data: <String, Object?>{'entity': entity, 'error': '$error'});
  }

  /// 账号恢复流程：`stage` 取 `exposure / submit / success / failure`。
  static void accountRestore(String stage, {String? reason}) {
    record('account_restore', data: <String, Object?>{
      'stage': stage,
      'reason': ?reason,
    });
  }

  /// 题库授权 / 副本导入结果。
  static void quizShare({required bool ok, String action = 'share'}) {
    record(ok ? 'quiz_share_success' : 'quiz_share_failure', data: <String, Object?>{
      'action': action,
    });
  }
}
