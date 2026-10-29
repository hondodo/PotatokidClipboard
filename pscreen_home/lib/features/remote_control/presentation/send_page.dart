import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pscreen_home/features/remote_control/core/control_config.dart';
import 'package:pscreen_home/core/di/injection.dart';
import 'package:pscreen_home/features/remote_control/application/send_cubit.dart';
import 'package:pscreen_home/features/remote_control/data/tv_directory.dart';
import 'package:pscreen_home/features/remote_control/presentation/widgets/command_panel.dart';
import 'package:pscreen_home/features/remote_control/presentation/widgets/target_remote_panel.dart';
import 'package:pscreen_home/features/remote_control/presentation/widgets/target_picker.dart';
import 'package:pscreen_home/features/remote_control/presentation/qr_scan_page.dart';
import 'package:pscreen_screen/core/network/realtime_channel.dart';
import 'package:pscreen_screen/core/utils/app_settings.dart';

/// 发送端主页：按账号分叉。
class SendPage extends StatelessWidget {
  const SendPage({super.key});

  @override
  Widget build(BuildContext context) {
    // 自定义账号为空 = 用设备号上报，天然不是管理员。
    final String account = AppSettings.instance.remoteAccount;
    final bool isAdmin = account == ControlConfig.adminAccount;
    return BlocProvider<SendCubit>(
      create: (_) => SendCubit(
        channel: Injection.get<RealtimeChannel>(),
        persistTargets: isAdmin,
        isAdmin: isAdmin,
      ),
      child: isAdmin ? const _AdminSendShell() : const _FamilySendPage(),
    );
  }
}

/// 断线提示 mixin：实时通道断开（含重连中）时提示。
///
/// `hideCurrentSnackBar` 先收起旧提示，避免重连期间提示堆积。
mixin _DisconnectHintMixin<T extends StatefulWidget> on State<T> {
  StreamSubscription<RealtimeConnectionState>? _stateSub;

  @override
  void initState() {
    super.initState();
    _stateSub = Injection.get<RealtimeChannel>()
        .connectionState
        .listen((RealtimeConnectionState s) {
      if (s == RealtimeConnectionState.disconnected) _showDisconnected();
    });
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    super.dispose();
  }

  void _showDisconnected() {
    if (!mounted) return;
    final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('连接断开，正在重连…')));
  }
}

/// 家人单页「发指令」：文本框 + 命令面板 + 手动/扫码选一台。
class _FamilySendPage extends StatefulWidget {
  const _FamilySendPage();

  @override
  State<_FamilySendPage> createState() => _FamilySendPageState();
}

