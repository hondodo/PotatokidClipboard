import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:pscreen_screen/app/app_log.dart';
import 'package:pscreen_screen/app/config/app_constants.dart';
import 'package:pscreen_screen/core/parental/parental_config.dart';
import 'package:pscreen_screen/core/utils/device_credentials.dart';
import 'package:pscreen_screen/core/utils/ptools_util.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 答题解锁题库模型（服务端 `datas/admin/parental_quizzes.json` 同构）。
///
/// - `choice`：2~10 个选项，`answers` 为正确选项下标，`multiple` 表示多选；
/// - `fill`：`accept` 为可接受答案（大小写 / 空格归一后比对）；
/// - 图片字段只存服务端相对 URL，展示时由 [imageUrl] 补全为绝对地址。
@immutable
class ParentalQuizOption {
  const ParentalQuizOption({this.text = '', this.image = ''});

  final String text;
  final String image;

  bool get empty => text.isEmpty && image.isEmpty;

  factory ParentalQuizOption.fromJson(Map<String, dynamic> json) =>
      ParentalQuizOption(
        text: (json['text'] as String?)?.trim() ?? '',
        image: (json['image'] as String?)?.trim() ?? '',
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'text': text,
    if (image.isNotEmpty) 'image': image,
  };
}

@immutable
class ParentalQuizQuestion {
  const ParentalQuizQuestion({
    required this.id,
    required this.type,
    this.prompt = '',
    this.promptImage = '',
    this.multiple = false,
    this.options = const <ParentalQuizOption>[],
    this.answers = const <int>[],
    this.accept = const <String>[],
  });

  final String id;

  /// `choice`（选择）| `fill`（填空）。
  final String type;
  final String prompt;
  final String promptImage;
  final bool multiple;
  final List<ParentalQuizOption> options;
  final List<int> answers;
  final List<String> accept;

  bool get isChoice => type == 'choice';

  /// 题干图片绝对地址（空串表示无图）。
  String get promptImageUrl => resolveImageUrl(promptImage);

  factory ParentalQuizQuestion.fromJson(Map<String, dynamic> json) {
    final List<ParentalQuizOption> options = <ParentalQuizOption>[];
    final Object? rawOptions = json['options'];
    if (rawOptions is List) {
      for (final Object? item in rawOptions) {
        if (item is Map) {
          options.add(
            ParentalQuizOption.fromJson(Map<String, dynamic>.from(item)),
          );
        } else if (item is String) {
          options.add(ParentalQuizOption(text: item.trim()));
        }
      }
    }
    final List<int> answers = <int>[];
    final Object? rawAnswers = json['answers'];
    if (rawAnswers is List) {
      for (final Object? item in rawAnswers) {
        if (item is num) answers.add(item.toInt());
      }
    }
    return ParentalQuizQuestion(
      id: (json['id'] as String?)?.trim() ?? '',
      type: json['type'] == 'fill' ? 'fill' : 'choice',
      prompt: (json['prompt'] as String?)?.trim() ?? '',
      promptImage: (json['promptImage'] as String?)?.trim() ?? '',
      multiple: json['multiple'] == true,
      options: options,
      answers: answers,
      accept: (json['accept'] is List)
          ? (json['accept'] as List)
                .whereType<String>()
                .map((String item) => item.trim())
                .where((String item) => item.isNotEmpty)
                .toList(growable: false)
          : const <String>[],
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'type': type,
    'prompt': prompt,
    if (promptImage.isNotEmpty) 'promptImage': promptImage,
    'multiple': multiple,
    if (options.isNotEmpty)
      'options': options.map((ParentalQuizOption o) => o.toJson()).toList(),
    if (answers.isNotEmpty) 'answers': answers,
    if (accept.isNotEmpty) 'accept': accept,
  };

  /// 题库卡片的一行摘要（家长端列表用）。
  String get summary {
    if (prompt.isNotEmpty) return prompt;
    if (promptImage.isNotEmpty) return '（图片题）';
    if (options.isNotEmpty) return options.first.text;
    return id;
  }

  /// 服务端相对图片地址 → 绝对地址（已是 http(s) 则原样返回）。
  static String resolveImageUrl(String raw) {
    final String path = raw.trim();
    if (path.isEmpty) return '';
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    return '${AppConstants.toolsBaseUrl}$path';
  }
}

/// 多儿童题库合并（家长选中多个孩子时）。
///
/// 规则：**所有在看的档案题库全部合并**，按题目 id 去重（同一道题只出现一次）。
/// 出题次序不在这里决定：由 [ParentalQuizRotation] 做「稳定随机打乱 + 跨重启轮换」。
class ParentalQuizSelector {
  const ParentalQuizSelector._();

