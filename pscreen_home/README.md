# 薯仔的中控台

A new Flutter project.

# Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

# 编译不同版本的包
flutter build apk --split-per-abi
# 选择包安装
adb -s 192.168.31.5:5555 install -r build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk
# 启动
adb -s 192.168.31.5:5555 shell monkey -p potatokid.tools.homecontroller -c android.intent.category.LAUNCHER 1