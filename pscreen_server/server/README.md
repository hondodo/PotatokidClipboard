# 文件上传服务器

## 🚀 快速启动

### 方法1：使用批处理脚本（推荐）
```bash
# 在项目根目录运行
start_server.bat
```

### 方法2：手动启动
```bash
# 1. 进入server目录
cd server

# 2. 安装依赖（首次运行）
npm install

# 3. 启动服务器
node server.js
```

## 📁 项目结构

```
server/
├── server.js          # 服务器代码
├── package.json       # 依赖配置
└── node_modules/      # 依赖包（自动生成）
```

## 🔧 依赖管理

- **express** - Web框架
- **multer** - 文件上传处理

## 📝 注意事项

1. **首次运行** - 需要先安装依赖
2. **依赖更新** - 删除node_modules后重新npm install
3. **版本控制** - node_modules已添加到.gitignore

## 🌐 访问地址

- 服务器：http://localhost:3000
- 上传接口：POST /upload
- 文件列表：GET /files
- 删除文件：DELETE /files/:filename