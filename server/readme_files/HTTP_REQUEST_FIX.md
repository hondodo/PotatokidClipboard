# HTTP请求修复说明

## 🐛 问题描述

在翻译文件上传时出现以下错误：
```
上传失败: Invalid argument(s): Invalid request body "Instance of 'minified:lD'.
```

## 🔍 问题分析

### 错误原因
1. **请求体格式不兼容**: `http.post()` 不能直接处理 `html.FormData`
2. **数据类型错误**: `html.FormData` 对象无法被 `http` 包正确序列化
3. **Content-Type不匹配**: 自动设置的Content-Type与实际数据格式不符

### 技术细节
```dart
// 问题代码
final formData = html.FormData();
formData.appendBlob('file', _selectedFile!);
formData.append('app', _selectedApp!);
formData.append('language', _selectedLanguage!);

// ❌ 错误：http.post 无法处理 html.FormData
final response = await http.post(
  Uri.parse('${Apis.baseUrl}/upload_translation'),
  body: formData,  // 这里会出错
);
```

## 🔧 修复方案

### 1. 使用原生HTTP请求
**修改前**:
```dart
// 使用 http 包发送请求
final response = await http.post(
  Uri.parse('${Apis.baseUrl}/upload_translation'),
  body: formData,  // ❌ 不兼容
);
```

**修改后**:
```dart
// 使用 html.HttpRequest 发送请求
final request = html.HttpRequest();
request.open('POST', '${Apis.baseUrl}/upload_translation');
request.send(formData);  // ✅ 兼容
```

### 2. 事件监听处理
```dart
// 监听上传完成
request.onLoad.listen((event) {
  if (request.status == 200) {
    // 处理成功响应
  } else {
    // 处理错误响应
  }
});

// 监听上传错误
request.onError.listen((event) {
  // 处理网络错误
});
```

## 📋 修复内容

### 1. 请求方式变更
- **从**: `http.post()` + `html.FormData`
- **到**: `html.HttpRequest` + `html.FormData`

### 2. 响应处理变更
- **从**: 同步等待响应
- **到**: 异步事件监听

### 3. 错误处理优化
- 添加网络错误监听
- 改进错误信息显示
- 确保状态正确重置

## ✅ 修复效果

### 修复前的问题
- ❌ `Invalid request body` 错误
- ❌ 请求体格式不兼容
- ❌ 上传失败无明确错误信息

### 修复后的效果
- ✅ 正确发送multipart/form-data请求
- ✅ 兼容文件上传格式
- ✅ 清晰的错误处理和状态管理

## 🛠️ 技术实现

### 完整的修复代码
```dart
Future<void> _uploadFile() async {
  if (_selectedFile == null || _selectedApp == null || _selectedLanguage == null) {
    _showError('请选择文件、App和语言');
    return;
  }

  setState(() {
    _isUploading = true;
  });

  try {
    // 创建FormData
    final formData = html.FormData();
    formData.appendBlob('file', _selectedFile!);
    formData.append('app', _selectedApp!);
    formData.append('language', _selectedLanguage!);

    // 创建HTTP请求
    final request = html.HttpRequest();
    request.open('POST', '${Apis.baseUrl}/upload_translation');
    
    // 监听上传完成
    request.onLoad.listen((event) {
      if (request.status == 200) {
        _showSuccess('翻译文件上传成功');
        _loadUploadedFiles();
        setState(() {
          _selectedFileName = null;
          _selectedFile = null;
          _selectedApp = null;
          _selectedLanguage = null;
        });
      } else {
        _showError('上传失败: ${request.responseText}');
      }
      setState(() {
        _isUploading = false;
      });
    });

    // 监听上传错误
    request.onError.listen((event) {
      _showError('上传失败: 网络错误');
      setState(() {
        _isUploading = false;
      });
    });

    // 发送请求
    request.send(formData);

  } catch (e) {
    _showError('上传失败: $e');
    setState(() {
      _isUploading = false;
    });
  }
}
```

## 🔄 请求流程

### 新的上传流程
```
1. 验证输入参数
2. 设置上传状态
3. 创建FormData对象
4. 创建HttpRequest对象
5. 设置事件监听器
6. 发送请求
7. 处理响应/错误
8. 重置状态
```

### 事件处理
- **onLoad**: 请求完成（成功或失败）
- **onError**: 网络错误
- **状态管理**: 确保UI状态正确更新

## ⚠️ 注意事项

### 1. 兼容性考虑
- `html.HttpRequest` 是Web专用API
- 不适用于移动端应用
- 需要确保在Web环境下使用

### 2. 错误处理
- 网络错误和HTTP错误分别处理
- 确保状态正确重置
- 提供用户友好的错误信息

### 3. 性能考虑
- 大文件上传可能需要进度显示
- 考虑添加上传超时处理
- 内存使用优化

## 🚀 未来优化

### 1. 上传进度
```dart
// 添加上传进度监听
request.upload.onProgress.listen((event) {
  final progress = event.loaded / event.total;
  // 更新进度条
});
```

### 2. 超时处理
```dart
// 添加超时处理
Timer.periodic(Duration(seconds: 30), (timer) {
  if (_isUploading) {
    request.abort();
    _showError('上传超时');
  }
});
```

### 3. 断点续传
- 支持大文件分块上传
- 实现断点续传功能
- 优化用户体验

## 📊 对比总结

| 方面 | 修复前 | 修复后 |
|------|--------|--------|
| 请求方式 | `http.post()` | `html.HttpRequest` |
| 数据格式 | 不兼容 | 完全兼容 |
| 错误处理 | 基础 | 完善 |
| 状态管理 | 简单 | 健壮 |
| 用户体验 | 差 | 好 |
