# TV 消息遥控（TV 端）实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** TV 端接收云信文本/命令消息（浮层展示 + 后台命令执行），并向系统管理员账号 `1000001` 发送登录/收看/切台上报。

**Architecture:** 沿用现有模式——NimManager 透传流、ChangeNotifier 单例控制器（仿 LiveChannelController）、DI 模块。新增 `lib/features/msg/` feature：协议解析 → 路由（浮层/命令）→ 上报服务。音量与设备型号走新建 Android MethodChannel（仓库现无音量能力，全库无 volume/mute 引用）。

**Tech Stack:** Flutter（bloc/get_it 已有）、nim_core_v2 10.9.91（已接入）、qr_flutter ^4.1.0（新依赖）、Android Kotlin MethodChannel。

**工作目录:** `E:\Code\potatokid_clipboard\pscreen\potatokid_screen`（分支 `feature/remote_msg`，直接提交）。

**规格:** `docs/superpowers/specs/2026-10-15-tv-message-remote-design.md`（本计划实现其 §3.2、§5 全部 + §3.1 的 TV 侧处理；§4 发送端属计划 2）。

---

## File Structure

| 文件 | 职责 |
|---|---|
| `lib/core/utils/platform_channel_service.dart` | 音量±/静音 + 设备型号（MethodChannel 封装） |
| `android/app/src/main/kotlin/**/MainActivity.kt` | MethodChannel 实现（AudioManager + Build.MODEL） |
| `lib/features/msg/protocol/message_envelope.dart` | 信封解析（纯函数） |
| `lib/features/msg/application/message_overlay_controller.dart` | 浮层状态机（可见/详情/1分钟计时/替换/屏保缓存） |
| `lib/features/msg/application/message_command_executor.dart` | 命令 switch（音量/切台） |
| `lib/features/msg/application/message_router.dart` | 收消息分流（文本→浮层，命令→执行器） |
| `lib/features/msg/application/reporting_service.dart` | 上行上报（登录两条/切台/5分钟心跳） |
| `lib/features/msg/presentation/widgets/message_overlay.dart` | 浮层 UI（滑入卡片 + 详情窗） |
| `lib/features/iptv/application/channel_info_provider.dart` | 频道名查询（非 UI 服务用） |
| `lib/features/app/application/app_tab_controller.dart` | 当前 tab 索引/页名（main_app 填充） |
| `lib/core/di/modules/msg_module.dart` | DI 注册（收消息订阅 + ReportingService） |
| `lib/features/app/presentation/pages/main_app.dart` | 挂载浮层、按键拦截、AppTabController 填充 |
| `lib/features/iptv/presentation/components/live_player_widget.dart` | 频道列表供给 + 切台确认钩子 |
| `lib/features/profile/presentation/pages/profile_page.dart` | 编辑浮层内二维码区 |

**测试新建:**
- `test/features/msg/message_envelope_test.dart`
- `test/features/msg/message_overlay_controller_test.dart`
- `test/features/msg/message_router_test.dart`
- `test/features/msg/reporting_service_test.dart`
- `test/core/utils/platform_channel_service_test.dart`

---

### Task 1: PlatformChannelService（音量 + 设备型号）

**Files:**
- Create: `lib/core/utils/platform_channel_service.dart`
- Modify: `android/app/src/main/kotlin/<包目录>/MainActivity.kt`（先 Glob `android/**/MainActivity.kt` 找实际路径，package 声明照抄现有文件）
- Test: `test/core/utils/platform_channel_service_test.dart`

- [ ] **Step 1: 写失败测试**

```dart
// test/core/utils/platform_channel_service_test.dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potatokid_screen/core/utils/platform_channel_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const MethodChannel channel = MethodChannel('potatokid_screen/platform');
  final List<String> calls = <String>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      calls.add(call.method);
      if (call.method == 'deviceModel') return 'MiBOX 4';
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('volumeUp/volumeDown/toggleMute 调用对应方法', () async {
    await PlatformChannelService.instance.volumeUp();
    await PlatformChannelService.instance.volumeDown();
    await PlatformChannelService.instance.toggleMute();
    expect(calls, <String>['volumeUp', 'volumeDown', 'toggleMute']);
  });

  test('deviceModel 返回型号，null 回落 Android TV', () async {
    expect(await PlatformChannelService.instance.deviceModel(), 'MiBOX 4');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async => null);
    expect(await PlatformChannelService.instance.deviceModel(), 'Android TV');
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/core/utils/platform_channel_service_test.dart`
Expected: FAIL（PlatformChannelService 不存在）

- [ ] **Step 3: 实现 Dart 封装**

```dart
// lib/core/utils/platform_channel_service.dart
import 'package:flutter/services.dart';

/// Android 平台通道：音量控制 + 设备型号（TV 端远程消息用）。
class PlatformChannelService {
  PlatformChannelService._();

  /// 全局单例。
  static final PlatformChannelService instance = PlatformChannelService._();

  static const MethodChannel _channel =
      MethodChannel('potatokid_screen/platform');

  /// 媒体音量 +。
  Future<void> volumeUp() => _channel.invokeMethod<void>('volumeUp');

  /// 媒体音量 −。
  Future<void> volumeDown() => _channel.invokeMethod<void>('volumeDown');

  /// 静音切换。
  Future<void> toggleMute() => _channel.invokeMethod<void>('toggleMute');

  /// 设备型号（读不到回落 'Android TV'）。
  Future<String> deviceModel() async {
    final String? model = await _channel.invokeMethod<String>('deviceModel');
    return (model == null || model.isEmpty) ? 'Android TV' : model;
  }
}
```

- [ ] **Step 4: 实现 Kotlin 端**

保留现有 MainActivity.kt 的 package 声明，整体替换为（package 行照抄现有文件，不照抄示例）：

```kotlin
package com.example.potatokid_screen

import android.media.AudioManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val platformChannel = "potatokid_screen/platform"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, platformChannel)
            .setMethodCallHandler { call, result ->
                val audio = getSystemService(AUDIO_SERVICE) as AudioManager
                when (call.method) {
                    "volumeUp" -> {
                        audio.adjustStreamVolume(
                            AudioManager.STREAM_MUSIC,
                            AudioManager.ADJUST_RAISE,
                            AudioManager.FLAG_SHOW_UI
                        )
                        result.success(null)
                    }
                    "volumeDown" -> {
                        audio.adjustStreamVolume(
                            AudioManager.STREAM_MUSIC,
                            AudioManager.ADJUST_LOWER,
                            AudioManager.FLAG_SHOW_UI
                        )
                        result.success(null)
                    }
                    "toggleMute" -> {
                        audio.ringerMode =
                            if (audio.ringerMode == AudioManager.RINGER_MODE_SILENT) {
                                AudioManager.RINGER_MODE_NORMAL
                            } else {
                                AudioManager.RINGER_MODE_SILENT
                            }
                        result.success(null)
                    }
                    "deviceModel" -> result.success(Build.MODEL ?: "Android TV")
                    else -> result.notImplemented()
                }
            }
    }
}
```

（若 MainActivity.kt 不存在，从默认模板创建同路径文件。）

