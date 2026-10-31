@echo off
echo 🚀 启动生产环境服务器

echo.
echo 📁 设置 Flutter Web 应用路径
set WEB_APP_PATH=D:\www\app_translator_web\build\web

echo.
echo 🔧 启动 Node.js 服务器
node server.js

echo.
echo ✅ 服务器已启动！
echo 🌐 访问地址: http://localhost:3000
pause
