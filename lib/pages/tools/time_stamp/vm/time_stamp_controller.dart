import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get_rx/src/rx_types/rx_types.dart';
import 'package:intl/intl.dart';
import 'package:potatokid_clipboard/app/app_enums.dart';
import 'package:potatokid_clipboard/framework/base/base_get_vm.dart';
import 'package:potatokid_clipboard/gen/assets.gen.dart';
import 'package:potatokid_clipboard/pages/tools/time_stamp/model.dart/time_zone_model.dart';

class TimeStampController extends BaseGetVM {
  // --------------------------------当前时间戳--------------------------------
  final TextEditingController textController = TextEditingController();
  final Rx<int> currentTimeStamp = 0.obs;
  final Rx<TimeStampUnit> timeStampUnit = TimeStampUnit.second.obs;
  Timer? _timer;
  final RxBool isTimerRunning = false.obs;
  final isHoverTimeStamp = false.obs;
  final RxList<TimeZoneModel> timeZoneList = <TimeZoneModel>[].obs;
  // --------------------------------时间戳转日期时间---------------------------------
  final TextEditingController timestamp2DateTimeDateTimeController =
      TextEditingController();
  final TextEditingController timestamp2DateTimeTimestampController =
      TextEditingController();
  final TextEditingController timestamp2DateTimeFormatController =
      TextEditingController(text: 'yyyy-MM-dd HH:mm:ss');
  final Rx<TimeStampUnit> timestamp2DateTimeUnit = TimeStampUnit.second.obs;
  Rx<TimeZoneModel?> selectedTimeZone = Rx<TimeZoneModel?>(null);
  //--------------------------------日期时间转时间戳---------------------------------
  final TextEditingController dateTimeToTimeStampDateTimeController =
      TextEditingController();
  final TextEditingController dateTimeToTimeStampTimestampController =
      TextEditingController();
  final Rx<TimeStampUnit> dateTimeToTimeStampUnit = TimeStampUnit.second.obs;
  Rx<TimeZoneModel?> selectedDateTimeToTimeZone = Rx<TimeZoneModel?>(null);

