# 翻译修改页面语言选择功能更新

## 🎯 更新概述

为翻译修改页面添加了语言选择功能，用户现在可以选择要编辑的具体翻译文件（如en_US.json、zh_CN.json等），而不是同时编辑所有语言文件。

## 📋 新增功能

### 1. 语言选择下拉框
- **位置**: 在App选择后显示
- **功能**: 选择要编辑的具体翻译文件
- **显示格式**: "语言名称 (文件名)"，如"英文 (en_US.json)"
- **数据源**: 从translation-config.json中获取

### 2. 单语言编辑模式
- **编辑范围**: 只编辑选中的语言文件
- **表格显示**: 三列布局（翻译键、源文值、翻译值）
- **输入框**: 只显示选中语言的翻译输入框

### 3. 数据结构适配
- **source.json**: 处理嵌套的`{"source": {...}}`结构
- **翻译文件**: 处理嵌套的`{"en_US": {...}}`结构
- **available.keys**: 保持原有的数组格式

## 🔧 技术实现

### 1. 状态变量更新
```dart
// 新增状态变量
String? _selectedLanguage;
List<Map<String, dynamic>> _availableLanguages = [];
```

### 2. 语言加载逻辑
```dart
// 加载App对应的语言列表
Future<void> _loadLanguagesForApp(String appName) async {
  final selectedApp = _availableApps.firstWhere(
    (app) => app['appName'] == appName,
    orElse: () => {},
  );
  
  if (selectedApp.containsKey('languages')) {
    setState(() {
      _availableLanguages = List<Map<String, dynamic>>.from(selectedApp['languages']);
    });
  }
}
```

### 3. 翻译数据加载
```dart
// 只加载选中的翻译文件
final response = await http.get(
  Uri.parse('${Apis.baseUrl}/download_translation/$_selectedApp/$_selectedLanguage'),
);

if (response.statusCode == 200) {
  final translationJson = json.decode(response.body);
  // 处理嵌套的语言结构
  _translationData[_selectedLanguage!] = translationJson[_selectedLanguage!] ?? translationJson;
}
```

### 4. 数据结构处理
```dart
// source.json处理
final sourceJson = json.decode(sourceResponse.body);
_sourceData = sourceJson['source'] ?? sourceJson;

// 翻译文件处理
final translationJson = json.decode(response.body);
_translationData[_selectedLanguage!] = translationJson[_selectedLanguage!] ?? translationJson;
```

### 5. 单语言输入框
```dart
Widget _buildTranslationInputs(TranslationItem item) {
  if (_selectedLanguage == null) {
    return Text('请先选择语言');
  }

  if (!item.translations.containsKey(_selectedLanguage)) {
    return Text('无翻译内容');
  }

  final controllerKey = '${item.key}_$_selectedLanguage';
  final controller = _controllers[controllerKey];

  return TextField(
    controller: controller,
    onChanged: (value) {
      item.translations[_selectedLanguage!] = value;
    },
  );
}
```

## 🎨 用户界面

### 1. 选择流程
```
选择App → 选择语言 → 编辑翻译 → 保存
```

### 2. 界面布局
```
┌─────────────────────────────────────────┐
│ 📱 选择App                              │
│ [App下拉框]                             │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│ 🌐 选择语言                              │
│ [语言下拉框]                             │
└─────────────────────────────────────────┘

┌─────────────────────────────────────────┐
│ ✏️ 翻译编辑表格                          │
│ ┌─────────┬─────────┬─────────────────┐ │
│ │ 翻译键  │ 源文值  │ 翻译值(en_US)   │ │
│ ├─────────┼─────────┼─────────────────┤ │
│ │ key1    │ value1  │ [输入框]        │ │
│ │ key2    │ value2  │ [输入框]        │ │
│ └─────────┴─────────┴─────────────────┘ │
└─────────────────────────────────────────┘
```

### 3. 条件显示
- **语言选择**: 只有在选择了App后才显示
- **翻译编辑**: 只有在选择了App和语言后才显示
- **保存按钮**: 只有在选择了App和语言后才显示

## 📊 数据结构支持

### 1. source.json格式
```json
{
  "source": {
    "com::not_defined": "未定义",
    "com::error": "出错了",
    "com::retry": "重试"
  }
}
```

### 2. 翻译文件格式
```json
{
  "en_US": {
    "com::not_defined": "Undefined",
    "com::error": "Something went wrong",
    "com::retry": "Retry"
  }
}
```

### 3. available.keys格式
```json
[
  "type::unknown",
  "type::mobile",
  "type::google"
]
```

## 🔄 工作流程

### 1. 用户操作流程
1. 选择要编辑的App
2. 选择要编辑的语言文件
3. 系统加载source.json和选中的翻译文件
4. 显示翻译编辑表格
5. 用户编辑翻译内容
6. 点击保存按钮
7. 系统备份原文件并保存新内容

### 2. 数据加载流程
```
选择App → 加载语言列表 → 选择语言 → 加载翻译数据 → 显示编辑界面
```

### 3. 保存流程
```
收集编辑数据 → 备份原文件 → 保存新文件 → 显示成功消息
```

## ⚡ 性能优化

### 1. 按需加载
- 只加载选中的翻译文件
- 避免加载所有语言文件
- 减少网络请求和内存使用

### 2. 状态管理
- 选择App时清空语言选择
- 选择语言时清空翻译数据
- 避免数据混乱和错误

### 3. 错误处理
- 文件不存在时显示友好提示
- 网络错误时显示错误信息
- 保存失败时显示具体错误

## 🎯 用户体验

### 1. 操作简化
- 两步选择：App → 语言
- 单语言编辑，避免混乱
- 清晰的界面提示

### 2. 数据安全
- 自动备份原文件
- 保存前确认操作
- 错误时不影响原数据

### 3. 反馈及时
- 加载状态显示
- 操作结果提示
- 错误信息明确

## 🔍 测试建议

### 1. 功能测试
- 测试App选择功能
- 测试语言选择功能
- 测试翻译编辑功能
- 测试保存功能

### 2. 数据测试
- 测试不同格式的JSON文件
- 测试嵌套结构处理
- 测试文件不存在的情况

### 3. 界面测试
- 测试条件显示逻辑
- 测试响应式布局
- 测试用户交互流程

## 📈 对比总结

| 方面 | 更新前 | 更新后 |
|------|--------|--------|
| 编辑模式 | 多语言同时编辑 | 单语言编辑 |
| 选择步骤 | 1步（App） | 2步（App + 语言） |
| 数据加载 | 加载所有翻译文件 | 只加载选中文件 |
| 界面复杂度 | 复杂（多列） | 简单（三列） |
| 用户体验 | 容易混乱 | 清晰明确 |

## 🚀 未来扩展

### 1. 功能增强
- 支持批量编辑
- 添加翻译历史
- 支持翻译对比

### 2. 界面优化
- 添加搜索功能
- 支持键盘快捷键
- 添加翻译进度显示

### 3. 数据处理
- 支持更多文件格式
- 添加数据验证
- 支持导入导出
