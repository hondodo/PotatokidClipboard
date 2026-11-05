import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pscreen_home/core/device/device_identity.dart';
import 'package:pscreen_home/core/di/injection.dart';
import 'package:pscreen_home/app/config/app_flavor.dart';
import 'package:pscreen_home/core/server/account_session.dart';
import 'package:pscreen_home/features/remote_control/core/control_log.dart';
import 'package:pscreen_home/features/settings/presentation/widgets/realtime_status_section.dart';
import 'package:pscreen_screen/core/network/realtime_channel.dart';
import 'package:pscreen_screen/core/utils/app_settings.dart';
import 'package:pscreen_screen/core/utils/client_info.dart';
import 'package:pscreen_screen/core/utils/device_credentials.dart';

/// 家长视图右上角「设置」弹层。
///
/// 家长身份只开放「遥控（实时通道）」这一段：连接状态、网关地址、最近错误，
/// 以及**实时账号 / 口令**的修改（保存后立即重连）；屏保、壁纸、界面缩放等
/// 其它设置项一律不出现。
/// [channel] 仅供测试注入，正式运行时由 [RealtimeStatusSection] 从全局
/// 依赖中读取。
class ParentalRealtimeSettingsSheet extends StatefulWidget {
  const ParentalRealtimeSettingsSheet({super.key, this.channel});

  final RealtimeChannel? channel;

  @override
  State<ParentalRealtimeSettingsSheet> createState() => _ParentalRealtimeSettingsSheetState();
}

class _ParentalRealtimeSettingsSheetState extends State<ParentalRealtimeSettingsSheet> {
  final TextEditingController _accountController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _saving = false;

  RealtimeChannel get _channel => widget.channel ?? Injection.get<RealtimeChannel>();

  @override
  void initState() {
    super.initState();
    unawaited(_loadSavedCredentials());
  }

  @override
  void dispose() {
    _accountController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// 异步回显已保存的凭据；用户已经开始输入时不覆盖。
  Future<void> _loadSavedCredentials() async {
    await AppSettings.instance.ensureLoaded();
    if (!mounted) return;
    if (_accountController.text.isEmpty && AppSettings.instance.remoteAccount.isNotEmpty) {
      _accountController.text = AppSettings.instance.remoteAccount;
    }
    if (_passwordController.text.isEmpty && AppSettings.instance.remotePassword.isNotEmpty) {
      _passwordController.text = AppSettings.instance.remotePassword;
    }
  }

  /// 保存实时账号 / 口令并立即重连（失败仅提示，不影响其它功能）。
  ///
  /// 账号留空 = home + 本机设备号（16hex）；口令留空 = 默认 123456。
  /// 重连顺序与启动一致：先 HTTP 登录（账号不存在时按默认口令自动建档），
  /// 再连 ws，否则 ws 握手会因「账号不存在」被拒。
  Future<void> _saveCredentials() async {
    final String account = _accountController.text.trim();
    final String password = _passwordController.text.trim().isEmpty
        ? DeviceCredentials.defaultPassword
        : _passwordController.text.trim();
    setState(() => _saving = true);
    await AppSettings.instance.setRemoteAccount(account);
    await AppSettings.instance.setRemotePassword(password);

    bool ok = false;
    try {
      await _channel.disconnect();
      // 先 HTTP 登录完成账号建档（失败返回 false，不阻断：ws 侧独立报错）。
      await AccountSession.loginWithSaved();
      final ClientInfo info = await ClientInfo.current();
      await _channel
          .connect(
            account: await DeviceCredentials.account(),
            token: DeviceCredentials.passwordMd5(),
            // 与心跳注册同源（android_/gen_ 前缀），服务端据此回写 admin 设备表。
            deviceId: await DeviceIdentity.deviceId(),
            role: 'controller',
            // 家长端默认 `parent`，其余 `home`。
            kind: AppFlavorConfig.deviceKind,
            name: AppFlavorConfig.deviceName,
            app: info.app,
            version: info.version,
            build: info.build,
          )
          .timeout(
            const Duration(seconds: 25),
            onTimeout: () {
              throw const RealtimeException(-3, '连接超时');
            },
          );
      ok = true;
    } catch (e) {
      ControlLog.e('[实时通道] 家长视图保存账号后连接失败: $e');
    }

    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            account.isEmpty ? (ok ? '已恢复默认设备号账号' : '已恢复默认设备号，暂未连接成功') : (ok ? '已保存遥控配置' : '已保存，暂未连接成功（断网时自动重试）'),
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    // 输入法弹起时把整块内容抬到键盘上方；`isScrollControlled: true` 的
    // bottom sheet 才能占满剩余高度，输入框不会落到键盘后面。
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('设置', style: theme.textTheme.titleLarge),
              const SizedBox(height: 16),
              Text('遥控（实时通道）', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                '家长视图可查看遥控通道的连接状态与网关地址，并可修改实时账号；'
                '其它设置项不对家长开放。',
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _accountController,
                decoration: const InputDecoration(
                  labelText: '实时账号',
                  helperText: '留空则用 home + 本机设备号（16位）',
                  border: OutlineInputBorder(),
                ),
                maxLines: 1,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: '实时口令',
                  helperText: '默认 ${DeviceCredentials.defaultPassword}',
                  border: const OutlineInputBorder(),
                ),
                maxLines: 1,
              ),
              const SizedBox(height: 10),
              FilledButton.tonalIcon(
                onPressed: _saving ? null : _saveCredentials,
                icon: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save_rounded),
                label: const Text('保存并重连'),
              ),
              const SizedBox(height: 12),
              RealtimeStatusSection(channel: widget.channel),
            ],
          ),
        ),
      ),
    );
  }
}
