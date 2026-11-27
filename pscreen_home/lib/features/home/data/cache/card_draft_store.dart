import 'package:flutter/foundation.dart';

/// 卡片选项「暂存」存储：选菜谱时只记录、不下发 HA，点开始时才提交。
///
/// 场景：米家空气炸锅的 `select.mode` 一旦写入 `select_option` 设备就立即启动，
/// 所以模式选择必须拆成两步——选中先存本地，用户点「开始烹饪」再真正下发。
///
/// - 只存内存、不落磁盘：App 进程重启后暂存自动清空，卡片通过
///   `{draft:<后缀>|fallback=s:<后缀>}` 回退显示设备当前值，不会沿用上一次的旧选择；
/// - key 用完整 entityId（渲染阶段 onClick 已 resolve 成完整 id），不同设备互不串扰；
/// - 用 [ValueNotifier] 让卡片在选中后立即重绘（显示当前模式），无需改 HomeState。
class CardDraftStore {
  CardDraftStore._();

  static final CardDraftStore instance = CardDraftStore._();

  /// 当前所有暂存：`{entityId: option}`。value 替换会触发卡片重绘。
  final ValueNotifier<Map<String, String>> drafts =
      ValueNotifier<Map<String, String>>(const <String, String>{});

  /// 读某个实体的暂存选项，无暂存返回空串。
  String read(String entityId) => drafts.value[entityId] ?? '';

  /// 写暂存并立即通知重绘（只改内存，不落盘）。
  void write(String entityId, String option) {
    if (entityId.isEmpty) return;
    final Map<String, String> next = Map<String, String>.from(drafts.value);
    if (option.isEmpty) {
      next.remove(entityId);
    } else {
      next[entityId] = option;
    }
    drafts.value = next;
  }

  /// 提交后清除暂存（点开始烹饪、模式已真正下发时调用）。
  void clear(String entityId) => write(entityId, '');

  /// 测试用：重置内存暂存。
  @visibleForTesting
  void resetForTest() {
    drafts.value = const <String, String>{};
  }
}
