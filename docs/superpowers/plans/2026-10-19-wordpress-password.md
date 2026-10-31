# WordPress 密码保护文章抓取 + 设置页密码行 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现 `WordPressUtil.fetchPostContent`（WordPress 密码保护文章两步抓取），并在「我的」设置页新增持久化的「WordPress密码」行，同时把云信行独占的行内输入编辑机制泛化为可扩展框架。

**Architecture:** 三层：`AppSettings`（SharedPreferences 持久化 wpPassword）→ `WordPressUtil`（dio 两步抓取：POST `wp-login.php?action=postpass` 拿 cookie → GET 文章页解析 `entry-content`）→ `ProfilePage`（`editingRow` 统一编辑信号 + 共用 `_InlineEditFrame` 输入外框，WordPress 行是第一个新用户）。设计文档：`docs/superpowers/specs/2026-10-19-wordpress-password-design.md`。

**Tech Stack:** Flutter / Dart 3.11、dio ^5.11.1、shared_preferences、easy_localization（4 个语言 JSON）、flutter_lints ^6.0.0。

**工作目录（所有命令的执行目录）：** `E:\Code\potatokid_clipboard\pscreen\potatokid_screen`（git 仓库根为 `E:\Code\potatokid_clipboard`）

**实测事实（编写本计划时已联网验证，勿再怀疑）：**
- 正确与错误密码在 `wp-login.php?action=postpass` 都返回 `302` 且都下发 `wp-postpass_*` cookie → 密码判定必须在第 2 步看页面是否仍含 `post-password-form`
- 解密成功页面**不含** `post-password-form`；被拒页面含
- `entry-content` div 尾部含 Jetpack 分享组件（`<div id="jp-post-flair"`），需在解析时截除
- 测试文章正文曾从 `hello page` 被作者改为 `更新内容` → 测试**禁止硬编码正文**

---

### Task 1: AppSettings.wpPassword 持久化

**Files:**
- Modify: `lib/core/utils/app_settings.dart`
- Test: `test/core/utils/app_settings_test.dart`（追加 2 个用例）

- [ ] **Step 1.1: 写失败测试**

在 `test/core/utils/app_settings_test.dart` 的 `main()` 内、最后一个 `}` 之前追加：

```dart
  test('wpPassword 默认空串，setWpPassword 内存与持久化同步更新', () async {
    final AppSettings settings = AppSettings.instance;
    await settings.clearAllPersisted();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await settings.ensureLoaded();
    expect(settings.wpPassword, isEmpty);

    await settings.setWpPassword('12345678');
    expect(settings.wpPassword, '12345678');
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_wp_password_v1'), '12345678');
  });

  test('clearAllPersisted 复位 wpPassword', () async {
    final AppSettings settings = AppSettings.instance;
    await settings.clearAllPersisted();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await settings.ensureLoaded();
    await settings.setWpPassword('abcd');

    await settings.clearAllPersisted();
    expect(settings.wpPassword, isEmpty);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_wp_password_v1'), isNull);
  });
```

- [ ] **Step 1.2: 运行确认失败**

Run: `flutter test test/core/utils/app_settings_test.dart`
Expected: 编译失败，含 `The getter 'wpPassword' isn't defined`（或 `setWpPassword` 未定义）

- [ ] **Step 1.3: 实现（app_settings.dart 共 6 处编辑）**

1) 在 `static const String _keyNimAccount = 'app_nim_account_v1';` 之后加：

```dart
  static const String _keyWpPassword = 'app_wp_password_v1';
```

2) 在字段 `String _nimAccount = '';` 之后加：

```dart
  /// WordPress 密码保护文章的访问密码；**空串表示未设置**。
  String _wpPassword = '';
```

3) 在 `String get nimAccount => _nimAccount;` 之后加：

```dart
  /// WordPress 密码：空串表示未设置。
  String get wpPassword => _wpPassword;
```

4) 在 `_load()` 中 `_nimAccount = prefs.getString(_keyNimAccount) ?? '';` 之后加：

```dart
      // WordPress 密码
      _wpPassword = prefs.getString(_keyWpPassword) ?? '';
```

5) 在 `setNimAccount` 方法整体之后加：

```dart
  /// 保存 WordPress 密码（空串表示清除）。
  Future<void> setWpPassword(String password) async {
    _wpPassword = password;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyWpPassword, password);
    } catch (_) {
      // 写入失败不影响运行。
    }
  }
```

6) 在 `clearAllPersisted()` 中 `_nimAccount = '';` 之后加：

```dart
    _wpPassword = '';
```

- [ ] **Step 1.4: 运行确认通过**

Run: `flutter test test/core/utils/app_settings_test.dart`
Expected: `All tests passed!`（原有 2 个 + 新增 2 个 = 4 个）

- [ ] **Step 1.5: 提交**

