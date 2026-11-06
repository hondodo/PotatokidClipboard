import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pscreen_home/app/config/app_flavor.dart';
import 'package:pscreen_home/core/di/injection.dart';
import 'package:pscreen_home/core/router/route_names.dart';
import 'package:pscreen_home/core/server/account_session.dart';
import 'package:pscreen_home/features/parental/data/parental_admin_api.dart';
import 'package:pscreen_home/features/parental/domain/parental_config.dart';
import 'package:pscreen_home/features/parental/presentation/parental_device_manager_sheet.dart';
import 'package:pscreen_home/features/parental/presentation/parental_realtime_settings_sheet.dart';
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
  const ParentalPage({super.key, this.api});

  /// 测试注入；正式运行时使用默认管理端接口。
  final ParentalAdminApi? api;

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

  ParentalAdminApi get _api => widget.api ?? const ParentalAdminApi();

  List<ParentalMachine> _machines = const <ParentalMachine>[];

  /// 尚未绑定到本账号、可自助认领的电视；解绑后设备会回到这里。
  List<ParentalMachine> _availableMachines = const <ParentalMachine>[];
  ParentalMachine? _selected;
  ParentalConfig _config = ParentalConfig.empty;
  List<RealtimeEvent> _watchEvents = const <RealtimeEvent>[];
  List<RealtimeEvent> _activeEvents = const <RealtimeEvent>[];
  List<RealtimeEvent> _unlockEvents = const <RealtimeEvent>[];
  /// 解锁回执（谁解锁 / 结果码），与请求按短码关联展示。
  List<RealtimeEvent> _unlockAckEvents = const <RealtimeEvent>[];
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
    _connSub = _channel?.connectionState.listen((RealtimeConnectionState state) {
      if (state != RealtimeConnectionState.connected) return;
      if (!AccountSession.isParentOrAdmin) return;
      unawaited(_loadEvents());
      unawaited(_loadParentalSessions());
    });
    _eventSub = _channel?.events.listen(_onRealtimeEvent);
    // 空态也要能显示「当前登录账号」，不依赖角色校验是否通过。
    unawaited(_loadMyAccount());
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
      setState(() => _unlockEvents = _dedupeUnlock(<RealtimeEvent>[..._unlockEvents, event]));
    } else if (event.event == 'parental_unlock_ack') {
      setState(() => _unlockAckEvents = _dedupeUnlock(<RealtimeEvent>[..._unlockAckEvents, event]));
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
  static List<RealtimeEvent> _withEvent(List<RealtimeEvent> list, RealtimeEvent event) {
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

  /// 读取当前生效账号（`<flavor>.<kind>.<设备号>`），空态用于告知用户身份。
  Future<void> _loadMyAccount() async {
    final String account = (await DeviceCredentials.account()).trim();
    if (!mounted || account == _myAccount) return;
    setState(() => _myAccount = account);
  }

  /// 空态「刷新」：重新登录一次刷新角色；成功后由 roleNotifier 切到正常页面。
  Future<void> _refreshPermission() async {
    if (_loading) return;
    setState(() => _loading = true);
    final bool ok = await AccountSession.loginWithSaved();
    await _loadMyAccount();
    if (!mounted) return;
    setState(() => _loading = false);
    if (!ok) {
      _hint('权限检测失败：请检查服务端连接后重试', error: true);
    } else if (!AccountSession.isParentOrAdmin) {
      _hint('已重新检测：当前账号仍无家长权限');
    }
  }

  /// 空态「设置」：进完整设置页（与中控右上角齿轮同一目标）。
  void _openAppSettings() {
    context.push(RouteNames.settingsPath);
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
      await _api.ensureAdminSession(username: account, passwordMd5: DeviceCredentials.passwordMd5());
      final List<ParentalMachine> machines = await _api.fetchMachines();
      final List<ParentalMachine> available = await _api.fetchAvailableMachines();
      // 家长控制只处理电视；中控屏（home）与家长端（parent）都没有儿童模式，
      // 也不参与家长绑定。
      final List<ParentalMachine> tvs = machines
          .where((ParentalMachine machine) => machine.kind == 'tv')
          .toList(growable: false);
      final List<ParentalMachine> availableTvs = available
          .where((ParentalMachine machine) => machine.kind == 'tv')
          .toList(growable: false);
      // parent 只看绑定到自己名下的 TV（多家长绑定）；admin 放开全部电视。
      final List<ParentalMachine> visible = AccountSession.isAdmin
          ? tvs
          : tvs.where((ParentalMachine machine) => machine.parents.contains(account)).toList(growable: false);
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
        _availableMachines = AccountSession.isAdmin ? const <ParentalMachine>[] : availableTvs;
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
      final List<RealtimeEvent> watch = await channel.fetchEvents(event: 'parental_watch', limit: 100);
      final List<RealtimeEvent> active = await channel.fetchEvents(event: 'parental_child_active', limit: 20);
      final List<RealtimeEvent> unlock = await channel.fetchEvents(event: 'parental_unlock_request', limit: 50);
      final List<RealtimeEvent> acks = await channel.fetchEvents(event: 'parental_unlock_ack', limit: 50);
      if (!mounted) return;
      setState(() {
        _watchEvents = watch;
        _activeEvents = active;
        _unlockEvents = _dedupeUnlock(unlock);
        _unlockAckEvents = _dedupeUnlock(acks);
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
    final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(context);
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

  /// 档案 / 设置保存：先乐观更新，再用服务端返回的落盘值校正。
  ///
  /// 曾出现「选了答题解锁、保存后电视仍是短码」：请求虽 2xx，但服务端存
  /// 的仍是 remote。这里直接用响应里的 parental 回读，模式不一致就明确
  /// 告警，避免界面假装已保存。答题模式还会提前检查题库，题库为空/只有
  /// 填空题时电视会回退短码页，保存时就要说明。
  Future<void> _saveConfig(ParentalConfig next) async {
    final ParentalMachine? machine = _selected;
    if (machine == null) {
      _hint('未选择设备，无法保存', error: true);
      return;
    }
    setState(() => _config = next);
    try {
      final ParentalConfig saved = await _api.saveParental(machine.id, next.toJson());
      if (!mounted || _selected?.id != machine.id) return;
      setState(() => _config = saved);
      if (next.unlockMode == 'quiz' && saved.unlockMode != 'quiz') {
        _hint('保存未生效：服务端返回的解锁方式仍是「${saved.unlockMode}」，请重试', error: true);
        return;
      }
      final String? warning =
          next.unlockMode == 'quiz' ? await _quizEmptyWarning(machine, next) : null;
      if (!mounted) return;
      _hint(warning ?? '已保存', error: warning != null);
    } catch (error) {
      _hint('保存失败：$error', error: true);
      unawaited(_loadConfig());
    }
  }

  /// 答题解锁缺可用选择题时的告警文案（无问题返回 null）。
  ///
  /// 与电视端同一口径：跳过填空题、缺选项/答案的题；优先只看当前观看的
  /// 孩子，没有 activeChildIds 时检查全部档案。
  Future<String?> _quizEmptyWarning(ParentalMachine machine, ParentalConfig config) async {
    final List<String> childIds = config.activeChildIds.isNotEmpty
        ? config.activeChildIds
        : config.children.map((ParentalChild child) => child.id).toList(growable: false);
    try {
      for (final String childId in childIds) {
        final List<Map<String, dynamic>> questions = await _api.fetchQuiz(machine.id, childId);
        if (questions.any(_isUsableChoice)) return null;
      }
    } catch (_) {
      // 题库查询失败不阻塞保存；电视机锁屏仍会给出回退提示。
      return null;
    }
    return '已保存，但该设备题库为空或只有填空题：电视会回退短码解锁，请先在儿童档案里添加选择题';
  }

  static bool _isUsableChoice(Map<String, dynamic> question) {
    if ('${question['type'] ?? ''}'.trim() != 'choice') return false;
    final dynamic options = question['options'];
    final dynamic answers = question['answers'];
    return options is List && options.isNotEmpty && answers is List && answers.isNotEmpty;
  }

  /// 解锁记录补发 / 弹层之外的主动解锁：向事件来源 TV 下发 parental_unlock。
  ///
  /// `sendText` 在「通道未连接」和「服务端拒绝（ok:false）」都返回 false，
  /// 必须按连接状态分开告知，否则会把「无权限 / 电视离线」误报成断线。
  Future<void> _sendUnlock(RealtimeEvent event) async {
    final String code = '${event.data['code'] ?? ''}'.trim();
    final String to = event.from.trim();
    final RealtimeChannel? channel = _channel;
    if (channel == null || !channel.isConnected) {
      _hint('发送失败：实时通道未连接，请等待自动重连后重试（也可稍后在「解锁记录」补发）', error: true);
      return;
    }
    if (code.isEmpty || to.isEmpty) {
      _hint('发送失败：该记录缺少短码或来源设备', error: true);
      return;
    }
    final bool ok = await channel.sendText(
      to: to,
      body: buildCommandEnvelope('parental_unlock', <String, dynamic>{'code': code}),
    );
    if (!ok) {
      final ParentalMachine? machine = _selected;
      final bool bound = machine == null || machine.parents.contains(_myAccount);
      _hint(
        bound
            ? '发送失败：服务端未受理（电视可能已离线，请确认电视开机联网）'
            : '发送失败：当前账号未绑定该电视，服务端按「无权限」拒绝（请先补绑）',
        error: true,
      );
      return;
    }
    _hint('已发送解锁命令（短码有效性由电视端校验）');
    unawaited(_loadEvents());
  }

  /// 遥控快捷入口：命令信封直发被控设备（与会话页同一投递通道）。
  Future<void> _sendRemoteCommand(String to, String command) async {
    final RealtimeChannel? channel = _channel;
    final bool ok = channel != null && await channel.sendText(to: to, body: command);
    _hint(ok ? '已发送' : '发送失败（设备离线或通道未连接）', error: !ok);
  }

  /// 家长身份右上角设置：展示「遥控（实时通道）」状态并允许修改实时账号。
  Future<void> _openSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const ParentalRealtimeSettingsSheet(),
    );
  }

  /// 设备管理：扫码添加、绑定 / 解绑；解绑不删除服务端设备记录。
  Future<void> _openDeviceManager() async {
    if (!AccountSession.isParent) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => ParentalDeviceManagerSheet(
        bound: _machines,
        available: _availableMachines,
        onBind: (String deviceId) => _bindDevice(deviceId, bind: true),
        onUnbind: (String deviceId) => _bindDevice(deviceId, bind: false),
        onScanBind: _bindScannedAccount,
      ),
    );
    if (mounted) unawaited(_reload());
  }

  Future<String?> _bindDevice(String deviceId, {required bool bind}) async {
    try {
      await _api.bindDevice(deviceId, bind: bind);
      unawaited(_reload());
      return null;
    } catch (error) {
      return bind ? '绑定失败：$error' : '解绑失败：$error';
    }
  }

  /// 电视二维码内容是实时通信账号；用 overview 的设备清单解析成 `deviceId`。
  Future<String?> _bindScannedAccount(String account) async {
    try {
      final List<ParentalMachine> bound = await _api.fetchMachines();
      final List<ParentalMachine> available = await _api.fetchAvailableMachines();
      ParentalMachine? target;
      for (final ParentalMachine machine in <ParentalMachine>[...bound, ...available]) {
        final String id = machine.id;
        if (machine.commAccount == account || id == account || id.replaceAll('-', '') == account) {
          target = machine;
          break;
        }
      }
      if (target == null) {
        return '未找到账号为 $account 的电视，请确认电视已开机并上报过服务端';
      }
      final String targetId = target.id;
      if (bound.any((ParentalMachine machine) => machine.id == targetId)) {
        return null; // 已绑定，视为成功
      }
      await _api.bindDevice(targetId);
      unawaited(_reload());
      return null;
    } catch (error) {
      return '绑定失败：$error';
    }
  }

  /// 模块⑥ 账号一致性引导：以设备绑定的 `parents` 为准。
  ///
  /// 多家长模型下一台 TV 可绑定多个家长，只要当前登录账号在 `parents`
  /// 中就算一致（解锁请求会经服务端扇出到所有绑定家长，无需再比对旧的
  /// 单值 `ownerAccount`）。仅当 TV 尚未绑定任何家长（admin 视角）时才
  /// 回落到 `parental.ownerAccount` / `machine.owner` 提示。
  Widget? _ownerBanner() {
    final ParentalMachine? machine = _selected;
    if (machine == null || _myAccount.isEmpty) return null;
    if (machine.parents.contains(_myAccount)) return null;
    final String expected = machine.parents.isNotEmpty
        ? machine.parents.join('、')
        : (_config.ownerAccount.isNotEmpty ? _config.ownerAccount : machine.owner);
    if (expected.isEmpty) return null;
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
                '账号不一致：当前登录 $_myAccount，这台 TV 的绑定家长是 $expected，'
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
      final String role = AccountSession.role;
      final String roleText = role.isEmpty ? '未确定（按 user 处理）' : role;
      return Scaffold(
        appBar: AppBar(
          title: const Text('家长视图'),
          // 空态不提供返回箭头：parent 变体没有中控台，返回只会落到无权限页面。
          automaticallyImplyLeading: false,
          actions: <Widget>[
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else
              IconButton(
                tooltip: '刷新（重新检测权限）',
                icon: const Icon(Icons.refresh),
                onPressed: () => unawaited(_refreshPermission()),
              ),
            // 与中控右上角齿轮同一目标，未登录家长角色也能进设置页。
            IconButton(
              tooltip: '设置',
              icon: const Icon(Icons.settings_outlined),
              onPressed: _openAppSettings,
            ),
          ],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.block, size: 40),
                const SizedBox(height: 12),
                const Text('当前账号没有家长权限（需 parent / admin 角色）'),
                const SizedBox(height: 16),
                // 明确告知当前身份，避免不知道自己在用什么号。
                SelectableText(
                  '当前登录账号：${_myAccount.isEmpty ? '检测中…' : _myAccount}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  '当前角色：$roleText',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Text(
                  role.isEmpty
                      ? '角色尚未校验成功（登录失败或服务端不可达），点右上角刷新重新检测。'
                      : '该账号在服务端只有 user 角色；可在管理后台「用户与家庭」把角色改为「家长」后，点右上角刷新重新检测。',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 模块⑥账号一致性横幅：与账号一致时返回 null，不占列表位。
    final Widget? ownerBanner = _ownerBanner();

    // 家长身份锁定：去掉左上角返回并拦截系统返回，不能退回中控台；
    // admin 保持原导航（可返回中控台）。
    final bool locked = AccountSession.isParent;
    return PopScope(
      canPop: !locked,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop || !locked) return;
        _hint(
          AppFlavorConfig.isParentOnly
              ? '家长视图已锁定'
              : '家长视图已锁定，无法返回中控台',
        );
      },
      child: DefaultTabController(
        length: _tabs.length,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('家长视图'),
            automaticallyImplyLeading: !locked,
            actions: <Widget>[
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else
                IconButton(tooltip: '刷新', icon: const Icon(Icons.refresh), onPressed: () => unawaited(_reload())),
              // 家长身份只开放「遥控（实时通道）」的状态与实时账号修改，其它设置不可见。
              if (AccountSession.isParent)
                IconButton(
                  tooltip: '设置',
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => unawaited(_openSettings()),
                ),
              // admin 复用家长视图后的返回口（parent 的默认首页就是本页）。
              // parent 变体没有中控台，即使 admin 登录也不提供该入口。
              if (AccountSession.isAdmin && !AppFlavorConfig.isParentOnly)
                TextButton(onPressed: () => context.go(RouteNames.home), child: const Text('中控台')),
            ],
            bottom: TabBar(
              isScrollable: true,
              tabs: _tabs
                  .map((_TabSpec tab) => Tab(icon: Icon(tab.icon, size: 20), text: tab.label))
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
                        Expanded(child: Text(_error!, style: Theme.of(context).textTheme.bodySmall)),
                        IconButton(
                          tooltip: '重试',
                          icon: const Icon(Icons.refresh, size: 18),
                          onPressed: () => unawaited(_reload()),
                        ),
                      ],
                    ),
                  ),
                ),
              // 家长即使暂时没有已绑定设备也保留入口，便于扫码添加。
              if (_machines.isNotEmpty || AccountSession.isParent) _buildMachineSelector(),
              ?ownerBanner,
              Expanded(
                child: TabBarView(
                  children: <Widget>[
                    _buildRemoteTab(),
                    ChildrenSection(
                      config: _config,
                      onSave: _saveConfig,
                      deviceId: _selected?.id,
                    ),
                    WatchSection(
                      config: _config,
                      machine: _selected,
                      watchEvents: _watchEvents,
                      activeEvents: _activeEvents,
                      sessions: _sessions,
                    ),
                    UnlockSection(
                      events: _unlockEvents,
                      onUnlock: _sendUnlock,
                      machine: _selected,
                      acks: _unlockAckEvents,
                      isAdmin: AccountSession.isAdmin,
                      myAccount: _myAccount,
                      onManageDevices:
                          AccountSession.isParent ? () => unawaited(_openDeviceManager()) : null,
                    ),
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
            child: _machines.isEmpty
                ? Text(
                    '未绑定设备，点右侧扫码添加',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline),
                  )
                : DropdownButtonHideUnderline(
                    child: DropdownButton<ParentalMachine>(
                      isExpanded: true,
                      value: selected,
                      items: _machines
                          .map(
                            (ParentalMachine machine) => DropdownMenuItem<ParentalMachine>(
                              value: machine,
                              child: Text(
                                '${(machine.name.isEmpty || machine.name == '未命名设备') ? machine.id : machine.name}'
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
                        // 下拉菜单打开期间 _reload 可能已把 _machines 换成全新
                        // 实例（菜单仍持有打开时捕获的旧实例），直接写入会导致
                        // DropdownButton 按 == 找不到匹配项而断言失败；按 id 取回
                        // 当前列表里的同一个实例。
                        ParentalMachine? picked;
                        for (final ParentalMachine item in _machines) {
                          if (item.id == machine.id) {
                            picked = item;
                            break;
                          }
                        }
                        if (picked == null) return; // 设备已被移除，忽略本次选择
                        setState(() {
                          _selected = picked;
                          _config = ParentalConfig.empty;
                        });
                        unawaited(_loadConfig());
                      },
                    ),
                  ),
          ),
          // 家长专用：扫码添加任意有效电视 / 解绑（解绑不删除设备记录）。
          if (AccountSession.isParent)
            IconButton(
              tooltip: '添加/解绑设备',
              icon: const Icon(Icons.qr_code_scanner),
              onPressed: () => unawaited(_openDeviceManager()),
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
        onCommand: (String command) => unawaited(_sendRemoteCommand(account, command)),
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
