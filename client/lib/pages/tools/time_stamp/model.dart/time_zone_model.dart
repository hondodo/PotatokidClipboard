class TimeZoneModel {
  final String name;
  final int offsetHours;
  final int offsetMinutes;

  String get offsetText {
    String text = '';
    if (offsetMinutes > 0) {
      text = '$offsetHours:${offsetMinutes.toString().padLeft(2, '0')}';
    } else {
      text = '$offsetHours';
    }
    if (text.startsWith('-') || text.startsWith('+')) {
      return 'UTC$text';
    }
    return 'UTC+$text';
  }

  TimeZoneModel(
      {required this.name,
      required this.offsetHours,
      required this.offsetMinutes});
}
