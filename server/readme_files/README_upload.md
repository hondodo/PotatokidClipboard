# Flutter Web 文件上传功能

这个项目演示了如何在Flutter Web应用中实现文件上传功能，包括文件选择和保存到指定目录。

## 功能特性

- ✅ 文件选择器（支持所有文件类型）
- ✅ 文件上传到服务器
- ✅ 本地文件保存（模拟）
- ✅ 上传进度显示
- ✅ 错误处理和状态反馈
- ✅ 美观的用户界面

## 项目结构

```
lib/
├── main.dart                           # 应用入口
├── pages/
│   └── upload/
│       ├── upload_page.dart           # 上传页面
│       └── widget/
│           └── upload_page_content.dart # 上传页面内容组件
```

## 依赖包

在 `pubspec.yaml` 中添加了以下依赖：

```yaml
dependencies:
  file_picker: ^8.0.0+1    # 文件选择器
  http: ^1.2.0            # HTTP请求
  path: ^1.9.0            # 路径处理
```

## 使用方法

### 1. 安装依赖

```bash
flutter pub get
```

### 2. 运行Flutter应用

```bash
flutter run -d chrome
```

### 3. 启动服务器（可选）

如果要测试文件上传到服务器的功能，可以启动提供的Node.js服务器：

```bash
# 安装Node.js依赖
npm install

# 启动服务器
npm start
```

服务器将在 `http://localhost:3000` 运行，文件将保存到 `uploads/` 目录。

## 主要功能

### 文件选择
- 点击"选择文件"按钮打开文件选择器
- 支持选择任何类型的文件
- 显示已选择的文件名

### 文件上传
- **上传到服务器**: 将文件发送到指定的服务器端点
- **保存到本地**: 模拟保存到本地目录（Flutter Web限制）

### 状态显示
- 上传进度指示器
- 成功/失败状态消息
- 错误信息显示

## 代码说明

### 核心方法

1. **`_pickFile()`**: 使用FilePicker选择文件
2. **`_uploadFile()`**: 上传文件到服务器
3. **`_saveToLocalDirectory()`**: 模拟保存到本地

### 文件上传流程

```dart
// 1. 选择文件
FilePickerResult? result = await FilePicker.platform.pickFiles();

// 2. 读取文件内容
Uint8List fileBytes = selectedFile!.bytes!;

// 3. 创建HTTP请求
var request = http.MultipartRequest('POST', Uri.parse('服务器地址'));

// 4. 添加文件到请求
request.files.add(http.MultipartFile.fromBytes('file', fileBytes));

// 5. 发送请求
var response = await request.send();
```

## 服务器配置

提供的Node.js服务器示例包含：

- Express.js框架
- Multer文件上传中间件
- CORS支持
- 文件大小限制（10MB）
- 自动创建上传目录
- 唯一文件名生成

## 注意事项

1. **Flutter Web限制**: 在Web环境中无法直接访问本地文件系统
2. **服务器地址**: 需要将代码中的服务器地址替换为实际的服务器地址
3. **文件大小**: 建议设置合理的文件大小限制
4. **安全性**: 生产环境中需要添加适当的验证和安全性检查

## 扩展功能

可以考虑添加的功能：

- 文件类型验证
- 文件大小限制
- 上传进度条
- 多文件上传
- 文件预览
- 拖拽上传
- 文件压缩

## 故障排除

### 常见问题

1. **文件选择器不工作**: 确保在Web环境中运行
2. **上传失败**: 检查服务器地址和网络连接
3. **依赖问题**: 运行 `flutter pub get` 重新安装依赖

### 调试技巧

- 使用浏览器开发者工具查看网络请求
- 检查控制台错误信息
- 验证服务器端点是否可访问
