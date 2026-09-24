# 网络部署指南

## 🌐 动态域名支持

现在应用支持动态获取当前域名和端口，无需硬编码 `localhost:3000`。

### 🔧 技术实现

```dart
// lib/apis.dart
class Apis {
  // 动态获取当前域名和端口
  static String get baseUrl {
    final location = html.window.location;
    return '${location.protocol}//${location.host}';
  }
  
  // API端点
  static String get upload => '$baseUrl/upload';
  static String get files => '$baseUrl/files';
  static String get deleteFile => '$baseUrl/files';
}
```

## 🚀 部署场景

### 1. 本地开发
- **访问地址**: http://localhost:3000
- **API地址**: 自动检测为 http://localhost:3000

### 2. 局域网部署
- **访问地址**: http://192.168.1.100:3000
- **API地址**: 自动检测为 http://192.168.1.100:3000

### 3. 万维网部署
- **访问地址**: https://yourdomain.com
- **API地址**: 自动检测为 https://yourdomain.com

## 📋 部署步骤

### 本地部署
```bash
# 1. 构建Flutter应用
flutter build web --release

# 2. 启动Node.js服务器
cd server
node server.js

# 3. 访问应用
# 浏览器打开: http://localhost:3000
```

### 局域网部署
```bash
# 1. 构建Flutter应用
flutter build web --release

# 2. 启动Node.js服务器（绑定所有网络接口）
cd server
set WEB_APP_PATH=D:\www\app_translator_web\build\web
node server.js

# 3. 访问应用
# 浏览器打开: http://[服务器IP]:3000
# 例如: http://192.168.1.100:3000
```

### 万维网部署
```bash
# 1. 构建Flutter应用
flutter build web --release

# 2. 配置域名和SSL证书
# 3. 启动Node.js服务器
cd server
set WEB_APP_PATH=/path/to/build/web
node server.js

# 4. 访问应用
# 浏览器打开: https://yourdomain.com
```

## 🔍 调试信息

应用会在页面上显示当前使用的API地址：

- **上传页面**: 显示在"使用说明"卡片中
- **文件管理页面**: 显示在统计信息卡片中

格式：`当前API地址: http://域名:端口`

## 🌐 网络配置

### 防火墙设置
确保3000端口在防火墙中开放：

**Windows**:
```cmd
netsh advfirewall firewall add rule name="Node.js Server" dir=in action=allow protocol=TCP localport=3000
```

**Linux**:
```bash
sudo ufw allow 3000
```

### 路由器配置
如果通过路由器访问，需要配置端口转发：
- 外部端口: 3000
- 内部IP: 服务器IP
- 内部端口: 3000

## 📱 移动设备访问

### 局域网访问
1. 确保移动设备和服务器在同一网络
2. 获取服务器IP地址
3. 在移动设备浏览器中访问: `http://[服务器IP]:3000`

### 万维网访问
1. 配置域名解析
2. 在移动设备浏览器中访问: `https://yourdomain.com`

## 🔧 服务器配置

### 环境变量
```bash
# 设置Flutter Web应用路径
set WEB_APP_PATH=D:\www\app_translator_web\build\web

# 设置端口（可选，默认3000）
set PORT=3000
```

### 生产环境优化
```javascript
// server/production.config.js
module.exports = {
    port: 3000,
    webAppPath: '/path/to/build/web',
    // 其他配置...
};
```

## 🚨 注意事项

1. **HTTPS支持**: 生产环境建议使用HTTPS
2. **CORS配置**: 服务器已配置CORS支持跨域请求
3. **文件上传限制**: 最大300MB，API请求最大5MB
4. **安全考虑**: 生产环境建议添加身份验证

## 📊 测试检查清单

- [ ] 本地访问正常
- [ ] 局域网访问正常
- [ ] 万维网访问正常
- [ ] 文件上传功能正常
- [ ] 文件列表功能正常
- [ ] 文件删除功能正常
- [ ] 移动设备访问正常
- [ ] API地址显示正确
