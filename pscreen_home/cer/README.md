# Potatokid Home 签名证书说明

本目录用于存放 `pscreen_home`（中控端 / 家长端）Android **release** 打包所需的签名证书。

> ⚠️ 本目录下的密钥文件与口令为**机密**，已被 `cer/.gitignore` 忽略，**切勿提交到公共仓库或分享给他人**。
> 其中 `potatokid-home-cert.cer`（公开证书）与本文档可正常提交。

## 文件清单

| 文件 | 说明 | 保密性 |
|------|------|--------|
| `potatokid-home-release.jks` | Java 密钥库（PKCS12），包含正式的 release 签名密钥对 | **机密，不可泄露** |
| `.storepass.txt` | 密钥库与密钥的口令（单行文本，store 与 key 共用） | **机密，不可泄露** |
| `potatokid-home-cert.cer` | 导出的公钥证书（PEM/RFC 格式） | 公开，用于校验 |

> 口令见同目录下的 `.storepass.txt`，请将口令与 `.jks` 分开存放或自行加密保管。

## 签名信息

- 别名（alias）：`potatokid-home`
- 密钥算法 / 位数：RSA / 2048
- 证书有效期：自 2026-11-13 起 **10,000 天**（至 2054-03-31）
- 证书主题（DN）：`CN=Potatokid Home, OU=Dev, O=Potatokid, L=Beijing, ST=Beijing, C=CN`
- 证书指纹：
  - **SHA-256**：`00:03:13:93:E4:3D:3B:41:6A:89:DF:EA:FF:81:D4:DF:D3:73:79:7B:D0:23:4F:A3:D0:1F:F7:9B:17:1C:0D:5C`
  - SHA-1：`4C:A3:6B:6A:3F:62:C0:40:82:30:9C:A8:AF:64:DD:19:57:97:1B:9A`

> 可通过 `apksigner verify --print-certs app-release.apk` 校验安装包签名的指纹是否与此一致。

## 与构建的关联

`android/app/build.gradle.kts` 的 `signingConfigs.release` **直接从此目录读取签名**（单一权威副本，无需在 `android/app/` 另存）：

```kotlin
val releaseSigningStore: File = file("../../cer/potatokid-home-release.jks")
val releaseSigningPassword: String = file("../../cer/.storepass.txt").readText().trim()

signingConfigs {
    create("release") {
        storeFile = releaseSigningStore
        storePassword = releaseSigningPassword
        keyAlias = "potatokid-home"
        keyPassword = releaseSigningPassword
    }
}
```

> 相对路径 `../../cer/` 是相对于 `android/app/`（即 `build.gradle.kts` 所在目录）解析的，等价于 `pscreen_home/cer/`。

## 重新打包正式 release

在 `pscreen_home` 项目根目录执行（任一 flavor 的 release 都会用本目录的密钥签名）：

```bash
flutter build apk --release --flavor board  --dart-define=APP_FLAVOR=board
flutter build apk --release --flavor phone  --dart-define=APP_FLAVOR=phone
flutter build apk --release --flavor parent --dart-define=APP_FLAVOR=parent
```

> 注意：release 构建依赖本目录的 `.jks` 与 `.storepass.txt`。这两份文件被 git 忽略，不会随仓库分发；新机器 / CI 需要先从安全的离线备份取回这两份文件，否则 `flutter build apk --release` 会报找不到密钥。

## 安装包签名校验

```bash
E:\Env\Android\SDK\build-tools\36.0.0\apksigner.bat verify --print-certs app-home-release.apk
```

当输出中的 `Signer #1 certificate DN` 为本说明中的 `CN=Potatokid Home`，且 **SHA-256 指纹一致**时，即为正式签名包。

## 重要风险提示

- **丢失 `.jks` 和口令** → 无法再对既有 home 包做覆盖升级，只能换签名重新分发（用户设备上的旧版将无法覆盖安装）。
- **口令泄露** → 他人可用你的签名伪造应用安装包。
- 建议另备一份加密副本（如密码管理器或离线加密存储），不要只存在本项目目录里。
- home 端此前一直沿用 Android 默认 **debug** 密钥签名（见 `FLAVORS.md` 旧说明）；切换到本正式密钥后，**首次发版必须用本密钥**，且今后所有 release 都必须用同一份 `.jks`，否则会出现「签名不一致 / 应用未安装」导致无法覆盖升级。
- 本密钥与 `pscreen/potatokid_screen/cer/` 下的 TV 端密钥（`potatokid-release.jks`，alias `potatokid`）是**两把不同的密钥**——home 与 TV 包名不同，各自独立签名，互不影响。

生成日期：2026-11-13
