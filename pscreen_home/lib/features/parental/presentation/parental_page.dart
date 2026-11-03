import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pscreen_home/core/di/injection.dart';
import 'package:pscreen_home/core/router/route_names.dart';
import 'package:pscreen_home/core/server/account_session.dart';
import 'package:pscreen_home/features/parental/data/parental_admin_api.dart';
import 'package:pscreen_home/features/parental/domain/parental_config.dart';
import 'package:pscreen_home/features/parental/presentation/parental_sections.dart';
import 'package:pscreen_home/features/remote_control/presentation/widgets/target_remote_panel.dart';
import 'package:pscreen_screen/core/network/realtime_channel.dart';
import 'package:pscreen_screen/core/utils/device_credentials.dart';
import 'package:pscreen_screen/features/msg/protocol/envelope_builder.dart';

/// 家长视图（方案 4.2 模块①-⑥ 的承载页）。
///
/// - `parent` 登录后的默认首页；`admin` 经设置页入口进入（代管 / 救急，
///   放开 owner 过滤看全部 TV——现状没有独立 admin 视图，直接复用本页
///   代码，风险 #13 的取舍）；`user` 无入口且本页有角色闸门。
/// - 模块：①儿童档案 CRUD ②当前观看者 + 分档案当日时长 ③解锁请求记录
///   （短码未过期可补发）④设置（ownerAccount / 解锁方式 / PIN）
///   ⑤遥控快捷入口（只渲染遥控面板，不打开完整中控台）⑥账号一致性引导。
/// - 档案读写走管理端接口（`GET /api/device/config` 读、
///   `PUT /api/admin/machines/:id` 写 parental 字段）。
class ParentalPage extends StatefulWidget {
  const ParentalPage({super.key});

  @override
  State<ParentalPage> createState() => _ParentalPageState();
}

class _ParentalPageState extends State<ParentalPage> {
  static const List<_TabSpec> _tabs = <_TabSpec>[
    _TabSpec('遥控', Icons.settings_remote_outlined),
    _TabSpec('档案', Icons.child_care_outlined),
    _TabSpec('观看者', Icons.visibility_outlined),
    _TabSpec('解锁', Icons.lock_open_outlined),
    _TabSpec('设置', Icons.tune_outlined),
  ];

  final ParentalAdminApi _api = const ParentalAdminApi();

  List<ParentalMachine> _machines = const <ParentalMachine>[];
  ParentalMachine? _selected;
  ParentalConfig _config = ParentalConfig.empty;
  List<RealtimeEvent> _watchEvents = const <RealtimeEvent>[];
  List<RealtimeEvent> _activeEvents = const <RealtimeEvent>[];
  List<RealtimeEvent> _unlockEvents = const <RealtimeEvent>[];
  List<ParentalSession> _sessions = const <ParentalSession>[];
  String _myAccount = '';
  bool _loading = false;
  String? _error;

  /// 实时通道连接状态：页面常在通道未连上时构建，连上后要补拉一次事件，
  /// 否则「观看者 / 解锁」会一直停在空态。
  StreamSubscription<RealtimeConnectionState>? _connSub;

  /// 在线期间新到的 parental_* 事件（服务端按绑定家长扇出）。
  StreamSubscription<RealtimeEvent>? _eventSub;

  RealtimeChannel? get _channel {
    if (!Injection.isRegistered<RealtimeChannel>()) return null;
    return Injection.get<RealtimeChannel>();
  }

  @override
  void initState() {
    super.initState();
    AccountSession.roleNotifier.addListener(_onRoleChanged);
    _connSub = _channel?.connectionState.listen((
      RealtimeConnectionState state,
    ) {
      if (state != RealtimeConnectionState.connected) return;
      if (!AccountSession.isParentOrAdmin) return;
      unawaited(_loadEvents());
      unawaited(_loadParentalSessions());
    });
    _eventSub = _channel?.events.listen(_onRealtimeEvent);
    if (AccountSession.isParentOrAdmin) unawaited(_reload());
  }

