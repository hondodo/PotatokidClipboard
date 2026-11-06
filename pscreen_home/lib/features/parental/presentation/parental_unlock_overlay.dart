import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pscreen_home/core/di/injection.dart';
import 'package:pscreen_home/core/server/account_session.dart';
import 'package:pscreen_home/features/parental/application/parental_unlock_tracker.dart';
import 'package:pscreen_home/features/parental/data/parental_admin_api.dart';
import 'package:pscreen_screen/core/network/realtime_channel.dart';
import 'package:pscreen_screen/core/utils/device_credentials.dart';
import 'package:pscreen_screen/features/msg/protocol/envelope_builder.dart';

/// 全局解锁确认弹层（方案 4.2「事件驱动的全局弹层」）。
///
/// - 任意页面收到 `parental_unlock_request` 即在最上层弹确认卡，
///   不依赖当前所在页面（Stack 盖在 Navigator / 屏保之上）；
/// - 仅 `parent` / `admin` 注册 `events.listen`：`user` 登录即使收到
///   该事件也不弹卡、不可下发 `parental_unlock`（口径「能弹 = 能点」）；
/// - 按短码去重：同一请求双发两条（owner 直投 + 线程可见），同 code
///   已有活动弹层时忽略后到的一条；
/// - 点「解锁」下发 `buildCommandEnvelope('parental_unlock', {code})`，
///   短码 60s 过期与校验由电视端负责。
class ParentalUnlockOverlay extends StatefulWidget {
  const ParentalUnlockOverlay({super.key, required this.child});

  /// 被覆盖的整棵应用子树。
  final Widget child;

  @override
  State<ParentalUnlockOverlay> createState() => _ParentalUnlockOverlayState();
}

class _ParentalUnlockOverlayState extends State<ParentalUnlockOverlay> {
  final ParentalUnlockTracker _tracker = ParentalUnlockTracker();

  StreamSubscription<RealtimeEvent>? _eventSub;
  _UnlockRequest? _pending;
  String _hint = '';
  bool _hintError = false;

  /// 当前账号绑定的电视清单：只弹「该电视绑定家长集合」内的请求；
  /// admin 仍收全量，但弹层标注「代管」。
  List<ParentalMachine> _machines = const <ParentalMachine>[];
  String _myAccount = '';
  bool _machinesLoaded = false;

  RealtimeChannel? get _channel {
    if (!Injection.isRegistered<RealtimeChannel>()) return null;
    return Injection.get<RealtimeChannel>();
  }

  @override
  void initState() {
    super.initState();
    AccountSession.roleNotifier.addListener(_syncSubscription);
    // 初始按当前角色决定是否注册（此时 _pending 必为空，不会触发 setState）。
    _syncSubscription();
    unawaited(_loadMachines());
  }

  /// 拉取当前账号可见的电视清单（admin 为全量），用于来源过滤与名称展示。
  Future<void> _loadMachines() async {
    try {
      _myAccount = (await DeviceCredentials.account()).trim();
      final List<ParentalMachine> machines =
          await const ParentalAdminApi().fetchMachines();
      if (!mounted) return;
      setState(() {
        _machines = machines;
        _machinesLoaded = true;
      });
    } catch (_) {
      // 清单拉取失败不阻塞弹层：退回「服务器已按家长扇出」的默认口径。
    }
  }

  /// `from`（电视的实时账号 / 设备 id）是否属于当前家长可见的电视。
  ///
  /// - admin：全量放行（展示时标「代管」）；
  /// - 家长：只放行绑定到自己账号的电视；清单尚未就绪时不误丢。
  bool _isVisibleFrom(String from) {
    if (AccountSession.isAdmin) return true;
    final String account = from.trim();
    if (account.isEmpty) return false;
    // 清单已就绪：没有匹配绑定关系的来源一律不弹（避免展示其它电视的请求）。
    if (_machinesLoaded && _machines.isEmpty) return false;
    if (!_machinesLoaded) return true;
    for (final ParentalMachine machine in _machines) {
      if (machine.commAccount != account && machine.id != account) continue;
      return machine.parents.contains(_myAccount);
    }
    return false;
  }

  ParentalMachine? _machineOf(String from) {
    for (final ParentalMachine machine in _machines) {
      if (machine.commAccount == from || machine.id == from) return machine;
    }
    return null;
  }

  @override
  void dispose() {
    AccountSession.roleNotifier.removeListener(_syncSubscription);
    _eventSub?.cancel();
    _eventSub = null;
    super.dispose();
  }

  /// 仅 parent/admin 注册事件监听；角色降级（重新登录为 user）时立即注销
  /// 并收起活动弹层。
  void _syncSubscription() {
    if (AccountSession.isParentOrAdmin) {
      if (_eventSub != null) return;
      _eventSub = _channel?.events.listen(_handleEvent);
      // 角色/账号切换后重拉绑定清单（admin 全量 vs 家长绑定集合）。
      unawaited(_loadMachines());
      return;
    }
    _eventSub?.cancel();
    _eventSub = null;
    final _UnlockRequest? pending = _pending;
    if (pending != null && mounted) {
      _tracker.release(pending.code);
      setState(() {
        _pending = null;
        _hint = '';
      });
    }
  }

