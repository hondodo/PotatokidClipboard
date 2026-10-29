import 'dart:convert';

/// 下行信封构造（与 TV 端 message_envelope 解析器对齐）。
///
/// 协议：
/// - 普通文本 → 原样发送（TV 端识别为 plainText → 浮层）
/// - `{"t":"txt","content":...}` → TV 端浮层
/// - `{"t":"cmd","name":...,"args":{...}}` → TV 端命令执行
String buildPlainText(String text) => text;

String buildTextCommand(String content) =>
    jsonEncode(<String, dynamic>{
      't': 'cmd',
      'name': 'text',
      'args': <String, dynamic>{'content': content},
    });

String buildVolumeCommand(String name) =>
    jsonEncode(<String, dynamic>{'t': 'cmd', 'name': name});

String buildChannelCommand({String? name, int? index}) =>
    jsonEncode(<String, dynamic>{
      't': 'cmd',
      'name': 'channel',
      'args': <String, dynamic>{
        'name': ?name,
        'index': ?index,
      },
    });

/// 通用命令信封（快捷面板/命令模式统一入口）。
String buildCommandEnvelope(String name, [Map<String, dynamic>? args]) =>
    jsonEncode(<String, dynamic>{
      't': 'cmd',
      'name': name,
      'args': ?args,
    });

/// 场景导航命令：`home` / `live` / `weather` / `settings` / `screensaver`。
String buildNavCommand(String page) =>
    buildCommandEnvelope('nav', <String, dynamic>{'page': page});
