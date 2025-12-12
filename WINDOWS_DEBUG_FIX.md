# Windows 调试连接断开问题修复

## 问题描述

在 Windows 平台上使用 VS Code 调试 Flutter 应用时，调试连接可能会在一段时间后自动断开，导致无法继续调试。

## 问题原因

### 主要原因

1. **应用窗口隐藏导致连接断开**
   - 应用在启动时会根据设置自动隐藏窗口（最小化到系统托盘）
   - 当窗口被隐藏后，Flutter 调试器可能认为应用已退出或失去连接
   - 这会导致调试连接断开

2. **Flutter 调试器超时**
   - VS Code 的 Flutter 调试器可能有默认的超时设置
   - 长时间没有调试活动可能导致连接断开

3. **Windows 防火墙/安全软件**
   - 防火墙或安全软件可能阻止调试连接
   - 某些安全策略可能导致连接中断

4. **系统电源管理**
   - Windows 的电源管理设置可能导致系统进入睡眠或休眠
   - 这会导致所有网络连接（包括调试连接）断开

## 解决方案

### 方案 1：调试模式下保持窗口可见（已实现）

**修改内容：**
- 在 `lib/main.dart` 中添加了调试模式检测
- 在调试模式下（`kDebugMode == true`），应用不会自动隐藏窗口
- 这样可以保持调试连接稳定

**代码变更：**
```dart
// 在调试模式下不隐藏窗口，避免调试连接断开
final bool isDebugMode = kDebugMode;
if (Get.find<SettingsService>().isHideWindowOnStartup.value && !isDebugMode) {
  // 只在非调试模式下隐藏窗口
  appWindow.hide();
}
```

### 方案 2：优化 VS Code 调试配置（已实现）

**修改内容：**
- 在 `.vscode/launch.json` 中添加了调试参数
- 使用 `--disable-service-auth-codes` 参数简化调试连接

**配置说明：**
```json
{
    "name": "potatokid_clipboard",
    "request": "launch",
    "type": "dart",
    "program": "lib/main.dart",
    "args": [
        "--disable-service-auth-codes"
    ],
    "toolArgs": [
        "--disable-service-auth-codes"
    ]
}
```

### 方案 3：检查 Windows 防火墙设置

1. **允许 Flutter 和 VS Code 通过防火墙**
   - 打开 Windows 安全中心
   - 进入"防火墙和网络保护"
   - 点击"允许应用通过防火墙"
   - 确保以下应用被允许：
     - Visual Studio Code
     - Flutter (flutter.exe)
     - Dart (dart.exe)

2. **临时禁用防火墙测试**（仅用于测试）
   - 如果问题解决，说明是防火墙问题
   - 然后重新启用防火墙并正确配置规则

### 方案 4：调整系统电源设置

1. **禁用睡眠和休眠**
   - 打开"电源选项"
   - 设置"关闭显示器"和"使计算机进入睡眠状态"为"从不"
   - 或者在调试期间临时禁用

2. **使用高性能电源计划**
   - 在调试期间切换到"高性能"电源计划

### 方案 5：检查防病毒软件

某些防病毒软件可能会干扰调试连接：

1. **添加排除项**
   - 将项目目录添加到防病毒软件的排除列表
   - 将 Flutter 和 VS Code 安装目录添加到排除列表

2. **临时禁用实时保护**（仅用于测试）
   - 如果问题解决，说明是防病毒软件问题
   - 然后重新启用并正确配置排除项

### 方案 6：使用 Flutter 命令行调试

如果 VS Code 调试仍然有问题，可以尝试使用命令行：

```bash
# 启动应用并保持连接
flutter run -d windows

# 在另一个终端中连接调试器
flutter attach
```

## 验证修复

1. **启动调试**
   - 在 VS Code 中按 F5 启动调试
   - 确认应用窗口保持可见（不会自动隐藏）

2. **测试连接稳定性**
   - 让应用运行一段时间（5-10 分钟）
   - 尝试设置断点并触发
   - 确认调试连接没有断开

3. **检查调试输出**
   - 查看 VS Code 的调试控制台
   - 确认没有连接错误信息

## 其他建议

1. **定期更新 Flutter 和 VS Code**
   - 确保使用最新版本的 Flutter SDK
   - 确保 VS Code 和 Flutter 扩展是最新版本

2. **清理构建缓存**
   - 如果问题持续，尝试运行：
     ```bash
     flutter clean
     flutter pub get
     ```

3. **检查 Flutter 环境**
   - 运行 `flutter doctor -v` 检查环境配置
   - 确保所有组件都正常

4. **使用 Release 模式测试**
   - 如果调试模式有问题，可以先用 Release 模式测试功能
   - Release 模式通常更稳定

## 常见错误信息

如果仍然遇到问题，请检查以下错误信息：

- `Lost connection to device` - 连接丢失
- `Timeout waiting for observatory` - 等待调试器超时
- `Failed to connect to service protocol` - 无法连接到服务协议

这些错误通常表明调试连接确实断开了，需要按照上述方案进行排查。

## 总结

通过以上修改和配置，Windows 调试连接断开的问题应该得到解决。主要改进包括：

1. ✅ 调试模式下保持窗口可见
2. ✅ 优化 VS Code 调试配置
3. ✅ 提供多种排查和解决方案

如果问题仍然存在，请检查系统日志和 Flutter 日志以获取更多信息。