```powershell
git add lib/core/utils/app_settings.dart test/core/utils/app_settings_test.dart
git commit -m "feat(settings): AppSettings 新增 WordPress 密码持久化"
```

---

### Task 2: WordPressUtil 两步抓取（真实网络 TDD）

**Files:**
- Create: `lib/core/utils/wordpress_util.dart`（已存在的空文件，写入内容）
- Test: `test/core/utils/wordpress_util_test.dart`（新建）

- [ ] **Step 2.1: 写失败测试**

创建 `test/core/utils/wordpress_util_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:potatokid_screen/core/utils/wordpress_util.dart';

/// 真实网络测试（需要联网）：用受密码保护的示例文章验证抓取流程。
///
/// 不硬编码正文：该测试文章的内容会被作者随时修改（实测会话期间
/// 从 `hello page` 变为 `更新内容`），只断言「拿到正文且未被密码挡住」。
void main() {
  const String postUrl = 'https://potatokid5.wordpress.com/2026/10/19/hello/';

  test('正确密码能抓取到正文', () async {
    final String content = await WordPressUtil.fetchPostContent(
      postUrl,
      password: '12345678',
    );
    expect(content, isNotEmpty);
    expect(content, isNot(contains('此内容受密码保护')));
    expect(content, isNot(contains('post-password-form')));
  });

  test('错误密码抛 WordPressPassException', () async {
    await expectLater(
      WordPressUtil.fetchPostContent(postUrl, password: 'definitely-wrong-pw'),
      throwsA(isA<WordPressPassException>()),
    );
  });

  test('密码为空抛 WordPressPassException', () async {
    await expectLater(
      WordPressUtil.fetchPostContent(postUrl, password: ''),
      throwsA(isA<WordPressPassException>()),
    );
  });

  test('未传密码且 AppSettings 未设置时抛 WordPressPassException', () async {
    await expectLater(
      WordPressUtil.fetchPostContent(postUrl),
      throwsA(isA<WordPressPassException>()),
    );
  });
}
```

- [ ] **Step 2.2: 运行确认失败**

Run: `flutter test test/core/utils/wordpress_util_test.dart`
Expected: 编译失败，含 `Target of URI doesn't exist: 'package:potatokid_screen/core/utils/wordpress_util.dart'` 或 `WordPressUtil` 未定义

- [ ] **Step 2.3: 实现 `lib/core/utils/wordpress_util.dart` 全文**

