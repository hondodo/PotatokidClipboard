# 翻译配置管理

## 📋 配置文件说明

翻译功能的App和语言配置通过 `server/translation-config.json` 文件管理。

## 🔧 配置文件格式

```json
{
  "apps": [
    {
      "appName": "myStar",
      "languages": [
        { "lanName": "英文", "lanFile": "en_US.json" },
        { "lanName": "日文", "lanFile": "ja_JP.json" },
        { "lanName": "中文", "lanFile": "zh_CN.json" }
      ]
    },
    {
      "appName": "PicsAi",
      "languages": [
        { "lanName": "英文", "lanFile": "en_US.json" },
        { "lanName": "日文", "lanFile": "ja_JP.json" },
        { "lanName": "中文", "lanFile": "zh_CN.json" }
      ]
    }
  ]
}
```

## 📝 配置字段说明

### apps 数组
- **appName**: App名称，用于显示和文件分类
- **languages**: 该App支持的语言列表

### languages 数组
- **lanName**: 语言显示名称（如"英文"、"日文"、"中文"）
- **lanFile**: 语言文件名称（如"en_US.json"、"ja_JP.json"、"zh_CN.json"）

## 🚀 如何修改配置

### 1. 添加新的App
```json
{
  "appName": "新App名称",
  "languages": [
    { "lanName": "英文", "lanFile": "en_US.json" },
    { "lanName": "中文", "lanFile": "zh_CN.json" }
  ]
}
```

### 2. 为现有App添加语言
在对应App的languages数组中添加新的语言项：
```json
{ "lanName": "法文", "lanFile": "fr_FR.json" }
```

### 3. 修改语言显示名称
修改对应语言的 `lanName` 字段：
```json
{ "lanName": "English", "lanFile": "en_US.json" }
```

## 🔄 配置更新流程

1. **修改配置文件**: 编辑 `server/translation-config.json`
2. **重启服务器**: 配置更改需要重启Node.js服务器
3. **验证配置**: 访问 `/translation_config` API端点验证配置

## 📡 API端点

### GET /translation_config
获取当前翻译配置

**响应示例**:
```json
{
  "apps": [
    {
      "appName": "myStar",
      "languages": [
        { "lanName": "英文", "lanFile": "en_US.json" },
        { "lanName": "日文", "lanFile": "ja_JP.json" },
        { "lanName": "中文", "lanFile": "zh_CN.json" }
      ]
    }
  ]
}
```

## 🛠️ 默认配置

如果配置文件不存在，服务器会使用以下默认配置：
- **myStar**: 英文、日文、中文
- **PicsAi**: 英文、日文、中文

## 📁 文件存储结构

翻译文件按以下结构存储：
```
translations/
├── myStar/
│   ├── filename_英文_timestamp.json
│   ├── filename_日文_timestamp.json
│   └── filename_中文_timestamp.json
└── PicsAi/
    ├── filename_英文_timestamp.json
    ├── filename_日文_timestamp.json
    └── filename_中文_timestamp.json
```

## ⚠️ 注意事项

1. **JSON格式**: 确保配置文件是有效的JSON格式
2. **重启服务器**: 配置更改后必须重启服务器
3. **备份配置**: 建议备份原始配置文件
4. **语言文件命名**: `lanFile` 字段用于文件命名，建议使用标准格式
5. **编码问题**: 确保配置文件使用UTF-8编码