  @override
  void onInit() {
    super.onInit();
    var now = DateTime.now();
    currentTimeStamp.value = now.millisecondsSinceEpoch;
    timeStampUnit.value = TimeStampUnit.second;
    isTimerRunning.value = false;
    if (timestamp2DateTimeUnit.value == TimeStampUnit.second) {
      timestamp2DateTimeTimestampController.text =
          (currentTimeStamp.value ~/ 1000).toString();
    } else {
      timestamp2DateTimeTimestampController.text =
          currentTimeStamp.value.toString();
    }
    loadTimeZoneList().then((value) {
      selectedTimeZone = timeZoneList
          .firstWhere((element) => element.name == 'Asia/Shanghai')
          .obs;
      selectedDateTimeToTimeZone = timeZoneList
          .firstWhere((element) => element.name == 'Asia/Shanghai')
          .obs;
      updateTimestamp2DateTimeDateTime();
      timestamp2DateTimeFormatController
          .addListener(onTimestamp2DateTimeFormatChange);
      dateTimeToTimeStampDateTimeController.text =
          DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now());
      updateDateTimeToTimeStampDateTime();
      startTimer();
    });
  }

  @override
  void onClose() {
    stopTimer();
    timestamp2DateTimeFormatController
        .removeListener(onTimestamp2DateTimeFormatChange);
    super.onClose();
  }

  Future<void> loadTimeZoneList() async {
    // 从assets读取timezone.csv文件
    String filename = Assets.datas.timezone;
    var text = await rootBundle.loadString(filename);
    var lines = text.split('\n');
    for (var line in lines) {
      var parts = line.split(',');
      // 有两种格式：
      // UTC+12,Pacific/Wallis
      // UTC+12:45,Pacific/Chatham
      if (parts.length >= 2) {
        String offSetText = parts[0].trim();
        String name = parts[1].trim();
        int offsetHours = 0;
        int offsetMinutes = 0;
        if (offSetText.startsWith('UTC')) {
          offSetText = offSetText.replaceAll('UTC', '').trim();
        }
        if (offSetText.contains(':')) {
          var offSetParts = offSetText.split(':');
          offsetHours = int.parse(offSetParts[0]);
          offsetMinutes = int.parse(offSetParts[1]);
        } else {
          offsetHours = int.parse(offSetText);
        }
        timeZoneList.add(TimeZoneModel(
            name: name,
            offsetHours: offsetHours,
            offsetMinutes: offsetMinutes));
      }
    }
    timeZoneList.sort((a, b) => a.name.compareTo(b.name));
  }

  void onTimerTick(Timer timer) {
    currentTimeStamp.value = DateTime.now().millisecondsSinceEpoch;
  }

  void onTimeStampUnitChange() {
    timeStampUnit.value = timeStampUnit.value == TimeStampUnit.second
        ? TimeStampUnit.millisecond
        : TimeStampUnit.second;
  }

  void onCopy() {
    Clipboard.setData(ClipboardData(text: currentTimeStamp.value.toString()));
  }

  void startTimer() {
    if (_timer == null || _timer?.isActive == false) {
      _timer = Timer.periodic(const Duration(microseconds: 100), onTimerTick);
      isTimerRunning.value = true;
    }
  }

  void stopTimer() {
    if (_timer != null && _timer?.isActive == true) {
      _timer?.cancel();
      _timer = null;
      isTimerRunning.value = false;
    }
  }

  void onStopOrStart() {
    if (isTimerRunning.value) {
      stopTimer();
    } else {
      startTimer();
    }
  }

  void onTimestamp2DateTimeFormatChange() {
    updateTimestamp2DateTimeDateTime();
  }

  void updateTimestamp2DateTimeDateTime() {
    DateTime dateTime;
    int timeStamp =
        int.tryParse(timestamp2DateTimeTimestampController.text) ?? 0;
    if (timestamp2DateTimeUnit.value == TimeStampUnit.second) {
      timeStamp = timeStamp * 1000;
    }
    dateTime = DateTime.fromMillisecondsSinceEpoch(timeStamp, isUtc: true);
    dateTime = dateTime.add(Duration(
        hours: selectedTimeZone.value?.offsetHours ?? 0,
        minutes: selectedTimeZone.value?.offsetMinutes ?? 0));
    timestamp2DateTimeDateTimeController.text =
        DateFormat(timestamp2DateTimeFormatController.text).format(dateTime);
  }

  void onDateTimeToTimeStampTimeStampUnitChange(TimeStampUnit unit) {
    timestamp2DateTimeUnit.value = unit;
    updateTimestamp2DateTimeDateTime();
  }

  void onTimeStampToDateTime() {
    updateTimestamp2DateTimeDateTime();
  }

  void onTimeZoneChange(TimeZoneModel timeZone) {
    selectedTimeZone.value = timeZone;
    updateTimestamp2DateTimeDateTime();
  }

  void onCurrentTimeStampClick() {
    if (timestamp2DateTimeUnit.value == TimeStampUnit.second) {
      timestamp2DateTimeTimestampController.text =
          (currentTimeStamp.value ~/ 1000).toString();
    } else {
      timestamp2DateTimeTimestampController.text =
          currentTimeStamp.value.toString();
    }
    updateTimestamp2DateTimeDateTime();
  }

  void onDateTimeToTimeStamp() {
    updateDateTimeToTimeStampDateTime();
  }

  void onDateTimeToTimeZoneChange(TimeZoneModel timeZone) {
    selectedDateTimeToTimeZone.value = timeZone;
    updateDateTimeToTimeStampDateTime();
  }

  /// 日期转时间戳
  void updateDateTimeToTimeStampDateTime() {
    /// 将文本转成时间（UTC-0）
    DateTime dateTime =
        DateTime.tryParse(dateTimeToTimeStampDateTimeController.text) ??
            DateTime(0);
    // dateTime =
    //     dateTime.add(Duration(hours: selectedDateTimeToTimeZone.value.offset));
    // int timeStamp = dateTime.millisecondsSinceEpoch;
    // if (dateTimeToTimeStampUnit.value == TimeStampUnit.second) {
    //   timeStamp = timeStamp ~/ 1000;
    // }
    // dateTimeToTimeStampTimestampController.text = timeStamp.toString();
    var utc = DateTime.utc(dateTime.year, dateTime.month, dateTime.day,
        dateTime.hour, dateTime.minute, dateTime.second, dateTime.millisecond);
    utc = utc.subtract(Duration(
        hours: selectedDateTimeToTimeZone.value?.offsetHours ?? 0,
        minutes: selectedDateTimeToTimeZone.value?.offsetMinutes ?? 0));
    int timeStamp = utc.millisecondsSinceEpoch;
    if (dateTimeToTimeStampUnit.value == TimeStampUnit.second) {
      timeStamp = timeStamp ~/ 1000;
    }
    dateTimeToTimeStampTimestampController.text = timeStamp.toString();
  }

  void onDateTimeToTimeStampUnitChange(TimeStampUnit unit) {
    dateTimeToTimeStampUnit.value = unit;
    updateDateTimeToTimeStampDateTime();
  }
}
