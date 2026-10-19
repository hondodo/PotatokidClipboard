# WordPress 密码保护文章抓取 + 设置页密码行 — 设计文档

日期：2026-10-19
状态：已批准

## 背景与目标

WordPress 密码保护文章的标准访问流程（已用真实请求验证）：

1. `POST {origin}/wp-login.php?action=postpass`，表单字段 `post_password`、`redirect_to`（文章 URL）、`Submit`
2. 密码正确 → 302 重定向并下发 `wp-postpass_*` cookie；密码错误 → 200 返回表单页（无该 cookie）
3. 带 `wp-postpass_*` cookie GET 文章 URL → 返回含正文的 HTML，正文位于 `entry-content` div 内

目标：

1. 在 `lib/core/utils/wordpress_util.dart`（当前为空文件）实现上述抓取方法
2. 在设置页（`ProfilePage`）新增「WordPress密码」行，持久化密码，交互与云信「远程」账号行完全一致
3. 为后续更多行内输入控件建立可扩展框架（用户明确要求，决定选择泛化方案而非复制方案）

本期**不接线**任何消费正文的业务功能，只交付 util + 设置行。

## 方案决策

| 备选 | 说明 | 结论 |
|---|---|---|
| A. 复制云信行平行模式 | 每个输入行复制一套静态信号/钩子/MainApp 分支 | 否 — 后续还要接入更多输入控件，复制会持续膨胀 |
| B. 泛化行内编辑框架 | 单一 `editingRow` 信号 + 统一分发 + 共用输入外框 | **采用** |
| C. 极简（不接悬浮遥控器） | 只拦页面焦点链按键 | 否 — 悬浮遥控器下交互不完整 |

## 一、总体架构（三层）

| 层 | 文件 | 职责 |
|---|---|---|
| 持久化 | `lib/core/utils/app_settings.dart` | 新增 `wpPassword`（SharedPreferences key `app_wp_password_v1`），getter `wpPassword` / setter `setWpPassword`，与云信账号 `nimAccount` 同款写法 |
| 网络 | `lib/core/utils/wordpress_util.dart` | 静态方法 `fetchPostContent`，纯 Dart（不依赖 Flutter 组件），可单测 |
| UI | `lib/features/profile/presentation/pages/profile_page.dart` | 行内编辑框架泛化 + 新增「WordPress密码」行 |

依赖关系：UI → AppSettings（读密码状态/保存）；Util → AppSettings（缺省取密码）+ dio。三层无循环依赖。

`clearAllPersisted` 采用「先取全部键再逐个删除」，新增 key 自动被覆盖，无需改动。

## 二、行内编辑框架泛化（核心改动）

现状（云信「远程」行独占）：

- `ProfilePage.editingRemote` 静态 bool 信号
- `ProfilePage.onCancelRemoteEdit` / `onSubmitRemoteEdit` 静态钩子（悬浮遥控器用）
- `MainApp` 两处 `if (ProfilePage.editingRemote)` 分支（返回=取消、OK=提交）
- `_ProfilePageState._handlePageKey` 编辑态按键拦截（物理遥控器）
- `_onFocusChanged` 焦点离开该行自动取消

泛化后：

1. **信号**：`static bool editingRemote` → `static int? editingRow`（null=未编辑，非 null=编辑中的行号），附 `static bool get isInlineEditing => editingRow != null`。云信行改为读 `editingRow == _remoteRow`
2. **钩子**：`onCancelRemoteEdit`/`onSubmitRemoteEdit` → `onCancelInlineEdit`/`onSubmitInlineEdit`（挂接/卸载生命周期与现状一致）
3. **MainApp**：两处判断改为 `ProfilePage.isInlineEditing`，分支内部逻辑不变（先取消/提交编辑、不冒泡为退出/激活）
4. **状态内分发**（按 `editingRow` switch）：
   - `_beginInlineEdit(int row)`：云信行预填当前账号；WP 行填空串；各自设置 obscure 标志与 controller/focus，下一帧聚焦弹输入法
   - `_submitInlineEdit()`：云信行→trim 后派发 `RemoteLoginSubmit`（空串=取消）；WP 行→`AppSettings.setWpPassword(原样文本)`（空串=取消，**不 trim**）
   - `_cancelInlineEdit()`：退出编辑态、unfocus、setState
   - `_handlePageKey` 编辑分支、`_onFocusChanged` 失焦取消，全部改为读 `editingRow`
