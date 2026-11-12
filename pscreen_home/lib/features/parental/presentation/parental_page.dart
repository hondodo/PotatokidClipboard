import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pscreen_home/app/config/app_flavor.dart';
import 'package:pscreen_home/core/di/injection.dart';
import 'package:pscreen_home/core/router/route_names.dart';
import 'package:pscreen_home/core/server/account_session.dart';
import 'package:pscreen_home/features/parental/data/parental_admin_api.dart';
import 'package:pscreen_home/features/parental/domain/parental_config.dart';
import 'package:pscreen_home/features/parental/presentation/child_profile_editor.dart';
import 'package:pscreen_home/features/parental/presentation/parental_common.dart';
import 'package:pscreen_home/features/parental/presentation/parental_device_manager_sheet.dart';
import 'package:pscreen_home/features/parental/presentation/parental_mine_tab.dart';
import 'package:pscreen_home/features/parental/presentation/parental_rules_tab.dart';
import 'package:pscreen_home/features/parental/presentation/parental_subpages.dart';
import 'package:pscreen_home/features/parental/presentation/parental_today_page.dart';
import 'package:pscreen_home/features/update/presentation/update_pill.dart';
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
///
/// 页面骨架（5 个领域模块）在此装配；各 Tab 的具体渲染拆分到
/// `parental_today_page.dart` / `parental_rules_tab.dart` / `parental_mine_tab.dart`，
/// 行为副作用通过 [ParentalActions] 下发给这些无状态视图。
class ParentalPage extends StatefulWidget {
  const ParentalPage({super.key, this.api});

  /// 测试注入；正式运行时使用默认管理端接口。
  final ParentalAdminApi? api;

  @override
  State<ParentalPage> createState() => _ParentalPageState();
}

