# 多文件上传功能说明

## 🎯 功能概述

在翻译上传页面中新增了多文件上传功能，支持同时上传三种不同类型的文件：
- **翻译文件**: 目标语言的翻译内容
- **源文文件**: 原始文本内容 (source.json)
- **可用值文件**: 可用的键值对 (available.keys)

## 📋 功能特性

### 1. 多文件选择
- 支持同时选择多个文件
- 每种文件类型独立选择
- 至少需要选择一个文件才能上传
- 文件类型验证（仅支持.json文件）

### 2. 文件类型说明
| 文件类型 | 文件名 | 用途 | 图标 |
|---------|--------|------|------|
| 翻译文件 | 根据语言配置 | 目标语言的翻译内容 | translate |
| 源文文件 | source.json | 原始文本内容 | source |
| 可用值文件 | available.keys | 可用的键值对 | list |

### 3. 服务器端处理
- 支持处理多个文件上传
- 自动备份现有文件
- 按文件类型分别存储
- 完整的错误处理和日志记录

## 🔧 技术实现

### 1. 前端实现

#### 状态管理
```dart
// 文件选择状态
String? _selectedFileName;
html.File? _selectedFile;
String? _selectedSourceFileName;
html.File? _selectedSourceFile;
String? _selectedAvailableFileName;
html.File? _selectedAvailableFile;
```

#### 文件选择方法
```dart
// 选择翻译文件
Future<void> _selectFile() async { ... }

// 选择源文文件
Future<void> _selectSourceFile() async { ... }

// 选择可用值文件
Future<void> _selectAvailableFile() async { ... }
```

#### 上传验证
```dart
// 检查是否至少选择了一个文件
if (_selectedFile == null && _selectedSourceFile == null && _selectedAvailableFile == null) {
  _showError('请至少选择一个文件');
  return;
}
```

#### FormData构建
```dart
final formData = html.FormData();

// 添加翻译文件
if (_selectedFile != null) {
  formData.appendBlob('file', _selectedFile!);
}

// 添加源文文件
if (_selectedSourceFile != null) {
  formData.appendBlob('source', _selectedSourceFile!);
}

// 添加可用值文件
if (_selectedAvailableFile != null) {
  formData.appendBlob('available', _selectedAvailableFile!);
}
```

### 2. 后端实现

#### Multer配置
```javascript
app.post('/upload_translation', translationUpload.fields([
    { name: 'file', maxCount: 1 },
    { name: 'source', maxCount: 1 },
    { name: 'available', maxCount: 1 }
]), (req, res) => {
    // 处理多个文件
});
```

#### 文件处理逻辑
```javascript
const uploadedFiles = [];

// 处理翻译文件
if (files.file && files.file[0]) {
    const translationFile = files.file[0];
    const targetFile = path.join(appDir, targetFileName);
    // 备份和移动文件
    uploadedFiles.push({ 
        type: 'translation', 
        filename: targetFileName, 
        originalName: translationFile.originalname 
    });
}

// 处理源文文件
if (files.source && files.source[0]) {
    const sourceFile = files.source[0];
    const targetFile = path.join(appDir, 'source.json');
    // 备份和移动文件
    uploadedFiles.push({ 
        type: 'source', 
        filename: 'source.json', 
        originalName: sourceFile.originalname 
    });
}

// 处理可用值文件
if (files.available && files.available[0]) {
    const availableFile = files.available[0];
    const targetFile = path.join(appDir, 'available.keys');
    // 备份和移动文件
    uploadedFiles.push({ 
        type: 'available', 
        filename: 'available.keys', 
        originalName: availableFile.originalname 
    });
}
```

## 🎨 用户界面

### 1. 文件选择区域
```
选择要上传的文件（可多选）

[选择翻译文件(.json)]     [✓]
[选择源文文件(source.json)]     [✓]
[选择可用值文件(available.keys)]     [✓]
```

### 2. 上传按钮状态
- 至少选择一个文件才能启用上传按钮
- 上传过程中显示加载状态
- 成功后重置所有文件选择状态

### 3. 使用说明
```
1. 选择要上传的文件（可多选）：
   • 翻译文件：目标语言的翻译内容
   • 源文文件：原始文本内容(source.json)
   • 可用值文件：可用的键值对(available.keys)
2. 选择对应的App（从服务器配置获取）
3. 选择翻译语言（从服务器配置获取）
4. 点击"上传到服务器"完成上传
5. 可以查看和管理已上传的翻译文件
```

## 📁 文件存储结构

### 目录结构
```
translations/
├── myStar/
│   ├── en_US.json          # 翻译文件
│   ├── source.json         # 源文文件
│   ├── available.keys      # 可用值文件
│   └── backups/            # 备份目录
│       ├── en_US_backup_2024-01-01T00-00-00-000Z.json
│       ├── source_backup_2024-01-01T00-00-00-000Z.json
│       └── available_backup_2024-01-01T00-00-00-000Z.keys
└── PicsAi/
    ├── en_US.json
    ├── source.json
    ├── available.keys
    └── backups/
```

### 文件命名规则
- **翻译文件**: 根据语言配置确定（如 en_US.json）
- **源文文件**: 固定为 source.json
- **可用值文件**: 固定为 available.keys
- **备份文件**: 原文件名_backup_时间戳.扩展名

## 🔄 上传流程

### 1. 前端流程
```
1. 用户选择文件（可多选）
2. 选择App和语言
3. 点击上传按钮
4. 构建FormData（包含所有选择的文件）
5. 发送HTTP请求
6. 处理响应结果
7. 重置选择状态
```

### 2. 后端流程
```
1. 接收multipart请求
2. 验证App和语言参数
3. 检查至少有一个文件
4. 创建目标目录
5. 处理每种文件类型：
   - 备份现有文件
   - 移动临时文件到目标位置
6. 清理临时文件
7. 返回成功响应
```

## ⚠️ 注意事项

### 1. 文件类型限制
- 所有文件必须是.json格式
- 文件大小限制：600MB
- 文件类型验证在前端和后端都进行

### 2. 备份机制
- 每个文件类型独立备份
- 备份文件包含时间戳
- 备份目录自动创建

### 3. 错误处理
- 网络错误处理
- 文件上传失败处理
- 服务器错误处理
- 临时文件清理

## 🚀 未来优化

### 1. 功能增强
- 支持拖拽上传
- 文件预览功能
- 批量文件管理
- 文件版本控制

### 2. 性能优化
- 大文件分块上传
- 上传进度显示
- 并发上传支持
- 断点续传

### 3. 用户体验
- 更直观的文件选择界面
- 实时上传状态显示
- 文件上传历史记录
- 智能文件类型识别

## 📊 对比总结

| 方面 | 单文件上传 | 多文件上传 |
|------|------------|------------|
| 文件数量 | 1个 | 最多3个 |
| 文件类型 | 翻译文件 | 翻译+源文+可用值 |
| 上传效率 | 低 | 高 |
| 用户体验 | 基础 | 优秀 |
| 服务器处理 | 简单 | 复杂 |
| 备份机制 | 单一 | 分类备份 |

## 🔍 调试建议

### 1. 前端调试
- 检查文件选择状态
- 验证FormData构建
- 监控HTTP请求
- 查看响应数据

### 2. 后端调试
- 检查multer配置
- 验证文件处理逻辑
- 监控备份操作
- 查看服务器日志

### 3. 文件系统调试
- 检查目录权限
- 验证文件移动操作
- 监控磁盘空间
- 查看备份文件
