import 'package:flutter/material.dart';
import 'package:pscreen_home/features/parental/data/parental_admin_api.dart';
import 'package:pscreen_home/features/remote_control/presentation/qr_scan_page.dart';

/// 家长视图的设备管理弹层：扫码添加电视、绑定/解绑。
///
/// - 扫码沿用电视端「我的」页二维码（内容为电视的实时通信账号），再用
///   服务端 overview 的设备清单解析成 `deviceId`；
/// - 解绑复用 `/api/admin/parental/bind` 的 `bind:false`，只清家长关联，
///   不删除 `machines.json` 里的设备记录，因此电视会回到「可绑定设备」，
///   下次进入仍能看到并重新绑定。
class ParentalDeviceManagerSheet extends StatefulWidget {
  const ParentalDeviceManagerSheet({
    super.key,
    required this.bound,
    required this.available,
    required this.onBind,
    required this.onUnbind,
    required this.onScanBind,
  });

  /// 当前已绑定到本账号的电视。
  final List<ParentalMachine> bound;

  /// 尚未绑定到本账号、可自助认领的电视（服务端 `availableMachines`）。
  final List<ParentalMachine> available;

  /// 绑定指定设备；成功返回 null，失败返回可展示的错误文案。
  final Future<String?> Function(String deviceId) onBind;

  /// 解绑指定设备；成功返回 null，失败返回可展示的错误文案。
  final Future<String?> Function(String deviceId) onUnbind;

  /// 扫码得到的通信账号 → 解析设备并绑定；成功返回 null。
  final Future<String?> Function(String account) onScanBind;

  @override
  State<ParentalDeviceManagerSheet> createState() =>
      _ParentalDeviceManagerSheetState();
}

class _ParentalDeviceManagerSheetState
    extends State<ParentalDeviceManagerSheet> {
  late final List<ParentalMachine> _bound = List<ParentalMachine>.of(
    widget.bound,
  );
  late final List<ParentalMachine> _available = List<ParentalMachine>.of(
    widget.available,
  );
  bool _busy = false;
  String? _message;
  bool _error = false;

  Future<void> _scan() async {
    final String? account = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const QrScanPage()),
    );
    if (!mounted || account == null || account.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final String? error = await widget.onScanBind(account.trim());
    if (!mounted) return;
    if (error == null) {
      // 绑定成功：关闭弹层，页面刷新后会出现在「已绑定设备」。
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = false;
      _message = error;
      _error = true;
    });
  }

  Future<void> _bind(ParentalMachine machine) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final String? error = await widget.onBind(machine.id);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (error == null) {
        _available.removeWhere((ParentalMachine item) => item.id == machine.id);
        if (!_bound.any((ParentalMachine item) => item.id == machine.id)) {
          _bound.add(machine);
        }
        _error = false;
        _message = '已绑定 ${_nameOf(machine)}';
      } else {
        _error = true;
        _message = error;
      }
    });
  }

  Future<void> _unbind(ParentalMachine machine) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    final String? error = await widget.onUnbind(machine.id);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (error == null) {
        _bound.removeWhere((ParentalMachine item) => item.id == machine.id);
        if (!_available.any((ParentalMachine item) => item.id == machine.id)) {
          _available.add(machine);
        }
        _error = false;
        _message = '已解绑 ${_nameOf(machine)}，设备记录仍保留，可重新绑定';
      } else {
        _error = true;
        _message = error;
      }
    });
  }

  static String _nameOf(ParentalMachine machine) =>
      machine.name.isEmpty ? machine.id : machine.name;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text('设备管理', style: theme.textTheme.titleLarge),
                ),
                IconButton(
                  tooltip: '关闭',
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '扫描电视端「我的」页二维码添加设备；家长可绑定任意已上报的电视。',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
            ),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              onPressed: _busy ? null : _scan,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('扫码添加电视'),
            ),
            if (_message != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                _message!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _error ? scheme.error : scheme.primary,
                ),
              ),
            ],
            if (_busy) ...<Widget>[
              const SizedBox(height: 10),
              const LinearProgressIndicator(),
            ],
            const SizedBox(height: 16),
            if (_available.isEmpty && _bound.isEmpty)
              Text(
                '暂无可见电视；请确认电视已开机并上报过服务端。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.outline,
                ),
              ),
            if (_available.isNotEmpty) ...<Widget>[
              Text(
                '可绑定设备',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              for (final ParentalMachine machine in _available)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.tv_outlined),
                  title: Text(_nameOf(machine)),
                  subtitle: Text(
                    machine.commDisplayName.isNotEmpty
                        ? machine.commDisplayName
                        : (machine.commAccount.isEmpty
                            ? machine.id
                            : machine.commAccount),
                  ),
                  trailing: TextButton(
                    onPressed: _busy ? null : () => _bind(machine),
                    child: const Text('绑定'),
                  ),
                ),
            ],
            if (_bound.isNotEmpty) ...<Widget>[
              if (_available.isNotEmpty) const SizedBox(height: 12),
              Text(
                '已绑定设备',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              for (final ParentalMachine machine in _bound)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.tv),
                  title: Text(_nameOf(machine)),
                  subtitle: Text(machine.online ? '在线' : '离线'),
                  trailing: TextButton(
                    onPressed: _busy ? null : () => _unbind(machine),
                    child: const Text('解绑'),
                  ),
                ),
            ],
            const SizedBox(height: 12),
            Text(
              '解绑只解除家长与电视的绑定关系，不会删除服务端设备记录；'
              '电视会回到「可绑定设备」，下次进入仍可重新绑定。',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}
