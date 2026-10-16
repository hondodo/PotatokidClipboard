import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pscreen_control/app/config/app_config.dart';
import 'package:pscreen_control/app/di/injection.dart';
import 'package:pscreen_control/app/storage/app_settings.dart';
import 'package:pscreen_control/core/nim_client.dart';
import 'package:pscreen_control/features/send/application/send_cubit.dart';
import 'package:pscreen_control/features/send/data/tv_directory.dart';
import 'package:pscreen_control/features/send/presentation/widgets/command_panel.dart';
import 'package:pscreen_control/features/send/presentation/widgets/target_picker.dart';
import 'package:pscreen_control/features/scan/presentation/qr_scan_page.dart';
import 'package:pscreen_control/features/admin/presentation/conversation_list_page.dart';

/// 发送端主页：按账号分叉。
class SendPage extends StatelessWidget {
  const SendPage({super.key});

  @override
  Widget build(BuildContext context) {
    final String account = AppSettings.instance.nimAccount;
    final bool isAdmin = account == AppConfig.adminAccount;
    return BlocProvider<SendCubit>(
      create: (_) => SendCubit(nim: getIt<NimClient>()),
      child: isAdmin ? const _AdminSendShell() : const _FamilySendPage(),
    );
  }
}

/// 家人单页「发指令」：文本框 + 命令面板 + 手动/扫码选一台。
class _FamilySendPage extends StatefulWidget {
  const _FamilySendPage();

  @override
  State<_FamilySendPage> createState() => _FamilySendPageState();
}

class _FamilySendPageState extends State<_FamilySendPage> {
  final TextEditingController _text = TextEditingController();
  final TextEditingController _manual = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    _manual.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final SendCubit cubit = context.read<SendCubit>();
    final String? account = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScanPage()),
    );
    if (account != null && account.isNotEmpty) {
      cubit.toggleTarget(account);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('发指令')),
      body: BlocBuilder<SendCubit, SendState>(
        builder: (BuildContext context, SendState state) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('目标: ${state.targets.join(", ")}'),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _manual,
                        decoration:
                            const InputDecoration(hintText: '手动输入 TV 账号'),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: () {
                        final String v = _manual.text.trim();
                        if (v.isNotEmpty) {
                          context.read<SendCubit>().toggleTarget(v);
                          _manual.clear();
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.qr_code_scanner),
                      onPressed: _scan,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                CommandPanel(
                  onCommand: (String body) =>
                      context.read<SendCubit>().sendRaw(body),
                ),
                const Spacer(),
                TextField(
                  controller: _text,
                  decoration: const InputDecoration(hintText: '输入消息'),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: state.isSending
                        ? null
                        : () {
                            context
                                .read<SendCubit>()
                                .sendPlainText(_text.text.trim());
                            _text.clear();
                          },
                    child: const Text('发送'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 管理员群发 shell：Tab（群发 / 会话）。
class _AdminSendShell extends StatelessWidget {
  const _AdminSendShell();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('PScreen 控制'),
          bottom: const TabBar(
            tabs: <Widget>[
              Tab(text: '群发'),
              Tab(text: '会话'),
            ],
          ),
        ),
        body: const TabBarView(
          children: <Widget>[
            _BroadcastTab(),
            ConversationListPage(),
          ],
        ),
      ),
    );
  }
}

/// 群发 tab。
class _BroadcastTab extends StatefulWidget {
  const _BroadcastTab();

  @override
  State<_BroadcastTab> createState() => _BroadcastTabState();
}

class _BroadcastTabState extends State<_BroadcastTab>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _text = TextEditingController();
  final TextEditingController _manual = TextEditingController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    getIt<TvDirectory>().loadFromAssets();
  }

  @override
  void dispose() {
    _text.dispose();
    _manual.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return BlocBuilder<SendCubit, SendState>(
      builder: (BuildContext context, SendState state) {
        final TvDirectory dir = getIt<TvDirectory>();
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: <Widget>[
              TargetPicker(
                devices: dir.devices,
                selected: state.targets.toSet(),
                onToggle: context.read<SendCubit>().toggleTarget,
                onScan: () async {
                  final SendCubit cubit = context.read<SendCubit>();
                  final String? account = await Navigator.of(context).push<
                      String>(
                    MaterialPageRoute(builder: (_) => const QrScanPage()),
                  );
                  if (account != null && account.isNotEmpty) {
                    cubit.toggleTarget(account);
                  }
                },
                manualController: _manual,
                onManualAdd: () {
                  final String v = _manual.text.trim();
                  if (v.isNotEmpty) {
                    context.read<SendCubit>().toggleTarget(v);
                    _manual.clear();
                  }
                },
              ),
              const Divider(),
              CommandPanel(
                onCommand: (String body) =>
                    context.read<SendCubit>().sendRaw(body),
              ),
              const Spacer(),
              _SendResultBanner(results: state.sendResults, directory: dir),
              TextField(
                controller: _text,
                decoration: const InputDecoration(hintText: '群发文本'),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: state.isSending
                      ? null
                      : () {
                          context
                              .read<SendCubit>()
                              .sendPlainText(_text.text.trim());
                          _text.clear();
                        },
                  child: Text(
                    state.isSending ? '发送中…' : '群发（${state.targets.length} 台）',
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 发送结果横幅：「已发 x/y 台」，失败目标可点重试。
class _SendResultBanner extends StatelessWidget {
  const _SendResultBanner({required this.results, required this.directory});

  final Map<String, bool> results;
  final TvDirectory directory;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) return const SizedBox.shrink();
    final int total = results.length;
    final int success = results.values.where((bool v) => v).length;
    final List<String> failed =
        results.entries.where((e) => !e.value).map((e) => e.key).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: <Widget>[
          Text('已发 $success/$total 台'),
          if (failed.isNotEmpty) ...<Widget>[
            const SizedBox(width: 12),
            Text(
              '失败: ${failed.map(directory.nameOf).join(", ")}',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            TextButton(
              onPressed: () => context.read<SendCubit>().retryFailed(failed),
              child: const Text('重试'),
            ),
          ],
        ],
      ),
    );
  }
}
