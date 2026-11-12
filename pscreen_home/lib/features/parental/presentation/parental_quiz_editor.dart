import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:pscreen_home/features/parental/data/parental_admin_api.dart';
import 'package:pscreen_home/features/parental/domain/parental_config.dart';
import 'package:pscreen_screen/app/config/app_constants.dart';

/// 儿童档案题库管理（答题解锁用）。
///
/// 题库存在服务端独立文件里（不随 parental 配置下发，见
/// `GET/PUT /api/admin/parental/quiz`）；本弹窗负责：
/// - 逐题添加 / 编辑 / 删除；
/// - JSON / CSV 文件导入（图片字段需先在题目里以 URL 形式存在）；
/// - 题干、选项配图上传（单张 ≤3MB，落盘后题目只存相对 URL）。
class ParentalQuizEditorSheet extends StatefulWidget {
  const ParentalQuizEditorSheet({
    super.key,
    required this.deviceId,
    required this.child,
    this.api = const ParentalAdminApi(),
  });

  final String deviceId;
  final ParentalChild child;
  final ParentalAdminApi api;

  static Future<void> show(
    BuildContext context, {
    required String deviceId,
    required ParentalChild child,
  }) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (BuildContext context) => ParentalQuizEditorSheet(
          deviceId: deviceId,
          child: child,
        ),
      );

  @override
  State<ParentalQuizEditorSheet> createState() =>
      _ParentalQuizEditorSheetState();
}

