// ignore_for_file: library_prefixes

import 'dart:io';

import "package:path/path.dart" as Path;
import 'package:potatokid_clipboard/framework/utils/app_log.dart';

class FilePath {
  FilePath(String path)
      : _path = path; //, _file = File(path), _dir = Directory(path);
  final String _path;
  // final File _file;
  // final Directory _dir;

  String get name => Path.basename(_path);
  String get baseName => Path.basenameWithoutExtension(_path);
  String get extension => Path.extension(_path);
  // String get absolute => Path.dirname(_dir.absolute.path);
  String get path => _path;
  bool get isFile => File(_path).existsSync();
  bool get isDir => Directory(_path).existsSync();
  String get dir => extension.isNotEmpty ? Path.dirname(_path) : _path;
  String filePath(String filename) => Path.join(dir, filename);
  void makeDir() {
    createDir(dir);
  }

  // 去重
  FilePath unique() {
    FilePath result = this;
    int index = 1;
    while (result.isFile) {
      result = FilePath.join(result.dir, '$baseName($index)$extension');
      index++;
    }
    return result;
  }

  void remove() {
    if (isFile) {
      File(_path).deleteSync();
    } else if (isDir) {
      Directory(_path).deleteSync(recursive: true);
    }
  }

  static void renameFile(String src, String dst) {
    File(src).renameSync(dst);
    // Log.d("rename $src to $dst");
  }

  static void createDir(String path) {
    try {
      if (!Directory(path).existsSync()) {
        Directory(path).createSync(recursive: true);
      }
    } catch (e) {
      Log.e("create directory error: $e");
    }
  }

  FilePath.join(String part1,
      [String? part2,
      String? part3,
      String? part4,
      String? part5,
      String? part6,
      String? part7,
      String? part8,
      String? part9,
      String? part10,
      String? part11,
      String? part12,
      String? part13,
      String? part14,
      String? part15,
      String? part16])
      : _path = (Path.join(
            part1,
            part2,
            part3,
            part4,
            part5,
            part6,
            part7,
            part8,
            part9,
            part10,
            part11,
            part12,
            part13,
            part14,
            part15,
            part16));

  @override
  String toString() => _path;
}
