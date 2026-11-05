# 产品变体（Flavor）

本 App（电视端）使用 Android product flavor 生成三个可并行安装的变体。

| flavor | applicationId | app_name | HOME / DEFAULT | 说明 |
| --- | --- | --- | --- | --- |
| `tv` | `screen.potatokid.tools` | 薯仔看电视 | 否 | 已上线包名，服务端按此包名识别电视端；行为与现有版本一致 |
| `phone` | `screen.potatokid.tools.phone` | 薯仔看电视 | 否 | 手机 / 平板安装，普通桌面图标 |
| `board` | `screen.potatokid.tools.board` | 薯仔电视桌面 | 是 | 注册为系统桌面（`HOME` + `DEFAULT`），可开机自启 |

- `HOME` / `DEFAULT` 只在 `android/app/src/board/AndroidManifest.xml`（flavor overlay）中注册；
  `src/main/AndroidManifest.xml` 不含这两个 category，因此 `tv` / `phone` 的合并清单里没有它们。
- `versionNameSuffix`：`phone` 为 `-phone`、`board` 为 `-board`，`tv` 不带后缀（沿用已上线版本号）。

## 构建命令

```bash
# release（沿用各 flavor 配置的签名；tv 使用原有 potatokid-release.jks）
flutter build apk --release --flavor tv    --dart-define=APP_FLAVOR=tv
flutter build apk --release --flavor phone --dart-define=APP_FLAVOR=phone
flutter build apk --release --flavor board --dart-define=APP_FLAVOR=board

# App Bundle
flutter build appbundle --release --flavor board --dart-define=APP_FLAVOR=board

# debug
flutter build apk --debug --flavor board --dart-define=APP_FLAVOR=board
```

- **必须显式指定 `--flavor`**。引入 flavor 后不存在无 flavor 的默认变体：`flutter build apk` 会执行
  `assembleDebug`，但最后报 `Gradle build failed to produce an .apk file`（产物名是
  `app-<flavor>-<buildType>.apk`，工具按无 flavor 的 `app-debug.apk` 找不到）。
- `--dart-define=APP_FLAVOR` 缺省为 `tv`，与现有行为一致；常量定义见 `lib/app/app_flavor.dart`。

## 合并清单检查

```bash
cd android
./gradlew :app:processTvDebugManifest :app:processPhoneDebugManifest :app:processBoardDebugManifest
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

`pscreen_server/server/realtime.js` 的 `APP_KIND_ALIASES` 与 `admin.js` 的 `TV_APP_IDS` 目前只认
`screen.potatokid.tools`（以及旧包名）。新增的两个 TV 包名：

- `screen.potatokid.tools.phone`
- `screen.potatokid.tools.board`

将来需要补进上述映射（映射值 `tv`），否则新变体上报的设备类型为空。本步不修改服务端。
