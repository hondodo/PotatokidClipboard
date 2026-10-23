/// 心知天气 V4 领域模型。
///
/// V4 返回外层容器为 `result`（部分版本为 `data`），字段键为 PascalCase
/// （如 `WeatherDaily`）。解析做防御式处理：兼容 result/data 容器与
/// Camel/Pascal/Snake 命名，避免不同数据产品结构差异导致崩溃。
library;

/// 天气数据聚合：实时 + 逐日预报。
class WeatherData {
  const WeatherData({this.now, this.daily = const <WeatherDay>[]});

  final WeatherNow? now;
  final List<WeatherDay> daily;

  bool get isEmpty => now == null && daily.isEmpty;
}

/// 实时天气。
class WeatherNow {
  const WeatherNow({
    this.temperature,
    this.skycon = '',
    this.text = '',
    this.humidity,
    this.windSpeed,
    this.city = '',
  });

  final double? temperature;
  final String skycon;
  final String text;
  final double? humidity;
  final double? windSpeed;
  final String city;
}

/// 单日预报。
class WeatherDay {
  const WeatherDay({
    this.date = '',
    this.skycon = '',
    this.text = '',
    this.tempMax,
    this.tempMin,
  });

  final String date;
  final String skycon;
  final String text;
  final double? tempMax;
  final double? tempMin;
}

/// 从 V4 整体响应中取指定字段的顶层对象（防御式容器/命名兼容）。
Map<String, dynamic>? extractField(Map<String, dynamic> root, String field) {
  final String camel = field.contains('_')
      ? field.split('_').map(_cap).join()
      : field[0].toLowerCase() + field.substring(1);
  final String pascal = _cap(field);
  final List<String> keys = <String>{field, camel, pascal}.toList();

  for (final String container in <String>['result', 'data', 'results', 'root']) {
    final Object? c = root[container];
    if (c is Map) {
      for (final String k in keys) {
        final Map<String, dynamic>? v = _asMap(c[k]);
        if (v != null) return v;
      }
    }
  }
  for (final String k in keys) {
    final Map<String, dynamic>? v = _asMap(root[k]);
    if (v != null) return v;
  }
  return null;
}

String _cap(String s) {
  if (s.isEmpty) return s;
  return s[0].toUpperCase() + s.substring(1);
}

/// 解析实时天气（网格 V4：`result.WeatherNow` 内为标量）。
WeatherNow? parseWeatherNow(Map<String, dynamic> root) {
  final Map<String, dynamic>? field = extractField(root, 'weather_now');
  if (field == null) return null;

  final Map<String, dynamic> now = _asMap(field['now']) ?? field;

  final num? temperature = _num(now['temperature'] ?? field['temperature']);
  final String skycon = _str(now['skycon'] ?? field['skycon']);
  final String text = _str(now['text'] ?? field['text']);
  final num? humidity = _num(now['humidity'] ?? field['humidity']);
  final Object? wind = now['wind'] ?? field['wind'];
  final num? windSpeed = _num(wind is Map ? wind['speed'] : now['wind_speed']);

  return WeatherNow(
    temperature: temperature?.toDouble(),
    skycon: skycon,
    text: text.isEmpty ? skyconToText(skycon) : text,
    humidity: humidity?.toDouble(),
    windSpeed: windSpeed?.toDouble(),
    city: _locationName(field),
  );
}

/// 解析逐日预报（网格 V4：`result.WeatherDaily.temperature[].min/max` + `skycon[].value`）。
List<WeatherDay> parseWeatherDaily(Map<String, dynamic> root) {
  final Map<String, dynamic>? field = extractField(root, 'weather_daily');
  if (field == null) return const <WeatherDay>[];

  final List<dynamic> temps = _asList(field['temperature']);
  final List<dynamic> skycons = _asList(field['skycon']);

  String skyconOf(String date) {
    for (final Object? item in skycons) {
      if (item is Map && _str(item['date']) == date) {
        return _str(item['value']);
      }
    }
    return '';
  }

  final List<WeatherDay> days = <WeatherDay>[];
  for (final Object? item in temps) {
    if (item is! Map) continue;
    final String date = _str(item['date']);
    final String skycon = skyconOf(date);
    days.add(WeatherDay(
      date: date,
      skycon: skycon,
      text: skyconToText(skycon),
      tempMax: _num(item['max'])?.toDouble(),
      tempMin: _num(item['min'])?.toDouble(),
    ));
  }
  return days;
}

String _locationName(Map<String, dynamic> f) {
  final Map<String, dynamic>? loc = _asMap(f['location']) ?? _asMap(f['Location']);
  return loc == null ? '' : _str(loc['name'] ?? loc['Name']);
}

/// 解析 V3 实时天气（`results[0].now`）。
WeatherNow? parseWeatherNowV3(Map<String, dynamic> root) {
  final List<dynamic> results = _asList(root['results']);
  if (results.isEmpty) return null;
  final Map<String, dynamic>? r = _asMap(results[0]);
  if (r == null) return null;

  final Map<String, dynamic> now = _asMap(r['now']) ?? const <String, dynamic>{};
  final String skycon = _str(now['code']);
  final String text = _str(now['text']);

  return WeatherNow(
    temperature: _num(now['temperature'])?.toDouble(),
    skycon: skycon,
    text: text.isEmpty ? skyconToTextV3(skycon) : text,
    humidity: _num(now['humidity'])?.toDouble(),
    city: _locationName(r),
  );
}

