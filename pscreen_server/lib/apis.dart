// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:html' as html;

import 'package:flutter/foundation.dart';

class Apis {
  // 动态获取当前域名和端口
  static String get baseUrl {
    final location = html.window.location;
    if (kDebugMode) {
      return 'http://localhost:3000';
    } else {
      return '${location.protocol}//${location.host}';
    }
    // return 'http://localhost:3000'; // 调试，暂时写死 //'${location.protocol}//${location.host}';
  }

  // API端点
  static String get upload => '$baseUrl/api/upload';
  static String get files => '$baseUrl/api/files';
  static String get deleteFile => '$baseUrl/api/files';
  static String get login => '$baseUrl/api/login';
  static String get register => '$baseUrl/api/register';
  static String get recordTranslationSelection =>
      '$baseUrl/api/record_translation_selection';

  // 文件管理API
  static String get download => '$baseUrl/api/download';
  static String downloadFile(String filename) =>
      '$baseUrl/api/download/$filename';
  static String deleteFileEndpoint(String filename) =>
      '$baseUrl/api/files/$filename';

  // 笔记管理API
  static String get notes => '$baseUrl/api/notes';
  static String deleteNote(String noteId) => '$baseUrl/api/notes/$noteId';

  // 翻译管理API
  static String get translationConfig => '$baseUrl/api/translation_config';
  static String get uploadTranslation => '$baseUrl/api/upload_translation';
  static String get translationFiles => '$baseUrl/api/translation_files';
  static String translationFilesForApp(String app) =>
      '$baseUrl/api/translation_files/$app';
  static String deleteTranslationFile(String app, String filename) =>
      '$baseUrl/api/translation_files/$app/$filename';
  static String downloadTranslationFile(String app, String filename) =>
      '$baseUrl/api/download_translation/$app/$filename';
  static String translationBackups(String app, String filename) =>
      '$baseUrl/api/translation_backups/$app/$filename';
  static String downloadBackupFile(String app, String filename) =>
      '$baseUrl/api/download_backup/$app/$filename';
  static String get backupTranslation => '$baseUrl/api/backup_translation';
  static String get saveTranslation => '$baseUrl/api/save_translation';

  // 其他API
  static String get getIpInfoUrl => '$baseUrl/api/ipinfo';

  // 调试信息
  static String get debugInfo => '当前API地址: $baseUrl';
}
