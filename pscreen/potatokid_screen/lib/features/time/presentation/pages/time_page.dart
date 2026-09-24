import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:potatokid_screen/features/time/application/time_style_controller.dart';
import 'package:potatokid_screen/features/time/domain/lunar_calendar.dart';
import 'package:potatokid_screen/features/time/presentation/components/analog_dial_clock.dart';
import 'package:potatokid_screen/features/time/presentation/components/flowing_gradient_background.dart';

/// 「时间」Tab 页：多样化时钟，三屏共用的流动彩色背景 + 20% 黑蒙层。
///
/// 样式通过遥控器 **上/下** 循环切换（由壳层 MainApp 的根按键处理器驱动
/// [TimeStyleController]），分别为：完整（时间+日期+农历+星期）/ 仅时间 / 转盘时钟。
class TimePage extends StatefulWidget {
  const TimePage({super.key});

  @override
  State<TimePage> createState() => _TimePageState();
}

class _TimePageState extends State<TimePage> {
  static final DateFormat _timeFmt = DateFormat('HH:mm:ss', 'zh_CN');
  static final DateFormat _dateFmt = DateFormat('y年M月d日', 'zh_CN');
  static final DateFormat _weekdayFmt = DateFormat('EEEE', 'zh_CN');

  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        const FlowingGradientBackground(),
        Center(
          child: ListenableBuilder(
            listenable: TimeStyleController.instance,
            builder: (context, _) {
              switch (TimeStyleController.instance.style) {
                case TimeStyle.timeOnly:
                  return _timeOnly();
                case TimeStyle.dial:
                  return const AnalogDialClock();
                case TimeStyle.full:
                  return _full();
              }
            },
          ),
        ),
      ],
    );
  }

  /// 完整样式：超大时间 + 日期 + 农历 + 星期。
  Widget _full() {
    final LunarDate? lunar = lunarDateOf(DateTime(_now.year, _now.month, _now.day));
    final String lunarStr = lunar?.fullCnString ?? '';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          _timeFmt.format(_now),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 120,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '${_dateFmt.format(_now)} $lunarStr ${_weekdayFmt.format(_now)}'
              .trim(),
          style: const TextStyle(color: Colors.white, fontSize: 28),
        ),
      ],
    );
  }

  /// 仅显示时间。
  Widget _timeOnly() {
    return Text(
      _timeFmt.format(_now),
      style: const TextStyle(
        color: Colors.white,
        fontSize: 150,
        fontWeight: FontWeight.bold,
        letterSpacing: 4,
      ),
    );
  }
}