class _ParentalPageState extends State<ParentalPage> {
  static const List<_TabSpec> _tabs = <_TabSpec>[
    _TabSpec('今天', Icons.today_outlined),
    _TabSpec('规则', Icons.rule_outlined),
    _TabSpec('我的', Icons.person_outline),
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
  /// 家长号（管理登录身份，随 claim 变化）。
  String _myAccount = '';
  /// 本机实时通道派生号（设备身份，只读，永不改名/禁用）。
  String _channelAccount = '';
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

  /// 读取两层身份：家长号（管理登录）+ 本机实时通道派生号（设备身份）。
  /// 两者彻底分开，改家长号不影响通道号。
  Future<void> _loadMyAccount() async {
    final String account = (await DeviceCredentials.account()).trim();
    final String channel = (await DeviceCredentials.channelAccount()).trim();
    if (!mounted || (account == _myAccount && channel == _channelAccount)) return;
    setState(() {
      _myAccount = account;
      _channelAccount = channel;
    });
  }

  /// 账号卡第一行「家长号」的展示值。
  ///
  /// [_myAccount] 是**回落的**管理登录账号：未设置独立家长号时它等于派生号。
  /// 若直接拿它展示，第一行会和第二行的通道号一模一样，让人以为重复。
  /// 只有当管理账号与设备派生号不同（即确实设置过家长号）时才显示家长号；
  /// 否则传空，由卡片渲染「未设置（使用设备号）」。
  /// 注意 [_myAccount] 本身仍供绑定校验 / 解锁扇出 / 账号不一致横幅使用，不变。
  String get _parentNoForDisplay =>
      (_myAccount.isNotEmpty &&
              _channelAccount.isNotEmpty &&
              _myAccount != _channelAccount)
          ? _myAccount
          : '';

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
      final String channel = (await DeviceCredentials.channelAccount()).trim();
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
        _channelAccount = channel;
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
        _unlockEvents = unlock;
        _unlockAckEvents = acks;
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
        onRename: _renameDevice,
      ),
    );
    if (mounted) unawaited(_reload());
  }

  /// 设置当前账号的私有别名：服务端成功落盘后才更新本地列表（失败回滚）。
  Future<String?> _renameDevice(String deviceId, String alias) async {
    try {
      final String saved = await _api.saveAlias(deviceId, alias);
      if (!mounted) return null;
      _applyAlias(deviceId, saved);
      return null;
    } catch (error) {
      return '重命名失败：$error';
    }
  }

  /// 用服务端回传的别名原地替换列表项；选中项也换成同一实例，
  /// 避免 DropdownButton 因实例不一致找不到匹配项。
  void _applyAlias(String deviceId, String alias) {
    final List<ParentalMachine> next = _machines
        .map(
          (ParentalMachine machine) =>
              machine.id == deviceId ? machine.copyWith(alias: alias) : machine,
        )
        .toList(growable: false);
    ParentalMachine? selected;
    for (final ParentalMachine machine in next) {
      if (machine.id == _selected?.id) {
        selected = machine;
        break;
      }
    }
    setState(() {
      _machines = next;
      _selected = selected ?? _selected;
    });
  }

  /// 重命名某台电视（与设备管理弹层同一套校验与提示）。
  ///
  /// 去掉顶部下拉后由「我的」页设备列表调用，可重命名任意一台，不限于当前目标。
  Future<void> _renameMachine(ParentalMachine machine) async {
    final String? alias = await showParentalAliasDialog(
      context,
      current: machine.alias,
    );
    if (!mounted || alias == null || alias == machine.alias.trim()) return;
    final String? error = await _renameDevice(machine.id, alias);
    if (!mounted) return;
    _hint(
      error ?? (alias.isEmpty ? '已清除别名' : '已重命名为「$alias」（仅自己可见）'),
      error: error != null,
    );
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

  /// 子页面下钻：返回后补拉一次事件与会话，保证首页数字新鲜。
  Future<void> _push(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (AccountSession.isParentOrAdmin) {
      unawaited(_loadEvents());
      unawaited(_loadParentalSessions());
    }
  }

  /// 三个 Tab 视图需要的副作用回调集合（数据加载 / 保存 / 解锁 / 导航等）。
  ParentalActions get _actions => ParentalActions(
        reload: () => _reload(),
        saveConfig: _saveConfig,
        unlock: _sendUnlock,
        openDeviceManager: () => _openDeviceManager(),
        push: _push,
        sendRemoteCommand: (String command) =>
            _sendRemoteCommand(_selected?.commAccount ?? '', command),
        refreshPermission: () => _refreshPermission(),
        toggleChildLock: (ParentalChild child) {
          unawaited(_toggleChildLock(child));
        },
        addChildExtra: (ParentalChild child) {
          unawaited(_addChildExtra(child));
        },
        editChild: (ParentalChild child) {
          unawaited(_editChild(child));
        },
        unbind: (String deviceId) {
          unawaited(_bindDevice(deviceId, bind: false));
        },
        selectDevice: (ParentalMachine machine) {
          if (_selected?.id == machine.id) return;
          setState(() {
            _selected = machine;
            _config = ParentalConfig.empty;
          });
          unawaited(_loadConfig());
        },
        renameMachine: (ParentalMachine machine) => unawaited(_renameMachine(machine)),
      );

  Future<void> _toggleChildLock(ParentalChild child) async {
    final List<ParentalChild> next = _config.children
        .map((ParentalChild c) => c.id == child.id ? c.copyWith(locked: !c.locked) : c)
        .toList(growable: false);
    await _saveConfig(_config.copyWith(children: next));
    _hint(child.locked ? '已解锁，电视恢复播放' : '已暂停，电视停止播放');
  }

  Future<void> _addChildExtra(ParentalChild child) async {
    final int next = (child.dailyLimitMin ?? 0) + 15;
    final List<ParentalChild> updated = _config.children
        .map((ParentalChild c) => c.id == child.id ? c.copyWith(dailyLimitMin: next) : c)
        .toList(growable: false);
    await _saveConfig(_config.copyWith(children: updated));
    _hint('今日额度 +15 分钟，已同步到电视');
  }

  Future<void> _editChild(ParentalChild child) async {
    final ParentalMachine? machine = _selected;
    if (machine == null) return;
    final ParentalChild? next = await ChildProfileEditorSheet.show(
      context,
      initial: child,
      deviceId: machine.id,
    );
    if (next == null || !mounted) return;
    final List<ParentalChild> updated = _config.children
        .map((ParentalChild c) => c.id == child.id ? next : c)
        .toList(growable: false);
    await _saveConfig(_config.copyWith(children: updated));
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
        child: Builder(
          builder: (BuildContext context) {
            final TabController controller = DefaultTabController.of(context);
            return Scaffold(
              // 对齐交互原型：标题随 Tab 变化（今天带「薯仔家长」副标题）；
              // Tab 栏从顶部移到底部；今天页右上提供解锁请求入口。
              appBar: PreferredSize(
                preferredSize: const Size.fromHeight(kToolbarHeight),
                child: AnimatedBuilder(
                  animation: controller,
                  builder: (BuildContext context, Widget? _) {
                    final int index = controller.index;
                    return AppBar(
                    automaticallyImplyLeading: !locked,
                    title: _buildTitle(index),
                    actions: <Widget>[
                      // 可用更新胶囊：有更新（下载中/已就绪）时显示，无更新自动隐藏。
                      const AppUpdatePill(compact: true, margin: EdgeInsets.only(right: 8)),
                      // 今天页：解锁请求入口（原型右上角的 ◎）。
                      if (index == 0)
                        IconButton(
                          tooltip: '解锁请求',
                          icon: const Icon(Icons.notifications_none_outlined),
                          onPressed: () => unawaited(_push(ParentalUnlockPage(
                            events: _unlockEvents,
                            onUnlock: _actions.unlock,
                            machine: _selected,
                            acks: _unlockAckEvents,
                            isAdmin: AccountSession.isAdmin,
                            myAccount: _myAccount,
                            onManageDevices: AccountSession.isParent
                                ? () => unawaited(_openDeviceManager())
                                : null,
                          ))),
                        ),
                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.all(14),
                          child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      else
                        IconButton(tooltip: '刷新', icon: const Icon(Icons.refresh), onPressed: () => unawaited(_reload())),
                      // 右上角设置齿轮已移除：改登录名 / 家长端名称 / 通道状态 /
                      // 版本更新全部并入「我的」页（对齐交互原型）。
                      // admin 复用家长视图后的返回口（parent 的默认首页就是本页）。
                      // parent 变体没有中控台，即使 admin 登录也不提供该入口。
                      if (AccountSession.isAdmin && !AppFlavorConfig.isParentOnly)
                        TextButton(onPressed: () => context.go(RouteNames.home), child: const Text('中控台')),
                    ],
                  );
                },
                ),
              ),
              bottomNavigationBar: BottomNavigationBar(
                currentIndex: controller.index,
                onTap: (int index) => controller.animateTo(index),
                type: BottomNavigationBarType.fixed,
                selectedItemColor: Theme.of(context).colorScheme.primary,
                unselectedItemColor: Theme.of(context).colorScheme.outline,
                selectedFontSize: 12,
                unselectedFontSize: 12,
                items: _tabs
                    .map((_TabSpec tab) => BottomNavigationBarItem(
                          icon: Icon(tab.icon, size: 22),
                          label: tab.label,
                        ))
                    .toList(growable: false),
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
                  ?ownerBanner,
                  Expanded(
                    child: TabBarView(
                      controller: controller,
                      children: <Widget>[
                        ParentalTodayView(
                          machines: _machines,
                          selected: _selected,
                          config: _config,
                          watchEvents: _watchEvents,
                          activeEvents: _activeEvents,
                          unlockEvents: _unlockEvents,
                          unlockAckEvents: _unlockAckEvents,
                          sessions: _sessions,
                          myAccount: _myAccount,
                          isAdmin: AccountSession.isAdmin,
                          actions: _actions,
                        ),
                        ParentalRulesView(
                          config: _config,
                          selected: _selected,
                          actions: _actions,
                        ),
                        ParentalMineView(
                          machines: _machines,
                          selected: _selected,
                          config: _config,
                          // 第一行只显示「独立家长号」；未设置时传空由卡片提示回落设备号，
                          // 避免与下面第二行的通道号显示成同一个值。
                          myAccount: _parentNoForDisplay,
                          channelAccount: _channelAccount,
                          actions: _actions,
                          // 家长号设置 / 跨设备说明入口，走 claim 路由。
                          onEditAccount: () => unawaited(context.push(RouteNames.claimAccountPath)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Tab 标题：今天带「薯仔家长」副标题，其余页仅主标题（对齐交互原型）。
  Widget _buildTitle(int index) {
    final ThemeData theme = Theme.of(context);
    if (index == 0) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(_tabs[index].label, style: theme.appBarTheme.titleTextStyle),
          Text(
            '薯仔家长',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      );
    }
    return Text(_tabs[index].label, style: theme.appBarTheme.titleTextStyle);
  }
}

/// 家长视图的标签页规格。
class _TabSpec {
  const _TabSpec(this.label, this.icon);

  final String label;
  final IconData icon;
}
