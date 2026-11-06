import 'package:pscreen_screen/app/config/app_constants.dart';
import 'package:pscreen_screen/core/network/dio_manager.dart';
import 'package:pscreen_screen/core/network/http_method.dart';
import 'package:pscreen_screen/core/utils/ptools_util.dart';

/// 账号资料（展示名）自助接口。
///
/// 只改服务端 `_info.txt` 的 `displayName`，账号 id / 目录 / 绑定关系不变；
/// 鉴权沿用 ptools 登录 cookie，故调用前先确保已登录。
class AccountProfileApi {
  const AccountProfileApi._();

  /// 保存展示名；空串 = 清除（各端回落显示账号 id）。失败返回 false。
  static Future<bool> updateDisplayName(String displayName) async {
    if (!await PtoolsUtil.loginWithSaved()) return false;
    try {
      final dynamic data = await DioManager().send(
        url: AppConstants.ptoolsDisplayNameUrl,
        method: HttpMethod.POST,
        params: <String, dynamic>{'displayName': displayName.trim()},
        contentType: 'application/json',
        notTipNetError: true,
      );
      final Map<String, dynamic>? map = _asMap(data);
      if (map == null) return false;
      final dynamic code = map['code'];
      final int? value = code is int ? code : int.tryParse('$code');
      return value == PtoolsCode.success;
    } catch (_) {
      return false;
    }
  }

  static Map<String, dynamic>? _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return null;
  }
}
