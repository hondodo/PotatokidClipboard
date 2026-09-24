// import 'package:permission_handler/permission_handler.dart';

class PermissionManager {
  static final PermissionManager _instance = PermissionManager._();
  PermissionManager._();
  static PermissionManager get instance => _instance;
}
