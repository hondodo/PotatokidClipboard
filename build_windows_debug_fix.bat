@echo off
REM 修复 Windows Debug 构建问题
REM 解决 LNK1168 错误：无法打开 Debug 可执行文件进行写入

echo 正在修复 Windows Debug 构建问题...
echo.

REM 1. 尝试关闭正在运行的 Debug 版本应用
echo [1/3] 检查并关闭正在运行的 Debug 应用...
taskkill /F /IM potatokid_clipboard.exe 2>nul
if %errorlevel% equ 0 (
    echo 已关闭正在运行的 potatokid_clipboard.exe
) else (
    echo 未发现正在运行的 potatokid_clipboard.exe
)
timeout /t 1 /nobreak >nul

REM 2. 删除 Debug 构建目录
echo [2/3] 清理 Debug 构建目录...
if exist "build\windows\x64\runner\Debug" (
    rmdir /s /q "build\windows\x64\runner\Debug" 2>nul
    if %errorlevel% equ 0 (
        echo Debug 构建目录已清理
    ) else (
        echo 警告: 无法完全删除 Debug 构建目录，可能仍有文件被占用
        echo 请手动关闭所有相关进程后重试
    )
) else (
    echo Debug 构建目录不存在，跳过清理
)
timeout /t 1 /nobreak >nul

REM 3. 重新构建 Debug 版本
echo [3/3] 重新构建 Debug 版本...
echo.
flutter build windows --debug

if %errorlevel% equ 0 (
    echo.
    echo ========================================
    echo Debug 构建成功！
    echo ========================================
) else (
    echo.
    echo ========================================
    echo Debug 构建失败！
    echo 如果问题仍然存在，请尝试：
    echo 1. 确保所有 potatokid_clipboard.exe 进程已关闭
    echo 2. 关闭可能占用文件的 IDE 或编辑器
    echo 3. 以管理员权限运行此脚本
    echo 4. 手动删除 build\windows 目录后重试
    echo ========================================
)

pause

