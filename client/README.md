# potatokid_clipboard

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.


## 安卓编译
由于使用了 file_icon 包（它使用非常量的 IconData），以后构建 Android Release APK 时都需要添加 --no-tree-shake-icons 标志。
flutter build apk --release --no-tree-shake-icons


## dart run build_runner build