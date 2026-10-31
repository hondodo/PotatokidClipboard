# Potatokid 签名证书备份说明

本目录用于备份 Android release 打包所需的签名证书及相关文件。
**此目录请妥善保管，切勿提交到公共仓库或分享给他人。**

## 文件清单

| 文件 | 说明 | 保密性 |
|------|------|--------|
| `potatokid-release.jks` | Java 密钥库，包含正式的 release 签名密钥对 | **机密，不可泄露** |
| `.storepass.txt` | 密钥库与密钥的口令（单行文本） | **机密，不可泄露** |
| `potatokid-cert.cer` | 导出的公钥证书（PEM/RFC 格式） | 公开，用于校验 |

> 签名口令见同目录下的 `.storepass.txt`，请将口令与 `.jks` 分开存放或自行加密保管。

## 签名信息

- 别名（alias）：`potatokid`
- 密钥算法 / 位数：RSA / 2048
- 证书有效期：自生成日起 10,000 天
- 证书主题（DN）：`CN=Potatokid, OU=Dev, O=Potatokid, L=Beijing, ST=Beijing, C=CN`
- 证书指纹：
  - SHA-256：`6b8a0bac2d8d5008c4402f154f3fdefaa1fd5aaf064a2c14caa9f902a420cc06`

> 可通过 `apksigner verify --print-certs app-release.apk` 校验安装包签名的指纹是否与此一致。

## 安装包签名校验

```bash
E:\Env\Android\SDK\build-tools\36.0.0\apksigner.bat verify --print-certs app-release.apk
```

当输出中的 `Signer #1 certificate DN` 为本说明中的 `CN=Potatokid`，且 SHA-256 指纹一致时，即为正式签名包。

## 使用说明

1. **不要移动/删除** `android/app/potatokid-release.jks` 与 `android/app/.storepass.txt`，release 构建会从这里读取签名。
2. **重新打包正式 release**：在项目根目录执行
   ```bash
   flutter build apk --release
   ```
3. **覆盖安装/升级依赖同一密钥**：以后所有 release 都必须用这份 `.jks` 签名，否则用户将无法覆盖升级（会提示"签名不一致/应用未安装"）。

## 重要风险提示

- **丢失 `.jks` 和口令** → 无法再对既有包做覆盖升级，只能换签名重新分发。
- **口令泄露** → 他人可用你的签名伪造应用安装包。
- 建议另备一份加密副本（如密码管理器或离线加密存储），不要只存在本项目目录里。

生成日期：2026-09-28