```dart
import 'package:dio/dio.dart';

import 'package:potatokid_screen/core/utils/app_settings.dart';

/// WordPress 密码保护文章访问失败（密码未设置、校验失败或正文为空）。
class WordPressPassException implements Exception {
  const WordPressPassException(this.message);

  final String message;

  @override
  String toString() => 'WordPressPassException: $message';
}

/// WordPress 密码保护文章抓取。
///
/// 流程（与浏览器表单一致，已联网实测）：
/// 1. `POST {origin}/wp-login.php?action=postpass`（不跟随重定向）。
///    注意：**错误密码同样返回 302 并下发 `wp-postpass_*` Cookie**，
///    因此本步只做「302 + Cookie 存在」的必要检查；
/// 2. 带该 Cookie `GET` 文章页：页面仍含 `post-password-form`
///    即密码被拒；否则解析 `entry-content` 并截除 Jetpack 分享等
///    附加组件，返回正文纯文本。
class WordPressUtil {
  WordPressUtil._();

  /// 抓取用的轻量客户端（不挂全局拦截器/日志）。
  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      responseType: ResponseType.plain,
    ),
  );

  static const String _passFormMarker = 'post-password-form';

  /// 抓取 [postUrl] 的正文纯文本。
  ///
  /// [password] 缺省时读 [AppSettings.wpPassword]。
  /// 密码未设置/被拒或正文为空抛 [WordPressPassException]，网络错误抛 [DioException]。
  static Future<String> fetchPostContent(
    String postUrl, {
    String? password,
  }) async {
    final String effectivePassword =
        password ?? AppSettings.instance.wpPassword;
    if (effectivePassword.isEmpty) {
      throw const WordPressPassException('密码未设置');
    }

    final Uri uri = Uri.parse(postUrl);
    final String origin = '${uri.scheme}://${uri.host}';

    // 第 1 步：提交密码表单。followRedirects:false 才能拿到 302 与 Set-Cookie。
    final Response<String> passResp = await _dio.post<String>(
      '$origin/wp-login.php?action=postpass',
      data: <String, String>{
        'post_password': effectivePassword,
        'redirect_to': postUrl,
        'Submit': '提交',
      },
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        followRedirects: false,
        validateStatus: (int? status) => status != null && status < 400,
        headers: <String, String>{'Referer': postUrl},
      ),
    );
    final String? passCookie = _postPassCookie(passResp);
    if (passResp.statusCode != 302 || passCookie == null) {
      throw const WordPressPassException('密码校验失败');
    }

    // 第 2 步：带 Cookie 抓取文章页。
    final Response<String> pageResp = await _dio.get<String>(
      postUrl,
      options: Options(
        headers: <String, String>{'Cookie': passCookie},
        validateStatus: (int? status) => status != null && status < 400,
      ),
    );
    final String html = pageResp.data ?? '';
    if (html.contains(_passFormMarker)) {
      throw const WordPressPassException('密码错误');
    }

    final String content = _extractEntryContent(html);
    if (content.isEmpty) {
      throw const WordPressPassException('正文为空');
    }
    return content;
  }

  /// 从 302 响应的 Set-Cookie 中提取 `wp-postpass_*`（`name=value` 形式）。
  static String? _postPassCookie(Response<String> resp) {
    final List<String>? setCookies = resp.headers['set-cookie'];
    if (setCookies == null) return null;
    for (final String raw in setCookies) {
      if (!raw.contains('wp-postpass_')) continue;
      final int semicolon = raw.indexOf(';');
      return semicolon < 0 ? raw : raw.substring(0, semicolon);
    }
    return null;
  }

  /// 解析 `entry-content` div 为纯文本。
  ///
  /// 定位 `<body>` 后首个 `class="entry-content`；div 范围用
  /// `<div>`/`</div>` 深度配对求出，并截去正文之后的 Jetpack 附加组件
  /// （`jp-post-flair`/`sharedaddy`）；再去标签、解码常见实体。
  static String _extractEntryContent(String html) {
    final int bodyIdx = html.indexOf('<body');
    final int clsIdx = html.indexOf(
      'class="entry-content',
      bodyIdx < 0 ? 0 : bodyIdx,
    );
    if (clsIdx < 0) return '';
    final int openEnd = html.indexOf('>', clsIdx);
    if (openEnd < 0) return '';

    int end = _divContentEnd(html, openEnd);
    final int cap = _indexOfAny(html, const <String>[
      '<div id="jp-post-flair"',
      '<div class="sharedaddy',
    ], openEnd);
    if (cap >= 0 && cap < end) end = cap;

    final String raw = html.substring(openEnd + 1, end);
    return _htmlToText(raw);
  }

  /// 从 [fromIdx]（开标签 `>` 之后）起，深度配对求 entry-content div 的结束下标。
  static int _divContentEnd(String html, int fromIdx) {
    final List<int> opens = RegExp(r'<div[\s>]')
        .allMatches(html)
        .map((Match m) => m.start)
        .toList(growable: false);
    final List<int> closes = RegExp(r'</div>')
        .allMatches(html)
        .map((Match m) => m.start)
        .toList(growable: false);

    int oi = 0;
    int ci = 0;
    while (oi < opens.length && opens[oi] <= fromIdx) {
      oi++;
    }
    while (ci < closes.length && closes[ci] <= fromIdx) {
      ci++;
    }

    int depth = 1;
    while (ci < closes.length) {
      final int nextOpen = oi < opens.length ? opens[oi] : -1;
      final int nextClose = closes[ci];
      if (nextOpen >= 0 && nextOpen < nextClose) {
        depth++;
        oi++;
      } else {
        depth--;
        ci++;
        if (depth == 0) return nextClose;
      }
    }
    return html.length;
  }

  /// 返回 [markers] 中任一字符串在 [html] 内（下标 ≥ [fromIdx]）的最早下标；全无则 -1。
  static int _indexOfAny(String html, List<String> markers, int fromIdx) {
    int best = -1;
    for (final String marker in markers) {
      final int idx = html.indexOf(marker, fromIdx);
      if (idx >= 0 && (best < 0 || idx < best)) best = idx;
    }
    return best;
  }

  /// 去 script/style 与标签、块级换行、解码常见实体、压缩空行。
  static String _htmlToText(String raw) {
    String text = raw
        .replaceAll(
          RegExp(r'<script[^>]*>[\s\S]*?</script>', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false),
          '',
        )
        .replaceAll(
          RegExp(
            r'</(?:p|div|h[1-6]|li|blockquote|pre|figcaption|figure)>',
            caseSensitive: false,
          ),
          '\n',
        )
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#8217;', "'")
        .replaceAll('&rsquo;', "'")
        .replaceAll('&#8220;', '"')
        .replaceAll('&#8221;', '"')
        .replaceAll('&ldquo;', '"')
        .replaceAll('&rdquo;', '"');
    // 通用十进制数字实体（如 &#8230;）。
    text = text.replaceAllMapped(
      RegExp(r'&#(\d+);'),
      (Match m) {
        final int? code = int.tryParse(m.group(1)!);
        return (code != null && code > 0 && code <= 0x10FFFF)
            ? String.fromCharCode(code)
            : '';
      },
    );
    return text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }
}
```

- [ ] **Step 2.4: 运行确认通过（真实网络）**

Run: `flutter test test/core/utils/wordpress_util_test.dart`
Expected: `All tests passed!`（4 个用例；若网络不通会超时失败——先确认联网再重跑）

- [ ] **Step 2.5: 提交**

```powershell
git add lib/core/utils/wordpress_util.dart test/core/utils/wordpress_util_test.dart
git commit -m "feat(core): WordPressUtil 密码保护文章两步抓取"
```

---

### Task 3: 行内编辑框架泛化（行为不变重构）

把云信行独占的 `editingRemote` 静态信号泛化为 `editingRow` + 统一 cancel/submit 钩子 + 共用 `_InlineEditFrame` 外框。**本任务不新增行**，云信行交互必须与改动前完全一致。

**Files:**
- Modify: `lib/features/profile/presentation/pages/profile_page.dart`
- Modify: `lib/features/app/presentation/pages/main_app.dart:200-232`

- [ ] **Step 3.1: profile_page.dart — 静态信号改名泛化（类头 57-69）**

将 `ProfilePage` 类内这三段（`static bool editingRemote`、`onCancelRemoteEdit`、`onSubmitRemoteEdit` 及其注释）整体替换为：

```dart
  /// 当前处于行内输入编辑态的行号；null = 未编辑（跨组件静态信号）。
  ///
  /// 悬浮遥控器按键不经过 Flutter 焦点链（[MainApp] 的 FloatingRemote.onKey
  /// 直调 `_handleLogical`），页面级 Focus 拦截不到，故壳层在返回/OK 分支
  /// 优先读取此信号；物理/蓝牙遥控器仍由页面 Focus 先拦截（见
  /// `_ProfilePageState._handlePageKey`）。
  static int? editingRow;

  /// 是否有行处于行内输入编辑态。
  static bool get isInlineEditing => editingRow != null;

  /// 取消行内输入编辑（由 [_ProfilePageState] 挂接，供悬浮遥控器返回键触发）。
  static VoidCallback? onCancelInlineEdit;

  /// 提交行内输入编辑（由 [_ProfilePageState] 挂接，供悬浮遥控器 OK 键触发）。
  static VoidCallback? onSubmitInlineEdit;
