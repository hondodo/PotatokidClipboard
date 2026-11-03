/// 解锁弹层的短码去重器。
///
/// TV 端同一解锁请求按同一短码双发两条 `parental_unlock_request`
/// （① owner 直投 + ② `1000001` 会话线程可见，事件 id 不同、`code`
/// 相同，方案 4.2）；弹层按短码判重：同 `code` 已有活动弹层时忽略
/// 后到的一条。弹层关闭（已解锁 / 取消）后短码在 [handleTtl] 内视为
/// 已处理，吸收迟到的重复帧；短码本身 60s 过期、TV 换新码自然弹新卡
///（过期语义由 TV 端校验，本类只管展示期去重）。
class ParentalUnlockTracker {
  ParentalUnlockTracker({
    this.handleTtl = const Duration(seconds: 60),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// 关闭后短码仍视为「已处理」的时长（覆盖 60s 内的迟到重复帧）。
  final Duration handleTtl;

  final DateTime Function() _now;

  /// 活动弹层持有的短码。
  final Set<String> _active = <String>{};

  /// 已关闭短码 → 处理窗口截止时间。
  final Map<String, DateTime> _handled = <String, DateTime>{};

  /// 活动弹层数量（测试/诊断用）。
  int get activeCount => _active.length;

  /// 尝试为 [code] 打开弹层：空码 / 已有活动弹层 / 关闭后窗口内 → false。
  bool tryAcquire(String code) {
    final String key = code.trim();
    if (key.isEmpty) return false;
    if (_active.contains(key)) return false;
    final DateTime? until = _handled[key];
    if (until != null && _now().isBefore(until)) return false;
    _active.add(key);
    return true;
  }

  /// 弹层关闭：释放活动标记，并把短码计入已处理窗口。
  void release(String code) {
    final String key = code.trim();
    if (key.isEmpty) return;
    _active.remove(key);
    _handled[key] = _now().add(handleTtl);
  }
}