  @override
  void dispose() {
    AccountSession.roleNotifier.removeListener(_onRoleChanged);
    _connSub?.cancel();
    _eventSub?.cancel();
    super.dispose();
  }

  /// 在线事件增量并入「观看者 / 解锁」，避免必须手动刷新才能看到新记录。
  void _onRealtimeEvent(RealtimeEvent event) {
    if (!mounted || !AccountSession.isParentOrAdmin) return;
    if (event.event == 'parental_watch') {
      setState(() => _watchEvents = _withEvent(_watchEvents, event));
    } else if (event.event == 'parental_child_active') {
      setState(() => _activeEvents = _withEvent(_activeEvents, event));
    } else if (event.event == 'parental_unlock_request') {
      setState(
        () => _unlockEvents = _dedupeUnlock(<RealtimeEvent>[
          ..._unlockEvents,
          event,
        ]),
      );
    }
  }

  /// 电视端同一请求会「owner 直投 + 管理员」双发（id 不同、短码相同）；
  /// 按来源 + 短码去重，取较新的一条。
  static List<RealtimeEvent> _dedupeUnlock(List<RealtimeEvent> events) {
    final Map<String, RealtimeEvent> latest = <String, RealtimeEvent>{};
    for (final RealtimeEvent event in events) {
      final String code = '${event.data['code'] ?? ''}'.trim();
      final String key = code.isEmpty ? event.id : '${event.from}|$code';
      final RealtimeEvent? current = latest[key];
      if (current == null || event.ts > current.ts) latest[key] = event;
    }
    final List<RealtimeEvent> result = latest.values.toList(growable: false);
    result.sort((RealtimeEvent a, RealtimeEvent b) => a.ts.compareTo(b.ts));
    return result;
  }

  /// 按 id 去重（服务端双发/重连补发可能同 id），并按时间升序排列。
  static List<RealtimeEvent> _withEvent(
    List<RealtimeEvent> list,
    RealtimeEvent event,
  ) {
    if (list.any((RealtimeEvent item) => item.id == event.id)) return list;
    final List<RealtimeEvent> next = <RealtimeEvent>[...list, event];
    next.sort((RealtimeEvent a, RealtimeEvent b) => a.ts.compareTo(b.ts));
    return next;
  }

  /// 后台刷新登录可能在页面构建之后才写回角色；角色变化时重新判定权限。
  void _onRoleChanged() {
    if (!mounted) return;
    final bool allowed = AccountSession.isParentOrAdmin;
    setState(() {});
    if (allowed && _machines.isEmpty) unawaited(_reload());
  }

  /// 拉设备清单（含 owner 过滤）→ 生效 parental 配置 → 事件历史。
  Future<void> _reload() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final String account = (await DeviceCredentials.account()).trim();
      await _api.ensureAdminSession(
        username: account,
        passwordMd5: DeviceCredentials.passwordMd5(),
      );
      final List<ParentalMachine> machines = await _api.fetchMachines();
      // parent 只看绑定到自己名下的 TV（多家长绑定）；admin 放开代管全部。
      final List<ParentalMachine> visible = AccountSession.isAdmin
          ? machines
          : machines
                .where(
                  (ParentalMachine machine) =>
                      machine.parents.contains(account) ||
                      machine.owner == account,
                )
                .toList(growable: false);
      // 重新拉取后设备列表是全新实例：按 id 找回选中项，且必须使用新列表
      // 里的同一个实例，否则 DropdownButton 按 == 比较会找不到匹配项。
      final String previousId = _selected?.id ?? '';
      ParentalMachine? selected;
      for (final ParentalMachine machine in visible) {
        if (machine.id == previousId) {
          selected = machine;
          break;
        }
      }
      selected ??= visible.isEmpty ? null : visible.first;
      if (!mounted) return;
      setState(() {
        _myAccount = account;
        _machines = visible;
        _selected = selected;
      });
      await _loadConfig();
      await _loadEvents();
      await _loadParentalSessions();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadConfig() async {
    final ParentalMachine? machine = _selected;
    if (machine == null) return;
    try {
      final ParentalConfig config = await _api.fetchParental(machine.id);
      if (!mounted || _selected?.id != machine.id) return;
      setState(() => _config = config);
    } catch (error) {
      if (mounted) setState(() => _error = '读取儿童模式配置失败：$error');
    }
  }