5. **共用输入外框**：从 `_buildRemoteEditRow` 抽出 `_InlineEditFrame`（AnimatedContainer 外框 + 标题 + TextField + ✕ 取消 + ✓ 提交，支持 `obscureText`、`hintText`、`child` 插槽）。云信行传 child=二维码，视觉与现状一致；WP 行传 `obscureText: true`
6. **后续扩展成本**：新增一个输入行 = 行号常量 + begin/submit 各一个 case + 编辑 widget 一个 case；MainApp、按键拦截、失焦逻辑零改动

## 三、「WordPress密码」设置行

- 行号：`_wpPasswordRow = 14`，插在云信「远程」行（13）之后；`ProfileFocusController.rowCount` 17 → 18
- 尾部三行（版本=`rowCount-3`、天气数据来源=`rowCount-2`、免责声明=`rowCount-1`）按计算自动顺延，无需改常量；已确认行号 6–13 的硬编码常量不含 14
- 常态展示：
  - label：`settings_wp_password`
  - 值：密码为空 → `remote_not_set`（复用「未设置」）；已设置 → `••••••`
  - 点按 / OK / 右键 → 进入编辑态（与云信行一致；`canStepLeft: false`、`canStepRight: true`）
- 编辑态：`_InlineEditFrame` + `obscureText: true`；**不预填**（空输入框，必须用户输入）；hint `wp_password_input_hint`；✕ 取消、✓ 提交、键盘 done 提交；空串=取消
- 翻译：`assets/translations/{zh-CN,zh-TW,en-US,ja-JP}.json` 各新增 2 个扁平 key：
  - `settings_wp_password`：zh-CN「WordPress密码」/ en-US「WordPress Password」等
  - `wp_password_input_hint`：zh-CN「输入WordPress密码」/ en-US「Enter WordPress password」等
- 持久化后重启应用无需重新输入（SharedPreferences 落盘）

## 四、WordPressUtil

```dart
/// 密码未设置或校验失败。
class WordPressPassException implements Exception {
  const WordPressPassException(this.message);
  final String message;
  @override
  String toString() => 'WordPressPassException: $message';
}

class WordPressUtil {
  /// [password] 缺省时读 AppSettings.instance.wpPassword。
  /// 两步抓取：POST wp-login.php?action=postpass（followRedirects:false，
  /// 要求 302 且 Set-Cookie 含 wp-postpass_*）→ 带该 Cookie GET [postUrl]
  /// → 解析 entry-content 去 HTML 标签 → 返回正文纯文本。
  /// 密码未设置/错误 → [WordPressPassException]；网络错误 → [DioException]。
  static Future<String> fetchPostContent(String postUrl, {String? password});
}
```

实现要点：

- 内部自建轻量 `Dio` 实例（不挂全局拦截器/日志），仅此方法使用
- Step 1：POST `{origin}/wp-login.php?action=postpass`，`data` 为 `UrlEncodedQueryParameters`（`post_password`、`redirect_to=postUrl`、`Submit=提交`），`followRedirects: false`，`validateStatus` 允许 2xx/3xx
  - 302 且 `set-cookie` 中存在 `wp-postpass_` → 成功，手工拼接 `name=value` Cookie 头
  - 否则（200 表单页等）→ `WordPressPassException('密码错误')`
  - `password` 为空（参数与 AppSettings 均空）→ `WordPressPassException('密码未设置')`
- Step 2：GET `postUrl`，带 `Cookie` 头
  - 解析：定位 `<body` 之后的 `class="entry-content` 标记，截取至下一个满足 `wp-block-group|wp-block-comments|sharedaddy|post-footer` 的 div；去 script/style → 块级标签换行 → 去其余标签 → 解码常见实体（`&nbsp; &amp; &lt; &gt; &#8217; &#8220; &#8221;` 等）→ 压缩空行 → trim
  - 结果仍含 `post-password-form` 或正文为空 → `WordPressPassException('密码错误或正文为空')`

## 五、验证与测试

1. **单测**：新增 `test/wordpress_util_test.dart`（真实网络）：
   - `fetchPostContent('https://potatokid5.wordpress.com/2026/10/19/hello/', password: '12345678')` → 等于 `'hello page'`
   - 错误密码 → 抛 `WordPressPassException`
   - 空密码 → 抛 `WordPressPassException`
2. **静态检查**：`flutter analyze` 无新增告警
3. **手动验证**（需设备）：
   - 设置页输入密码 → 显示 `••••••` → 杀进程重启 → 仍显示已设置
   - 编辑态：✕ 取消不保存、✓/done 保存、失焦不提交、物理遥控器返回=取消/OK=提交、悬浮遥控器返回=取消/OK=提交
   - 云信「远程」行编辑交互回归（泛化改动影响面）

## 范围外

- 正文的业务消费方（展示、缓存等）— 后续接入
- 文章列表/多篇文章管理
- 密码输入框的显示明文切换（TV 场景不需要）
