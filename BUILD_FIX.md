# 构建问题修复说明

## 问题描述
由于使用了 `file_icon` 包，该包使用了非常量的 `IconData` 实例，导致 Flutter 无法进行图标字体树摇（tree shaking），构建时会报错。

## 解决方案

### 方法 1：使用命令行构建（推荐）

使用提供的构建脚本：

**Windows:**
```bash
build_android.bat
```

**Linux/Mac:**
```bash
chmod +x build_android.sh
./build_android.sh
```

或者直接使用 Flutter 命令：
```bash
flutter build apk --release --no-tree-shake-icons
```

### 方法 2：在 Android Studio 中构建

如果您使用 Android Studio 构建，需要：

1. 打开 Android Studio
2. 在 Terminal 中运行：
   ```bash
   flutter build apk --release --no-tree-shake-icons
   ```

或者：

1. 在 Android Studio 中，打开 `Run` -> `Edit Configurations`
2. 在 `Additional run args` 中添加：`--no-tree-shake-icons`
3. 然后使用 Android Studio 的构建功能

### 方法 3：修改构建配置（如果支持）

如果您的 Flutter 版本支持，可以在 `android/app/build.gradle` 的 `flutter` 块中添加：
```gradle
flutter {
    source = "../.."
    // 注意：此配置可能在某些 Flutter 版本中不支持
    // 如果构建失败，请使用方法 1 或 2
}
```

## 注意事项

- 禁用图标树摇会增加应用体积（包含所有图标字体）
- 这是使用 `file_icon` 包的必要配置
- 如果构建仍然失败，请检查其他错误信息


