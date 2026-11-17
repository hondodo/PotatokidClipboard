import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:pscreen_screen/features/iptv/application/recording/recording_library_controller.dart';
import 'package:pscreen_screen/features/iptv/application/recording/recording_platform.dart'
    show RecordedFile;
import 'package:pscreen_screen/features/iptv/application/recording/recording_storage.dart';
import 'package:potatokid_screen/core/di/injection.dart';
import 'package:potatokid_screen/core/router/app_router.dart';
import 'package:potatokid_screen/core/router/route_params.dart';

/// 录制中心弹层：两个 Tab「录制设置」「录制列表」。
///
/// 用原生按钮承载焦点（遥控 OK / 触屏点击一致），不自研 16 行焦点链，
/// 避免影响「我的」页既有遥控逻辑。
class RecordingSheetPage extends StatefulWidget {
  const RecordingSheetPage({super.key});

  @override
  State<RecordingSheetPage> createState() => _RecordingSheetPageState();
}

class _RecordingSheetPageState extends State<RecordingSheetPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final RecordingStorage _storage = RecordingStorage();
  final RecordingLibraryController _library = RecordingLibraryController.instance;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _library.refresh();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext finalContext) {
    final ThemeData theme = Theme.of(finalContext);
    return Align(
      alignment: Alignment.bottomCenter,
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'recording_center_title'.tr(),
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    TextButton(
                      onPressed: () => Injection.get<AppRouter>().pop(),
                      child: Text('action_close'.tr()),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TabBar(
                  controller: _tabs,
                  tabs: <Widget>[
                    Tab(text: 'recording_tab_settings'.tr()),
                    Tab(text: 'recording_tab_files'.tr()),
                  ],
                ),
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(finalContext).height * 0.62,
                  ),
                  child: TabBarView(
                    controller: _tabs,
                    children: <Widget>[
                      _SettingsTab(storage: _storage, library: _library),
                      _FilesTab(storage: _storage, library: _library),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 录制设置：存储位置、可用空间、单文件上限、低空间阈值。
class _SettingsTab extends StatefulWidget {
  const _SettingsTab({required this.storage, required this.library});

  final RecordingStorage storage;
  final RecordingLibraryController library;

  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  late String _locationLabel;
  late int _maxMb;
  late int _lowMb;
  String _freeText = '—';

  static const List<int> _maxOptions = <int>[512, 1024, 2048, 4096];
  static const List<int> _lowOptions = <int>[256, 512, 1024, 2048];

  @override
  void initState() {
    super.initState();
    _sync();
    _loadFree();
  }

  void _sync() {
    _locationLabel = widget.storage.locationLabel;
    _maxMb = (widget.storage.maxFileBytes / (1024 * 1024)).round();
    _lowMb = (widget.storage.lowSpaceBytes / (1024 * 1024)).round();
  }

  Future<void> _loadFree() async {
    final int free = await widget.storage.freeBytes();
    if (!mounted) return;
    setState(() {
      _freeText = free < 0
          ? 'recording_space_unknown'.tr()
          : RecordingLibraryController.formatSize(free);
    });
  }

  Future<void> _pickDir() async {
    final bool ok = await widget.storage.pickAndSetDirectory();
    if (!mounted) return;
    if (ok) {
      setState(() {
        _sync();
      });
      await _loadFree();
      await widget.library.refresh();
    }
  }

  Future<void> _useInternal() async {
    await widget.storage.useInternal();
    if (!mounted) return;
    setState(_sync);
    await _loadFree();
    await widget.library.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: <Widget>[
        ListTile(
          title: Text('recording_location'.tr()),
          subtitle: Text(_locationLabel),
          trailing: TextButton(
            onPressed: _pickDir,
            child: Text('recording_choose_dir'.tr()),
          ),
        ),
        ListTile(
          title: Text('recording_use_internal'.tr()),
          onTap: _useInternal,
        ),
        ListTile(
          title: Text('recording_free_space'.tr()),
          subtitle: Text(_freeText),
          trailing: IconButton(
            onPressed: _loadFree,
            icon: const Icon(Icons.refresh),
            tooltip: 'action_refresh'.tr(),
          ),
        ),
        ListTile(
          title: Text('recording_max_file'.tr()),
          subtitle: Text('$_maxMb MB'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              IconButton(
                onPressed: () => _stepMax(-1),
                icon: const Icon(Icons.remove_circle_outline),
              ),
              IconButton(
                onPressed: () => _stepMax(1),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
        ),
        ListTile(
          title: Text('recording_low_space'.tr()),
          subtitle: Text('$_lowMb MB'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              IconButton(
                onPressed: () => _stepLow(-1),
                icon: const Icon(Icons.remove_circle_outline),
              ),
              IconButton(
                onPressed: () => _stepLow(1),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _stepMax(int delta) async {
    int idx = _maxOptions.indexOf(_maxMb);
    if (idx < 0) idx = 2;
    final int next = (idx + delta).clamp(0, _maxOptions.length - 1);
    await widget.storage.setMaxFileMb(_maxOptions[next]);
    if (!mounted) return;
    setState(() {
      _maxMb = _maxOptions[next];
    });
  }

  Future<void> _stepLow(int delta) async {
    int idx = _lowOptions.indexOf(_lowMb);
    if (idx < 0) idx = 1;
    final int next = (idx + delta).clamp(0, _lowOptions.length - 1);
    await widget.storage.setLowSpaceMb(_lowOptions[next]);
    if (!mounted) return;
    setState(() {
      _lowMb = _lowOptions[next];
    });
  }
}

/// 录制列表：列出 / 播放 / 删除。
class _FilesTab extends StatefulWidget {
  const _FilesTab({required this.storage, required this.library});

  final RecordingStorage storage;
  final RecordingLibraryController library;

  @override
  State<_FilesTab> createState() => _FilesTabState();
}

class _FilesTabState extends State<_FilesTab> {
  @override
  void initState() {
    super.initState();
    widget.library.refresh();
  }

  Future<void> _play(RecordedFile file) async {
    await Injection.get<AppRouter>().pushRecordingPlayback(
          RecordingPlaybackParams(uri: file.uri, title: file.name),
        );
  }

  Future<void> _delete(RecordedFile file) async {
    final bool ok = await widget.library.delete(file);
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'recording_deleted'.tr() : 'recording_delete_failed'.tr(),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<RecordedFile>>(
      valueListenable: widget.library.items,
      builder: (context, items, _) {
        if (items.isEmpty) {
          return Center(child: Text('recording_empty'.tr()));
        }
        return ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final RecordedFile f = items[i];
            final String size = RecordingLibraryController.formatSize(f.size);
            return ListTile(
              title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(size),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  IconButton(
                    onPressed: () => _play(f),
                    icon: const Icon(Icons.play_circle_outline),
                    tooltip: 'recording_play'.tr(),
                  ),
                  IconButton(
                    onPressed: () => _delete(f),
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'recording_delete'.tr(),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
