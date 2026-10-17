# 设计：设置页「远程」云信账号登录

- 日期：2026-10-13
- 分支：feature/remote_control
- 前置提交：`795fd8f feat: nim init`（NimManager / DI 注册 / main 启动初始化）

## 1. 需求

在「我的」设置页新增一行「远程」，用于配置网易云信（NIM）登录账号：

1. 只需输入账号；密码（NIM token）固定为 `12345678`，配置在 `.env` 中。
2. 行常态展示：`远程  {账号} {状态} >`；点击右侧 `>`（或遥控器 OK）后行内变为输入框，等待用户输入完成。
3. 输入完成后：若账号与当前不同（或当前会话异常），先登出已登录账号，再用新账号登录；账号未变且会话正常时跳过。
4. 账号持久化，App 每次启动时自动登录。
5. 状态文案五态：
   - 未设置（无账号）
   - `{账号} 正在登录`
   - `{账号} 同步数据`
   - `{账号} 已登录`（登录成功且主数据同步完成）
   - `{账号} 登录异常`（登录失败 / 被踢下线）

## 2. 背景事实（已调研确认）

- 云信客户端登录即 `login(accid, token)`；「密码 12345678」即控制台创建账号时设置的统一 token，客户端登录时直接作为 token 传入。
- SDK（`nim_core_v2 10.9.91`）可用能力：
  - `loginService.login(accid, token, NIMLoginOption())` → `NIMResult<void>`（`isSuccess` = code 0/200）
  - `loginService.logout()` / `getLoginUser()` / `getLoginStatus()`
  - 事件流：`onLoginStatus`（logining/logined/logout/unlogin）、`onDataSync`（type + waiting/inSyncing/completed）、`onLoginFailed`、`onKickedOffline`
- 设置页为遥控器焦点驱动列表：行号硬编码常量 + `ProfileFocusController.rowCount`；版本/天气来源/免责声明三行序号为 `rowCount - N` 相对计算。

## 3. 架构（方案B：独立 BLoC feature）

按 AGENT.md 四层结构新增 feature，状态管理用 flutter_bloc：

```
lib/features/remote/
├── application/
│   └── bloc/
│       ├── remote_login_bloc.dart
│       ├── remote_login_event.dart
│       └── remote_login_state.dart
├── domain/
│   └── repositories/
│       └── remote_login_repository.dart          # 纯抽象接口
└── data/
    └── repositories/
        └── remote_login_repository_impl.dart     # 封装 NimManager + AppSettings + AppConfig
```

无 HTTP 网络层（NIM 走 SDK，不走 `HttpBaseRequest`），故不建 `datasources` 与 `models`。

### 3.1 Domain：`RemoteLoginRepository`

```dart
abstract class RemoteLoginRepository {
  /// 已持久化的账号（空串表示未设置）。
  String get savedAccount;

  /// SDK 事件流转发（登录状态 / 数据同步 / 登录失败 / 被踢下线）。
  Stream<NIMLoginStatus> get onLoginStatus;
  Stream<NIMDataSyncDetail> get onDataSync;
  Stream<NIMError> get onLoginFailed;
  Stream<NIMKickedOfflineDetail> get onKickedOffline;

  /// 启动自动登录：无账号则静默返回；有账号直接 login（无需登出）。
  Future<void> autoLogin();

  /// 切换账号：有活跃会话先 logout，再 login 新账号；账号写入持久化。
  /// 抛出异常表示登录失败（Bloc 转 error 态）。
  Future<void> switchAccount(String account);
}
```

### 3.2 Data：`RemoteLoginRepositoryImpl`

- 依赖：`NimManager`（构造注入，来自 DI）、`AppSettings.instance`（账号持久化）、`AppConfig.nimPassword`（.env 密码）。
- `switchAccount` 流程：
  1. 先 `AppSettings.instance.setNimAccount(account)` 持久化新账号（登录失败也保留配置，重启后仍重试该账号）；
  2. `getLoginStatus()` 若为 logined/logining → `logout()`（忽略 logout 失败结果，新登录本身会顶掉旧会话）；
  3. `login(account, AppConfig.nimPassword)`，`!isSuccess` 时抛出带 code/errorDetails 的异常。
