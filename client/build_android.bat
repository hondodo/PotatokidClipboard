@echo off
REM 构建 Android Release APK，禁用图标树摇以解决 file_icon 包的问题
flutter build apk --release --no-tree-shake-icons


