import 'package:connectivity_plus/connectivity_plus.dart';

class NetworkHelper {
  static Future<bool> isNetworkDisconnected() async {
    final List<ConnectivityResult> connectivityResult =
        await (Connectivity().checkConnectivity());
    return connectivityResult.contains(ConnectivityResult.none);
  }
}
