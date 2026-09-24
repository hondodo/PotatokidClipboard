# 项目结构说明

## 📁 当前项目结构

```
app_translator_web/
├── lib/                          # Flutter应用代码
│   ├── main.dart                 # 应用入口
│   ├── pages/                    # 页面目录
│   │   ├── home/                # 主页
│   │   ├── upload/              # 上传页面
│   │   └── view_upload/         # 文件管理页面
│   └── ...
├── server/                       # 独立的Node.js服务器
│   ├── server.js               # 服务器主文件
│   ├── package.json            # Node.js依赖配置
│   ├── node_modules/           # Node.js依赖包
│   └── README.md               # 服务器说明
├── uploads/                     # 文件上传目录
├── start_server.bat            # 启动服务器脚本
├── start_flutter.bat           # 启动Flutter脚本
└── 项目结构说明.md              # 本文件
```

## 🚀 启动方式

### 方式1：使用批处理脚本（推荐）
```bash
# 启动服务器
双击 start_server.bat

# 启动Flutter应用
双击 start_flutter.bat
```

### 方式2：手动启动
```bash
# 启动服务器
cd server
D:\env\nvm\v23.1.0\node.exe server.js

# 启动Flutter应用
flutter run -d chrome --web-port=8080
```

## 📦 依赖管理

### Flutter依赖
- 位置：项目根目录
- 管理：`flutter pub get`
- 文件：`pubspec.yaml`

### Node.js依赖
- 位置：`server/` 目录
- 管理：`npm install`
- 文件：`server/package.json`

## 🔧 部署选项

### 开发环境（当前）
- Flutter应用和Node.js服务器在同一台机器
- 使用相对路径访问文件
- 适合开发和测试

### 生产环境（推荐）
- Flutter应用部署到Web服务器（如Nginx）
- Node.js服务器独立部署
- 使用绝对路径和配置文件
- 支持负载均衡和集群部署

## 📝 优势

### 独立服务器方式的优势：
1. **职责分离** - Flutter负责前端，Node.js负责后端
2. **独立部署** - 可以分别部署和扩展
3. **依赖隔离** - Node.js依赖不会影响Flutter项目
4. **团队协作** - 前后端可以独立开发
5. **生产就绪** - 更容易部署到生产环境

### 文件组织：
- `node_modules` 只在 `server/` 目录下
- Flutter项目保持干净
- 上传文件统一管理在 `uploads/` 目录
