import 'package:flutter/material.dart';

import 'package:pscreen_screen/features/iptv/application/recording/recording_library_controller.dart';
import 'package:pscreen_screen/features/iptv/application/recording/recording_platform.dart'
    show RecordedFile;
import 'package:pscreen_screen/features/iptv/application/recording/recording_storage.dart';
import 'package:pscreen_home/features/settings/presentation/widgets/recording_playback_page.dart';

/// 录制设置分组（嵌入设置页，不占路由）。
///
/// 包含：存储位置选择 / 可用空间 / 单文件上限 / 低空间阈值 / 录制文件列表。
class RecordingSettingsSection extends StatefulWidget {
  const RecordingSettingsSection({super.key});

  @override
  State<RecordingSettingsSection> createState() => _RecordingSettingsSectionState();
}

class _RecordingSettingsSectionState extends State<RecordingSettingsSection> {
  final RecordingStorage _storage = RecordingStorage();
  final RecordingLibraryController _library = RecordingLibraryController.instance;

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
    _library.refresh();
  }

  void _sync() {
    _locationLabel = _storage.locationLabel;
    _maxMb = (_storage.maxFileBytes / (1024 * 1024)).round();
    _lowMb = (_storage.lowSpaceBytes / (1024 * 1024)).round();
  }

  Future<void> _loadFree() async {
    final int free = await _storage.freeBytes();
    if (!mounted) return;
    setState(() {
      _freeText = free < 0 ? '无法获取（设备可能不支持）' : RecordingLibraryController.formatSize(free);
    });
  }

  Future<void> _pickDir() async {
    final bool ok = await _storage.pickAndSetDirectory();
    if (!mounted || !ok) return;
    setState(_sync);
    await _loadFree();
    await _library.refresh();
  }

  Future<void> _useInternal() async {
    await _storage.useInternal();
    if (!mounted) return;
    setState(_sync);
    await _loadFree();
    await _library.refresh();
  }

  Future<void> _stepMax(int delta) async {
    int idx = _maxOptions.indexOf(_maxMb);
    if (idx < 0) idx = 2;
    final next = (idx + delta).clamp(0, _maxOptions.length - 1);
    await _storage.setMaxFileMb(_maxOptions[next]);
    if (mounted) setState(() => _maxMb = _maxOptions[next]);
  }

  Future<void> _stepLow(int delta) async {
    int idx = _lowOptions.indexOf(_lowMb);
    if (idx < 0) idx = 1;
    final next = (idx + delta).clamp(0, _lowOptions.length - 1);
    await _storage.setLowSpaceMb(_lowOptions[next]);
    if (mounted) setState(() => _lowMb = _lowOptions[next]);
  }

  void _play(RecordedFile file) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RecordingPlaybackPage(uri: file.uri, title: file.name),
      ),
    );
  }

  Future<void> _delete(RecordedFile file) async {
    final bool ok = await _library.delete(file);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '已删除' : '删除失败'), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const SizedBox(height: 24),
        Text('录制设置', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        ListTile(
          title: const Text('存储位置'),
          subtitle: Text(_locationLabel),
          trailing: TextButton(onPressed: _pickDir, child: const Text('选择目录')),
        ),
        ListTile(title: const Text('使用应用内部存储'), onTap: _useInternal),
        ListTile(
          title: const Text('可用空间'),
          subtitle: Text(_freeText),
          trailing: IconButton(
            onPressed: _loadFree,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新',
          ),
        ),
        ListTile(
          title: const Text('单文件上限'),
          subtitle: Text('$_maxMb MB'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              IconButton(onPressed: () => _stepMax(-1), icon: const Icon(Icons.remove_circle_outline)),
              IconButton(onPressed: () => _stepMax(1), icon: const Icon(Icons.add_circle_outline)),
            ],
          ),
        ),
        ListTile(
          title: const Text('低空间提醒阈值'),
          subtitle: Text('$_lowMb MB'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              IconButton(onPressed: () => _stepLow(-1), icon: const Icon(Icons.remove_circle_outline)),
              IconButton(onPressed: () => _stepLow(1), icon: const Icon(Icons.add_circle_outline)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text('录制文件', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        ValueListenableBuilder<List<RecordedFile>>(
          valueListenable: _library.items,
          builder: (context, items, _) {
            if (items.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('暂无录制文件', style: TextStyle(color: Colors.grey)),
              );
            }
            return Column(
              children: items.map((f) => ListTile(
                title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(RecordingLibraryController.formatSize(f.size)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    IconButton(onPressed: () => _play(f), icon: const Icon(Icons.play_circle_outline), tooltip: '播放'),
                    IconButton(onPressed: () => _delete(f), icon: const Icon(Icons.delete_outline), tooltip: '删除'),
                  ],
                ),
              )).toList(),
            );
          },
        ),
      ],
    );
  }
}
