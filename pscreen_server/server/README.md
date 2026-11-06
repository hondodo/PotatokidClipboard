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
## 中转白名单（relay_allow_hosts.txt）

- 唯一权威来源：`datas/screen/datas/relay_allow_hosts.txt`，管理页「节目编辑」可编辑。
- 文件不存在时 `GET /api/allow_reply_host` 回退默认值 `["jdshipin.com"]`；文件存在但
  没有有效域名时返回空数组（= 全部直连）。
- 首次在管理页保存时自动创建该文件（父目录递归创建 + 原子写，已有文件不会被覆盖或删除）。

`allow-reply-host.json` 是 2026-11-04 引入、2026-11-06 被 `relay_allow_hosts.txt` 取代的旧文件：
当前代码不再读写它，已从版本库移除并加入 `.gitignore`。仓库只保留
`allow-reply-host.example.json`（内容为旧默认值 `["jdshipin.com"]`）作回溯参考；
运行期真实文件由旧版本服务或运维手工产生，`deploy.sh` 的 rsync 不带 `--delete`，不会删除它。