  void _handleEvent(RealtimeEvent event) {
    if (event.event == 'parental_unlock_ack') {
      _handleAck(event);
      return;
    }
    if (event.event != 'parental_unlock_request') return;
    // 只展示该电视绑定家长集合内的请求（admin 全量，展示时标「代管」）。
    if (!_isVisibleFrom(event.from)) return;
    final String code = '${event.data['code'] ?? ''}'.trim();
    if (code.isEmpty) return;
    // 同码已有活动弹层（双发的第二条 / 迟到重复帧）→ 忽略。
    if (!_tracker.tryAcquire(code)) return;
    if (!mounted) return;
    setState(() {
      _pending = _UnlockRequest(
        code: code,
        from: event.from.trim(),
        reason: '${event.data['reason'] ?? ''}'.trim(),
      );
      _hint = '';
      _hintError = false;
    });
  }

  /// 解锁回执：`ok` / `already-unlocked` 关闭弹层；`expired` / `forbidden`
  /// 保留弹层并提示原因（`forbidden` 由服务端在发送者校验失败时代发）。
  void _handleAck(RealtimeEvent event) {
    final _UnlockRequest? request = _pending;
    if (request == null) return;
    final String code = '${event.data['code'] ?? ''}'.trim();
    if (code.isEmpty || code != request.code) return;
    final String result = '${event.data['result'] ?? ''}'.trim();
    final String actor = '${event.data['actor'] ?? ''}'.trim();
    if (result == 'ok' || result == 'already-unlocked') {
      _close();
      return;
    }
    if (!mounted) return;
    setState(() {
      _hintError = true;
      _hint = switch (result) {
        'expired' => '短码已过期或无效，请在电视上重新请求',
        'forbidden' =>
          '无权限：${actor.isEmpty ? '该账号' : actor} 不是这台电视绑定的家长',
        _ => '解锁失败（${result.isEmpty ? '未知原因' : result}）',
      };
    });
  }

  /// 下发解锁命令；成功后关闭弹层，失败保留弹层并提示（可重试）。
  Future<void> _unlock() async {
    final _UnlockRequest? request = _pending;
    if (request == null) return;
    final RealtimeChannel? channel = _channel;
    final bool ok = channel != null &&
        request.from.isNotEmpty &&
        await channel.sendText(
          to: request.from,
          body: buildCommandEnvelope(
            'parental_unlock',
            <String, dynamic>{'code': request.code},
          ),
        );
    if (!mounted || _pending != request) return;
    if (ok) {
      _close();
      return;
    }
    setState(() {
      _hint = '发送失败（实时通道未连接），可稍后在「解锁记录」补发';
      _hintError = true;
    });
  }

  void _close() {
    final _UnlockRequest? request = _pending;
    if (request == null) return;
    _tracker.release(request.code);
    if (!mounted) return;
    setState(() {
      _pending = null;
      _hint = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final _UnlockRequest? request = _pending;
    if (request == null) return widget.child;
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final ParentalMachine? machine = _machineOf(request.from);
    return Stack(
      children: <Widget>[
        widget.child,
        Positioned.fill(
          child: ModalBarrier(color: Colors.black54, dismissible: false),
        ),
        Positioned.fill(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Icon(Icons.lock_outline, color: scheme.primary),
                            const SizedBox(width: 8),
                            Text(
                              '电视请求解锁',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (AccountSession.isAdmin &&
                                !(machine?.parents.contains(_myAccount) ?? false))
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: scheme.tertiaryContainer,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '代管',
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: scheme.onTertiaryContainer,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '短码 ${request.code}',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (request.from.isNotEmpty)
                          Text(
                            machine == null
                                ? '来源：${request.from}'
                                : '来源：${machine.name.isEmpty ? request.from : machine.name}'
                                  '${machine.parents.contains(_myAccount) ? '' : '（代管）'}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        if (request.reason.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '原因：${request.reason}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        if (_hint.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              _hint,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: _hintError
                                    ? scheme.error
                                    : scheme.primary,
                              ),
                            ),
                          ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: <Widget>[
                            TextButton(
                              onPressed: _close,
                              child: const Text('取消'),
                            ),
                            const SizedBox(width: 8),
                            FilledButton.icon(
                              onPressed: _unlock,
                              icon: const Icon(Icons.lock_open_rounded, size: 18),
                              label: const Text('解锁'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 一条待确认的解锁请求（展示期以短码为唯一键）。
class _UnlockRequest {
  const _UnlockRequest({
    required this.code,
    required this.from,
    required this.reason,
  });

  /// TV 端生成的 6 位短码（60s 有效期，一次性）。
  final String code;

  /// 请求发起方（TV 的实时账号），解锁命令的投递目标。
  final String from;

  /// 触发原因（计时到点 / 禁看时段等）。
  final String reason;
}