```

- [ ] **Step 3.2: profile_page.dart — 状态字段与编辑方法（137-145 区域）**

将这两个 getter/setter（原 `_editingRemote`）：

```dart
  /// 「远程」行是否处于输入编辑态：真值源为 [ProfilePage.editingRemote]
  /// （跨组件静态信号，悬浮遥控器直调路径读取）。
  bool get _editingRemote => ProfilePage.editingRemote;
  set _editingRemote(bool value) => ProfilePage.editingRemote = value;
```

替换为：

```dart
  /// 当前行内编辑行号：真值源为 [ProfilePage.editingRow]
  /// （跨组件静态信号，悬浮遥控器直调路径读取）。
  int? get _editingRow => ProfilePage.editingRow;
  set _editingRow(int? value) => ProfilePage.editingRow = value;
```

`_remoteInputController`/`_remoteInputFocusNode` 两个字段保持不动（每个输入行一套 controller/focus 的模式在 Task 4 再加）。

- [ ] **Step 3.3: profile_page.dart — initState / dispose 钩子（164-165、177-184）**

`initState` 中：

```dart
    ProfilePage.onCancelRemoteEdit = _endRemoteEdit;
    ProfilePage.onSubmitRemoteEdit = _submitRemoteEdit;
```

改为：

```dart
    ProfilePage.onCancelInlineEdit = _cancelInlineEdit;
    ProfilePage.onSubmitInlineEdit = _submitInlineEdit;
```

`dispose` 中：

```dart
    if (ProfilePage.onCancelRemoteEdit == _endRemoteEdit) {
      ProfilePage.onCancelRemoteEdit = null;
    }
    if (ProfilePage.onSubmitRemoteEdit == _submitRemoteEdit) {
      ProfilePage.onSubmitRemoteEdit = null;
    }
    // 防御：编辑态中被销毁时复位静态信号，避免残留 true 卡住壳层按键。
    ProfilePage.editingRemote = false;
```

改为：

```dart
    if (ProfilePage.onCancelInlineEdit == _cancelInlineEdit) {
      ProfilePage.onCancelInlineEdit = null;
    }
    if (ProfilePage.onSubmitInlineEdit == _submitInlineEdit) {
      ProfilePage.onSubmitInlineEdit = null;
    }
    // 防御：编辑态中被销毁时复位静态信号，避免残留值卡住壳层按键。
    ProfilePage.editingRow = null;
```

- [ ] **Step 3.4: profile_page.dart — 失焦自动取消（209-211）**

```dart
    // 焦点离开「远程」行时取消输入编辑态（不提交）。
    if (_editingRemote && c.row != _remoteRow) {
      _endRemoteEdit();
    }