- [ ] **Step 5: 跑测试确认通过 + analyze**

Run: `flutter test test/core/utils/platform_channel_service_test.dart`
Expected: PASS（2 用例）
Run: `flutter analyze`
Expected: No issues found

- [ ] **Step 6: Commit**

```bash
git add lib/core/utils/platform_channel_service.dart android/app/src/main/kotlin test/core/utils/platform_channel_service_test.dart
git commit -m "feat: platform channel for volume and device model"
```

---

### Task 2: 信封解析器

**Files:**
- Create: `lib/features/msg/protocol/message_envelope.dart`
- Test: `test/features/msg/message_envelope_test.dart`

- [ ] **Step 1: 写失败测试**

```dart
// test/features/msg/message_envelope_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:potatokid_screen/features/msg/protocol/message_envelope.dart';

void main() {
  group('parseIncomingText', () {
    test('普通文本', () {
      final ParsedMessage m = parseIncomingText('晚饭好了');
      expect(m.kind, EnvelopeKind.plainText);
      expect(m.plainText, '晚饭好了');
    });

    test('显式 txt 信封', () {
      final ParsedMessage m =
          parseIncomingText('{"t":"txt","content":"你好"}');
      expect(m.kind, EnvelopeKind.text);
      expect(m.content, '你好');
    });

    test('cmd 信封带 args', () {
      final ParsedMessage m = parseIncomingText(
          '{"t":"cmd","name":"channel","args":{"name":"CCTV-5"}}');
      expect(m.kind, EnvelopeKind.command);
      expect(m.commandName, 'channel');
      expect(m.args, <String, dynamic>{'name': 'CCTV-5'});
    });

    test('cmd 信封无 args', () {
      final ParsedMessage m =
          parseIncomingText('{"t":"cmd","name":"volume_up"}');
      expect(m.kind, EnvelopeKind.command);
      expect(m.commandName, 'volume_up');
      expect(m.args, isNull);
    });

    test('{ 开头但坏 JSON → 普通文本', () {
      final ParsedMessage m = parseIncomingText('{broken');
      expect(m.kind, EnvelopeKind.plainText);
      expect(m.plainText, '{broken');
    });

    test('{ 开头合法 JSON 但无 t → 普通文本', () {
      final ParsedMessage m = parseIncomingText('{"x":1}');
      expect(m.kind, EnvelopeKind.plainText);
      expect(m.plainText, '{"x":1}');
    });

    test('未知 t 值 → 普通文本', () {
      final ParsedMessage m = parseIncomingText('{"t":"other","a":1}');
      expect(m.kind, EnvelopeKind.plainText);
    });

    test('前后空白容忍', () {
      final ParsedMessage m =
          parseIncomingText('  {"t":"cmd","name":"mute"}  ');
      expect(m.kind, EnvelopeKind.command);
      expect(m.commandName, 'mute');
    });
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/features/msg/message_envelope_test.dart`
Expected: FAIL（文件不存在）

- [ ] **Step 3: 实现解析器**

