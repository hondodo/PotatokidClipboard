# 用户登录功能说明

## 功能概述

已成功实现用户登录模块，包括以下功能：

### 1. 登录按钮组件 (UserLoginWidget)
- **未登录状态**：显示"请登录"按钮，点击后底部弹出登录页面
- **已登录状态**：显示用户名和下拉菜单，可以退出登录
- 自动检测登录状态（通过cookie）

### 2. 登录页面 (LoginPage)
- 底部弹出式设计，支持拖拽关闭
- 用户名和密码输入验证
- 登录成功后自动关闭页面并显示欢迎消息
- 支持键盘操作（回车键登录）

### 3. 服务器端支持
- 新增 `/login` 接口，支持用户名密码验证
- 使用cookie管理用户登录状态
- 支持用户个人目录结构

### 4. 目录结构变更
- **个人文件**：`datas/users/用户名/uploads/` 和 `datas/users/用户名/notes/`
- **翻译文件**：`datas/translations/`（公共目录）
- **向后兼容**：未登录用户仍可使用原有目录

## 测试账号

系统预设了以下测试账号：
- 用户名：`admin`，密码：`admin123`
- 用户名：`user`，密码：`user123`
- 用户名：`test`，密码：`test123`

## 使用方法

1. 启动服务器：`npm start`（在server目录下）
2. 启动Flutter应用：`flutter run -d chrome`
3. 点击右上角的"请登录"按钮
4. 输入测试账号进行登录
5. 登录后可以看到用户名显示，点击可退出登录

## 技术实现

### 前端 (Flutter)
- 使用 `dart:html` 进行HTTP请求和cookie操作
- 底部弹出页面使用 `showModalBottomSheet`
- 状态管理通过 `StatefulWidget` 实现

### 后端 (Node.js)
- 使用 `cookie-parser` 中间件处理cookie
- 简单的内存验证（生产环境应使用数据库）
- 支持用户个人目录和公共目录的分离

## 文件变更

### 新增文件
- `lib/components/user_login_widget.dart` - 登录按钮组件
- `lib/pages/user/login_page.dart` - 登录页面

### 修改文件
- `lib/pages/home/home_page.dart` - 添加登录按钮到AppBar
- `lib/apis.dart` - 添加登录API端点
- `server/server.js` - 添加登录接口和目录结构支持
- `server/package.json` - 添加cookie-parser依赖

### 目录结构
```
datas/
├── users/
│   └── [用户名]/
│       ├── uploads/     # 用户个人上传文件
│       └── notes/       # 用户个人笔记
└── translations/        # 公共翻译文件
    └── [应用名]/
        ├── [语言文件]
        └── backups/
```

## 注意事项

1. 当前使用简单的硬编码验证，生产环境应使用数据库和加密
2. Cookie设置为24小时过期
3. 支持中文文件名和路径
4. 保持向后兼容性，未登录用户仍可正常使用
