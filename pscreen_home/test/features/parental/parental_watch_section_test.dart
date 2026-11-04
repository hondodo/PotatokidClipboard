import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/parental/data/parental_admin_api.dart';
import 'package:pscreen_home/features/parental/domain/parental_config.dart';
import 'package:pscreen_home/features/parental/presentation/parental_sections.dart';
import 'package:pscreen_screen/core/network/realtime_channel.dart';

String _dateKey(DateTime time) =>
    '${time.year.toString().padLeft(4, '0')}-'
    '${time.month.toString().padLeft(2, '0')}-'
    '${time.day.toString().padLeft(2, '0')}';

RealtimeEvent _watch({
  required String from,
  required int ts,
  required String date,
  required Map<String, int> daily,
  List<String> childIds = const <String>['c1'],
}) => RealtimeEvent(
  id: 'watch-$from-$ts',
  from: from,
  to: '1000001',
  event: 'parental_watch',
  data: <String, dynamic>{
    'childIds': childIds,
    'dailySecByChild': daily,
    'sessionSecByChild': <String, int>{},
    'date': date,
  },
  ts: ts,
);

RealtimeEvent _active({
  required String from,
  required int ts,
  required List<String> childIds,
}) => RealtimeEvent(
  id: 'active-$from-$ts',
  from: from,
  to: '1000001',
  event: 'parental_child_active',
  data: <String, dynamic>{'childIds': childIds},
  ts: ts,
);

ParentalMachine _machine(String id, String comm) => ParentalMachine(
  id: id,
  name: 'TV $id',
  kind: 'tv',
  owner: 'home',
  parents: const <String>['home'],
  commAccount: comm,
  online: true,
);

const ParentalConfig _config = ParentalConfig(
  mode: 'on',
  children: <ParentalChild>[
    ParentalChild(id: 'c1', name: '甲', dailyLimitMin: 60),
    ParentalChild(id: 'c2', name: '乙', dailyLimitMin: 60),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('只显示当前选中设备的时长/观看者/最后上报', (WidgetTester tester) async {
    final DateTime now = DateTime.now();
    final String today = _dateKey(now);
    final List<RealtimeEvent> watch = <RealtimeEvent>[
      _watch(
        from: 'tvA',
        ts: now
            .subtract(const Duration(minutes: 2, seconds: 10))
            .millisecondsSinceEpoch,
        date: today,
        daily: <String, int>{'c1': 600},
      ),
      // 另一台电视更新、数字更小：选中 A 时不得被它覆盖。
      _watch(
        from: 'tvB',
        ts: now.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch,
        date: today,
        daily: <String, int>{'c1': 300},
      ),
    ];
    final List<RealtimeEvent> active = <RealtimeEvent>[
      _active(
        from: 'tvA',
        ts: now.subtract(const Duration(minutes: 2)).millisecondsSinceEpoch,
        childIds: const <String>['c1'],
      ),
      _active(
        from: 'tvB',
        ts: now.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch,
        childIds: const <String>['c2'],
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: WatchSection(
            config: _config,
            machine: _machine('mA', 'tvA'),
            watchEvents: watch,
            activeEvents: active,
          ),
        ),
      ),
    );

    expect(find.text('10 分 0 秒'), findsOneWidget); // A 的 600 秒
    expect(find.text('5 分 0 秒'), findsNothing); // B 的 300 秒不得出现
    expect(find.widgetWithText(Chip, '甲'), findsOneWidget);
    expect(find.widgetWithText(Chip, '乙'), findsNothing);
    expect(find.textContaining('2 分钟前'), findsOneWidget);
  });

  testWidgets('无今日事件时展示最后上报时间', (WidgetTester tester) async {
    final DateTime now = DateTime.now();
    final List<RealtimeEvent> watch = <RealtimeEvent>[
      _watch(
        from: 'tvA',
        ts: now
            .subtract(const Duration(hours: 3, minutes: 5))
            .millisecondsSinceEpoch,
        date: _dateKey(now.subtract(const Duration(days: 1))),
        daily: <String, int>{'c1': 600},
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: WatchSection(
            config: _config,
            machine: _machine('mA', 'tvA'),
            watchEvents: watch,
            activeEvents: const <RealtimeEvent>[],
          ),
        ),
      ),
    );

    expect(find.text('今日未上报'), findsNWidgets(2));
    expect(find.textContaining('最后上报'), findsOneWidget);
    expect(find.textContaining('3 小时前'), findsOneWidget);
  });

  testWidgets('最新 childIds 为空时表达「无人在看」', (WidgetTester tester) async {
    final DateTime now = DateTime.now();
    final List<RealtimeEvent> watch = <RealtimeEvent>[
      _watch(
        from: 'tvA',
        ts: now.millisecondsSinceEpoch,
        date: _dateKey(now),
        daily: <String, int>{'c1': 120},
        childIds: const <String>[],
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(useMaterial3: true),
        home: Scaffold(
          body: WatchSection(
            config: _config,
            machine: _machine('mA', 'tvA'),
            watchEvents: watch,
            activeEvents: const <RealtimeEvent>[],
          ),
        ),
      ),
    );

    expect(find.text('未上报在看孩子'), findsOneWidget);
    expect(find.text('2 分 0 秒'), findsOneWidget);
  });
}