- `autoLogin`：`savedAccount` 为空直接返回，否则 `login(savedAccount, nimPassword)`（异常上抛，由 Bloc 捕获转 error 态）。

### 3.3 Application：`RemoteLoginBloc`

**State：**

```dart
enum RemoteLoginStatus { notConfigured, loggingIn, syncing, loggedIn, error }

class RemoteLoginState {
  final String account;          // 已保存账号，'' = 未设置
  final RemoteLoginStatus status;
  final String? errorMessage;    // error 态详情（日志/调试用）
}
```

**Event：**

| 事件 | 触发方 | 处理 |
| --- | --- | --- |
| `RemoteLoginAutoLogin` | main.dart（NIM init 完成后，无论成败） | 无账号→notConfigured；有账号→loggingIn + `repository.autoLogin()` |
| `RemoteLoginSubmit(String account)` | 设置页输入提交 | 见下方提交规则 |
| `RemoteLoginStatusChanged(NIMLoginStatus)` | 订阅 repository | logining→loggingIn；logined→syncing；logout/unlogin→忽略（不驱动展示） |
| `RemoteLoginDataSyncChanged(NIMDataSyncDetail)` | 订阅 repository | main 同步 completed→loggedIn |
| `RemoteLoginLoginFailed(NIMError)` / `RemoteLoginKickedOffline(String reasonDesc)` | 订阅 repository | →error（被踢 reasonDesc 由 `NIMKickedOfflineDetail.reasonDesc ?? ''` 转换） |

> 注：logout/unlogin 事件一律忽略、不驱动展示。服务端登出且未触发被踢事件时，UI 会保持当前展示态直到用户下次提交（已知限制）。

Bloc 构造时以 `repository.savedAccount` 构造初始 State：空串 → 未设置；非空 → 正在登录（autoLogin 事件随即到达驱动后续流转）。

**提交规则（`RemoteLoginSubmit`）：**

1. `account.trim()` 为空 → 不变更状态（等价取消）。
2. 与 `state.account` 相同且状态 ∈ {loggingIn, syncing, loggedIn} → 跳过（不登出不登录）。
3. 否则 → emit `loggingIn`（account 为新值）；`await repository.switchAccount(...)`；成功后等待 SDK 事件流转（不直接置 loggedIn），失败捕获 → error 态。

**同步完成判定与兜底：**

- 登录成功（onLoginStatus=logined）→ `syncing`；
- `onDataSync` 中主数据（`nimDataSyncMain`）completed → `loggedIn`；
- 进入 syncing 时启动 15 秒兜底定时器：超时未收到主数据完成事件 → 直接 `loggedIn`（防止 PC 等平台无同步事件时卡在「同步数据」）。

**DI：`core/di/modules/remote_module.dart`**

```dart
class RemoteModule {
  static Future<void> register() async {
    getIt.registerLazySingleton<RemoteLoginRepository>(
      () => RemoteLoginRepositoryImpl(nim: getIt<NimManager>()));
    getIt.registerLazySingleton<RemoteLoginBloc>(
      () => RemoteLoginBloc(repository: getIt<RemoteLoginRepository>()));
  }
  static Future<void> unregister() async { /* 逆序注销 */ }
}
```

`Injection.init()` 在 `CoreModule`（NimManager）之后注册；`reset()` 逆序注销。

## 4. NimManager 扩展（保持薄封装，不持有 UI 状态）

在现有类上补充：

- `Future<NIMResult<void>> logout()`
- `Future<NIMResult<String?>> getLoginUser()`
- `Future<NIMResult<NIMLoginStatus>> getLoginStatus()`
- 事件流透传 getter：`onLoginStatus` / `onDataSync` / `onLoginFailed` / `onKickedOffline`（委托 `NimCore.instance.loginService`；现有 `startListen` 日志监听保持不变）

## 5. UI：设置页「远程」行

位置：**第 13 行（「重置」之后、「版本」之前）**。

