# 用户注册功能说明

## 功能概述

已成功实现用户注册功能，与登录功能完美集成：

### 1. 注册接口 (`/register`)
- **用户名验证**：2-20个字符
- **密码验证**：4-50个字符
- **重复检查**：防止用户名重复注册
- **密码加密**：使用MD5哈希存储密码
- **文件存储**：用户信息存储在 `datas/register/users/用户名` 文件中

### 2. 登录接口 (`/login`) 更新
- **文件验证**：从注册文件读取用户信息
- **密码验证**：MD5哈希比较
- **错误提示**：
  - 用户不存在：提示"用户不存在"
  - 密码错误：提示"密码错误"

### 3. 前端界面更新
- **登录按钮**：显示"登录|注册"下拉菜单
- **登录页面**：支持登录/注册模式切换
- **注册表单**：包含确认密码字段
- **智能验证**：根据模式调整验证规则

## 目录结构

```
datas/
├── register/
│   └── users/
│       ├── [用户名1]     # 包含密码MD5哈希
│       ├── [用户名2]     # 包含密码MD5哈希
│       └── ...
├── users/
│   └── [用户名]/
│       ├── uploads/     # 用户个人上传文件
│       └── notes/        # 用户个人笔记
└── translations/        # 公共翻译文件
```

## 使用方法

### 注册新用户
1. 点击右上角"登录|注册"按钮
2. 选择"注册"选项
3. 填写用户名（2-20字符）和密码（4-50字符）
4. 确认密码
5. 点击"注册"按钮
6. 注册成功后自动切换到登录模式

### 用户登录
1. 点击右上角"登录|注册"按钮
2. 选择"登录"选项
3. 输入已注册的用户名和密码
4. 点击"登录"按钮

## 技术实现

### 后端 (Node.js)
```javascript
// 注册接口
app.post('/register', (req, res) => {
    const { username, password } = req.body;
    const passwordHash = crypto.createHash('md5').update(password).digest('hex');
    fs.writeFileSync(userFilePath, passwordHash, 'utf8');
});

// 登录接口
app.post('/login', (req, res) => {
    const storedHash = fs.readFileSync(userFilePath, 'utf8').trim();
    const inputHash = crypto.createHash('md5').update(password).digest('hex');
    if (storedHash !== inputHash) {
        return res.status(401).json({ message: '密码错误' });
    }
});
```

### 前端 (Flutter)
```dart
// 注册请求
final response = await html.HttpRequest.request(
    '${Apis.baseUrl}/register',
    method: 'POST',
    sendData: jsonEncode({
        'username': username,
        'password': password,
    }),
);

// 登录请求
final response = await html.HttpRequest.request(
    '${Apis.baseUrl}/login',
    method: 'POST',
    sendData: jsonEncode({
        'username': username,
        'password': password,
    }),
);
```

## 安全特性

1. **密码加密**：使用MD5哈希存储，不存储明文密码
2. **输入验证**：前后端双重验证用户名和密码长度
3. **重复检查**：防止用户名重复注册
4. **错误处理**：详细的错误提示信息

## 文件变更

### 新增功能
- 注册接口 `/register`
- 用户文件存储系统
- 登录/注册模式切换

### 修改文件
- `server/server.js` - 添加注册接口和文件验证
- `lib/pages/user/login_page.dart` - 支持注册模式
- `lib/components/user_login_widget.dart` - 显示登录|注册选项
- `lib/apis.dart` - 添加注册API端点

## 测试流程

1. **启动服务器**：`cd server && npm start`
2. **启动Flutter应用**：`flutter run -d chrome`
3. **测试注册**：
   - 点击"登录|注册" → "注册"
   - 输入新用户名和密码
   - 确认注册成功
4. **测试登录**：
   - 点击"登录|注册" → "登录"
   - 使用注册的用户名和密码登录
   - 确认登录成功

## 注意事项

1. **密码安全**：当前使用MD5，生产环境建议使用更安全的哈希算法
2. **文件权限**：确保服务器有写入 `datas/register/users/` 目录的权限
3. **数据备份**：定期备份用户注册文件
4. **错误处理**：所有网络请求都有完整的错误处理机制

## 未来扩展

1. **密码强度**：添加密码复杂度验证
2. **邮箱验证**：支持邮箱注册和验证
3. **密码重置**：添加忘记密码功能
4. **用户管理**：管理员查看和管理用户
5. **数据库**：迁移到数据库存储（MySQL/PostgreSQL）