```

改为：

```dart
    // 焦点离开编辑中的行时取消输入编辑态（不提交）。
    if (_editingRow != null && c.row != _editingRow) {
      _cancelInlineEdit();
    }
```

- [ ] **Step 3.5: profile_page.dart — 激活与步进调用点**

`_onActivateRow`（234 行）：

```dart
    if (row == _remoteRow && mounted) _beginRemoteEdit();
```

改为：

```dart
    if (row == _remoteRow && mounted) _beginInlineEdit(_remoteRow);
```

`_stepRow` 的 `case _remoteRow`（375-377）：

```dart
      case _remoteRow: // 远程：左/右键打开行内输入框
        _beginRemoteEdit();
        break;
```

改为：

```dart
      case _remoteRow: // 远程：左/右键打开行内输入框
        _beginInlineEdit(_remoteRow);
        break;
```

- [ ] **Step 3.6: profile_page.dart — 常态行的编辑判断与入口（846-871 区域）**

`_buildRemoteLoginRow` 内：

```dart
        if (_editingRemote) {
          return _buildRemoteEditRow();
        }
```

改为：

```dart
        if (_editingRow == _remoteRow) {
          return _buildRemoteEditRow();
        }
```

同方法内共 2 处 `_beginRemoteEdit()` 调用（`onTap` 与 `onStepRight`），全部改为 `_beginInlineEdit(_remoteRow)`；`onStepLeft` 原本就只有 `c.select(_remoteRow)`，不动。

- [ ] **Step 3.7: profile_page.dart — 用泛化方法替换三个旧方法（892-919）**

删除 `_beginRemoteEdit`、`_submitRemoteEdit`、`_endRemoteEdit` 三个方法整体（含注释），在原位置写入：

```dart
  /// 行内输入编辑态的焦点节点，按行号取（未配置的行返回 null）。
  FocusNode? _focusNodeOf(int row) {
    if (row == _remoteRow) return _remoteInputFocusNode;
    return null;
  }

  /// 进入行内输入编辑态：各行为自己的输入框装文本，下一帧聚焦弹出输入法。
  void _beginInlineEdit(int row) {
    if (_editingRow != null || !mounted) return;
    if (row == _remoteRow) {
      // 云信账号：预填当前账号。
      _remoteInputController.text =
          context.read<RemoteLoginBloc>().state.account;
    }
    _editingRow = row;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNodeOf(row)?.requestFocus();
    });
  }

  /// 提交行内输入：按编辑中的行分发；空串一律视为取消。
  void _submitInlineEdit() {
    final int? row = _editingRow;
    if (row == null) return;
    if (row == _remoteRow) {
      final String account = _remoteInputController.text.trim();
      _cancelInlineEdit();
      if (account.isEmpty || !mounted) return;
      context.read<RemoteLoginBloc>().add(RemoteLoginSubmit(account));
    }
  }

  /// 退出行内输入编辑态（取消，不提交）。
  void _cancelInlineEdit() {
    final int? row = _editingRow;
    if (row == null) return;
    _editingRow = null;
    _focusNodeOf(row)?.unfocus();
    if (mounted) setState(() {});
  }
```

- [ ] **Step 3.8: profile_page.dart — 页面按键拦截（965-980 与 926 注释）**

`_handlePageKey` 中：

```dart
    if (!_editingRemote) return KeyEventResult.ignored;
    // 返回键（部分遥控器发 goBack；悬浮遥控器的 escape 走 MainApp 分支）→ 取消编辑。
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack) {
      _endRemoteEdit();
      return KeyEventResult.handled;
    }
    // OK 键 → 提交输入。
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.gameButtonA) {
      _submitRemoteEdit();
      return KeyEventResult.handled;
    }
```

改为：

```dart
    if (_editingRow == null) return KeyEventResult.ignored;
    // 返回键（部分遥控器发 goBack；悬浮遥控器的 escape 走 MainApp 分支）→ 取消编辑。
    if (key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.goBack) {
      _cancelInlineEdit();
      return KeyEventResult.handled;
    }
    // OK 键 → 提交输入。
    if (key == LogicalKeyboardKey.select ||
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.gameButtonA) {
      _submitInlineEdit();
      return KeyEventResult.handled;
    }
```

同方法 doc 注释中 `[ProfilePage.editingRemote]`（926 行）改为 `[ProfilePage.isInlineEditing]`。

- [ ] **Step 3.9: profile_page.dart — 编辑态行改为共用外框（986-1054）**

用下面的 `_buildRemoteEditRow` 替换原方法整体（原方法含 AnimatedContainer 外框、TextField、双 IconButton、二维码 child）：

```dart
  /// 「远程」行编辑态：共用 [_InlineEditFrame]；已登录时下方附二维码。
  Widget _buildRemoteEditRow() {
    final RemoteLoginState remoteState =
        context.read<RemoteLoginBloc>().state;
    return _InlineEditFrame(
      label: 'settings_remote'.tr(),
      controller: _remoteInputController,
      focusNode: _remoteInputFocusNode,
      hintText: 'remote_input_hint'.tr(),
      onCancel: _cancelInlineEdit,
      onSubmit: _submitInlineEdit,
      child: (remoteState.status == RemoteLoginStatus.loggedIn &&
              remoteState.account.isNotEmpty)
          ? QrImageView(
              data: remoteState.account,
              size: 120,
              backgroundColor: Colors.white,
            )
          : null,
    );
  }
