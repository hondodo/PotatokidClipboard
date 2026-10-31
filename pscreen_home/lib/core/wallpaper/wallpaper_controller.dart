import 'package:flutter/foundation.dart';
import 'package:pscreen_home/core/storage/settings_store.dart';

/// 屏保壁纸配置控制器。
///
/// 只负责「开关 / API 地址 / 刷新间隔」的即时状态与持久化；
/// 计时器和当前图片地址由时钟页持有：离开屏保即停止请求。
class WallpaperController extends ChangeNotifier {
  WallpaperController(this._store)
    : _enabled = _store.wallpaperEnabled,
      _apiUrl = _store.wallpaperApiUrl,
      _minutes = _store.wallpaperMinutes;

  final SettingsStore _store;
  bool _enabled;
  String _apiUrl;
  int _minutes;
  int _nonce = 0;

  /// 是否显示屏保壁纸。
  bool get enabled => _enabled;

  /// 当前壁纸 API 地址。
  String get apiUrl => _apiUrl;

  /// 自动换图间隔（分钟）。
  int get minutes => _minutes;

  /// 更新开关并持久化。
  Future<void> setEnabled(bool enabled) async {
    if (enabled == _enabled) return;
    _enabled = enabled;
    notifyListeners();
    await _store.saveWallpaperEnabled(enabled);
  }

  /// 更新 API 地址；空白输入回落默认风景接口。
  Future<void> setApiUrl(String url) async {
    final String next = url.trim().isEmpty
        ? SettingsStore.defaultWallpaperApiUrl
        : url.trim();
    if (next == _apiUrl) return;
    _apiUrl = next;
    notifyListeners();
    await _store.saveWallpaperApiUrl(next);
  }

  /// 更新自动换图间隔；非法值忽略。
  Future<void> setMinutes(int minutes) async {
    if (!SettingsStore.wallpaperMinuteOptions.contains(minutes) ||
        minutes == _minutes) {
      return;
    }
    _minutes = minutes;
    notifyListeners();
    await _store.saveWallpaperMinutes(minutes);
  }

  /// 生成一张新的壁纸请求地址。
  ///
  /// 追加 `_t` 查询参数，避免 Flutter 按 URL 缓存图片：同一个 302
  /// 接口每次都会跳转到不同图片，不换 URL 会一直显示第一张。
  String nextImageUrl() {
    final Uri? parsed = Uri.tryParse(_apiUrl);
    final Uri base =
        parsed != null && (parsed.isScheme('http') || parsed.isScheme('https'))
        ? parsed
        : Uri.parse(SettingsStore.defaultWallpaperApiUrl);
    final String nonce = '${DateTime.now().microsecondsSinceEpoch}-${++_nonce}';
    return base
        .replace(
          queryParameters: <String, String>{
            ...base.queryParameters,
            '_t': nonce,
          },
        )
        .toString();
  }
}