- `ProfileFocusController.rowCount` 16 → 17，同步更新行号文档注释。
- 版本/天气来源/免责声明为 `rowCount - 3/2/1` 相对计算自动顺延为 14/15/16；既有 0–12 行常量不动。
- `ProfilePage` 新增 `_remoteRow = 13` 常量与 `_buildRemoteLoginRow`。

**常态（非编辑）**：复用 `_SettingRow` 风格：

- 未设置：`远程  未设置`（不显示左右步进）；
- 其余：`远程  {账号} {状态文案} >`，右侧 `>` 指示可进入编辑（不是值步进）。

**编辑态（点击 `>` / OK / 左右键触发）**：

- 行内替换为 `TextField`（预填当前账号、自动 `requestFocus` 弹出系统输入法）+ ✓ 提交 + ✕ 取消；
- 提交：键盘「完成」键（`TextInputAction.done` 的 `onSubmitted`）或 ✓ → `RemoteLoginSubmit(trim 后的值)`，退出编辑态；
- 取消：✕，或焦点移出该行（上下切行走焦点控制器）→ 退出编辑态不提交；
- 提交空串按取消处理（状态不变）。

**翻译键（zh-CN / zh-TW / en-US / ja-JP 四文件同步）：**

| key | zh-CN |
| --- | --- |
| `settings_remote` | 远程 |
| `remote_not_set` | 未设置 |
| `remote_logging_in` | 正在登录 |
| `remote_syncing` | 同步数据 |
| `remote_logged_in` | 已登录 |
| `remote_error` | 登录异常 |
| `remote_input_hint` | 输入云信账号 |

## 6. 配置与启动接线

- `.env` 新增：

  ```bash
  # 云信登录：各账号统一 token（控制台创建账号时设置的固定口令）
  NIM_PASSWORD=12345678
  ```

- `AppConfig`：新增 `static String nimPassword = ''`，`initialize()` 中 `_readString('NIM_PASSWORD', ...)`。
- `AppSettings`：新增 `nimAccount`（key `app_nim_account_v1`）读写；`clearAllPersisted` 一并复位（重置后重启即未设置）。
- `main.dart`：NIM `init().then(startListen)` 完成后（`whenComplete`，含 init 失败）派发 `Injection.get<RemoteLoginBloc>().add(const RemoteLoginAutoLogin())`；`MultiBlocProvider` 增加 `RemoteLoginBloc`。

## 7. 错误处理

| 场景 | 行为 |
| --- | --- |
| 登录失败（token 错误、账号不存在等） | error 态，行显示 `{账号} 登录异常`；可重新提交同账号触发重试（error 态同账号不跳过） |
| 被踢下线 | error 态，同上 |
| NIM init 失败 | autoLogin 时 login 抛异常 → error 态；日志记录 |
| 切换账号时 logout 失败 | 忽略 logout 结果继续 login（新登录本身会顶掉旧会话） |
| 提交空串 | 等价取消，状态不变 |

## 8. 测试与验证

- 单元测试（`test/features/remote/`，mockito）：
  - `RemoteLoginBloc`：五态流转、同账号跳过、error 态同账号重登、空提交取消、同步兜底定时器；
  - `RemoteLoginRepositoryImpl`：switchAccount 先登出后登录顺序、登录失败抛异常、autoLogin 无账号静默、持久化写入时机（mock `NimManager`）。
- 验证命令：`flutter analyze`、`flutter test`。

## 9. 范围外（YAGNI）

- 不做消息收发/远程指令处理（后续 feature）；
- 不做账号注册、不校验 accid 字符集（交给 NIM 服务端拒绝）；
- 不迁移 appKey 到 .env（维持 `AppConstants.nimAppKey` 现状）。

## 10. 已知限制

- **登录阶段无超时**：15 秒兜底仅覆盖「同步数据」阶段（§3.3）；若 SDK 在 `loggingIn` 阶段既不回调成功也不回调失败，UI 保持「正在登录」直至用户下次提交。
- **服务端登出静默**：服务端登出且未触发被踢事件时，UI 保持当前展示态直到用户下次提交（详见 §3.3 注）。
- **行内编辑左右键不移光标**：编辑态左右键被根键处理器消费，不移动输入框光标；修改账号需重新输入，或用 ✕ 取消后重新进入编辑。
