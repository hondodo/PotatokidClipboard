import 'package:crypto/crypto.dart';
import 'dart:convert';

extension StringUtils on String {
  String get toMd5 {
    return md5.convert(utf8.encode(this)).toString();
  }
}
