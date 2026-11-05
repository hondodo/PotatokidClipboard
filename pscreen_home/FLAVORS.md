# 产品变体（Flavor）

本 App（中控端 / 家长端）使用 Android product flavor 生成三个可并行安装的变体。

| flavor | applicationId | app_name | HOME / DEFAULT | 说明 |
| --- | --- | --- | --- | --- |
| `board` | `potatokid.tools.homecontroller` | 薯仔的中控台 | 是 | 已上线包名，现有版本就以系统桌面方式运行；行为保持一致 |
| `phone` | `potatokid.tools.homecontroller.phone` | 薯仔手机端 | 否 | 手机安装，普通桌面图标；可登录任意类型账号并按角色自动分流 |
| `parent` | `potatokid.tools.homecontroller.parent` | 薯仔家长端 | 否 | 只提供家长端功能；中控入口在启动分流处被收敛 |

- `HOME` / `DEFAULT` 只在 `android/app/src/board/AndroidManifest.xml`（flavor overlay）中注册；
  `src/main/AndroidManifest.xml` 不含这两个 category，因此 `phone` / `parent` 合并清单里没有它们，
  普通手机不会被注册成桌面。
- `versionNameSuffix`：`phone` 为 `-phone`、`parent` 为 `-parent`，`board` 不带后缀（沿用已上线版本号）。

## 构建命令

### 分包
```bash
--split-per-abi

```bash
# release（board 沿用现有 debug 签名配置，与已上线包一致）
flutter build apk --release --flavor board  --dart-define=APP_FLAVOR=board 
flutter build apk --release --flavor phone  --dart-define=APP_FLAVOR=phone
flutter build apk --release --flavor parent --dart-define=APP_FLAVOR=parent

# App Bundle
flutter build appbundle --release --flavor parent --dart-define=APP_FLAVOR=parent

# debug
flutter build apk --debug --flavor parent --dart-define=APP_FLAVOR=parent
```

- **必须显式指定 `--flavor`**。引入 flavor 后不存在无 flavor 的默认变体：`flutter build apk` 会执行
  `assembleDebug`，但最后报 `Gradle build failed to produce an .apk file`（产物名是
  `app-<flavor>-<buildType>.apk`）。
- `--dart-define=APP_FLAVOR` 缺省为 `board`，与现有行为一致；常量定义见
  `lib/app/config/app_flavor.dart`。

## `parent` flavor 的编译期语义

- `AppFlavorConfig.isParentOnly == true`。
- `AccountSession.initialHomePathFor()` 在该 flavor 下恒定返回家长视图 `/parental`，
  即使登录角色是 `admin` / `user` 也不会进入中控台首页。
- 仍待收敛（本步只做编译开关，不做大重构）：
  - 登录 / 账号页仍保留中控相关的文案与入口；
  - 设置页仍保留中控设置项；
  - `DeviceReporter` / `RealtimeChannel` 仍会按中控设备上报；
  - 服务端仍需针对 `parent` 包名/账号做权限收敛，不能只依赖客户端隐藏。

## 合并清单检查

```bash
cd android
./gradlew :app:processBoardDebugManifest :app:processPhoneDebugManifest :app:processParentDebugManifest
# 产物：build/app/intermediates/merged_manifests/<flavor>Debug/process<Flavor>DebugManifest/AndroidManifest.xml

# 只应看到 board 的 HOME / DEFAULT
grep -n android.intent.category.HOME    build/app/intermediates/merged_manifests/*Debug/*/AndroidManifest.xml
grep -n android.intent.category.DEFAULT build/app/intermediates/merged_manifests/*Debug/*/AndroidManifest.xml
```

安装包内清单也可以用 aapt2 复核：

```bash
aapt2 dump xmltree build/app/outputs/flutter-apk/app-board-debug.apk --file AndroidManifest.xml | grep category
```

## 服务端包名映射

`pscreen_server/server/realtime.js` 的 `APP_KIND_ALIASES` 与 `admin.js` 的 `HOME_APP_IDS` /
`TV_APP_IDS` 目前只认 `potatokid.tools.homecontroller`。新增的两个包名：

- `potatokid.tools.homecontroller.phone` → `home`
- `potatokid.tools.homecontroller.parent` → `home`（或视「家长端是否作为设备上报」新增独立 kind）

将来需要补进上述映射；本步不修改服务端。
