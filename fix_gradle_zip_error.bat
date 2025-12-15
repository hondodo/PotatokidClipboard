@echo off
echo 正在修复 Gradle ZIP 错误...
echo.

echo [1/4] 清理 Flutter 构建缓存...
call flutter clean
if %errorlevel% neq 0 (
    echo Flutter clean 失败
    pause
    exit /b 1
)

echo.
echo [2/4] 清理 Android 构建目录...
if exist android\build (
    rmdir /s /q android\build
    echo Android build 目录已删除
)

if exist android\app\build (
    rmdir /s /q android\app\build
    echo Android app build 目录已删除
)

echo.
echo [3/4] 清理 Gradle 缓存...
set GRADLE_USER_HOME=%USERPROFILE%\.gradle
if exist "%GRADLE_USER_HOME%\caches" (
    echo 正在删除 Gradle 缓存...
    rmdir /s /q "%GRADLE_USER_HOME%\caches"
    echo Gradle 缓存已清理
)

if exist "%GRADLE_USER_HOME%\wrapper\dists" (
    echo 正在删除 Gradle wrapper 下载文件...
    rmdir /s /q "%GRADLE_USER_HOME%\wrapper\dists"
    echo Gradle wrapper 下载文件已清理
)

echo.
echo [4/4] 重新获取 Flutter 依赖...
call flutter pub get
if %errorlevel% neq 0 (
    echo Flutter pub get 失败
    pause
    exit /b 1
)

echo.
echo ========================================
echo 清理完成！
echo.
echo 现在请尝试重新运行应用：
echo   flutter run
echo ========================================
pause