```

- [ ] **Step 3.10: profile_page.dart — 新增 `_InlineEditFrame` 类**

在文件末尾 `_StepIcon` 类之后追加：

```dart
/// 行内输入编辑态的共用外框：标题 + 输入框 + ✕ 取消 + ✓ 提交。
///
/// 云信「远程」行等输入行共用；[child] 用于附加内容（如云信行的二维码）。
/// 视觉与原云信编辑态完全一致（外框、字体、密度逐项照搬）。
class _InlineEditFrame extends StatelessWidget {
  const _InlineEditFrame({
    required this.label,
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.onCancel,
    required this.onSubmit,
    this.obscureText = false,
    this.child,
  });

  final String label;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final VoidCallback onCancel;
  final VoidCallback onSubmit;

  /// 密码类输入用圆点遮蔽（默认 false，与原云信行一致）。
  final bool obscureText;

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.primary, width: 2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                label,
                style:
                    textTheme.titleMedium?.copyWith(color: scheme.onSurface),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  textInputAction: TextInputAction.done,
                  textCapitalization: TextCapitalization.none,
                  autocorrect: false,
                  obscureText: obscureText,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: scheme.primary,
                  ),
                  decoration: InputDecoration(
                    hintText: hintText,
                    isDense: true,
                    border: InputBorder.none,
                  ),
                  onSubmitted: (_) => onSubmit(),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.close, color: scheme.onSurfaceVariant),
                onPressed: onCancel,
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.check, color: scheme.primary),
                onPressed: onSubmit,
              ),
            ],
          ),
          if (child != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: child,
            ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 3.11: main_app.dart — 两处分支改读统一信号（201-229）**

OK 分支（201-212）：

```dart
      // 编辑「远程」行时 OK = 提交输入，不走 activate。
      // 悬浮遥控器直调本方法、不经焦点链，页面 Focus 拦截不到，故在此优先处理；
      // 物理/蓝牙遥控器的 OK 已被页面 Focus 消费（见 ProfilePage._handlePageKey）。
      // 仅在「我的」分支生效：ProfilePage State 在 IndexedStack 常驻，
      // 切走后 editingRemote 可能仍为 true，不限分支会吞掉其它页的 OK。
      final VoidCallback? submitRemote = ProfilePage.onSubmitRemoteEdit;
      if (cur == _profileBranchIndex &&
          ProfilePage.editingRemote &&
          submitRemote != null) {
        submitRemote();
        return true;
      }
```

改为：

```dart
      // 行内输入编辑态 OK = 提交输入，不走 activate。
      // 悬浮遥控器直调本方法、不经焦点链，页面 Focus 拦截不到，故在此优先处理；
      // 物理/蓝牙遥控器的 OK 已被页面 Focus 消费（见 ProfilePage._handlePageKey）。
      // 仅在「我的」分支生效：ProfilePage State 在 IndexedStack 常驻，
      // 切走后 editingRow 可能仍非 null，不限分支会吞掉其它页的 OK。
      final VoidCallback? submitInline = ProfilePage.onSubmitInlineEdit;
      if (cur == _profileBranchIndex &&
          ProfilePage.isInlineEditing &&
          submitInline != null) {
        submitInline();
        return true;
      }
```

返回分支（221-229）：

```dart
      // 编辑「远程」行时返回 = 取消编辑，不弹退出确认（同上，悬浮遥控器路径）。
      // 同样仅限「我的」分支，理由同上。
      final VoidCallback? cancelRemote = ProfilePage.onCancelRemoteEdit;
      if (cur == _profileBranchIndex &&
          ProfilePage.editingRemote &&
          cancelRemote != null) {
        cancelRemote();
        return true;
      }
```

改为：

```dart
      // 行内输入编辑态返回 = 取消编辑，不弹退出确认（同上，悬浮遥控器路径）。
      // 同样仅限「我的」分支，理由同上。
      final VoidCallback? cancelInline = ProfilePage.onCancelInlineEdit;
      if (cur == _profileBranchIndex &&
          ProfilePage.isInlineEditing &&
          cancelInline != null) {
        cancelInline();
        return true;
      }
```

- [ ] **Step 3.12: 残留引用清零 + 静态检查**

Run:

```powershell
Select-String -Path "lib\features\profile\presentation\pages\profile_page.dart","lib\features\app\presentation\pages\main_app.dart" -Pattern "editingRemote|onCancelRemoteEdit|onSubmitRemoteEdit|_beginRemoteEdit|_submitRemoteEdit|_endRemoteEdit"
```

Expected: 无任何输出（0 匹配）

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3.13: 提交**

```powershell
git add lib/features/profile/presentation/pages/profile_page.dart lib/features/app/presentation/pages/main_app.dart
git commit -m "refactor(profile): 行内输入编辑框架泛化为 editingRow 统一信号"
```

---

### Task 4: 「WordPress密码」设置行 + 翻译 + rowCount 17→18

**Files:**
- Modify: `lib/features/profile/application/profile_focus_controller.dart`
- Modify: `lib/features/profile/presentation/pages/profile_page.dart`
- Modify: `assets/translations/zh-CN.json`、`assets/translations/zh-TW.json`、`assets/translations/en-US.json`、`assets/translations/ja-JP.json`

- [ ] **Step 4.1: profile_focus_controller.dart — 行数与文档**

1) `static const int rowCount = 17;` → `static const int rowCount = 18;`