```dart
// lib/features/msg/protocol/message_envelope.dart
import 'dart:convert';

/// 解析结果类别。
enum EnvelopeKind {
  /// 普通文本（含 `{` 开头但不构成信封的回退）。
  plainText,

  /// 显式 txt 信封。
  text,

  /// 命令信封（未知命令名由执行层忽略）。
  command,
}

/// 一条入站文本消息的解析结果。
class ParsedMessage {
  const ParsedMessage({
    required this.kind,
    this.plainText,
    this.content,
    this.commandName,
    this.args,
  });

  final EnvelopeKind kind;
  final String? plainText;
  final String? content;
  final String? commandName;
  final Map<String, dynamic>? args;
}

/// 按设计 §3.1 判别入站文本：非 `{` 开头/坏 JSON/无 `t`/未知 `t` 一律回退普通文本。
ParsedMessage parseIncomingText(String raw) {
  final String trimmed = raw.trim();
  if (!trimmed.startsWith('{')) {
    return ParsedMessage(kind: EnvelopeKind.plainText, plainText: raw);
  }
  try {
    final dynamic decoded = jsonDecode(trimmed);
    if (decoded is! Map) {
      return ParsedMessage(kind: EnvelopeKind.plainText, plainText: raw);
    }
    final dynamic t = decoded['t'];
    if (t is! String) {
      return ParsedMessage(kind: EnvelopeKind.plainText, plainText: raw);
    }
    if (t == 'txt') {
      final dynamic content = decoded['content'];
      return ParsedMessage(
        kind: EnvelopeKind.text,
        content: content is String ? content : '',
        plainText: raw,
      );
    }
    if (t == 'cmd') {
      final dynamic name = decoded['name'];
      final dynamic args = decoded['args'];
      return ParsedMessage(
        kind: EnvelopeKind.command,
        commandName: name is String ? name : '',
        args: args is Map ? Map<String, dynamic>.from(args) : null,
      );
    }
    return ParsedMessage(kind: EnvelopeKind.plainText, plainText: raw);
  } catch (_) {
    return ParsedMessage(kind: EnvelopeKind.plainText, plainText: raw);
  }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/features/msg/message_envelope_test.dart`
Expected: PASS（8 用例）

- [ ] **Step 5: Commit**

```bash
git add lib/features/msg/protocol/message_envelope.dart test/features/msg/message_envelope_test.dart
git commit -m "feat: message envelope parser"
```

---

### Task 3: NimManager 收/发透传

**Files:**
- Modify: `lib/core/utils/nim_manager.dart`（类内 `onKickedOffline` getter 之后追加两个成员，不动现有代码）
- 参考: `lib/features/remote/data/repositories/remote_login_repository_impl.dart`——先读它确认本仓库 `NIMResult` 成功判断的既有写法，发送包装用同一写法（示例按 `data == null` 判失败；若现场是 `code != 0` 则照改）。

- [ ] **Step 1: 在 NimManager 类内追加**

```dart
  /// 新消息事件流（透传 SDK，仅上层关心文本消息）。
  Stream<List<NIMMessage>> get onReceiveMessages =>
      NimCore.instance.messageService.onReceiveMessages;

  /// 发送 P2P 文本消息；任何一步失败记日志并返回 false，不抛出。
  Future<bool> sendTextMessage({
    required String toAccount,
    required String text,
  }) async {
    try {
      final NIMResult<String> cid = await NimCore.instance.conversationIdUtil
          .p2pConversationId(toAccount);
      if (cid.data == null) {
        Log.e('[NimManager] p2pConversationId 失败: ${cid.code}');
        return false;
      }
      final NIMResult<NIMMessage> msg =
          await MessageCreator.createTextMessage(text);
      if (msg.data == null) {
        Log.e('[NimManager] createTextMessage 失败: ${msg.code}');
        return false;
      }
      final NIMResult<NIMSendMessageResult> r =
          await NimCore.instance.messageService.sendMessage(
        message: msg.data!,
        conversationId: cid.data!,
      );
      if (r.data == null) {
        Log.e('[NimManager] sendMessage 失败: ${r.code}');
        return false;
      }
      return true;
    } catch (e) {
      Log.e('[NimManager] sendTextMessage 异常: $e');
      return false;
    }
  }
```

（`MessageCreator`/`NIMSendMessageResult` 由 `nim_core.dart` 与 platform_interface 导出；现有 import 已覆盖则不动，analyze 报缺再按现有 `hide Log` 风格补。）

- [ ] **Step 2: 验证**

Run: `flutter analyze`
Expected: No issues found
Run: `flutter test`
Expected: All tests passed（不新增用例——SDK 薄透传，逻辑在 Router/Reporting 用 Fake 测）

- [ ] **Step 3: Commit**

```bash
git add lib/core/utils/nim_manager.dart
git commit -m "feat: nim message receive stream and text send"
```

---

### Task 4: ChannelInfoProvider + AppTabController（位置状态源）

上报与 `channel` 命令需要「序号 → 频道名」「当前页名」，不能拿 BuildContext。

**Files:**
- Create: `lib/features/iptv/application/channel_info_provider.dart`
- Create: `lib/features/app/application/app_tab_controller.dart`
- Modify: `lib/features/iptv/presentation/components/live_player_widget.dart`

- [ ] **Step 1: 频道名查询**

```dart
// lib/features/iptv/application/channel_info_provider.dart
import 'package:potatokid_screen/features/iptv/domain/models/iptv_channel.dart';

/// 频道名查询（非 UI 服务用：上报/命令解析），真值由 LivePlayerWidget 供给。
class ChannelInfoProvider {
  ChannelInfoProvider._();

  /// 全局单例。
  static final ChannelInfoProvider instance = ChannelInfoProvider._();

  /// 当前生效的频道列表。
  List<IptvChannel> channels = <IptvChannel>[];

  /// 供给列表（频道加载/刷新时调用）。
  void setChannels(List<IptvChannel> value) {
    channels = value;
  }

  /// 序号对应的频道名；越界返回 null。
  String? nameAt(int index) {
    if (index < 0 || index >= channels.length) return null;
    return channels[index].name;
  }
}
```

- [ ] **Step 2: 当前页状态源**

```dart
// lib/features/app/application/app_tab_controller.dart
/// 当前顶部 Tab 状态（MainApp 每次 build 填充；上报/浮层互斥读这里）。
class AppTabController {
  AppTabController._();

  /// 「我的」在 MainApp._tabs 中的序号（与 MainApp._profileBranchIndex 一致）。
  static const int profileIndex = 3;

  /// 「屏保」在 MainApp._tabs 中的序号。
  static const int screensaverIndex = 2;

  /// 当前分支序号（0 首页 / 1 时间 / 2 屏保 / 3 我的）。
  static int branchIndex = 0;

  /// 屏保是否激活。
  static bool get isScreensaver => branchIndex == screensaverIndex;

  /// 上报用页名（设计 §3.2：不在频道时报当前页面）。
  static String get pageName {
    switch (branchIndex) {
      case 0:
        return '主页';
      case 1:
        return '时间页';
      case 2:
        return '屏保';
      case 3:
        return '设置';
      default:
        return '主页';
    }
  }
}
```

- [ ] **Step 3: 接线 LivePlayerWidget**

在 `live_player_widget.dart` 定位调用 `LiveChannelController.instance.setCount(...)` 处（频道列表加载/刷新成功分支），紧邻其后追加（列表变量以现场为准，即 setCount 传入 length 的那个列表）：

```dart
        ChannelInfoProvider.instance.setChannels(<频道列表变量>);
```
同时在该 widget 内（initState 或频道加载完成处）注册切台确认钩子：

```dart
    LiveChannelController.instance.onPlayCommit.addListener(_onPlayCommitForMsg);
```
其中：

```dart
  void _onPlayCommitForMsg() {
    Injection.get<ReportingService>().notifyChannelCommitted();
  }
```
（dispose 时对应 removeListener；ReportingService 由 Task 9 注册，此步先写引用，Task 9 之前 analyze 会报缺——若想保持每任务 analyze 绿，把钩子注册推迟到 Task 9 一并做。两种顺序都允许，报告中说明。）

- [ ] **Step 4: 验证**

Run: `flutter analyze`（若钩子推迟 Task 9，此时应 0 issues）
Run: `flutter test`
Expected: All tests passed

- [ ] **Step 5: Commit**

```bash
git add lib/features/iptv/application/channel_info_provider.dart lib/features/app/application/app_tab_controller.dart lib/features/iptv/presentation/components/live_player_widget.dart
git commit -m "feat: channel info and tab state providers"
```

---

### Task 5: MessageOverlayController（浮层状态机）

**Files:**
- Create: `lib/features/msg/application/message_overlay_controller.dart`
- Test: `test/features/msg/message_overlay_controller_test.dart`

- [ ] **Step 1: 写失败测试**

```dart
// test/features/msg/message_overlay_controller_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:potatokid_screen/features/msg/application/message_overlay_controller.dart';

void main() {
  late MessageOverlayController c;

  setUp(() {
    c = MessageOverlayController();
    c.deferActive = false;
  });

  tearDown(() => c.dispose());

  test('show 后可见，close 隐藏', () {
    c.show('你好');
    expect(c.visible, isTrue);
    expect(c.text, '你好');
    expect(c.detail, isFalse);
    c.close();
    expect(c.visible, isFalse);
  });

  test('显示期间新消息直接替换内容', () {
    c.show('第一条');
    c.show('第二条');
    expect(c.text, '第二条');
    expect(c.visible, isTrue);
  });

  test('OK 开详情，详情内 Back 回浮层，再 Back 关闭（两级返回）', () {
    c.show('内容');
    expect(c.handleOk(), isTrue);
    expect(c.detail, isTrue);
    expect(c.handleBack(), isTrue);
    expect(c.detail, isFalse);
    expect(c.visible, isTrue);
    expect(c.handleBack(), isTrue);
    expect(c.visible, isFalse);
  });

  test('不可见时 Back/OK 不消费', () {
    expect(c.handleBack(), isFalse);
    expect(c.handleOk(), isFalse);
  });

  test('详情中 OK 不消费', () {
    c.show('内容');
    c.openDetail();
    expect(c.handleOk(), isFalse);
  });

  test('deferActive 时 show 缓存不弹出，结束后 flush', () {
    c.deferActive = true;
    c.show('屏保中的消息');
    expect(c.visible, isFalse);
    expect(c.pending, '屏保中的消息');
    c.deferActive = false;
    c.onDeferEnd();
    expect(c.visible, isTrue);
    expect(c.text, '屏保中的消息');
  });

  test('defer 期间多条只留最新', () {
    c.deferActive = true;
    c.show('旧');
    c.show('新');
    c.deferActive = false;
    c.onDeferEnd();
    expect(c.text, '新');
  });

  test('visible 变化触发通知（供 UI 订阅）', () {
    int n = 0;
    c.addListener(() => n++);
    c.show('x');
    expect(n, 1);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/features/msg/message_overlay_controller_test.dart`
Expected: FAIL（文件不存在）

- [ ] **Step 3: 实现状态机**

```dart
// lib/features/msg/application/message_overlay_controller.dart
import 'dart:async';
import 'package:flutter/foundation.dart';

/// 消息浮层状态机（全局单例式，但构造器开放供测试；生产用 [instance]）。
///
/// 交互（设计 §5.2）：从上滑入卡片；OK 开详情；两级返回；无操作 1 分钟关闭；
/// 任意按键由外部调 [onAnyKey] 重置计时；新消息直接替换并重置计时；
/// 屏保期间缓存（[deferActive]），退出时调 [onDeferEnd] 弹出。
class MessageOverlayController extends ChangeNotifier {
  MessageOverlayController();

  /// 生产环境全局单例。
  static final MessageOverlayController instance = MessageOverlayController();

  /// 无操作自动关闭时长。
  static const Duration idleTimeout = Duration(minutes: 1);

  String? _text;
  String? _pending;
  bool _visible = false;
  bool _detail = false;
  bool _deferActive = false;
  Timer? _idleTimer;

  /// 屏保互斥：真值由 MainApp 依 AppTabController.isScreensaver 填充。
  bool get deferActive => _deferActive;
  set deferActive(bool value) {
    _deferActive = value;
  }

  /// 屏保期间缓存的最新消息（未弹出）。
  String? get pending => _pending;

  /// 当前展示文本。
  String? get text => _text;

  /// 浮层是否可见。
  bool get visible => _visible;

  /// 详情窗是否打开。
  bool get detail => _detail;

  /// 新消息到达：defer 时缓存；否则直接替换内容并重置计时。
  void show(String text) {
    _pending = text;
    if (_deferActive) return;
    _display(text);
  }

  /// 退出屏保（MainApp 在 deferActive 转 false 时调用）。
  void onDeferEnd() {
    final String? pendingText = _pending;
    if (_deferActive || pendingText == null) return;
    _display(pendingText);
  }

  void _display(String text) {
    _text = text;
    _visible = true;
    _detail = false;
    _resetIdleTimer();
    notifyListeners();
  }

  /// 关闭浮层。
  void close() {
    _idleTimer?.cancel();
    _idleTimer = null;
    _visible = false;
    _detail = false;
    notifyListeners();
  }

  /// 打开详情（仅可见且未在详情中）。
  void openDetail() {
    if (!_visible || _detail) return;
    _detail = true;
    _idleTimer?.cancel();
    _idleTimer = null;
    notifyListeners();
  }

  /// 关闭详情回浮层卡片，重开计时。
  void closeDetail() {
    if (!_visible || !_detail) return;
    _detail = false;
    _resetIdleTimer();
    notifyListeners();
  }

  /// 返回键：详情→回卡片；卡片→关闭。返回是否消费。
  bool handleBack() {
    if (!_visible) return false;
    if (_detail) {
      closeDetail();
      return true;
    }
    close();
    return true;
  }

  /// OK 键：卡片→开详情。返回是否消费。
  bool handleOk() {
    if (!_visible || _detail) return false;
    openDetail();
    return true;
  }

  /// 浮层可见期间任意按键（由 MainApp 拦截层调用）：重置自动关闭计时。
  void onAnyKey() {
    if (!_visible || _detail) return;
    _resetIdleTimer();
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(idleTimeout, close);
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    super.dispose();
  }
}
```

- [ ] **Step 4: 跑测试确认通过 + analyze**

Run: `flutter test test/features/msg/message_overlay_controller_test.dart`
Expected: PASS（8 用例；fakeAsync/timer 无需——本组用例不依赖计时到期）
Run: `flutter analyze`
Expected: No issues found

- [ ] **Step 5: Commit**

```bash
git add lib/features/msg/application/message_overlay_controller.dart test/features/msg/message_overlay_controller_test.dart
git commit -m "feat: message overlay controller state machine"
```

---

### Task 6: 命令执行器 + 消息路由

**Files:**
- Create: `lib/features/msg/application/message_command_executor.dart`
- Create: `lib/features/msg/application/message_router.dart`
- Test: `test/features/msg/message_router_test.dart`

- [ ] **Step 1: 写失败测试（路由与执行合并测——Router 是唯一入口）**

```dart
// test/features/msg/message_router_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:potatokid_screen/features/iptv/application/channel_info_provider.dart';
import 'package:potatokid_screen/features/iptv/application/live_channel_controller.dart';
import 'package:potatokid_screen/features/iptv/domain/models/iptv_channel.dart';
import 'package:potatokid_screen/features/msg/application/message_command_executor.dart';
import 'package:potatokid_screen/features/msg/application/message_overlay_controller.dart';
import 'package:potatokid_screen/features/msg/application/message_router.dart';

/// 记录型音量 Fake（结构体鸭子类型：Executor 只调 volumeUp/volumeDown/toggleMute）。
class FakeVolume {
  final List<String> calls = <String>[];
  Future<void> volumeUp() async => calls.add('up');
  Future<void> volumeDown() async => calls.add('down');
  Future<void> toggleMute() async => calls.add('mute');
}

void main() {
  late MessageOverlayController overlay;
  late FakeVolume volume;
  late LiveChannelController live;
  late MessageRouter router;

  setUp(() {
    overlay = MessageOverlayController();
    overlay.deferActive = false;
    volume = FakeVolume();
    live = LiveChannelController.instance;
    live.setCount(3);
    ChannelInfoProvider.instance.setChannels(<IptvChannel>[
      const IptvChannel(name: 'CCTV-1', sources: <String>['a']),
      const IptvChannel(name: 'CCTV-5', sources: <String>['b']),
      const IptvChannel(name: '湖南卫视', sources: <String>['c']),
    ]);
    router = MessageRouter(
      overlay: overlay,
      executor: MessageCommandExecutor(
        volume: volume,
        liveChannel: live,
        channelInfo: ChannelInfoProvider.instance,
      ),
    );
  });

  tearDown(() {
    overlay.dispose();
    ChannelInfoProvider.instance.setChannels(<IptvChannel>[]);
    live.setCount(0);
  });

  test('普通文本 → 浮层', () {
    router.handleIncoming('晚饭好了');
    expect(overlay.visible, isTrue);
    expect(overlay.text, '晚饭好了');
    expect(volume.calls, isEmpty);
  });

  test('txt 信封 → 浮层（content）', () {
    router.handleIncoming('{"t":"txt","content":"你好"}');
    expect(overlay.text, '你好');
  });

  test('volume_up/volume_down/mute 命令 → 音量调用，不弹浮层', () {
    router.handleIncoming('{"t":"cmd","name":"volume_up"}');
    router.handleIncoming('{"t":"cmd","name":"volume_down"}');
    router.handleIncoming('{"t":"cmd","name":"mute"}');
    expect(volume.calls, <String>['up', 'down', 'mute']);
    expect(overlay.visible, isFalse);
  });

  test('channel 按 name 命令 → select 对应序号', () {
    router.handleIncoming('{"t":"cmd","name":"channel","args":{"name":"CCTV-5"}}');
    expect(live.index, 1);
  });

  test('channel 按 index 命令 → select（0 基）', () {
    router.handleIncoming('{"t":"cmd","name":"channel","args":{"index":2}}');
    expect(live.index, 2);
  });

  test('channel 名字不存在 → 忽略（序号不变）', () {
    router.handleIncoming('{"t":"cmd","name":"channel","args":{"name":"不存在"}}');
    expect(live.index, 0);
    expect(overlay.visible, isFalse);
  });

  test('未知命令名 → 忽略不弹浮层', () {
    router.handleIncoming('{"t":"cmd","name":"fly"}');
    expect(overlay.visible, isFalse);
    expect(volume.calls, isEmpty);
  });

  test('text 命令 → 浮层', () {
    router.handleIncoming('{"t":"cmd","name":"text","args":{"content":"集合吃饭"}}');
    expect(overlay.text, '集合吃饭');
  });

  test('坏 JSON → 按普通文本弹浮层', () {
    router.handleIncoming('{broken');
    expect(overlay.text, '{broken');
  });
}
```

（`IptvChannel` 构造以现场模型为准——先读 `lib/features/iptv/domain/models/iptv_channel.dart`，用其真实构造/工厂调整测试数据；若为 freezed 常量构造则如上，否则改字段赋值写法。）

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/features/msg/message_router_test.dart`
Expected: FAIL（Router/Executor 不存在）

- [ ] **Step 3: 实现 Executor**

```dart
// lib/features/msg/application/message_command_executor.dart
import 'package:potatokid_screen/core/utils/platform_channel_service.dart';
import 'package:potatokid_screen/features/iptv/application/channel_info_provider.dart';
import 'package:potatokid_screen/features/iptv/application/live_channel_controller.dart';
import 'package:potatokid_screen/features/iptv/domain/channel_name_normalizer.dart';

/// 命令执行器：音量/切台（text 命令由 Router 直接走浮层，不进这里）。
class MessageCommandExecutor {
  MessageCommandExecutor({
    required this.volume,
    required this.liveChannel,
    required this.channelInfo,
  });

  final PlatformChannelService volume;
  final LiveChannelController liveChannel;
  final ChannelInfoProvider channelInfo;

  /// 执行命令；未知命令名返回 false（调用方记日志）。
  bool execute(String name, Map<String, dynamic>? args) {
    switch (name) {
      case 'volume_up':
        volume.volumeUp();
        return true;
      case 'volume_down':
        volume.volumeDown();
        return true;
      case 'mute':
        volume.toggleMute();
        return true;
      case 'channel':
        return _channel(args);
      default:
        return false;
    }
  }

  bool _channel(Map<String, dynamic>? args) {
    if (args == null) return false;
    final dynamic byName = args['name'];
    if (byName is String && byName.isNotEmpty) {
      final int idx = channelInfo.channels.indexWhere(
        (c) => normalizeChannelName(c.name) == normalizeChannelName(byName),
      );
      if (idx < 0) return false;
      liveChannel.select(idx);
      return true;
    }
    final dynamic byIndex = args['index'];
    if (byIndex is int) {
      liveChannel.select(byIndex);
      return true;
    }
    return false;
  }
}
```

- [ ] **Step 4: 实现 Router**

```dart
// lib/features/msg/application/message_router.dart
import 'package:potatokid_screen/app/app_log.dart';
import 'package:potatokid_screen/features/msg/application/message_command_executor.dart';
import 'package:potatokid_screen/features/msg/application/message_overlay_controller.dart';
import 'package:potatokid_screen/features/msg/protocol/message_envelope.dart';

/// 入站消息分流：文本 → 浮层；命令 → 执行器（text 命令特例走浮层）。
class MessageRouter {
  MessageRouter({required this.overlay, required this.executor});

  final MessageOverlayController overlay;
  final MessageCommandExecutor executor;

  void handleIncoming(String raw) {
    final ParsedMessage msg = parseIncomingText(raw);
    switch (msg.kind) {
      case EnvelopeKind.plainText:
        if (msg.plainText != null && msg.plainText!.isNotEmpty) {
          overlay.show(msg.plainText!);
        }
        break;
      case EnvelopeKind.text:
        if (msg.content != null && msg.content!.isNotEmpty) {
          overlay.show(msg.content!);
        }
        break;
      case EnvelopeKind.command:
        final String name = msg.commandName ?? '';
        if (name.isEmpty) break;
        if (name == 'text') {
          final dynamic content = msg.args?['content'];
          if (content is String && content.isNotEmpty) {
            overlay.show(content);
          }
          break;
        }
        if (!executor.execute(name, msg.args)) {
          Log.i('[MessageRouter] 忽略未知/无效命令: $name ${msg.args}');
        }
        break;
    }
  }
}
```

- [ ] **Step 5: 跑测试确认通过 + analyze**

Run: `flutter test test/features/msg/message_router_test.dart`
Expected: PASS（9 用例；若 IptvChannel 构造调整导致编译错，修测试数据后重跑）
Run: `flutter analyze`
Expected: No issues found

- [ ] **Step 6: Commit**

```bash
git add lib/features/msg/application/message_command_executor.dart lib/features/msg/application/message_router.dart test/features/msg/message_router_test.dart
git commit -m "feat: message router and command executor"
```

---

### Task 7: 浮层 UI + MainApp 挂载与按键拦截

**Files:**
- Create: `lib/features/msg/presentation/widgets/message_overlay.dart`
- Modify: `pubspec.yaml`（dependencies 追加 `qr_flutter: ^4.1.0`——Task 9 二维码用，本步先加避免二次 pub get）
- Modify: `lib/features/app/presentation/pages/main_app.dart`
- Test: 无新增 widget 测试（仓库 UI 层无测试惯例；逻辑已在 Task 5 覆盖）

- [ ] **Step 1: 添加依赖**

`pubspec.yaml` dependencies 段（`nim_core_v2` 之后）追加：

```yaml
  qr_flutter: ^4.1.0
```
Run: `flutter pub get`

- [ ] **Step 2: 实现浮层 Widget**

```dart
// lib/features/msg/presentation/widgets/message_overlay.dart
import 'package:flutter/material.dart';
import 'package:potatokid_screen/features/msg/application/message_overlay_controller.dart';

/// 消息浮层：顶部滑入卡片 + 详情窗（设计 §5.2）。
class MessageOverlay extends StatefulWidget {
  const MessageOverlay({super.key});

  @override
  State<MessageOverlay> createState() => _MessageOverlayState();
}

class _MessageOverlayState extends State<MessageOverlay> {
  final MessageOverlayController _controller = MessageOverlayController.instance;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChange);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    setState(() {});
    if (_controller.visible && !_controller.detail) {
      // 抢占焦点（关闭后由页面自行恢复——main_app 拦截层负责全局键）。
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_controller.visible) return const SizedBox.shrink();
    final String text = _controller.text ?? '';
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 48),
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 220),
          offset: Offset.zero,
          child: Material(
            color: scheme.surfaceContainerHigh,
            elevation: 8,
            borderRadius: BorderRadius.circular(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: _controller.detail
                  ? _DetailPane(text: text)
                  : _PreviewPane(text: text),
            ),
          ),
        ),
      ),
    );
  }
}

