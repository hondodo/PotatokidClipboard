# 文件类型验证修复说明

## 🐛 问题描述

在翻译上传页面中，选择可用值文件时出现以下问题：
- 用户选择`.keys`文件时，系统提示"请选择.json文件"
- 文件类型验证不正确，导致可用值文件无法正常选择

## 🔍 问题分析

### 错误原因
1. **前端文件类型验证错误**: 可用值文件选择方法中设置了`.json`文件类型验证
2. **服务器端文件过滤器限制**: 服务器端只允许`.json`文件，不支持`.keys`文件
3. **文件类型不匹配**: 可用值文件应该是`.keys`格式，但验证逻辑错误

### 技术细节
```dart
// 问题代码
Future<void> _selectAvailableFile() async {
  final input = html.FileUploadInputElement();
  input.accept = '.json';  // ❌ 错误：应该是 .keys
  // ...
  if (file.name.toLowerCase().endsWith('.json')) {  // ❌ 错误：应该是 .keys
    // ...
  } else {
    _showError('请选择.json文件');  // ❌ 错误：应该是 .keys
  }
}
```

## 🔧 修复方案

### 1. 前端修复

**修改前**:
```dart
// 选择可用值文件
Future<void> _selectAvailableFile() async {
  final input = html.FileUploadInputElement();
  input.accept = '.json';  // ❌ 错误
  // ...
  if (file.name.toLowerCase().endsWith('.json')) {  // ❌ 错误
    // ...
  } else {
    _showError('请选择.json文件');  // ❌ 错误
  }
}
```

**修改后**:
```dart
// 选择可用值文件
Future<void> _selectAvailableFile() async {
  final input = html.FileUploadInputElement();
  input.accept = '.keys';  // ✅ 正确
  // ...
  if (file.name.toLowerCase().endsWith('.keys')) {  // ✅ 正确
    // ...
  } else {
    _showError('请选择.keys文件');  // ✅ 正确
  }
}
```

### 2. 后端修复

**修改前**:
```javascript
fileFilter: function (req, file, cb) {
    // 只允许.json文件
    if (file.mimetype === 'application/json' || file.originalname.toLowerCase().endsWith('.json')) {
        cb(null, true);
    } else {
        cb(new Error('只允许上传.json文件'), false);
    }
}
```

**修改后**:
```javascript
fileFilter: function (req, file, cb) {
    // 允许.json和.keys文件
    const fileName = file.originalname.toLowerCase();
    if (file.mimetype === 'application/json' || 
        fileName.endsWith('.json') || 
        fileName.endsWith('.keys')) {
        cb(null, true);
    } else {
        cb(new Error('只允许上传.json或.keys文件'), false);
    }
}
```

## 📋 修复内容

### 1. 前端文件类型验证
- **文件选择器**: 修改`input.accept`从`.json`改为`.keys`
- **文件扩展名验证**: 修改验证逻辑从`.json`改为`.keys`
- **错误提示**: 修改错误信息从"请选择.json文件"改为"请选择.keys文件"

### 2. 后端文件过滤器
- **支持文件类型**: 添加对`.keys`文件的支持
- **MIME类型检查**: 保持对`application/json`的支持
- **扩展名检查**: 同时检查`.json`和`.keys`扩展名
- **错误信息**: 更新错误信息为"只允许上传.json或.keys文件"

## ✅ 修复效果

### 修复前的问题
- ❌ 可用值文件选择失败
- ❌ 文件类型验证错误
- ❌ 用户无法上传`.keys`文件
- ❌ 错误提示信息不准确

### 修复后的效果
- ✅ 可用值文件选择正常
- ✅ 支持`.keys`文件上传
- ✅ 文件类型验证正确
- ✅ 错误提示信息准确

## 🎯 文件类型支持

### 支持的文件类型
| 文件类型 | 扩展名 | MIME类型 | 用途 |
|---------|--------|----------|------|
| 翻译文件 | .json | application/json | 目标语言翻译内容 |
| 源文文件 | .json | application/json | 原始文本内容 |
| 可用值文件 | .keys | text/plain | 可用的键值对 |

### 文件验证逻辑
```javascript
// 服务器端验证
const fileName = file.originalname.toLowerCase();
if (file.mimetype === 'application/json' || 
    fileName.endsWith('.json') || 
    fileName.endsWith('.keys')) {
    // 允许上传
} else {
    // 拒绝上传
}
```

## 🔄 上传流程

### 新的文件选择流程
```
1. 用户点击"选择可用值文件"按钮
2. 文件选择器只显示.keys文件
3. 用户选择.keys文件
4. 前端验证文件扩展名
5. 如果验证通过，显示文件选择状态
6. 上传时服务器端再次验证
7. 验证通过后处理文件上传
```

### 错误处理
- **前端验证失败**: 显示"请选择.keys文件"
- **服务器验证失败**: 返回"只允许上传.json或.keys文件"
- **文件类型不匹配**: 提供清晰的错误信息

## ⚠️ 注意事项

### 1. 文件格式要求
- **翻译文件**: 必须是有效的JSON格式
- **源文文件**: 必须是有效的JSON格式
- **可用值文件**: 可以是任意文本格式（.keys）

### 2. 文件大小限制
- 所有文件类型都遵循相同的600MB大小限制
- 服务器端统一处理文件大小验证

### 3. 兼容性考虑
- 保持对现有JSON文件的支持
- 新增对.keys文件的支持
- 不影响其他文件类型的处理

## 🚀 未来优化

### 1. 文件类型检测
- 自动检测文件内容格式
- 提供更智能的文件类型识别
- 支持更多文件格式

### 2. 用户体验优化
- 文件拖拽上传
- 文件预览功能
- 批量文件处理

### 3. 错误处理增强
- 更详细的错误信息
- 文件格式验证提示
- 上传进度显示

## 📊 对比总结

| 方面 | 修复前 | 修复后 |
|------|--------|--------|
| 文件类型支持 | 仅.json | .json + .keys |
| 验证逻辑 | 错误 | 正确 |
| 错误提示 | 不准确 | 准确 |
| 用户体验 | 差 | 好 |
| 功能完整性 | 不完整 | 完整 |

## 🔍 测试建议

### 1. 前端测试
- 测试.keys文件选择
- 验证文件类型过滤
- 检查错误提示信息

### 2. 后端测试
- 测试.keys文件上传
- 验证文件过滤器
- 检查错误响应

### 3. 集成测试
- 完整的上传流程测试
- 多文件类型混合上传
- 错误场景处理测试
