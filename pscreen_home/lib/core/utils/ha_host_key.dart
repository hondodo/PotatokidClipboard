/// HA 地址归一化：本地缓存按服务器隔离时用于比较。
///
/// 同一台 HA 可能被写成 `http://host:8123` / `host:8123/` / `ws://host:8123`，
/// 归一化后再比较，避免仅因写法不同导致缓存失效。
String normalizeHaHost(String host) {
  String value = host.trim().toLowerCase();
  if (value.startsWith('http://')) {
    value = value.substring('http://'.length);
  } else if (value.startsWith('https://')) {
    value = value.substring('https://'.length);
  } else if (value.startsWith('ws://')) {
    value = value.substring('ws://'.length);
  } else if (value.startsWith('wss://')) {
    value = value.substring('wss://'.length);
  }
  while (value.endsWith('/')) {
    value = value.substring(0, value.length - 1);
  }
  return value;
}
