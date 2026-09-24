class FileSizeUtils {
  static String formatSize(int size) {
    if (size < 1024) {
      return '$size B';
    }
    if (size < 1024 * 1024) {
      return '${(size / 1024).toStringAsFixed(2)} KB';
    }
    return '${(size / 1024 / 1024).toStringAsFixed(2)} MB';
  }
}
