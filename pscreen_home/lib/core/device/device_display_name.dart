/// 设备名称的唯一解析口径（会话列表 / 家长页下拉 / 设备管理 / 遥控标题共用）。
///
/// 优先级：本机备注别名 > 家长私有别名 > 账号展示名（displayName）
/// > 设备备注（machines.json.name）> 账号 id。
///
/// - 本机别名只存在当前中控本地（`remote_sessions.json`）；
/// - 家长别名由服务端按登录账号下发（方案 B，互不可见）；
/// - 「未命名设备」是服务端历史占位符，任何一层出现都当作未设置跳过。
class DeviceDisplayName {
  const DeviceDisplayName._();

  /// 服务端历史占位名；读到它等同于「没有备注」。
  static const String placeholder = '未命名设备';

  static String resolve({
    required String account,
    String localAlias = '',
    String alias = '',
    String displayName = '',
    String machineName = '',
  }) {
    for (final String candidate in <String>[
      localAlias,
      alias,
      displayName,
      machineName,
    ]) {
      final String value = candidate.trim();
      if (value.isEmpty || value == placeholder) continue;
      return value;
    }
    return account.trim();
  }
}
