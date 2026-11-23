/// 卡片标题：选中房间时只显示设备名，显示全部房间时前置房间名。
String cardTitle({
  required String title,
  required String? areaLabel,
  required bool showArea,
}) {
  if (!showArea) return title;
  final String area =
      areaLabel == null || areaLabel.isEmpty ? '未分配房间' : areaLabel;
  return '$area $title';
}
