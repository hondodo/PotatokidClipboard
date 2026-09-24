# 简化的项目结构

## 🎯 最佳实践：只保留必要文件

### 项目结构
```
app_translator_web/
├── lib/                    # Flutter代码
├── server/
│   ├── server.js          # 服务器代码（唯一必要文件）
│   └── README.md          # 使用说明
├── uploads/               # 文件上传目录
├── start_server.bat      # 启动脚本
└── start_flutter.bat     # Flutter启动脚本
```

## 📦 依赖管理策略

### 方案1：全局安装（推荐）
```bash
# 全局安装常用依赖
npm install -g express multer nodemon

# 项目只保留server.js
# 启动时直接使用全局依赖
```

### 方案2：本地安装（如果需要版本隔离）
```bash
# 在server目录创建package.json
cd server
npm init -y
npm install express multer

# 项目包含node_modules（但.gitignore忽略）
```

## 🚀 启动方式

### 使用全局依赖
```bash
# 启动服务器
cd server
node server.js

# 或使用批处理脚本
start_server.bat
```

### 使用本地依赖
```bash
# 启动服务器
cd server
npm start
```

## ✅ 推荐方案

**全局安装 + 项目只保留server.js**

优势：
- 项目结构简洁
- 不需要package.json
- 不需要node_modules
- 启动简单
- 适合小型项目

## 📝 注意事项

1. **全局依赖** - 适合开发环境，所有项目共享
2. **本地依赖** - 适合生产环境，版本隔离
3. **混合使用** - 常用工具全局，项目特定依赖本地