class _FamilySendPageState extends State<_FamilySendPage>
    with _DisconnectHintMixin<_FamilySendPage> {
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
    final String? account = await Navigator.of(
      context,
    ).push<String>(MaterialPageRoute(builder: (_) => const QrScanPage()));
    if (account != null && account.isNotEmpty) {
      cubit.setSingleTarget(account);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SendCubit, SendState>(
      builder: (BuildContext context, SendState state) {
        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('目标: ${state.targets.join(", ")}'),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _manual,
                        decoration: const InputDecoration(
                          hintText: '手动输入 TV 账号',
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: () {
                        final String v = _manual.text.trim();
                        if (v.isNotEmpty) {
                          context.read<SendCubit>().setSingleTarget(v);
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
                // 已选目标：按设备类型展示对应遥控面板（进入即 watch 场景状态）；
                // 未选目标时仍给出通用面板并提示先选目标。
                if (state.targets.isNotEmpty)
                  TargetRemotePanel(
                    account: state.targets.first,
                    onCommand: (String body) =>
                        context.read<SendCubit>().sendTo(state.targets.first, body),
                  )
                else
                  CommandPanel(
                    onCommand: (String body) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('请先选择目标')));
                    },
                  ),
                const SizedBox(height: 12),
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
                        : () async {
                            final SendCubit cubit = context.read<SendCubit>();
                            if (cubit.state.targets.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('请先选择目标')),
                              );
                              return;
                            }
                            await cubit.sendPlainText(_text.text.trim());
                            _text.clear();
                            if (!context.mounted) return;
                            final Map<String, bool> r =
                                cubit.state.sendResults;
                            final int ok = r.values
                                .where((bool v) => v)
                                .length;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  r.isEmpty ? '未发送' : '已发 $ok/${r.length} 台',
                                ),
                              ),
                            );
                          },
                    child: const Text('发送'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 管理员外壳：外层 TabBar（遥控面板 / 会话）由 RemoteControlPage 提供，
/// 这里只负责「群发」内容，不再自带 Scaffold 与 TabBar。
class _AdminSendShell extends StatelessWidget {
  const _AdminSendShell();

  @override
  Widget build(BuildContext context) {
    return const _BroadcastTab();
  }
}

/// 群发 tab。
class _BroadcastTab extends StatefulWidget {
  const _BroadcastTab();

  @override
  State<_BroadcastTab> createState() => _BroadcastTabState();
}

class _BroadcastTabState extends State<_BroadcastTab>
    with AutomaticKeepAliveClientMixin, _DisconnectHintMixin<_BroadcastTab> {
  final TextEditingController _text = TextEditingController();
  final TextEditingController _manual = TextEditingController();

  @override
  bool get wantKeepAlive => true;

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
        final TvDirectory dir = Injection.get<TvDirectory>();
        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TargetPicker(
                  devices: dir.devices,
                  selected: state.targets.toSet(),
                  onToggle: context.read<SendCubit>().toggleTarget,
                  onScan: () async {
                    final SendCubit cubit = context.read<SendCubit>();
                    final String? account = await Navigator.of(context)
                        .push<String>(
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
                // 非预设目标（手动/扫码/历史）以可移除 chip 展示
                Builder(builder: (BuildContext context) {
                  final Set<String> presetAccounts =
                      dir.devices.map((TvDevice d) => d.account).toSet();
                  final List<String> extra = state.targets
                      .where((String a) => !presetAccounts.contains(a))
                      .toList();
                  if (extra.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: extra
                          .map((String a) => Chip(
                                label: Text(dir.nameOf(a)),
                                onDeleted: () =>
                                    context.read<SendCubit>().toggleTarget(a),
                              ))
                          .toList(),
                    ),
                  );
                }),
                const Divider(),
                // 每个已选目标一张可折叠卡片：展开后是对应设备类型的遥控面板。
                // 只选一台时默认展开，免去多余点击。
                if (state.targets.isEmpty)
                  CommandPanel(
                    onCommand: (String body) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('请先选择目标')));
                    },
                  )
                else
                  ...state.targets.map(
                    (String account) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ExpansionTile(
                        title: Text(dir.nameOf(account)),
                        initiallyExpanded: state.targets.length == 1,
                        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        children: <Widget>[
                          TargetRemotePanel(
                            account: account,
                            showHeader: false,
                            onCommand: (String body) =>
                                context.read<SendCubit>().sendTo(account, body),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
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
                            final SendCubit cubit = context.read<SendCubit>();
                            if (cubit.state.targets.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('请先选择目标')),
                              );
                              return;
                            }
                            cubit.sendPlainText(_text.text.trim());
                            _text.clear();
                          },
                    child: Text(
                      state.isSending
                          ? '发送中…'
                          : '群发（${state.targets.length} 台）',
                    ),
                  ),
                ),
              ],
            ),
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
    final List<String> failed = results.entries
        .where((e) => !e.value)
        .map((e) => e.key)
        .toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: <Widget>[
          Text('已发 $success/$total 台'),
          if (failed.isNotEmpty) ...<Widget>[
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '失败: ${failed.map(directory.nameOf).join(", ")}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
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
