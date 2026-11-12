/// 桌面型号的纯字符串处理，不依赖任何平台 API，便于单测。
library;

/// 服务端 `setCommInfo` 对 model 字段的截断上限（admin.js 中为 64）。
const int kDeviceModelMaxLength = 64;

/// BIOS/DMI 里常见的占位值，视为「取不到型号」。
const List<String> _placeholderValues = <String>[
  'to be filled by o.e.m.',
  'to be filled by oem',
  'default string',
  'system product name',
  'system manufacturer',
  'system version',
  'not applicable',
  'not specified',
  'unknown',
  'none',
  'n/a',
  'o.e.m.',
];

/// 清洗单个 BIOS/DMI 值：去空白、过滤占位值；无效返回 null。
String? cleanDesktopModelValue(String? raw) {
  if (raw == null) return null;
  final String value = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (value.isEmpty) return null;
  final String lower = value.toLowerCase();
  if (_placeholderValues.contains(lower)) return null;
  if (lower.startsWith('to be filled')) return null;
  return value;
}

/// 把「厂商 / 产品名 / 系统名」拼成后台可读的一行型号。
///
/// 优先级：真实机型（产品名，必要时前缀厂商）> 操作系统名称 > [fallback]。
/// 产品名已包含厂商时不再重复拼接；结果统一截断到 [kDeviceModelMaxLength]。
String formatDesktopModel({
  String? manufacturer,
  String? product,
  String? osName,
  String fallback = '',
}) {
  final String? vendor = cleanDesktopModelValue(manufacturer);
  final String? model = cleanDesktopModelValue(product);

  String result = '';
  if (model != null) {
    final bool containsVendor =
        vendor != null && model.toLowerCase().contains(vendor.toLowerCase());
    result = (vendor != null && !containsVendor) ? '$vendor $model' : model;
  } else if (vendor != null) {
    result = vendor;
  }

  if (result.isEmpty) result = cleanDesktopModelValue(osName) ?? '';
  if (result.isEmpty) result = cleanDesktopModelValue(fallback) ?? '';
  if (result.length > kDeviceModelMaxLength) {
    result = result.substring(0, kDeviceModelMaxLength);
  }
  return result;
}
