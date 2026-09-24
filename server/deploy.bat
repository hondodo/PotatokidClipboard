@echo off
echo 🚀 部署 Flutter Web 应用到 Node.js 服务器

echo.
echo 📦 步骤1: 构建 Flutter Web 应用
flutter build web --release

echo.
echo 📁 步骤2: 复制构建文件到部署目录
if not exist "D:\www\app_translator_web\build\web" (
    echo ❌ 错误: Flutter 构建目录不存在
    echo 请先运行: flutter build web
    pause
    exit /b 1
)

echo ✅ Flutter Web 应用已构建完成
echo 📍 部署路径: D:\www\app_translator_web\build\web

echo.
echo 🔧 步骤3: 启动 Node.js 服务器
cd server
set WEB_APP_PATH=D:\www\app_translator_web\build\web
node server.js

echo.
echo ✅ 部署完成！
echo 🌐 访问地址: http://localhost:3000
pause
