import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pscreen_home/app/config/app_flavor.dart';
import 'package:pscreen_home/core/server/account_session.dart';
import 'package:pscreen_home/core/server/server_api.dart';
import 'package:pscreen_home/features/parental/data/parental_admin_api.dart';
import 'package:pscreen_screen/core/utils/app_settings.dart';
import 'package:pscreen_screen/core/utils/device_credentials.dart';

/// 家长号与跨设备（route 2 / claim）。
///
/// 两层身份彻底分开、互不替代：
/// - **家长号**（如 mama_01）：家长「人」的身份，仅用于 HTTP 管理登录与
///   `machine.parents` 可见性判定。可自设口令、可重置、可跨设备登录。
/// - **本机实时通道号**：设备派生号 `parent.parent.<设备号>`，实时通道、心跳、
///   遥控永远用它，永不改名/禁用、口令恒 123456。
///
/// 本页三种形态：
/// 1. 未设置家长号 → 「新建家长号」表单（自设口令 + 确认）；
/// 2. 已设置家长号 → 只读展示家长号 + 通道号，可「修改口令」；
/// 3. 「在另一台手机登录」→ 输入别人给的家长号 + 口令，校验后本机保存。
///
/// 只 parent flavor 可用；路由表不分 flavor，故这里再做一次自检。
class ClaimAccountPage extends StatefulWidget {
  const ClaimAccountPage({
    super.key,
    this.initialMode = ClaimAccountOpenMode.auto,
    this.popAfterSuccess = false,
  });

  /// 打开时直接进入的形态；[auto] 时按本地是否已设置家长号推断
  /// （已设置 → 概览、未设置 → 新建）。账号恢复入口用它直达「登录」或「创建」。
  final ClaimAccountOpenMode initialMode;

  /// 成功后是否直接 pop 回上一页（账号恢复场景：登录成功后由父页监听
  /// [AccountSession.roleNotifier] 自动重载设备与档案）。默认 false（留在概览）。
  final bool popAfterSuccess;

  @override
  State<ClaimAccountPage> createState() => _ClaimAccountPageState();
}

/// 家长号页的进入形态（详见 [ClaimAccountPage.initialMode]）。
enum ClaimAccountOpenMode {
  /// 按本地是否已设置家长号推断（默认）。
  auto,

  /// 直接进入「在另一台手机登录」形态（账号恢复主入口）。
  join,

  /// 直接进入「新建家长号」形态。
  create,
}

enum _ClaimMode { overview, create, join }

/// 把异常转成用户可读文案：服务端业务错误直接取 msg；网络/超时给通用提示。
String _friendlyError(Object error) {
  if (error is ServerApiException) return error.message;
  final String s = '$error';
  if (s.contains('DioException') ||
      s.contains('SocketException') ||
      s.contains('TimeoutException') ||
      s.contains('连接失败') ||
      s.contains('超时') ||
      s.contains('timeout')) {
    return '网络连接失败，请检查网络后重试';
  }
  return '操作失败：$s';
}

class _ClaimAccountPageState extends State<ClaimAccountPage> {
  // 与服务端 claims.js 的 CLAIM_NAME_PATTERN 保持一致（两套校验的交集）。
  static final RegExp _namePattern = RegExp(r'^[A-Za-z0-9_.-]{2,64}$');
  static final RegExp _derivedPattern = RegExp(r'^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[0-9a-fA-F]{16}$');
  static final RegExp _reservedScope = RegExp(r'^(parent|tv|board|phone|home)\.', caseSensitive: false);