2) 类 doc 中（10 行）`[row]` 行号清单末段：

```
13=远程 / 14=版本 / 15=天气数据来源 / 16=免责声明
```

改为：

```
13=远程 / 14=WordPress密码 / 15=版本 / 16=天气数据来源 / 17=免责声明
```

3) 按键语义行（13 行）`「导航条 ↔ 十七列设置行」` → `「导航条 ↔ 十八列设置行」`

4) `row` getter 的 doc（37 行）中同样的行号清单，做与第 2 点相同的替换。

- [ ] **Step 4.2: profile_page.dart — 行号常量与输入资源**

1) 在 `static const int _remoteRow = 13;`（含其 doc 注释）之后加：

```dart
  /// 「WordPress密码」行（密码保护文章访问密码：常态掩码展示，激活后行内输入框）的序号。
  static const int _wpPasswordRow = 14;
```

2) 在 `_remoteInputFocusNode` 字段之后加：

```dart
  /// 「WordPress密码」行输入框的控制器与焦点节点。
  final TextEditingController _wpPasswordInputController =
      TextEditingController();
  final FocusNode _wpPasswordInputFocusNode = FocusNode();
```

3) `dispose()` 中 `_remoteInputController.dispose(); _remoteInputFocusNode.dispose();` 之后加：

```dart
    _wpPasswordInputController.dispose();
    _wpPasswordInputFocusNode.dispose();
```

- [ ] **Step 4.3: profile_page.dart — 分发方法接入 WP 行**

`_focusNodeOf`：

```dart
  FocusNode? _focusNodeOf(int row) {
    if (row == _remoteRow) return _remoteInputFocusNode;
    if (row == _wpPasswordRow) return _wpPasswordInputFocusNode;
    return null;
  }
```

`_beginInlineEdit` 的行分支（在云信分支后加）：

```dart
    if (row == _wpPasswordRow) {
      // 密码：不预填，必须由用户输入。
      _wpPasswordInputController.text = '';
    }
```

`_submitInlineEdit` 加分支（方法末尾、云信分支之后）：

```dart
    if (row == _wpPasswordRow) {
      final String password = _wpPasswordInputController.text;
      _cancelInlineEdit();
      if (password.isEmpty || !mounted) return;
      // 密码不 trim、原样保存；setWpPassword 内存赋值同步、落盘异步。
      AppSettings.instance.setWpPassword(password);
    }
```

`_onActivateRow` 加一行：

```dart
    if (row == _wpPasswordRow && mounted) _beginInlineEdit(_wpPasswordRow);
```

`_stepRow` 的 switch 中 `case _remoteRow` 分支后加：

```dart
      case _wpPasswordRow: // WordPress密码：左/右键打开行内输入框
        _beginInlineEdit(_wpPasswordRow);
        break;
```

- [ ] **Step 4.4: profile_page.dart — 常态行与编辑行 Widget**

在 `_buildRemoteLoginRow` 方法之后加：

```dart
  /// 「WordPress密码」行：常态掩码展示（未设置显示「未设置」），
  /// 点按 / OK / 右键进入行内输入（编辑态替换为掩码输入框）。
  Widget _buildWpPasswordRow(bool inContent, ProfileFocusController c) {
    if (_editingRow == _wpPasswordRow) return _buildWpPasswordEditRow();
    final String value = AppSettings.instance.wpPassword.isEmpty
        ? 'remote_not_set'.tr()
        : '••••••';
    return _SettingRow(
      highlighted: inContent && c.row == _wpPasswordRow,
      label: 'settings_wp_password'.tr(),
      value: value,
      canStepLeft: false,
      canStepRight: true,
      onTap: () {
        c.select(_wpPasswordRow);
        _beginInlineEdit(_wpPasswordRow);
      },
      onStepLeft: () => c.select(_wpPasswordRow),
      onStepRight: () {
        c.select(_wpPasswordRow);
        _beginInlineEdit(_wpPasswordRow);
      },
    );
  }

  /// 「WordPress密码」行编辑态：掩码输入框（不预填），✕ 取消、✓ 提交保存。
  Widget _buildWpPasswordEditRow() {
    return _InlineEditFrame(
      label: 'settings_wp_password'.tr(),
      controller: _wpPasswordInputController,
      focusNode: _wpPasswordInputFocusNode,
      hintText: 'wp_password_input_hint'.tr(),
      obscureText: true,
      onCancel: _cancelInlineEdit,
      onSubmit: _submitInlineEdit,
    );
  }
```

