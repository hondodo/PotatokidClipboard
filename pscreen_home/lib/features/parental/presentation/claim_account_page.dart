import 'package:flutter/material.dart';
import 'package:pscreen_home/app/config/app_flavor.dart';
import 'package:pscreen_home/core/server/account_session.dart';
import 'package:pscreen_home/features/parental/data/parental_admin_api.dart';
import 'package:pscreen_screen/core/utils/app_settings.dart';
import 'package:pscreen_screen/core/utils/device_credentials.dart';

/// 家长端「设置登录名」（route 2 / claim）。
///
/// 把设备自举的 `parent.parent.<设备号>` 换成家长自己记得住的登录名：
/// 先换管理会话 → 领一次性凭证 → 提交改名（服务端同步迁移所有账号引用、
/// 生成新随机口令）→ 本地持久化这一对凭据。
///
/// 服务端仍按「账号文件里的 MD5 比对」校验，登录链路不用改；新口令只在
/// claim 响应里下发一次并保存在本机，中控端 / TV 端不受影响。
///
/// 该页只在 parent flavor 可用；路由表不分 flavor，故这里再做一次自检。
class ClaimAccountPage extends StatefulWidget {
  const ClaimAccountPage({super.key});

  @override
  State<ClaimAccountPage> createState() => _ClaimAccountPageState();
}

class _ClaimAccountPageState extends State<ClaimAccountPage> {
  // 与服务端 claims.js 的 CLAIM_NAME_PATTERN 保持一致（两套校验的交集）。
  static final RegExp _namePattern = RegExp(r'^[A-Za-z0-9_.-]{2,64}$');
  static final RegExp _derivedPattern =
      RegExp(r'^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[0-9a-fA-F]{16}$');
  static final RegExp _reservedScope =
      RegExp(r'^(parent|tv|board|phone|home)\.', caseSensitive: false);

  final ParentalAdminApi _api = const ParentalAdminApi();
  final TextEditingController _controller = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String _currentAccount = '';
  String _claimedAccount = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await AppSettings.instance.ensureLoaded();
    final String account = await DeviceCredentials.account();
    final String claimed = AppSettings.instance.claimedAccount.trim();
    if (!mounted) return;
    setState(() {
      _currentAccount = account;
      _claimedAccount = claimed;
      _loading = false;
    });
  }

  String? _validate(String value) {
    final String name = value.trim();
    if (!_namePattern.hasMatch(name)) {
      return '需为 2-64 位字母、数字、下划线、点或连字符（暂不支持中文与冒号）';
    }
    if (name.startsWith('.')) return '登录名不能以点开头';
    if (_reservedScope.hasMatch(name)) return '该前缀为设备账号保留，请换一个';
    if (_derivedPattern.hasMatch(name)) return '不能使用设备派生账号格式';
    return null;
  }

  Future<void> _submit() async {
    final String name = _controller.text.trim();
    final String? validation = _validate(name);
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('确认设置登录名？'),
        content: Text(
          '将把当前账号改为「$name」。已绑定的电视、儿童档案、题库、私有别名与'
          '观看记录会一并迁移。\n\n一个设备只能设置一次，之后无法自助修改。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('再想想'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('确认设置'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // 1. 用当前派生账号换管理会话（cookie jar 自动携带 pk_admin）。
      await _api.ensureAdminSession(
        username: _currentAccount,
        passwordMd5: DeviceCredentials.passwordMd5(),
      );
      // 2. 领票 + 核销：凭证短时有效且只能用一次。
      final String ticket = await _api.requestClaimTicket();
      final ClaimAccountResult result = await _api.claimAccount(
        account: name,
        claimToken: ticket,
      );
      // 3. 先写口令再写账号，避免出现「账号已切、口令仍是旧的」短暂窗口。
      //    重启后 account() / password() 继续返回这一对新凭据。
      await AppSettings.instance.setClaimedPassword(result.password);
      await AppSettings.instance.setClaimedAccount(result.account);
      // 4. 刷新 ptools 会话与角色，让后续接口立即使用新账号。
      await AccountSession.loginWithSaved();
      if (!mounted) return;
      setState(() {
        _claimedAccount = result.account;
        _currentAccount = result.account;
        _saving = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    if (!AppFlavorConfig.isParentOnly) {
      return Scaffold(
        appBar: AppBar(title: const Text('设置登录名')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('此页面仅家长端可用', textAlign: TextAlign.center),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('设置登录名')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: _claimedAccount.isNotEmpty
                  ? _buildDone(theme, scheme)
                  : _buildForm(theme, scheme),
            ),
    );
  }

  Widget _buildDone(ThemeData theme, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(Icons.check_circle_outline_rounded, size: 44, color: scheme.primary),
        const SizedBox(height: 12),
        Text('登录名已设置', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Card(
          child: ListTile(
            title: const Text('当前登录名'),
            subtitle: Text(
              _claimedAccount,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '已绑定的电视、规则与观看记录都保留。服务端已为这个登录名生成新随机'
          '口令，只保存在本机家长端，请勿执行「重置」（重置会清掉凭据且服务端'
          '不会再次下发口令）。\n\n'
          '实时通道会在下次重连时使用新登录名，建议重启一次家长端 App '
          '让所有页面立即切换。\n\n'
          '一个设备只能设置一次；如需再次变更，请联系管理员在服务端处理。',
          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.outline),
        ),
      ],
    );
  }

  Widget _buildForm(ThemeData theme, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('给家长账号起个名字', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          '现在账号跟着这台设备走，换手机就会变成另一个家长。设置登录名后，'
          '账号跟着家长走，换设备也能继续用同一个身份。',
          style: theme.textTheme.bodyMedium?.copyWith(color: scheme.outline),
        ),
        const SizedBox(height: 20),
        Card(
          child: ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('当前设备账号'),
            subtitle: Text(
              _currentAccount,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _controller,
          enabled: !_saving,
          autofocus: false,
          maxLength: 64,
          decoration: const InputDecoration(
            labelText: '自定义登录名',
            hintText: '例如 mama_01',
            helperText: '2-64 位字母、数字、下划线、点或连字符；设置后不可自助修改',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.person_outline_rounded),
          ),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            _error!,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _saving ? null : _submit,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.how_to_reg_outlined),
          label: Text(_saving ? '正在设置…' : '设置登录名'),
        ),
        const SizedBox(height: 24),
        Text('设置时会发生什么', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        _bullet('服务端把旧账号的绑定关系整体迁移到新登录名'),
        _bullet('已绑定的电视、儿童档案、题库、别名、观看记录都保留'),
        _bullet('服务端会生成新随机口令并只保存在本机，中控端与电视端登录方式不受影响'),
        _bullet('凭证 10 分钟内有效且只能用一次，过期可重新点按钮领取'),
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