  final ParentalAdminApi _api = const ParentalAdminApi();
  final TextEditingController _accountCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
  final TextEditingController _confirmCtrl = TextEditingController();
  final TextEditingController _currentPwdCtrl = TextEditingController();
  final TextEditingController _newPwdCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String _derivedAccount = '';
  String _claimedAccount = '';
  _ClaimMode _mode = _ClaimMode.overview;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _accountCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _currentPwdCtrl.dispose();
    _newPwdCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await AppSettings.instance.ensureLoaded();
    final String channel = await DeviceCredentials.channelAccount();
    final String claimed = AppSettings.instance.claimedAccount.trim();
    if (!mounted) return;
    _ClaimMode mode;
    switch (widget.initialMode) {
      case ClaimAccountOpenMode.join:
        mode = _ClaimMode.join;
      case ClaimAccountOpenMode.create:
        mode = _ClaimMode.create;
      case ClaimAccountOpenMode.auto:
        mode = claimed.isEmpty ? _ClaimMode.create : _ClaimMode.overview;
    }
    setState(() {
      _derivedAccount = channel;
      _claimedAccount = claimed;
      _mode = mode;
      _loading = false;
    });
  }

  String? _validateName(String value) {
    final String name = value.trim();
    if (!_namePattern.hasMatch(name)) {
      return '需为 2-64 位字母、数字、下划线、点或连字符（暂不支持中文与冒号）';
    }
    if (name.startsWith('.')) return '家长号不能以点开头';
    if (_reservedScope.hasMatch(name)) return '该前缀为设备账号保留，请换一个';
    if (_derivedPattern.hasMatch(name)) return '不能使用设备派生账号格式';
    return null;
  }

  String? _validatePassword(String value, {String? confirm}) {
    if (value.length < 6 || value.length > 128) return '口令需为 6-128 位';
    if (value == '123456') return '密码过于简单'; //'不能与设备默认口令相同，请自设一个';
    if (confirm != null && value != confirm) return '两次输入的口令不一致';
    return null;
  }

  /// 新建家长号：派生号领票 → 提交「家长号 + 自设口令」→ 本地持久化。
  Future<void> _submitCreate() async {
    final String name = _accountCtrl.text.trim();
    final String pwd = _passwordCtrl.text;
    final String? nameErr = _validateName(name);
    final String? pwdErr = _validatePassword(pwd, confirm: _confirmCtrl.text);
    if (nameErr != null || pwdErr != null) {
      setState(() => _error = nameErr ?? pwdErr);
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('确认设置家长号？'),
        content: Text(
          '家长号「$name」是你在家长端的身份，可跨设备登录。'
          '已绑电视的家长关系会归到这个号下；\n\n'
          '本机实时通道号不会改变、不会被禁用。请记住自设口令——'
          '换手机时凭「家长号 + 口令」登录即可。',
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('再想想')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('确认设置')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // 先用设备派生号换管理会话（此时 account() 仍是派生号）。
      await _api.ensureAdminSession(username: _derivedAccount, passwordMd5: DeviceCredentials.channelPasswordMd5());
      final String ticket = await _api.requestClaimTicket();
      final ClaimAccountResult result = await _api.claimAccount(account: name, password: pwd, claimToken: ticket);
      // 先写口令再写账号，避免「账号已切、口令仍是旧的」短暂窗口。
      await AppSettings.instance.setClaimedPassword(result.password);
      await AppSettings.instance.setClaimedAccount(result.account);
      await AccountSession.loginWithSaved();
      if (!mounted) return;
      if (widget.popAfterSuccess) {
        _saving = false;
        Navigator.of(context).pop();
        return;
      }
      setState(() {
        _claimedAccount = result.account;
        _mode = _ClaimMode.overview;
        _saving = false;
        _passwordCtrl.clear();
        _confirmCtrl.clear();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _friendlyError(error);
      });
    }
  }

  /// 跨设备登录：用别人给的家长号 + 口令校验，通过后本机保存。
  Future<void> _submitJoin() async {
    final String name = _accountCtrl.text.trim();
    final String pwd = _passwordCtrl.text;
    final String? nameErr = _validateName(name);
    final String? pwdErr = _validatePassword(pwd);
    if (nameErr != null || pwdErr != null) {
      setState(() => _error = nameErr ?? pwdErr);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final String role = await _api.loginRole(account: name, passwordMd5: DeviceCredentials.md5Of(pwd));
      if (role != 'parent' && role != 'admin') {
        throw const ServerApiException('家长号或口令不正确，或该账号无家长权限');
      }
      await AppSettings.instance.setClaimedPassword(pwd);
      await AppSettings.instance.setClaimedAccount(name);
      await AccountSession.loginWithSaved();
      if (!mounted) return;
      if (widget.popAfterSuccess) {
        _saving = false;
        Navigator.of(context).pop();
        return;
      }
      setState(() {
        _claimedAccount = name;
        _mode = _ClaimMode.overview;
        _saving = false;
        _passwordCtrl.clear();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _friendlyError(error);
      });
    }
  }

  /// 修改当前家长号口令。
  Future<void> _submitChangePassword() async {
    final String cur = _currentPwdCtrl.text;
    final String next = _newPwdCtrl.text;
    final String? err = _validatePassword(next, confirm: _confirmCtrl.text);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _api.ensureAdminSession(username: _claimedAccount, passwordMd5: DeviceCredentials.md5Of(cur));
      await _api.changeParentPassword(currentPassword: cur, newPassword: next);
      await AppSettings.instance.setClaimedPassword(next);
      await AccountSession.loginWithSaved();
      if (!mounted) return;
      setState(() {
        _saving = false;
        _currentPwdCtrl.clear();
        _newPwdCtrl.clear();
        _confirmCtrl.clear();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('口令已更新，请用新口令在其它设备登录')));
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _friendlyError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    if (!AppFlavorConfig.isParentOnly) {
      return Scaffold(
        appBar: AppBar(title: const Text('家长号与跨设备')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('此页面仅家长端可用', textAlign: TextAlign.center),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('家长号与跨设备'),
        leading: _mode == _ClaimMode.overview
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() {
                  _mode = _claimedAccount.isEmpty ? _ClaimMode.create : _ClaimMode.overview;
                  _error = null;
                }),
              ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: switch (_mode) {
                _ClaimMode.overview => _buildOverview(theme, scheme),
                _ClaimMode.create => _buildCreate(theme, scheme),
                _ClaimMode.join => _buildJoin(theme, scheme),
              },
            ),
    );
  }

  Widget _identityPrimer(ThemeData theme, ColorScheme scheme) {
    return SizedBox.shrink();
    // 保留注释，但不需要给用户看
    // return Card(
    //   color: scheme.surfaceContainerLow,
    //   margin: EdgeInsets.zero,
    //   child: Padding(
    //     padding: const EdgeInsets.all(14),
    //     child: Text(
    //       '两层身份，互不替代。「家长号」跟着人走，回答"你是谁"；'
    //       '「实时通道号」跟着设备走，回答"哪台设备"。改家长号，通道号原封不动。',
    //       style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
    //     ),
    //   ),
    // );
  }

  Widget _channelRow(ThemeData theme, ColorScheme scheme) {
    return SizedBox.shrink();
    // 保留注释，不用给用户看
    // return Card(
    //   margin: EdgeInsets.zero,
    //   child: Padding(
    //     padding: const EdgeInsets.all(14),
    //     child: Column(
    //       crossAxisAlignment: CrossAxisAlignment.start,
    //       children: <Widget>[
    //         Text('本机实时通道号（设备身份 · 只读）',
    //             style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline)),
    //         const SizedBox(height: 3),
    //         SelectableText(
    //           _derivedAccount.isEmpty ? '检测中…' : _derivedAccount,
    //           style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
    //         ),
    //         const SizedBox(height: 6),
    //         Text(
    //           '设备自举时生成，实时通道、心跳、遥控全靠它。'
    //           '永不改名、不禁用、不参与"设置家长号"。',
    //           style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
    //         ),
    //       ],
    //     ),
    //   ),
    // );
  }

  Widget _buildOverview(ThemeData theme, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _identityPrimer(theme, scheme),
        const SizedBox(height: 14),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(Icons.account_circle_outlined, color: scheme.primary),
                    const SizedBox(width: 10),
                    Text('家长号', style: theme.textTheme.titleSmall),
                    const Spacer(),
                    const Chip(label: Text('已设置'), visualDensity: VisualDensity.compact),
                  ],
                ),
                const SizedBox(height: 8),
                SelectableText(
                  _claimedAccount,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '在另一台手机用同一个家长号 + 口令登录，就能看到同一批电视和档案。',
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _channelRow(theme, scheme),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: () => setState(() {
            _mode = _ClaimMode.join;
            _error = null;
          }),
          icon: const Icon(Icons.phonelink_setup_outlined),
          label: const Text('在另一台手机登录这个家长号'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => setState(() {
            _mode = _ClaimMode.create;
            _currentPwdCtrl.clear();
            _newPwdCtrl.clear();
            _error = null;
          }),
          icon: const Icon(Icons.password_outlined),
          label: const Text('修改家长号口令'),
        ),
      ],
    );
  }

  Widget _buildCreate(ThemeData theme, ColorScheme scheme) {
    final bool changing = _claimedAccount.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _identityPrimer(theme, scheme),
        const SizedBox(height: 16),
        Text(changing ? '修改家长号口令' : '给家长账号起个名字', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          changing
              ? '改完请用新口令在其它设备登录。派生号口令不变，实时通道照常工作。'
              : '家长号跟着家长走，换设备也能用同一个身份。口令由你自设，'
                    '请记牢——换手机时凭「家长号 + 口令」登录。',
          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.outline),
        ),
        const SizedBox(height: 18),
        if (changing)
          Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: const Text('当前家长号'),
              subtitle: Text(_claimedAccount, style: const TextStyle(fontFamily: 'monospace')),
            ),
          ),
        if (!changing)
          TextField(
            controller: _accountCtrl,
            enabled: !_saving,
            maxLength: 64,
            decoration: const InputDecoration(
              labelText: '家长号',
              hintText: '例如 mama_01',
              helperText: '2-64 位字母、数字、下划线、点或连字符；不能用设备号前缀',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
        if (changing) ...<Widget>[
          TextField(
            controller: _currentPwdCtrl,
            enabled: !_saving,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '当前口令',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.lock_outline),
            ),
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 4),
        TextField(
          controller: _passwordCtrl,
          enabled: !_saving,
          obscureText: true,
          maxLength: 128,
          decoration: InputDecoration(
            labelText: changing ? '新口令' : '设置口令',
            hintText: '至少 6 位，不要用 123456',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.password_outlined),
          ),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirmCtrl,
          enabled: !_saving,
          obscureText: true,
          maxLength: 128,
          decoration: const InputDecoration(
            labelText: '再输一次口令',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.password_outlined),
          ),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: scheme.error)),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _saving
              ? null
              : changing
              ? _submitChangePassword
              : _submitCreate,
          icon: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.check_circle_outline),
          label: Text(
            _saving
                ? '正在保存…'
                : changing
                ? '确认修改口令'
                : '设置家长号',
          ),
        ),
        const SizedBox(height: 22),
        _channelRow(theme, scheme),
        if (!changing) ...<Widget>[
          const SizedBox(height: 18),
          Text('设置时会发生什么', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          _bullet('只新建一个家长号账号，口令由你自设，不再随机下发'),
          _bullet('已绑电视的家长关系归到这个号下，保留档案、规则、观看记录'),
          _bullet('本机实时通道号原样不动，永不改名、永不禁用'),
          _bullet('换手机用「家长号 + 口令」登录，看到同一批电视'),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () => setState(() {
              _mode = _ClaimMode.join;
              _error = null;
            }),
            icon: const Icon(Icons.login, size: 18),
            label: const Text('已经有一个家长号？在这台手机登录'),
          ),
        ],
      ],
    );
  }

  Widget _buildJoin(ThemeData theme, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('在另一台手机登录', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          '输入已设置好的家长号和口令。登录成功后，这台手机就能看到'
          '该家长号绑定的所有电视与档案；实时通道仍用本机派生号，互不影响。',
          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.outline),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _accountCtrl,
          enabled: !_saving,
          maxLength: 64,
          decoration: const InputDecoration(
            labelText: '家长号',
            hintText: '例如 mama_01',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.person_outline_rounded),
          ),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passwordCtrl,
          enabled: !_saving,
          obscureText: true,
          maxLength: 128,
          decoration: const InputDecoration(
            labelText: '口令',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.lock_outline),
          ),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: scheme.error)),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _saving ? null : _submitJoin,
          icon: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.login),
          label: Text(_saving ? '正在登录…' : '登录家长号'),
        ),
        const SizedBox(height: 22),
        _channelRow(theme, scheme),
        const SizedBox(height: 16),
        Card(
          color: scheme.surfaceContainerLow,
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              'A、B 手机都登录同一个家长号，看到的是同一批绑定关系下的档案——'
              '档案从没被"搬来搬去"，只是被不同设备读取。',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ),
      ],
    );
  }

  Widget _bullet(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text('·  ', style: TextStyle(fontSize: 15)),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