class _ParentalQuizEditorSheetState extends State<ParentalQuizEditorSheet> {
  final List<Map<String, dynamic>> _questions = <Map<String, dynamic>>[];
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final List<Map<String, dynamic>> list = await widget.api.fetchQuiz(
        widget.deviceId,
        widget.child.id,
      );
      if (!mounted) return;
      setState(() {
        _questions
          ..clear()
          ..addAll(list);
        _loading = false;
        _dirty = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = '$e';
      });
    }
  }

  Future<void> _edit([int? index]) async {
    final Map<String, dynamic>? result =
        await showModalBottomSheet<Map<String, dynamic>>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (BuildContext context) => QuizQuestionEditorSheet(
            deviceId: widget.deviceId,
            childId: widget.child.id,
            api: widget.api,
            initial: index == null ? null : _questions[index],
          ),
        );
    if (result == null || !mounted) return;
    setState(() {
      if (index == null) {
        _questions.add(result);
      } else {
        _questions[index] = result;
      }
      _dirty = true;
    });
  }

  Future<void> _delete(int index) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('删除题目'),
        content: Text('确定删除第 ${index + 1} 题？保存后生效。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _questions.removeAt(index);
      _dirty = true;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.api.saveQuiz(
        widget.deviceId,
        widget.child.id,
        _questions,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已保存 ${_questions.length} 道题')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败：$e')));
    }
  }

  Future<void> _import(String ext) async {
    try {
      final List<PlatformFile> picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: <String>[ext],
      );
      if (picked.isEmpty) return;
      final Uint8List bytes = await picked.first.readAsBytes();
      final String text = utf8.decode(bytes, allowMalformed: true);
      final List<Map<String, dynamic>> parsed = ext == 'json'
          ? _parseJsonQuestions(text)
          : _parseCsvQuestions(text);
      if (parsed.isEmpty) throw const FormatException('文件里没有可用题目');
      final Set<String> existingIds = <String>{
        for (final Map<String, dynamic> q in _questions) '${q['id']}',
      };
      int added = 0;
      int skipped = 0;
      for (final Map<String, dynamic> q in parsed) {
        if (existingIds.contains('${q['id']}')) {
          skipped++;
          continue;
        }
        existingIds.add('${q['id']}');
        _questions.add(q);
        added++;
      }
      setState(() => _dirty = _dirty || added > 0);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入完成：新增 $added 题，跳过重复 $skipped 题')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('导入失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final int maxQuestions = 200;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '${widget.child.name} · 题库（${_questions.length}/$maxQuestions）',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
              Text(
                '家长选中「答题解锁」后，电视只能用这些题解锁；'
                '多个孩子同时选中时，取年龄最大的题库，同岁合并。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              const SizedBox(height: 8),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_loadError != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('题库读取失败：$_loadError'),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _load,
                      child: const Text('重试'),
                    ),
                  ],
                )
              else ...<Widget>[
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    FilledButton.icon(
                      onPressed: _questions.length >= maxQuestions
                          ? null
                          : () => _edit(),
                      icon: const Icon(Icons.add),
                      label: const Text('添加题目'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _import('json'),
                      icon: const Icon(Icons.file_open_outlined),
                      label: const Text('导入 JSON'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _import('csv'),
                      icon: const Icon(Icons.file_open_outlined),
                      label: const Text('导入 CSV'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'CSV 列：type,prompt,options,answers,multiple；'
                  'options 用 | 分隔，选择题 answers 填选项序号（从 1 开始），'
                  '填空 answers 填可接受答案。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 12),
                if (_questions.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        '还没有题目，先添加或导入吧',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  )
                else
                  for (int i = 0; i < _questions.length; i++)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          radius: 14,
                          child: Text('${i + 1}', style: const TextStyle(fontSize: 12)),
                        ),
                        title: Text(
                          _summaryOf(_questions[i]),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(_describe(_questions[i])),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            IconButton(
                              tooltip: '编辑',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _edit(i),
                            ),
                            IconButton(
                              tooltip: '删除',
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _delete(i),
                            ),
                          ],
                        ),
                      ),
                    ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: <Widget>[
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).maybePop(),
                      child: const Text('关闭'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _saving || !_dirty ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('保存题库'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _summaryOf(Map<String, dynamic> q) {
    final String prompt = '${q['prompt'] ?? ''}'.trim();
    if (prompt.isNotEmpty) return prompt;
    if ('${q['promptImage'] ?? ''}'.isNotEmpty) return '（图片题）';
    return '${q['id'] ?? ''}';
  }

  static String _describe(Map<String, dynamic> q) {
    final bool isFill = q['type'] == 'fill';
    if (isFill) {
      final List<dynamic> accept = q['accept'] is List
          ? q['accept'] as List<dynamic>
          : const <dynamic>[];
      return '填空 · 可接受答案：${accept.join(' / ')}';
    }
    final List<dynamic> options = q['options'] is List
        ? q['options'] as List<dynamic>
        : const <dynamic>[];
    final String mode = q['multiple'] == true ? '多选' : '单选';
    final String texts = options.map((dynamic o) {
      if (o is Map) return '${o['text'] ?? ''}'.trim();
      return '$o';
    }).where((String t) => t.isNotEmpty).join(' / ');
    return '$mode · $texts';
  }

  /// JSON：顶层数组，或 `{ "questions": [...] }`。
  static List<Map<String, dynamic>> _parseJsonQuestions(String text) {
    final dynamic raw = jsonDecode(text);
    final dynamic list = raw is List
        ? raw
        : (raw is Map ? raw['questions'] : null);
    if (list is! List) throw const FormatException('JSON 需为数组或含 questions 数组');
    final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
    for (int i = 0; i < list.length; i++) {
      final dynamic item = list[i];
      if (item is! Map) throw FormatException('第 ${i + 1} 条不是对象');
      final Map<String, dynamic> q = Map<String, dynamic>.from(item);
      q['id'] = (q['id'] as String?)?.trim().isNotEmpty == true
          ? q['id']
          : 'q${DateTime.now().millisecondsSinceEpoch}_$i';
      q['type'] = q['type'] == 'fill' ? 'fill' : 'choice';
      out.add(q);
    }
    return out;
  }

  /// CSV：type,prompt,options,answers,multiple（无引号语法，内容里别用英文逗号）。
  static List<Map<String, dynamic>> _parseCsvQuestions(String text) {
    final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
    final List<String> lines = const LineSplitter().convert(text);
    for (int i = 0; i < lines.length; i++) {
      final String line = lines[i].trim();
      if (line.isEmpty) continue;
      if (i == 0 && line.toLowerCase().startsWith('type,')) continue;
      final List<String> cells = line.split(',');
      if (cells.length < 4) {
        throw FormatException('第 ${i + 1} 行少于 4 列');
      }
      final String type = cells[0].trim() == 'fill' ? 'fill' : 'choice';
      final String prompt = cells[1].trim();
      final List<String> parts = cells[2]
          .split('|')
          .map((String item) => item.trim())
          .where((String item) => item.isNotEmpty)
          .toList();
      final String multipleCell = cells.length > 4 ? cells[4].trim() : '';
      final Map<String, dynamic> q = <String, dynamic>{
        'id': 'q${DateTime.now().millisecondsSinceEpoch}_$i',
        'type': type,
        'prompt': prompt,
      };
      if (type == 'fill') {
        q['accept'] = parts;
      } else {
        q['multiple'] = multipleCell == 'true' || multipleCell == '1';
        q['options'] = parts;
        final List<int> answers = <int>[];
        for (final String item in cells[3].split('|')) {
          final int? index = int.tryParse(item.trim());
          if (index != null && index >= 1) answers.add(index - 1);
        }
        q['answers'] = answers;
      }
      out.add(q);
    }
    return out;
  }
}

/// 单题编辑：支持选择题（单选 / 多选、2~10 个选项、选项图文）与填空题。
class QuizQuestionEditorSheet extends StatefulWidget {
  const QuizQuestionEditorSheet({
    super.key,
    required this.deviceId,
    required this.childId,
    required this.api,
    this.initial,
  });

  final String deviceId;
  final String childId;
  final ParentalAdminApi api;
  final Map<String, dynamic>? initial;

  @override
  State<QuizQuestionEditorSheet> createState() =>
      _QuizQuestionEditorSheetState();
}

class _OptionDraft {
  _OptionDraft({String text = '', this.image = ''})
      : controller = TextEditingController(text: text);

  final TextEditingController controller;

  /// 选项输入框焦点：新增选项后主动聚焦到新框，避免输入落到上一个选项里。
  final FocusNode focusNode = FocusNode(debugLabel: 'quiz-option');

  String image;

  void dispose() {
    controller.dispose();
    focusNode.dispose();
  }
}

class _QuizQuestionEditorSheetState extends State<QuizQuestionEditorSheet> {
  static const int _maxOptions = 10;
  static const int _maxImageBytes = 3 * 1024 * 1024;

  late final TextEditingController _prompt;
  late final TextEditingController _accept;
  late String _id;
  late String _type;
  late bool _multiple;
  late String _promptImage;
  final List<_OptionDraft> _options = <_OptionDraft>[];
  final Set<int> _answers = <int>{};
  String? _error;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    final Map<String, dynamic>? init = widget.initial;
    _id =
        (init?['id'] as String?)?.trim().isNotEmpty == true
        ? init!['id'] as String
        : 'q${DateTime.now().millisecondsSinceEpoch}';
    _type = init?['type'] == 'fill' ? 'fill' : 'choice';
    _multiple = init?['multiple'] == true;
    _prompt = TextEditingController(text: '${init?['prompt'] ?? ''}');
    _accept = TextEditingController(
      text: (init?['accept'] is List)
          ? (init!['accept'] as List).join('\n')
          : '',
    );
    _promptImage = '${init?['promptImage'] ?? ''}';
    final Object? rawOptions = init?['options'];
    if (rawOptions is List && rawOptions.isNotEmpty) {
      for (final Object? item in rawOptions) {
        if (item is Map) {
          _options.add(
            _OptionDraft(
              text: '${item['text'] ?? ''}',
              image: '${item['image'] ?? ''}',
            ),
          );
        } else {
          _options.add(_OptionDraft(text: '$item'));
        }
      }
    }
    while (_options.length < 2) {
      _options.add(_OptionDraft());
    }
    final Object? rawAnswers = init?['answers'];
    if (rawAnswers is List) {
      for (final Object? item in rawAnswers) {
        if (item is num) _answers.add(item.toInt());
      }
    }
  }

  @override
  void dispose() {
    _prompt.dispose();
    _accept.dispose();
    for (final _OptionDraft option in _options) {
      option.dispose();
    }
    super.dispose();
  }

  void _save() {
    final String prompt = _prompt.text.trim();
    if (prompt.isEmpty && _promptImage.isEmpty) {
      setState(() => _error = '请填写题干或上传题干图片');
      return;
    }
    if (_type == 'choice') {
      if (_options.length < 2 || _options.length > _maxOptions) {
        setState(() => _error = '选择题需要 2~$_maxOptions 个选项');
        return;
      }
      for (int i = 0; i < _options.length; i++) {
        if (_options[i].controller.text.trim().isEmpty &&
            _options[i].image.isEmpty) {
          setState(() => _error = '第 ${i + 1} 个选项的文案和图片不能同时为空');
          return;
        }
      }
      if (_answers.isEmpty) {
        setState(() => _error = '请勾选正确答案');
        return;
      }
      if (!_multiple && _answers.length != 1) {
        setState(() => _error = '单选题只能勾选 1 个正确答案');
        return;
      }
    } else {
      final List<String> accept = _accept.text
          .split('\n')
          .map((String item) => item.trim())
          .where((String item) => item.isNotEmpty)
          .toList();
      if (accept.isEmpty) {
        setState(() => _error = '请至少填写 1 个可接受答案');
        return;
      }
    }
    final Map<String, dynamic> result = <String, dynamic>{
      'id': _id,
      'type': _type,
      'prompt': prompt,
      if (_promptImage.isNotEmpty) 'promptImage': _promptImage,
      'multiple': _type == 'choice' && _multiple,
      if (_type == 'choice')
        'options': _options
            .map(
              (_OptionDraft o) => <String, dynamic>{
                'text': o.controller.text.trim(),
                if (o.image.isNotEmpty) 'image': o.image,
              },
            )
            .toList(),
      if (_type == 'choice') 'answers': _answers.toList()..sort(),
      if (_type == 'fill')
        'accept': _accept.text
            .split('\n')
            .map((String item) => item.trim())
            .where((String item) => item.isNotEmpty)
            .toList(),
    };
    Navigator.of(context).pop(result);
  }

  Future<void> _pickImage({required void Function(String url) apply}) async {
    if (_uploading) return;
    try {
      final PlatformFile? picked = await FilePicker.pickFile(
        type: FileType.image,
      );
      if (picked == null) return;
      final Uint8List bytes = await picked.readAsBytes();
      if (bytes.length > _maxImageBytes) {
        throw const FormatException('图片不能超过 3MB');
      }
      final String ext = (picked.extension ?? 'png').toLowerCase();
      final String mime = switch (ext) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'webp' => 'image/webp',
        'gif' => 'image/gif',
        _ => 'image/png',
      };
      setState(() => _uploading = true);
      final String url = await widget.api.uploadQuizImage(
        widget.deviceId,
        widget.childId,
        bytes: bytes,
        mime: mime,
      );
      if (!mounted) return;
      setState(() {
        _uploading = false;
        apply(url);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('图片上传失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Text(
                    widget.initial == null ? '添加题目' : '编辑题目',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '关闭',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                children: <Widget>[
                  ChoiceChip(
                    label: const Text('选择题'),
                    selected: _type == 'choice',
                    onSelected: (_) => setState(() => _type = 'choice'),
                  ),
                  ChoiceChip(
                    label: const Text('填空题'),
                    selected: _type == 'fill',
                    onSelected: (_) => setState(() => _type = 'fill'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _prompt,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '题干',
                  hintText: '例：3 + 5 = ?',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              _ImageRow(
                label: '题干图片',
                url: _promptImage,
                uploading: _uploading,
                onPick: () => _pickImage(
                  apply: (String url) => setState(() => _promptImage = url),
                ),
                onClear: () => setState(() => _promptImage = ''),
              ),
              const SizedBox(height: 12),
              if (_type == 'choice') ...<Widget>[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('多选题'),
                  subtitle: const Text('开启后可勾选多个正确选项'),
                  value: _multiple,
                  onChanged: (bool value) => setState(() {
                    _multiple = value;
                    if (!value && _answers.length > 1) {
                      final int keep = _answers.first;
                      _answers
                        ..clear()
                        ..add(keep);
                    }
                  }),
                ),
                for (int i = 0; i < _options.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: <Widget>[
                        SizedBox(
                          width: 22,
                          child: Text('${i + 1}.'),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _options[i].controller,
                            focusNode: _options[i].focusNode,
                            decoration: InputDecoration(
                              hintText: '选项 ${i + 1}',
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '选项图片',
                          icon: Icon(
                            _options[i].image.isEmpty
                                ? Icons.image_outlined
                                : Icons.image,
                            size: 18,
                          ),
                          onPressed: () => _pickImage(
                            apply: (String url) =>
                                setState(() => _options[i].image = url),
                          ),
                        ),
                        IconButton(
                          tooltip: '删除选项',
                          icon: const Icon(
                            Icons.remove_circle_outline,
                            size: 18,
                          ),
                          onPressed: _options.length <= 2
                              ? null
                              : () => setState(() {
                                  _options.removeAt(i).dispose();
                                  // 删除第 i 个后，大于 i 的正确选项下标整体前移。
                                  final List<int> next = _answers
                                      .where((int a) => a != i)
                                      .map((int a) => a > i ? a - 1 : a)
                                      .toList();
                                  _answers
                                    ..clear()
                                    ..addAll(next);
                                }),
                        ),
                      ],
                    ),
                  ),
                if (_options.length < _maxOptions)
                  TextButton.icon(
                    onPressed: () {
                      final _OptionDraft draft = _OptionDraft();
                      setState(() => _options.add(draft));
                      // 新选项输入框在下一帧才挂到树上，届时聚焦并滚动到可见区
                      // （TextField 获得焦点会自动把自身滚进视口）。
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) draft.focusNode.requestFocus();
                      });
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('添加选项'),
                  ),
                const SizedBox(height: 4),
                Text('正确答案（点选）', style: theme.textTheme.bodySmall),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: <Widget>[
                    for (int i = 0; i < _options.length; i++)
                      FilterChip(
                        label: Text('${i + 1}'),
                        selected: _answers.contains(i),
                        onSelected: (bool selected) => setState(() {
                          if (!_multiple) {
                            _answers
                              ..clear()
                              ..add(i);
                          } else if (selected) {
                            _answers.add(i);
                          } else {
                            _answers.remove(i);
                          }
                        }),
                      ),
                  ],
                ),
              ] else ...<Widget>[
                TextField(
                  controller: _accept,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: '可接受答案（每行一个）',
                    hintText: '北京\nBeijing',
                    helperText: '判题时忽略大小写、首尾与内部空格',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
              if (_error != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _uploading ? null : _save,
                    child: const Text('确定'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 图片选择行：显示缩略图 + 选择 / 移除。
class _ImageRow extends StatelessWidget {
  const _ImageRow({
    required this.label,
    required this.url,
    required this.uploading,
    required this.onPick,
    required this.onClear,
  });

  final String label;
  final String url;
  final bool uploading;
  final VoidCallback onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      children: <Widget>[
        Text(label, style: theme.textTheme.bodySmall),
        const SizedBox(width: 12),
        if (url.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.network(
              url.startsWith('http') ? url : '${AppConstants.toolsBaseUrl}$url',
              width: 56,
              height: 56,
              fit: BoxFit.cover,
              errorBuilder: (
                BuildContext context,
                Object error,
                StackTrace? stack,
              ) => const Icon(Icons.broken_image_outlined, size: 28),
            ),
          ),
        TextButton(
          onPressed: uploading ? null : onPick,
          child: Text(uploading ? '上传中…' : (url.isEmpty ? '选择图片' : '更换')),
        ),
        if (url.isNotEmpty)
          IconButton(
            tooltip: '移除图片',
            icon: const Icon(Icons.close, size: 18),
            onPressed: onClear,
          ),
      ],
    );
  }
}