/// 卡片预览：截断单行。
class _PreviewPane extends StatelessWidget {
  const _PreviewPane({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}

/// 详情窗：全文可滚动（D-pad 上下）。
class _DetailPane extends StatelessWidget {
  const _DetailPane({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 720,
      height: 360,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: Text(
              '消息详情',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          Expanded(
            child: Scrollbar(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '返回：关闭',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 3: MainApp 挂载 + tab 填充**

`main_app.dart`：
1. import 增加：

```dart
import 'package:potatokid_screen/features/app/application/app_tab_controller.dart';
import 'package:potatokid_screen/features/msg/application/message_overlay_controller.dart';
import 'package:potatokid_screen/features/msg/presentation/widgets/message_overlay.dart';
```

2. 在 `build` 方法返回的最外层（导航条+页面外壳）套 Stack 挂载浮层：

```dart
    return Stack(
      children: <Widget>[
        <原有 build 返回的整个 widget 原样放入>,
        const Positioned.fill(child: MessageOverlay()),
      ],
    );
```

3. 在 `build` 开头（或 `_goTab`/`_handleLogical` 可达处）填充 tab 状态与屏保互斥——在 build 方法第一行加：

```dart
    AppTabController.branchIndex = navigationShell.currentIndex;
    final MessageOverlayController msgOverlay = MessageOverlayController.instance;
    final bool wasDeferred = msgOverlay.deferActive;
    msgOverlay.deferActive = AppTabController.isScreensaver;
    if (wasDeferred && !msgOverlay.deferActive) {
      msgOverlay.onDeferEnd();
    }
```

- [ ] **Step 4: MainApp 按键拦截**

在 `_handleLogical` 方法**最顶部**（数字键处理之前）插入：

```dart
    // 消息浮层可见：OK 开详情 / 返回 关闭；其余按键吞掉（详情内滚动由浮层
    // 自身 Focus 处理），并重置自动关闭计时。
    if (MessageOverlayController.instance.visible) {
      MessageOverlayController.instance.onAnyKey();
      if (key == LogicalKeyboardKey.escape) {
        MessageOverlayController.instance.handleBack();
        return true;
      }
      final bool ok =
          key == LogicalKeyboardKey.enter ||
          key == LogicalKeyboardKey.numpadEnter ||
          key == LogicalKeyboardKey.select ||
          key == LogicalKeyboardKey.gameButtonA;
      if (ok) {
        MessageOverlayController.instance.handleOk();
        return true;
      }
      return true; // 吞掉其余按键，防止浮层下页面被操作
    }
```

同时在 `_onRemoteButton`（悬浮遥控器直调入口）确认其走 `_handleLogical`——现有实现如此，无需改。

- [ ] **Step 5: 验证**

Run: `flutter analyze`
Expected: No issues found
Run: `flutter test`
Expected: All tests passed

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/features/msg/presentation/widgets/message_overlay.dart lib/features/app/presentation/pages/main_app.dart
git commit -m "feat: message overlay ui with global key intercept"
```

---

### Task 8: ReportingService（上行上报）

**Files:**
- Create: `lib/features/msg/application/reporting_service.dart`
- Test: `test/features/msg/reporting_service_test.dart`

- [ ] **Step 1: 写失败测试**

```dart
// test/features/msg/reporting_service_test.dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:potatokid_screen/features/app/application/app_tab_controller.dart';
import 'package:potatokid_screen/features/iptv/application/channel_info_provider.dart';
import 'package:potatokid_screen/features/iptv/application/live_channel_controller.dart';
import 'package:potatokid_screen/features/iptv/domain/models/iptv_channel.dart';
import 'package:potatokid_screen/features/msg/application/reporting_service.dart';

/// 假发送器：记录目标与文本。
class FakeSender implements MessageSender {
  final List<(String, String)> sent = <(String, String)>[];
  bool ok = true;

  @override
  Future<bool> sendText({required String toAccount, required String text}) async {
    sent.add((toAccount, text));
    return ok;
  }
}

/// 假型号源。
class FakeModel {
  Future<String> call() async => 'MiBOX 4';
}

void main() {
  late FakeSender sender;
  late ReportingService service;

  setUp(() {
    sender = FakeSender();
    ChannelInfoProvider.instance.setChannels(<IptvChannel>[
      const IptvChannel(name: 'CCTV-1', sources: <String>['a']),
      const IptvChannel(name: 'CCTV-5', sources: <String>['b']),
    ]);
    LiveChannelController.instance.setCount(2);
    AppTabController.branchIndex = 0;
    service = ReportingService(
      sender: sender,
      deviceModel: () async => 'MiBOX 4',
      channelInfo: ChannelInfoProvider.instance,
      liveChannel: LiveChannelController.instance,
      now: () => DateTime(2026, 10, 15, 20, 30),
    );
  });

  tearDown(() {
    service.stop();
    ChannelInfoProvider.instance.setChannels(<IptvChannel>[]);
    LiveChannelController.instance.setCount(0);
    AppTabController.branchIndex = 0;
  });

  test('登录：发两条给 1000001（账号时间型号 + 正在收看）', () async {
    service.start('TV_001');
    await pumpEventQueue();
    expect(sender.sent.length, 2);
    expect(sender.sent[0].$1, '1000001');
    expect(sender.sent[0].$2, 'TV_001于2026-10-15 20:30使用MiBOX 4登录成功。');
    expect(sender.sent[1].$2, '正在收看CCTV-1');
    service.stop();
  });

  test('不在频道页（时间页）→ 正在收看时间页', () async {
    AppTabController.branchIndex = 1;
    service.start('TV_001');
    await pumpEventQueue();
    expect(sender.sent[1].$2, '正在收看时间页');
    service.stop();
  });

  test('切台确认（防抖后）发切换频道消息', () async {
    service.start('TV_001');
    await pumpEventQueue();
    sender.sent.clear();

    LiveChannelController.instance.select(1);
    service.notifyChannelCommitted();
    // 防抖窗口内再次触发 → 只发一条
    await Future<void>.delayed(const Duration(milliseconds: 300));
    LiveChannelController.instance.select(0);
    service.notifyChannelCommitted();
    await Future<void>.delayed(
        ReportingService.channelDebounce + const Duration(milliseconds: 100));
    expect(sender.sent.length, 1);
    expect(sender.sent[0].$2, '切换频道：CCTV-1');
    service.stop();
  });

  test('stop 后不再发送', () async {
    service.start('TV_001');
    await pumpEventQueue();
    sender.sent.clear();
    service.stop();
    service.notifyChannelCommitted();
    await Future<void>.delayed(
        ReportingService.channelDebounce + const Duration(milliseconds: 100));
    expect(sender.sent, isEmpty);
  });

  test('重复 start 不重发登录消息', () async {
    service.start('TV_001');
    await pumpEventQueue();
    final int n = sender.sent.length;
    service.start('TV_001');
    await pumpEventQueue();
    expect(sender.sent.length, n);
    service.stop();
  });

  test('发送失败不抛出', () async {
    sender.ok = false;
    service.start('TV_001');
    await pumpEventQueue();
    service.stop();
  });
}
```

（`IptvChannel` 构造同 Task 6——以现场模型为准调整。）

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/features/msg/reporting_service_test.dart`
Expected: FAIL（ReportingService 不存在）

- [ ] **Step 3: 实现 ReportingService**

```dart
// lib/features/msg/application/reporting_service.dart
import 'dart:async';

import 'package:potatokid_screen/app/app_log.dart';
import 'package:potatokid_screen/features/app/application/app_tab_controller.dart';
import 'package:potatokid_screen/features/iptv/application/channel_info_provider.dart';
import 'package:potatokid_screen/features/iptv/application/live_channel_controller.dart';

/// 文本发送抽象（生产为 NimManager 包装；测试用 Fake）。
abstract class MessageSender {
  Future<bool> sendText({required String toAccount, required String text});
}

/// 上行上报服务（设计 §3.2/§5.5）：登录两条、切台防抖、5 分钟心跳。
class ReportingService {
  ReportingService({
    required this.sender,
    required this.deviceModel,
    required this.channelInfo,
    required this.liveChannel,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    _playCommitListener = () => notifyChannelCommitted();
    liveChannel.onPlayCommit.addListener(_playCommitListener);
  }

  /// 系统管理员账号。
  static const String adminAccount = '1000001';

  /// 心跳间隔。
  static const Duration heartbeatInterval = Duration(minutes: 5);

  /// 切台确认防抖。
  static const Duration channelDebounce = Duration(seconds: 1);

  final MessageSender sender;
  final Future<String> Function() deviceModel;
  final ChannelInfoProvider channelInfo;
  final LiveChannelController liveChannel;
  final DateTime Function _now;

  late final VoidCallback _playCommitListener;

  Timer? _heartbeat;
  Timer? _channelTimer;
  DateTime? _loginAt;
  bool _started = false;

  /// 登录成功（RemoteLoginState.loggedIn 边沿）时调用；先取设备型号再发前两条。
  Future<void> start(String account) async {
    if (_started) return;
    _started = true;
    _loginAt = _now();
    _model = await deviceModel();
    _send('${account}于${_fmt(_loginAt!)}使用$_deviceModelCache登录成功。');
    _send('正在收看${positionText()}');
    _heartbeat = Timer.periodic(heartbeatInterval, (_) => _onHeartbeat());
  }

  /// 登出/停止（error/notConfigured 边沿、dispose 时）。
  void stop() {
    _started = false;
    _loginAt = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    _channelTimer?.cancel();
    _channelTimer = null;
  }

  /// 切台确认（onPlayCommit 钩子）：防抖后发「切换频道」。
  void notifyChannelCommitted() {
    if (!_started) return;
    _channelTimer?.cancel();
    _channelTimer = Timer(channelDebounce, () {
      _channelTimer = null;
      final String? name = channelInfo.nameAt(liveChannel.index);
      if (name == null) return;
      _send('切换频道：$name');
    });
  }

  /// 当前位置文本：在频道上报频道名，否则报当前页名。
  String positionText() {
    if (AppTabController.branchIndex == 0) {
      final String? name = channelInfo.nameAt(liveChannel.index);
      if (name != null) return name;
    }
    return AppTabController.pageName;
  }

  String get _deviceModelCache => _model ?? 'Android TV';
  String? _model;

  void _onHeartbeat() {
    if (!_started || _loginAt == null) return;
    final int minutes = _now().difference(_loginAt!).inMinutes;
    _send('已收看$minutes分钟，当前频道是${positionText()}');
  }

  void _send(String text) {
    // 型号首条消息前尽量就绪：start 内先同步 _model 缓存。
    sender.sendText(toAccount: adminAccount, text: text).then((bool ok) {
      if (!ok) Log.i('[ReportingService] 上报发送失败: $text');
    }).catchError((Object e) {
      Log.e('[ReportingService] 上报异常: $e');
    });
  }

  static String _fmt(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}';
  }

  void dispose() {
    stop();
    liveChannel.onPlayCommit.removeListener(_playCommitListener);
  }
}
```

**调用方注意**：MsgModule 的 bloc 监听里写 `unawaited(service.start(account));`（import `dart:async` 的 unawaited）；测试里 `service.start(...)` 后 `await pumpEventQueue()`，覆盖异步型号获取。

- [ ] **Step 4: 跑测试确认通过 + analyze**

Run: `flutter test test/features/msg/reporting_service_test.dart`
Expected: PASS（6 用例；切台用例 real timer 等待约 1.4s，可接受）
Run: `flutter analyze`
Expected: No issues found

- [ ] **Step 5: Commit**

```bash
git add lib/features/msg/application/reporting_service.dart test/features/msg/reporting_service_test.dart
git commit -m "feat: admin reporting service"
```

---

### Task 9: DI 接线 + 收消息订阅 + 二维码

**Files:**
- Create: `lib/core/di/modules/msg_module.dart`
- Modify: `lib/core/di/injection.dart`（RemoteModule 之后注册/之前注销）
- Modify: `lib/features/iptv/presentation/components/live_player_widget.dart`（Task 4 若推迟的钩子在此补齐）
- Modify: `lib/features/profile/presentation/pages/profile_page.dart`（二维码区）
- Modify: `pubspec.yaml`（qr_flutter 若 Task 7 未加）

- [ ] **Step 1: MessageSender 生产实现（放 MsgModule 文件内）+ 模块**

```dart
// lib/core/di/modules/msg_module.dart
import 'dart:async';

import 'package:potatokid_screen/core/di/get_it.dart';
import 'package:potatokid_screen/core/utils/nim_manager.dart';
import 'package:potatokid_screen/features/iptv/application/live_channel_controller.dart';
import 'package:potatokid_screen/features/msg/application/message_command_executor.dart';
import 'package:potatokid_screen/features/msg/application/message_overlay_controller.dart';
import 'package:potatokid_screen/features/msg/application/message_router.dart';
import 'package:potatokid_screen/features/msg/application/reporting_service.dart';
import 'package:potatokid_screen/features/iptv/application/channel_info_provider.dart';
import 'package:potatokid_screen/core/utils/platform_channel_service.dart';
import 'package:potatokid_screen/features/remote/application/bloc/remote_login_bloc.dart';
import 'package:potatokid_screen/features/remote/application/bloc/remote_login_state.dart';

/// NimManager 包装的发送器。
class NimMessageSender implements MessageSender {
  NimMessageSender(this._nim);

  final NimManager _nim;

  @override
  Future<bool> sendText({
    required String toAccount,
    required String text,
  }) =>
      _nim.sendTextMessage(toAccount: toAccount, text: text);
}

/// 消息模块：收消息路由 + 上报服务（依赖 RemoteModule 的 [RemoteLoginBloc]
/// 与 CoreModule 的 [NimManager]，注册顺序在其后）。
class MsgModule {
  const MsgModule._();

  static StreamSubscription<dynamic>? _sub;

  static Future<void> register() async {
    final MessageRouter router = MessageRouter(
      overlay: MessageOverlayController.instance,
      executor: MessageCommandExecutor(
        volume: PlatformChannelService.instance,
        liveChannel: LiveChannelController.instance,
        channelInfo: ChannelInfoProvider.instance,
      ),
    );
    final ReportingService reporting = ReportingService(
      sender: NimMessageSender(getIt<NimManager>()),
      deviceModel: () => PlatformChannelService.instance.deviceModel(),
      channelInfo: ChannelInfoProvider.instance,
      liveChannel: LiveChannelController.instance,
    );
    getIt.registerLazySingleton<ReportingService>(() => reporting);

    // 收消息：仅文本进路由；未登录静默丢弃由 SDK 侧保证（未登录收不到）。
    _sub = getIt<NimManager>().onReceiveMessages.listen((messages) {
      for (final dynamic m in messages) {
        final dynamic text = _textOf(m);
        if (text is String && text.isNotEmpty) {
          router.handleIncoming(text);
        }
      }
    });

    // 登录态边沿驱动上报启停。
    getIt<RemoteLoginBloc>().stream.listen((RemoteLoginState state) {
      if (state.status == RemoteLoginStatus.loggedIn) {
        unawaited(reporting.start(state.account));
      } else if (state.status == RemoteLoginStatus.notConfigured ||
          state.status == RemoteLoginStatus.error) {
        reporting.stop();
      }
    });
  }

  /// 从 NIMMessage 提取文本（字段以 SDK 模型为准：先读 platform_interface
  /// 的 NIMMessage/attachment 定型，再实现本方法）。
  static dynamic _textOf(dynamic message) {
    // 预期形态：message.attachment is NIMTextAttachment → .text
    // 现场按 SDK 实际字段实现；非文本附件返回 null。
    return null; // TODO(Task 9 Step 1b): 按 SDK 模型实现后删除本行
  }

  static Future<void> unregister() async {
    await _sub?.cancel();
    _sub = null;
    await getIt.unregister<ReportingService>();
  }
}
```

**Step 1b（必做）**：读 `D:\env\pub\pub-cache\hosted\pub.dev\nim_core_v2_platform_interface-10.9.91\lib` 下 NIMMessage 与文本附件模型（Glob `**/*message*.dart`），按真实字段实现 `_textOf`（典型：`(message as NIMMessage).attachment is NIMTextAttachment` → `.text`），删除 TODO。同步用真实类型替换 `dynamic`（消息循环变量改 `NIMMessage`）。

- [ ] **Step 2: injection.dart 注册**

import 增加 `msg_module.dart`；`await RemoteModule.register();` 之后加 `await MsgModule.register();`；unregister 序列中 `RemoteModule.unregister()` **之前**加 `await MsgModule.unregister();`。

- [ ] **Step 3: LivePlayerWidget 钩子补齐（若 Task 4 推迟）**

```dart
  void _onPlayCommitForMsg() {
    Injection.get<ReportingService>().notifyChannelCommitted();
  }
```
initState 注册到 `LiveChannelController.instance.onPlayCommit`，dispose 反注册；频道列表供给 `ChannelInfoProvider.instance.setChannels(...)` 若 Task 4 未做一并补。

- [ ] **Step 4: 远程行二维码（profile_page.dart）**

1. `pubspec.yaml` 确认已有 `qr_flutter: ^4.1.0`（Task 7 已加则跳过）。
2. 读 `_buildRemoteEditRow` 现有结构，在编辑态行内（输入框与 ✕/✓ 之外的下方区域，`AnimatedContainer` 内追加）当 `state.status == RemoteLoginStatus.loggedIn && state.account.isNotEmpty` 时显示二维码区：

```dart
              if (context.read<RemoteLoginBloc>().state.status ==
                      RemoteLoginStatus.loggedIn &&
                  context.read<RemoteLoginBloc>().state.account.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: QrImageView(
                    data: context.read<RemoteLoginBloc>().state.account,
                    size: 120,
                    backgroundColor: Colors.white,
                  ),
                ),
```
（`import 'package:qr_flutter/qr_flutter.dart';`；`_buildRemoteEditRow` 无 Bloc 参数则用已有的 `context.read` 风格；具体嵌入点以现场 widget 树为准，保持 ✕/✓ 交互不变。）

- [ ] **Step 5: 验证**

Run: `flutter analyze`
Expected: No issues found
Run: `flutter test`
Expected: All tests passed
Run: `flutter build apk --debug`（或至少 `flutter build apk --debug` 的编译检查可改为 `flutter analyze` + 手动真机验证清单，构建耗时长时报告中说明跳过理由）

- [ ] **Step 6: Commit**

```bash
git add lib/core/di/modules/msg_module.dart lib/core/di/injection.dart lib/features/iptv/presentation/components/live_player_widget.dart lib/features/profile/presentation/pages/profile_page.dart
git commit -m "feat: wire msg module receive and reporting"
```

---

### Task 10: 全量验证 + 手动清单

- [ ] **Step 1: 全量静态检查**

Run: `flutter analyze`
Expected: No issues found

- [ ] **Step 2: 全量测试**

Run: `flutter test`
Expected: All tests passed（原有 47 + 新增约 33）

- [ ] **Step 3: 修复发现的问题（如有）后提交**

```bash
git add -A
git commit -m "fix: message remote review fixes"
```
（无问题则跳过提交。）

- [ ] **Step 4: 真机手动验证清单（报告结果，无法自动化）**

1. 管理员手机（任意 NIM 客户端，账号 1000001）发纯文本 → TV 弹浮层、焦点抢占、OK 详情、两级返回、1 分钟自动关
2. 连发两条 → 第二条直接替换、计时重置
3. 发 `{"t":"cmd","name":"volume_up"}` → 系统音量条出现且音量+
4. 发 `channel` 命令（name/index）→ 切台且 1 秒后 TV 向 1000001 发「切换频道：xxx」
5. TV 登录 → 1000001 收到两条登录消息；5 分钟后收到心跳
6. 屏保中发文本 → 退出屏保后弹出
7. 「远程」行编辑态（已登录）→ 二维码显示，手机扫码得账号
8. 未登录 TV → 上报不发、二维码不显示

- [ ] **Step 5: 最终报告**

Status / 各 Task 提交 SHA / analyze+test 结果 / 手动清单结果 / 偏离说明。

---

## Self-Review 记录（计划作者已跑）

1. **Spec coverage:** §3.1 判别→Task 2/6；§3.2 上报→Task 8；§5.1 收→Task 3/6/9；§5.2 浮层→Task 5/7；§5.3 二维码→Task 9；§5.4 命令→Task 6；§5.5 上报→Task 8/9；测试策略各条对应各任务。§4 发送端 = 计划 2。
2. **Placeholder scan:** Task 9 `_textOf` 的 TODO 是「现场读 SDK 模型」的受控步骤（Step 1b 必做并删除），非遗留占位。
3. **Type consistency:** `MessageSender.sendText`（Task 8 定义，Task 9 实现）；`MessageCommandExecutor(volume, liveChannel, channelInfo)` 构造在 Task 6 定义、Task 9 复用；`ReportingService.notifyChannelCommitted/start/stop` 在 Task 8 定义、Task 4/9 引用；`MessageOverlayController.deferActive/onDeferEnd` 在 Task 5 定义、Task 7 使用。