  static List<ParentalQuizQuestion> select({
    required List<ChildProfile> profiles,
    required Map<String, List<ParentalQuizQuestion>> banks,
  }) {
    final Map<String, ParentalQuizQuestion> merged =
        <String, ParentalQuizQuestion>{};
    for (final ChildProfile child in profiles) {
      for (final ParentalQuizQuestion q
          in banks[child.id] ?? const <ParentalQuizQuestion>[]) {
        merged.putIfAbsent(q.id, () => q);
      }
    }
    return merged.values.toList(growable: false);
  }
}

/// 出题次序与游标：稳定随机打乱 + 跨重启轮换。
///
/// - **稳定随机**：题库签名（题目 id 排序后拼接）不变时，随机种子与题目顺序
///   保持不变——否则「轮流」会因每次顺序不同而失去意义；题库增删题后签名变化，
///   自动换新种子重新打乱、游标归 0。
/// - **跨重启轮换**：记录「下一题」的题目 id（而不是下标），题库顺序调整也不会错位；
///   锁屏题库页与验证弹窗共用同一份游标，交替进入时继续往后出题。
class ParentalQuizRotation {
  const ParentalQuizRotation({required this.questions, required this.start});

  /// 打乱后的题目列表（消费方应使用这份顺序渲染与翻页）。
  final List<ParentalQuizQuestion> questions;

  /// 本次起始下标（`0 <= start < questions.length`）。
  final int start;

  static const String storageKey = 'parental_quiz_rotation_v1';

  /// 读取已保存的种子/游标，返回排好序的题目与起始下标。
  static Future<ParentalQuizRotation> prepare(
    List<ParentalQuizQuestion> questions,
  ) async {
    if (questions.isEmpty) {
      return const ParentalQuizRotation(
        questions: <ParentalQuizQuestion>[],
        start: 0,
      );
    }
    final String signature = _signatureOf(questions);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final Map<String, dynamic>? saved = _decode(prefs.getString(storageKey));
    final bool sameBank = saved != null && saved['signature'] == signature;
    final int seed = sameBank
        ? ((saved['seed'] as num?)?.toInt() ?? _newSeed())
        : _newSeed();
    final String? nextId = sameBank ? saved['nextId'] as String? : null;
    final List<ParentalQuizQuestion> ordered = List<ParentalQuizQuestion>.of(
      questions,
    )..shuffle(math.Random(seed));
    int start =
        nextId == null ? 0 : ordered.indexWhere((ParentalQuizQuestion q) => q.id == nextId);
    if (start < 0) start = 0;
    await _save(prefs, signature: signature, seed: seed, nextId: nextId);
    return ParentalQuizRotation(questions: ordered, start: start);
  }

  /// 答完第 [index] 题后，把下一题记为下次答题的起点。
  static Future<void> markAnswered(
    List<ParentalQuizQuestion> ordered,
    int index,
  ) async {
    if (ordered.isEmpty) return;
    final String signature = _signatureOf(ordered);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final Map<String, dynamic>? saved = _decode(prefs.getString(storageKey));
    final int seed = saved != null && saved['signature'] == signature
        ? ((saved['seed'] as num?)?.toInt() ?? _newSeed())
        : _newSeed();
    final int safe = index < 0 ? 0 : (index >= ordered.length ? ordered.length - 1 : index);
    final String nextId = ordered[(safe + 1) % ordered.length].id;
    await _save(prefs, signature: signature, seed: seed, nextId: nextId);
  }

  static String _signatureOf(List<ParentalQuizQuestion> questions) {
    final List<String> ids = questions
        .map((ParentalQuizQuestion q) => q.id)
        .toList()
      ..sort();
    return ids.join('|');
  }

  static int _newSeed() => DateTime.now().millisecondsSinceEpoch & 0x3fffffff;