  /// 当日观看时长与解锁记录都来自事件历史（`case 'events'`）。
  Future<void> _loadEvents() async {
    final RealtimeChannel? channel = _channel;
    if (channel == null || !channel.isConnected) return;
    try {
      final List<RealtimeEvent> watch = await channel.fetchEvents(
        event: 'parental_watch',
        limit: 100,
      );
      final List<RealtimeEvent> active = await channel.fetchEvents(
        event: 'parental_child_active',
        limit: 20,
      );
      final List<RealtimeEvent> unlock = await channel.fetchEvents(
        event: 'parental_unlock_request',
        limit: 50,
      );
      if (!mounted) return;
      setState(() {
        _watchEvents = watch;
        _activeEvents = active;
        _unlockEvents = _dedupeUnlock(unlock);
      });
    } catch (_) {
      // 事件查询依赖 WS 在线；失败不阻塞档案 / 设置等模块。
    }
  }

  /// 会话级观看记录走 HTTP，避免实时通道未连接时看不到历史。
  Future<void> _loadParentalSessions() async {
    try {
      final List<ParentalSession> sessions = await _api.fetchParentalSessions();
      if (!mounted) return;
      setState(() => _sessions = sessions);
    } catch (_) {
      // 记录查询失败不阻塞档案 / 设置。
    }
  }

