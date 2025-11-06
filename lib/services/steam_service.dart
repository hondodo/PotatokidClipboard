import 'dart:async';

import 'package:get/get.dart';
import 'package:potatokid_clipboard/app/app_enums.dart';

class SteamService extends GetxService {
  StreamController<AppPage> homePageStreamController =
      StreamController<AppPage>.broadcast();
}

extension StreamServiceGetterStreamMixin on SteamService {
  Stream<AppPage> get homePageStream => homePageStreamController.stream;
}
