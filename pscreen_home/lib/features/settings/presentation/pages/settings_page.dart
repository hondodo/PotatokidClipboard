import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pscreen_home/app/config/app_config.dart';
import 'package:pscreen_home/core/di/injection.dart';
import 'package:pscreen_home/core/network/ha_ws_client.dart';
import 'package:pscreen_home/core/storage/settings_store.dart';
import 'package:pscreen_home/features/connection/application/bloc/connection_bloc.dart';
import 'package:pscreen_home/features/connection/application/bloc/connection_event.dart';
import 'package:pscreen_home/features/connection/application/bloc/connection_state.dart';

/// 设置页：Home Assistant 连接配置（地址 + 长期访问令牌）。
///
/// - 输入框回显**生效值**：持久化覆盖 > `.env`（默认即 localhost）；
/// - 保存时：非空输入存入 `SettingsStore` 作为覆盖，**清空保存则删除覆盖
///   回落 `.env`**；生效值发生变化时触发 `Reconnect` 断开重建连接，
///   连接就绪后主页自动重新加载（刷新）；
/// - 底部实时显示连接状态，便于换地址后确认是否连通。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _hostController;
  late final TextEditingController _tokenController;
  bool _tokenVisible = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _hostController = TextEditingController(text: AppConfig.haHost);
    _tokenController = TextEditingController(text: AppConfig.haToken);
  }

  @override
  void dispose() {
    _hostController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  /// 保存：持久化输入 → 更新生效值 → 生效值变化时重连刷新。
  Future<void> _save() async {
    final String hostInput = _hostController.text.trim();
    final String tokenInput = _tokenController.text.trim();

    // 覆盖语义：与 .env 默认值相同（或清空）= 不覆盖，保持跟随 .env；
    // 不同才存持久化。生效值据此归一化后与当前生效值比较，判定是否刷新。
    final String hostPersist =
        hostInput == AppConfig.envHost ? '' : hostInput;
    final String tokenPersist =
        tokenInput == AppConfig.envToken ? '' : tokenInput;
    final String newHost =
        hostPersist.isEmpty ? AppConfig.envHost : hostPersist;
    final String newToken =
        tokenPersist.isEmpty ? AppConfig.envToken : tokenPersist;
    final bool changed =
        newHost != AppConfig.haHost || newToken != AppConfig.haToken;

    setState(() => _saving = true);
    final SettingsStore store = Injection.get<SettingsStore>();
    await store.save(host: hostPersist, token: tokenPersist);
    // 从存储回读（保证与实际持久化结果一致，失败时自动回落）
    AppConfig.applyOverrides(
      host: store.hostOverride,
      token: store.tokenOverride,
    );
    if (!mounted) return;
    setState(() => _saving = false);

    // 回显生效值：清空保存后输入框显示回落的 .env 值
    _hostController.text = AppConfig.haHost;
    _tokenController.text = AppConfig.haToken;

    if (changed) {
      context.read<ConnectionBloc>().add(const Reconnect());
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(changed ? '已保存，正在用新配置重新连接…' : '已保存'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          TextField(
            controller: _hostController,
            decoration: InputDecoration(
              labelText: 'Home Assistant 地址',
              hintText: '如 192.168.1.10:8123 或 home.example.com:8123',
              helperText: AppConfig.hasHostOverride
                  ? '已手动设置，优先于 .env（清空保存可恢复）'
                  : '当前使用 .env 默认值',
              border: const OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
            maxLines: 1,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _tokenController,
            obscureText: !_tokenVisible,
            decoration: InputDecoration(
              labelText: '长期访问令牌 (KEY)',
              helperText: AppConfig.hasTokenOverride
                  ? '已手动设置，优先于 .env（清空保存可恢复）'
                  : '当前使用 .env 默认值',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: _tokenVisible ? '隐藏' : '显示',
                icon: Icon(_tokenVisible
                    ? Icons.visibility_off_rounded
                    : Icons.visibility_rounded),
                onPressed: () =>
                    setState(() => _tokenVisible = !_tokenVisible),
              ),
            ),
            maxLines: 1,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_rounded),
            label: const Text('保存'),
          ),
          const SizedBox(height: 24),
          const _ConnectionStatusLine(),
        ],
      ),
    );
  }
}

/// 底部连接状态行：换地址保存后无需返回主页即可确认连通性。
class _ConnectionStatusLine extends StatelessWidget {
  const _ConnectionStatusLine();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConnectionBloc, ConnectionState>(
      builder: (BuildContext context, ConnectionState state) {
        final (String label, Color color) = switch (state.phase) {
          HaConnectionPhase.ready => ('已连接', Colors.greenAccent),
          HaConnectionPhase.connecting => ('连接中…', Colors.orangeAccent),
          HaConnectionPhase.authenticating => ('认证中…', Colors.orangeAccent),
          HaConnectionPhase.authFailed =>
            (state.message ?? '认证失败', Colors.redAccent),
          HaConnectionPhase.disconnected =>
            (state.isRetrying ? '重连中…' : '未连接', Colors.redAccent),
        };
        return Row(
          children: <Widget>[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ],
        );
      },
    );
  }
}