  static Map<String, dynamic>? _decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final Object? decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _save(
    SharedPreferences prefs, {
    required String signature,
    required int seed,
    required String? nextId,
  }) async {
    await prefs.setString(
      storageKey,
      jsonEncode(<String, dynamic>{
        'signature': signature,
        'seed': seed,
        'nextId': ?nextId,
      }),
    );
  }
}

/// 题库读取：先本地缓存（离线可用），再按需从服务端刷新。
///
/// 服务端接口 `GET /api/parental/quiz?deviceId=` 用登录 cookie（`username`）
/// 鉴权；电视启动时 [PtoolsUtil.loginWithSaved] 已建立会话，这里复用同一
/// 通路，遇到未登录自动重登一次。
class ParentalQuizRepository {
  const ParentalQuizRepository();

  static const String cacheKey = 'parental_quiz_banks_v1';

  Future<Map<String, List<ParentalQuizQuestion>>> readCache() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String deviceId = await DeviceCredentials.deviceId();
      if (deviceId.isEmpty) return <String, List<ParentalQuizQuestion>>{};
      final Object? raw = _decode(prefs.getString(cacheKey));
      if (raw is! Map) return <String, List<ParentalQuizQuestion>>{};
      final Object? banks = raw[deviceId];
      return _banksOf(banks);
    } catch (e) {
      Log.error('[Quiz] 读取缓存失败: $e');
      return <String, List<ParentalQuizQuestion>>{};
    }
  }

  /// 从服务端拉取题库并写缓存；失败返回 null（调用方沿用缓存）。
  Future<Map<String, List<ParentalQuizQuestion>>?> fetchRemote() async {
    final String deviceId = await DeviceCredentials.deviceId();
    if (deviceId.isEmpty) return null;
    try {
      final String url =
          '${AppConstants.toolsBaseUrl}/api/parental/quiz?deviceId=$deviceId';
      final String text = await PtoolsUtil.fetchUrl(url);
      final Object? decoded = _decode(text);
      if (decoded is! Map) return null;
      if (((decoded['code'] as num?)?.toInt() ?? -1) != 0) return null;
      final Object? data = decoded['data'];
      if (data is! Map) return null;
      final Map<String, List<ParentalQuizQuestion>> banks = <String,
          List<ParentalQuizQuestion>>{};
      final Object? rawBanks = data['banks'];
      if (rawBanks is List) {
        for (final Object? item in rawBanks) {
          if (item is! Map) continue;
          final String childId = (item['childId'] as String?)?.trim() ?? '';
          if (childId.isEmpty) continue;
          banks[childId] = _questionsOf(item['questions']);
        }
      }
      await _writeCache(deviceId, banks);
      return banks;
    } catch (e) {
      Log.error('[Quiz] 拉取题库失败: $e');
      return null;
    }
  }

  Future<void> _writeCache(
    String deviceId,
    Map<String, List<ParentalQuizQuestion>> banks,
  ) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final Object? raw = _decode(prefs.getString(cacheKey));
      final Map<String, dynamic> root = raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{};
      root[deviceId] = <String, dynamic>{
        for (final MapEntry<String, List<ParentalQuizQuestion>> entry
            in banks.entries)
          entry.key: entry.value
              .map((ParentalQuizQuestion q) => q.toJson())
              .toList(growable: false),
      };
      await prefs.setString(cacheKey, jsonEncode(root));
    } catch (e) {
      Log.error('[Quiz] 写入缓存失败: $e');
    }
  }

  static Map<String, List<ParentalQuizQuestion>> _banksOf(Object? raw) {
    if (raw is! Map) return <String, List<ParentalQuizQuestion>>{};
    return <String, List<ParentalQuizQuestion>>{
      for (final MapEntry<dynamic, dynamic> entry in raw.entries)
        if (entry.key is String)
          entry.key as String: _questionsOf(entry.value),
    };
  }

  static List<ParentalQuizQuestion> _questionsOf(Object? raw) {
    if (raw is! List) return const <ParentalQuizQuestion>[];
    final List<ParentalQuizQuestion> out = <ParentalQuizQuestion>[];
    for (final Object? item in raw) {
      if (item is! Map) continue;
      final ParentalQuizQuestion q = ParentalQuizQuestion.fromJson(
        Map<String, dynamic>.from(item),
      );
      if (q.id.isNotEmpty) out.add(q);
    }
    return out;
  }

  static Object? _decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }
}