/// 解析 V3 逐日预报（`results[0].daily[]`）。
List<WeatherDay> parseWeatherDailyV3(Map<String, dynamic> root) {
  final List<dynamic> results = _asList(root['results']);
  if (results.isEmpty) return const <WeatherDay>[];
  final Map<String, dynamic>? r = _asMap(results[0]);
  if (r == null) return const <WeatherDay>[];

  final List<WeatherDay> days = <WeatherDay>[];
  for (final Object? item in _asList(r['daily'])) {
    final Map<String, dynamic>? d = _asMap(item);
    if (d == null) continue;
    final String skycon = _str(d['code_day']);
    final String textDay = _str(d['text_day']);
    days.add(WeatherDay(
      date: _str(d['date']),
      skycon: skycon,
      text: textDay.isNotEmpty ? textDay : skyconToTextV3(skycon),
      tempMax: _num(d['high'])?.toDouble(),
      tempMin: _num(d['low'])?.toDouble(),
    ));
  }
  return days;
}

num? _num(dynamic v) {
  if (v is num) return v;
  if (v is String) return double.tryParse(v);
  return null;
}

String _str(dynamic v) => v == null ? '' : v.toString();

Map<String, dynamic>? _asMap(dynamic v) {
  if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
  return null;
}

List<dynamic> _asList(dynamic v) => v is List ? v : const <dynamic>[];

/// 心知网格天气代码 → 中文。
String skyconToText(String code) {
  switch (code) {
    case 'CLEAR_DAY':
    case 'CLEAR_NIGHT':
      return '晴';
    case 'PARTLY_CLOUDY_DAY':
    case 'PARTLY_CLOUDY_NIGHT':
      return '多云';
    case 'CLOUDY':
      return '阴';
    case 'LIGHT_HAZE':
      return '轻度雾霾';
    case 'MODERATE_HAZE':
      return '中度雾霾';
    case 'HEAVY_HAZE':
      return '重度雾霾';
    case 'LIGHT_RAIN':
      return '小雨';
    case 'MODERATE_RAIN':
      return '中雨';
    case 'HEAVY_RAIN':
      return '大雨';
    case 'STORM_RAIN':
      return '暴雨';
    case 'FOG':
      return '雾';
    case 'LIGHT_SNOW':
      return '小雪';
    case 'MODERATE_SNOW':
      return '中雪';
    case 'HEAVY_SNOW':
      return '大雪';
    case 'SLEET':
      return '雨夹雪';
    case 'WIND':
    case 'GALE':
      return '大风';
    case 'HAIL':
      return '冰雹';
    case 'THUNDER_SHOWER':
      return '雷阵雨';
    case 'RAIN':
      return '雨';
    case 'SNOW':
      return '雪';
    case 'DUST':
      return '浮尘';
    case 'SAND':
      return '沙尘';
    default:
      return code;
  }
}

/// 心知 V3 数字天气代码 → 中文。
///
/// V3 的 `code` / `code_day` 为数字字符串（如 `4` 表示雷阵雨），
/// 与 V4 网格字符串码不同，需单独映射。
String skyconToTextV3(String code) {
  switch (code) {
    case '0':
      return '晴';
    case '1':
      return '多云';
    case '2':
      return '阴';
    case '3':
      return '阵雨';
    case '4':
      return '雷阵雨';
    case '5':
      return '冰雹';
    case '6':
      return '雨夹雪';
    case '7':
      return '小雨';
    case '8':
      return '中雨';
    case '9':
      return '大雨';
    case '10':
      return '暴雨';
    case '11':
      return '大暴雨';
    case '12':
      return '特大暴雨';
    case '13':
      return '阵雪';
    case '14':
      return '小雪';
    case '15':
      return '中雪';
    case '16':
      return '大雪';
    case '17':
      return '暴雪';
    case '18':
      return '雾';
    case '19':
      return '冻雨';
    case '20':
      return '沙尘暴';
    case '21':
      return '小到中雨';
    case '22':
      return '中到大雨';
    case '23':
      return '大到暴雨';
    case '24':
      return '暴雨到大暴雨';
    case '25':
      return '大暴雨到特大暴雨';
    case '26':
      return '小到中雪';
    case '27':
      return '中到大雪';
    case '28':
      return '大到暴雪';
    case '29':
      return '浮尘';
    case '30':
      return '扬沙';
    case '31':
      return '强沙尘暴';
    case '32':
      return '浓雾';
    case '33':
      return '强浓雾';
    case '34':
      return '霾';
    case '35':
      return '中度霾';
    case '36':
      return '重度霾';
    case '37':
      return '严重霾';
    case '38':
      return '大雾';
    case '39':
      return '特强浓雾';
    case '99':
      return '';
    default:
      return code;
  }
}