  void _hint(String message, {bool error = false}) {
    if (!mounted) return;
    final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(
      context,
    );
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: error ? Theme.of(context).colorScheme.error : null,
        ),
      );
  }

  /// 档案 / 设置保存：先乐观更新，失败回读服务端真实值。
  Future<void> _saveConfig(ParentalConfig next) async {
    final ParentalMachine? machine = _selected;
    if (machine == null) {
      _hint('未选择设备，无法保存', error: true);
      return;
    }
    setState(() => _config = next);
    try {
      await _api.saveParental(machine.id, next.toJson());
      _hint('已保存');
    } catch (error) {
      _hint('保存失败：$error', error: true);
      unawaited(_loadConfig());
    }
  }

  /// 解锁记录补发 / 弹层之外的主动解锁：向事件来源 TV 下发 parental_unlock。
  Future<void> _sendUnlock(RealtimeEvent event) async {
    final String code = '${event.data['code'] ?? ''}'.trim();
    final String to = event.from.trim();
    final RealtimeChannel? channel = _channel;
    final bool ok =
        channel != null &&
        code.isNotEmpty &&
        to.isNotEmpty &&
        await channel.sendText(
          to: to,
          body: buildCommandEnvelope('parental_unlock', <String, dynamic>{
            'code': code,
          }),
        );
    _hint(ok ? '已发送解锁命令（短码有效性由电视端校验）' : '发送失败：实时通道未连接', error: !ok);
    if (ok) unawaited(_loadEvents());
  }

  /// 遥控快捷入口：命令信封直发被控设备（与会话页同一投递通道）。
  Future<void> _sendRemoteCommand(String to, String command) async {
    final RealtimeChannel? channel = _channel;
    final bool ok =
        channel != null && await channel.sendText(to: to, body: command);
    _hint(ok ? '已发送' : '发送失败（设备离线或通道未连接）', error: !ok);
  }

  /// 模块⑥ 账号一致性引导：当前登录账号 vs `parental.ownerAccount`
  /// / `machine.owner` 不一致时提示收不到解锁请求直投。
  Widget? _ownerBanner() {
    final ParentalMachine? machine = _selected;
    if (machine == null || _myAccount.isEmpty) return null;
    final String expected = _config.ownerAccount.isNotEmpty
        ? _config.ownerAccount
        : machine.owner;
    if (expected.isEmpty || expected == _myAccount) return null;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      color: scheme.errorContainer.withValues(alpha: 0.5),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          children: <Widget>[
            Icon(Icons.warning_amber_rounded, size: 18, color: scheme.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '账号不一致：当前登录 $_myAccount，这台 TV 的家长账号是 $expected，'
                '收不到解锁请求直投；仍可经该 TV 的会话线程只读查看。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 角色闸门：user 即使经深链进入也不提供任何家长能力（口径「能弹 = 能点」）。
    if (!AccountSession.isParentOrAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('家长视图')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.block, size: 40),
                const SizedBox(height: 12),
                const Text('当前账号没有家长权限（需 parent / admin 角色）'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => context.go(RouteNames.home),
                  child: const Text('返回中控台'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 模块⑥账号一致性横幅：与账号一致时返回 null，不占列表位。
    final Widget? ownerBanner = _ownerBanner();

    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('家长视图'),
          actions: <Widget>[
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              IconButton(
                tooltip: '刷新',
                icon: const Icon(Icons.refresh),
                onPressed: () => unawaited(_reload()),
              ),
            // admin 复用家长视图后的返回口（parent 的默认首页就是本页）。
            if (AccountSession.isAdmin)
              TextButton(
                onPressed: () => context.go(RouteNames.home),
                child: const Text('中控台'),
              ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabs: _tabs
                .map(
                  (_TabSpec tab) =>
                      Tab(icon: Icon(tab.icon, size: 20), text: tab.label),
                )
                .toList(growable: false),
          ),
        ),
        body: Column(
          children: <Widget>[
            if (_error != null)
              Card(
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          _error!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      IconButton(
                        tooltip: '重试',
                        icon: const Icon(Icons.refresh, size: 18),
                        onPressed: () => unawaited(_reload()),
                      ),
                    ],
                  ),
                ),
              ),
            if (_machines.isNotEmpty) _buildMachineSelector(),
            ?ownerBanner,
            Expanded(
              child: TabBarView(
                children: <Widget>[
                  _buildRemoteTab(),
                  ChildrenSection(config: _config, onSave: _saveConfig),
                  WatchSection(
                    config: _config,
                    watchEvents: _watchEvents,
                    activeEvents: _activeEvents,
                    sessions: _sessions,
                  ),
                  UnlockSection(events: _unlockEvents, onUnlock: _sendUnlock),
                  ParentalSettingsSection(
                    // 换设备重建编辑态，避免残留上一台的输入。
                    key: ValueKey<String>(_selected?.id ?? 'none'),
                    config: _config,
                    machine: _selected,
                    onSave: _saveConfig,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMachineSelector() {
    final ParentalMachine? selected = _selected;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: <Widget>[
          const Icon(Icons.tv_outlined, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<ParentalMachine>(
                isExpanded: true,
                value: selected,
                items: _machines
                    .map(
                      (
                        ParentalMachine machine,
                      ) => DropdownMenuItem<ParentalMachine>(
                        value: machine,
                        child: Text(
                          '${machine.name.isEmpty ? machine.id : machine.name}'
                          '${machine.online ? '' : '（离线）'}'
                          '${machine.owner.isEmpty ? '' : ' · ${machine.owner}'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (ParentalMachine? machine) {
                  if (machine == null) return;
                  setState(() {
                    _selected = machine;
                    _config = ParentalConfig.empty;
                  });
                  unawaited(_loadConfig());
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 模块⑤ 遥控快捷入口：只渲染遥控面板（TargetRemotePanel → 面板注册表
  /// → 直播控制行来自 live_remote_panel），不打开完整中控台。
  Widget _buildRemoteTab() {
    final ParentalMachine? machine = _selected;
    final String account = machine?.commAccount ?? '';
    if (account.isEmpty) {
      return const Center(child: Text('未选择可遥控的设备'));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: TargetRemotePanel(
        account: account,
        title: machine?.name,
        onCommand: (String command) =>
            unawaited(_sendRemoteCommand(account, command)),
      ),
    );
  }
}

/// 家长视图的标签页规格。
class _TabSpec {
  const _TabSpec(this.label, this.icon);

  final String label;
  final IconData icon;
}
