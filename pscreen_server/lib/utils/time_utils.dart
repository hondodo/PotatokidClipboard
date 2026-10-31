import 'package:intl/intl.dart';

class TimeUtils {
  /// 将ISO时间字符串转换为本地时间显示
  static String formatLocalTime(String? isoTime) {
    if (isoTime == null || isoTime.isEmpty) {
      return '未知时间';
    }

    try {
      final dateTime = DateTime.parse(isoTime);
      final localTime = dateTime.toLocal();
      final formatter = DateFormat('yyyy-MM-dd HH:mm:ss');
      return formatter.format(localTime);
    } catch (e) {
      return '时间格式错误';
    }
  }

  /// 将ISO时间字符串转换为本地时间显示（简短格式）
  static String formatLocalTimeShort(String? isoTime) {
    if (isoTime == null || isoTime.isEmpty) {
      return '未知';
    }

    try {
      final dateTime = DateTime.parse(isoTime);
      final localTime = dateTime.toLocal();
      final now = DateTime.now().toLocal();
      final difference = now.difference(localTime);

      // 如果是今天
      if (difference.inDays == 0) {
        final formatter = DateFormat('HH:mm:ss');
        return '今天 ${formatter.format(localTime)}';
      }
      // 如果是昨天
      else if (difference.inDays == 1) {
        final formatter = DateFormat('HH:mm:ss');
        return '昨天 ${formatter.format(localTime)}';
      }
      // 如果是本周
      else if (difference.inDays < 7) {
        final formatter = DateFormat('EEEE HH:mm');
        return formatter.format(localTime);
      }
      // 其他情况显示完整日期
      else {
        final formatter = DateFormat('MM-dd HH:mm');
        return formatter.format(localTime);
      }
    } catch (e) {
      return '时间错误';
    }
  }

  /// 将ISO时间字符串转换为相对时间显示
  static String formatRelativeTime(String? isoTime) {
    if (isoTime == null || isoTime.isEmpty) {
      return '未知时间';
    }

    try {
      final dateTime = DateTime.parse(isoTime);
      final localTime = dateTime.toLocal();
      final now = DateTime.now().toLocal();
      final difference = now.difference(localTime);

      if (difference.inSeconds < 60) {
        return '刚刚';
      } else if (difference.inMinutes < 60) {
        return '${difference.inMinutes}分钟前';
      } else if (difference.inHours < 24) {
        return '${difference.inHours}小时前';
      } else if (difference.inDays < 7) {
        return '${difference.inDays}天前';
      } else {
        final formatter = DateFormat('MM-dd');
        return formatter.format(localTime);
      }
    } catch (e) {
      return '时间错误';
    }
  }
}