- [ ] **Step 4.5: profile_page.dart — 列表插入（build 中 454-455 之间）**

在云信行的 `KeyedSubtree` 与其后的 `const SizedBox(height: 12)` 之后、`_versionRow` 的 `KeyedSubtree` 之前插入：

```dart
                const SizedBox(height: 12),
                KeyedSubtree(
                  key: _rowKeys[_wpPasswordRow],
                  child: _buildWpPasswordRow(inContent, c),
                ),
```

即该区域变为：

```dart
                KeyedSubtree(
                  key: _rowKeys[_remoteRow],
                  child: _buildRemoteLoginRow(inContent, c),
                ),
                const SizedBox(height: 12),
                KeyedSubtree(
                  key: _rowKeys[_wpPasswordRow],
                  child: _buildWpPasswordRow(inContent, c),
                ),
                const SizedBox(height: 12),
                KeyedSubtree(
                  key: _rowKeys[_versionRow],
                  child: _buildVersionRow(inContent, c),
                ),
```

（尾部三行常量是 `rowCount-N` 计算，自动顺延为 15/16/17，无需改。）

- [ ] **Step 4.6: 四个翻译文件各加 2 个 key**

每个文件在 `  "settings_remote": …,` 行之后插入两行（保持 2 空格缩进、CRLF、逗号齐全）：

`assets/translations/zh-CN.json`：

```json
  "settings_wp_password": "WordPress密码",
  "wp_password_input_hint": "输入WordPress密码",
```

`assets/translations/zh-TW.json`（锚点 `  "settings_remote": "遠程",`）：

```json
  "settings_wp_password": "WordPress密碼",
  "wp_password_input_hint": "輸入WordPress密碼",
```

`assets/translations/en-US.json`（锚点 `  "settings_remote": "Remote",`）：

```json
  "settings_wp_password": "WordPress Password",
  "wp_password_input_hint": "Enter WordPress password",
```

`assets/translations/ja-JP.json`（锚点 `  "settings_remote": "リモート",`）：

```json
  "settings_wp_password": "WordPressパスワード",
  "wp_password_input_hint": "WordPressパスワードを入力",
```

- [ ] **Step 4.7: JSON 合法性校验**

Run:

```powershell
foreach ($f in 'zh-CN','zh-TW','en-US','ja-JP') { Get-Content "assets\translations\$f.json" -Raw -Encoding UTF8 | ConvertFrom-Json | Out-Null; "$f OK" }
```

Expected: 四行 `… OK`，无解析错误

- [ ] **Step 4.8: 静态检查**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4.9: 提交**

```powershell
git add lib/features/profile/application/profile_focus_controller.dart lib/features/profile/presentation/pages/profile_page.dart assets/translations/zh-CN.json assets/translations/zh-TW.json assets/translations/en-US.json assets/translations/ja-JP.json
git commit -m "feat(settings): 我的页新增 WordPress密码 行（掩码展示+行内输入）"
```

---

### Task 5: 全量验证

- [ ] **Step 5.1: 全仓静态检查**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5.2: 全量测试**

Run: `flutter test`
Expected: `All tests passed!`（含既有 11 个测试文件 + 新增 6 个用例；`wordpress_util_test` 需要联网）

- [ ] **Step 5.3: 报告人工验证清单（需设备，交给用户）**

1. 设置页 → 「WordPress密码」行显示「未设置」；输入 `12345678` → 显示 `••••••`；杀进程重启仍显示 `••••••`（持久化）
2. 编辑态交互回归（与云信行逐项一致）：✕ 取消不保存、✓/键盘 done 保存、失焦不提交、上下键移焦自动取消
3. 物理遥控器：编辑态按返回=取消、按 OK=提交；悬浮遥控器同样生效
4. 云信「远程」行编辑回归（框架泛化的受影响面）：预填账号、提交登录、取消
5. 行导航：第 14 行是「WordPress密码」，其后依次为版本/天气数据来源/免责声明；尾部三行无错位

- [ ] **Step 5.4: 汇总**

向用户汇报：完成的 Task、analyze/test 结果、待人工验证清单。
