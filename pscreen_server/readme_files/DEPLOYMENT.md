# Flutter Web + Node.js 部署指南

## 🎯 部署概述

本指南将帮助您将Flutter Web应用部署到Node.js服务器上，实现前后端一体化部署。

## 📁 部署结构

```
D:\www\app_translator_web\
├── build\web\                    # Flutter Web 构建输出
│   ├── index.html               # 主页面
│   ├── main.dart.js             # Flutter 应用代码
│   ├── assets\                  # 静态资源
│   └── ...
└── server\                      # Node.js 服务器
    ├── server.js               # 服务器代码
    ├── package.json            # 依赖配置
    ├── node_modules\           # 依赖包
    └── start-production.bat     # 生产启动脚本
```

## 🚀 快速部署

### 方法1：使用部署脚本（推荐）

```bash
# 1. 构建并部署
deploy.bat

# 2. 访问应用
# 浏览器打开: http://localhost:3000
```

### 方法2：手动部署

```bash
# 1. 构建 Flutter Web 应用
flutter build web --release

# 2. 启动 Node.js 服务器
cd server
set WEB_APP_PATH=D:\www\app_translator_web\build\web
node server.js
```

## 🔧 服务器配置

### 环境变量配置

服务器支持以下环境变量：

- `PORT`: 服务器端口（默认: 3000）
- `WEB_APP_PATH`: Flutter Web应用路径
- `NODE_ENV`: 运行环境（development/production）

### 生产环境配置

```javascript
// server/production.config.js
module.exports = {
    port: 3000,
    webAppPath: 'D:\\www\\app_translator_web\\build\\web',
    uploadDir: '../uploads',
    // ... 其他配置
};
```

## 📋 功能特性

### ✅ 已实现功能

1. **静态文件服务** - 提供Flutter Web应用
2. **文件上传API** - POST /upload
3. **文件列表API** - GET /files  
4. **文件删除API** - DELETE /files/:filename
5. **SPA路由支持** - 所有路由重定向到Flutter应用
6. **CORS支持** - 跨域请求支持

### 🔧 API 端点

| 方法 | 端点 | 描述 |
|------|------|------|
| GET | / | Flutter Web应用首页 |
| POST | /upload | 上传文件 |
| GET | /files | 获取文件列表 |
| DELETE | /files/:filename | 删除指定文件 |

## 🛠️ 开发工作流

### 1. 开发阶段
```bash
# 启动开发服务器
start_server.bat

# 启动Flutter开发服务器
start_flutter.bat
```

### 2. 构建阶段
```bash
# 构建Flutter Web应用
flutter build web --release
```

### 3. 部署阶段
```bash
# 使用部署脚本
deploy.bat

# 或手动部署
cd server
set WEB_APP_PATH=D:\www\app_translator_web\build\web
node server.js
```

## 🔍 故障排除

### 常见问题

1. **Flutter应用无法加载**
   - 检查 `WEB_APP_PATH` 环境变量是否正确
   - 确认Flutter构建文件是否存在

2. **文件上传失败**
   - 检查 `uploads` 目录权限
   - 确认文件大小未超过限制（10MB）

3. **API请求失败**
   - 检查CORS配置
   - 确认服务器端口未被占用

### 日志查看

服务器启动后会显示详细日志：
```
🚀 应用服务器运行在 http://localhost:3000
📁 Flutter Web应用路径: D:\www\app_translator_web\build\web
📁 上传目录: E:\Code\mystic_app\app_translator_web\uploads
```

## 📦 生产环境优化

### 性能优化建议

1. **启用Gzip压缩**
2. **配置缓存策略**
3. **使用CDN加速静态资源**
4. **配置负载均衡**

### 安全配置

1. **文件上传限制**: 最大300MB
2. **API请求限制**: JSON和URL编码请求最大5MB
3. **配置CORS白名单**
4. **启用HTTPS**
5. **添加请求频率限制**

## 🌐 访问应用

部署成功后，通过以下地址访问：

- **本地访问**: http://localhost:3000
- **网络访问**: http://[服务器IP]:3000

## 📝 注意事项

1. **路径配置**: 确保 `WEB_APP_PATH` 指向正确的Flutter构建目录
2. **端口占用**: 确保3000端口未被其他应用占用
3. **文件权限**: 确保服务器有读写 `uploads` 目录的权限
4. **依赖安装**: 首次运行前需要执行 `npm install`
