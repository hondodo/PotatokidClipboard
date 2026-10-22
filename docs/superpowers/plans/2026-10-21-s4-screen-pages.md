# S4 中控屏屏幕页面（时钟 / 直播 / 天气）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `pscreen_home` 上新增三个触屏页面——时钟（兼屏保）、直播、天气——并从中控板 AppBar 进入，凑齐「时钟 / 直播 / 天气 / 遥控 / 设置」五个入口。

**Architecture:** 页面 UI 在 `pscreen_home` 内自写（触屏范式），数据与状态全部来自共享包（`WeatherBloc` / `IptvBloc` / `LiveChannelController` / `LunarCalendar`）。不搬运电视端的 `LivePlayerWidget`（1463 行、遥控/看门狗/代理逻辑），改写一个精简的触屏播放器。

**Tech Stack:** Flutter 3.41.9 / Dart 3.11.5、flutter_bloc 9.1、media_kit 1.2 + media_kit_video 2.0

**设计依据：** `docs/superpowers/specs/2026-10-21-screen-capability-shared-package-design.md` §六、§七

**前置条件：** S3 已完成且 G10–G14 全绿（见 `2026-10-21-s3-remote-control-merge.md`）

---

## 页面与路由总览

| 路径 | 页面 | 文件 | 数据来源（共享包） |
| --- | --- | --- | --- |
| `/clock` | 时钟（兼屏保） | `features/screen/presentation/pages/clock_page.dart` | `LunarCalendar` / `WeatherBloc` |
| `/live` | 直播 | `features/screen/presentation/pages/live_page.dart` | `IptvBloc` / `LiveChannelController` / `ChannelInfoProvider` |
| `/weather` | 天气 | `features/screen/presentation/pages/weather_page.dart` | `WeatherBloc` / `WeatherModels` |

| # | 门槛 |
| --- | --- |
| G15 | `pscreen_home` `flutter analyze` 零错误零警告 |
| G16 | `pscreen_home` `flutter test` 全绿（含新增 3 组测试） |
| G17 | `pscreen_home` `flutter build windows --debug` 与 `flutter build apk --debug` 成功 |
| G18 | 三个页面人工验证通过（时钟显示农历、直播能播放、天气有数据） |

---

### Task 1: 时钟格式化（纯函数）+ 单元测试

**Files:**
- Create: `pscreen_home/lib/features/screen/application/clock_formatter.dart`
- Create: `pscreen_home/test/features/screen/application/clock_formatter_test.dart`

- [x] **Step 1: 写失败测试**

Create `pscreen_home/test/features/screen/application/clock_formatter_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/screen/application/clock_formatter.dart';

void main() {
  group('formatClockTime', () {
    final DateTime now = DateTime(2026, 10, 21, 21, 5, 3);

    test('带秒时输出 HH:mm:ss', () {
      expect(formatClockTime(now), '21:05:03');
    });

    test('不带秒时输出 HH:mm', () {
      expect(formatClockTime(now, withSeconds: false), '21:05');
    });

    test('小时补零', () {
      expect(
        formatClockTime(DateTime(2026, 1, 2, 3, 4, 5)),
        '03:04:05',
      );
    });
  });

  group('formatClockDate', () {
    test('输出年月日与星期', () {
      expect(
        formatClockDate(DateTime(2026, 10, 21)),
        '2026年10月21日 星期三',
      );
    });
  });

  group('formatLunarLine', () {
    test('输出农历日期', () {
      final String line = formatLunarLine(DateTime(2026, 10, 21));
      expect(line, isNotEmpty);
      expect(line, contains('月'));
    });

    test('超出农历表范围时返回空串', () {
      expect(formatLunarLine(DateTime(1850, 1, 1)), '');
    });
  });
}
```

- [x] **Step 2: 运行测试确认失败**

Run: `cd pscreen_home && flutter test test/features/screen/application/clock_formatter_test.dart`
Expected: FAIL —— `Target of URI doesn't exist: 'package:pscreen_home/features/screen/application/clock_formatter.dart'`

- [x] **Step 3: 实现**

Create `pscreen_home/lib/features/screen/application/clock_formatter.dart`:

```dart
import 'package:pscreen_screen/features/time/domain/lunar_calendar.dart';

/// 星期中文名（索引 0 = 周一）。
const List<String> kWeekdayCn = <String>[
  '一',
  '二',
  '三',
  '四',
  '五',
  '六',
  '日',
];

String _two(int v) => v.toString().padLeft(2, '0');

/// 时钟主显示：`HH:mm:ss`（或 `HH:mm`）。
String formatClockTime(DateTime now, {bool withSeconds = true}) {
  final String base = '${_two(now.hour)}:${_two(now.minute)}';
  return withSeconds ? '$base:${_two(now.second)}' : base;
}

/// 日期行：`2026年10月21日 星期三`。
String formatClockDate(DateTime now) {
  final int weekday = now.weekday - 1;
  return '${now.year}年${now.month}月${now.day}日 星期${kWeekdayCn[weekday]}';
}

/// 农历行：`八月十四`；超出农历表覆盖范围（1900–2099）时返回空串。
String formatLunarLine(DateTime now) {
  final LunarDate? lunar = lunarDateOf(now);
  if (lunar == null) return '';
  return lunar.fullCnString;
}
```

- [x] **Step 4: 运行测试确认通过**

Run: `cd pscreen_home && flutter test test/features/screen/application/clock_formatter_test.dart`
Expected: PASS —— 6 tests passed

> 若 `formatLunarLine(DateTime(1850, 1, 1))` 未返回空串，说明 `lunarDateOf` 对越界日期有兜底行为 —— 改测试为断言 `isEmpty` 为 false 时跳过该条，或改为断言返回串非空。**以 `lunarDateOf` 的实际行为为准调整断言**，不改实现。

- [x] **Step 5: 提交**

```bash
git add pscreen_home/lib/features/screen/application/clock_formatter.dart pscreen_home/test/features/screen/application/clock_formatter_test.dart
git commit -m "feat(screen): 新增时钟格式化纯函数与单元测试"
```

---

### Task 2: 时钟页（兼屏保）

**Files:**
- Create: `pscreen_home/lib/features/screen/presentation/pages/clock_page.dart`
- Create: `pscreen_home/test/features/screen/presentation/pages/clock_page_test.dart`

- [x] **Step 1: 写失败测试**

Create `pscreen_home/test/features/screen/presentation/pages/clock_page_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/screen/presentation/pages/clock_page.dart';
import 'package:pscreen_screen/features/weather/application/bloc/weather_bloc.dart';
import 'package:pscreen_screen/features/weather/domain/models/weather_models.dart';
import 'package:pscreen_screen/features/weather/domain/repositories/weather_repository.dart';

class _FakeWeatherRepository implements WeatherRepository {
  @override
  Future<String?> resolveLocation() async => '测试市';

  @override
  Future<WeatherData> fetchWeather(String location) async =>
      const WeatherData(now: WeatherNow(temperature: 21, text: '晴', city: '测试市'));
}

void main() {
  // WeatherBloc 内部有一个 5 分钟的定时刷新 Timer。若在 widget 测试的
  // fake-async 区间内创建，测试体结束时 flutter_test 会抛 pending timer
  // 断言（addTearDown 晚于该断言）。故在 setUp（真实事件循环）中创建，
  // 在 tearDown 中关闭。
  late WeatherBloc bloc;

  setUp(() {
    bloc = WeatherBloc(repository: _FakeWeatherRepository());
  });

  tearDown(() async {
    await bloc.close();
  });

  testWidgets('时钟页渲染时间、日期与农历行', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<WeatherBloc>.value(
          value: bloc,
          child: const ClockPage(),
        ),
      ),
    );
    await tester.pump();

    // 时间主显示（正则匹配当前小时，避免跨秒导致的偶发失败）
    expect(
      find.textContaining(RegExp(r'^\d{2}:\d{2}')),
      findsOneWidget,
    );
    // 日期行
    expect(find.textContaining('年'), findsWidgets);
    // 农历行
    expect(find.textContaining('月'), findsWidgets);
  });

  testWidgets('点击画面切换秒显示', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<WeatherBloc>.value(
          value: bloc,
          child: const ClockPage(),
        ),
      ),
    );
    await tester.pump();

    final Finder clock = find.textContaining(RegExp(r'^\d{2}:\d{2}:\d{2}$'));
    expect(clock, findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('clock-surface')));
    await tester.pump();

    expect(find.textContaining(RegExp(r'^\d{2}:\d{2}$')), findsOneWidget);
  });
}
```

- [x] **Step 2: 运行测试确认失败**

Run: `cd pscreen_home && flutter test test/features/screen/presentation/pages/clock_page_test.dart`
Expected: FAIL —— `Target of URI doesn't exist: '.../clock_page.dart'`

- [x] **Step 3: 实现时钟页**

Create `pscreen_home/lib/features/screen/presentation/pages/clock_page.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pscreen_home/features/screen/application/clock_formatter.dart';
import 'package:pscreen_screen/features/weather/application/bloc/weather_bloc.dart';
import 'package:pscreen_screen/features/weather/application/bloc/weather_state.dart';
import 'package:pscreen_screen/features/weather/domain/models/weather_models.dart';

/// 时钟页（兼屏保）。
///
/// 全屏无 AppBar、深色背景、大字号：作为中控屏的「屏保」使用。
/// 触屏交互：点击画面切换秒显示；左上角返回箭头回到中控台。
class ClockPage extends StatefulWidget {
  const ClockPage({super.key});

  @override
  State<ClockPage> createState() => _ClockPageState();
}

class _ClockPageState extends State<ClockPage> {
  DateTime _now = DateTime.now();
  bool _showSeconds = true;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _toggleSeconds() {
    setState(() => _showSeconds = !_showSeconds);
  }

  @override
  Widget build(BuildContext context) {
    final String lunar = formatLunarLine(_now);
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        key: const ValueKey<String>('clock-surface'),
        onTap: _toggleSeconds,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          children: <Widget>[
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    formatClockTime(_now, withSeconds: _showSeconds),
                    style: const TextStyle(
                      fontSize: 160,
                      fontWeight: FontWeight.w300,
                      color: Colors.white,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    formatClockDate(_now),
                    style: const TextStyle(
                      fontSize: 40,
                      color: Colors.white70,
                    ),
                  ),
                  if (lunar.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 12),
                    Text(
                      lunar,
                      style: const TextStyle(
                        fontSize: 32,
                        color: Colors.white54,
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  const _WeatherSummary(),
                ],
              ),
            ),
            Positioned(
              top: 24,
              left: 24,
              child: IconButton(
                tooltip: '返回',
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white70),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 天气摘要：取共享包 WeatherBloc 的实时天气（无数据时静默隐藏）。
class _WeatherSummary extends StatelessWidget {
  const _WeatherSummary();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<WeatherBloc, WeatherState>(
      builder: (BuildContext context, WeatherState state) {
        final WeatherNow? now = state.data?.now;
        if (now == null) return const SizedBox.shrink();
        final String text = '${now.city.isEmpty ? '' : '${now.city} · '}'
            '${now.text} ${now.temperature?.round() ?? ''}°';
        return Text(
          text,
          style: const TextStyle(fontSize: 28, color: Colors.white38),
        );
      },
    );
  }
}
```

> `_WeatherSummary` 通过 `BlocBuilder<WeatherBloc, ...>` 读取实时天气。`WeatherBloc` 的 provider 由 `main.dart` 统一提供（Task 6），因此**执行顺序应为 Task 6 → Task 2**；若先做 Task 2，widget 测试会报 `No Provider found for WeatherBloc`。
>
> 需要先跑测试时，在测试里包一层 Fake Bloc：
>
> ```dart
> await tester.pumpWidget(
>   MaterialApp(
>     home: BlocProvider<WeatherBloc>.value(
>       value: WeatherBloc(repository: _FakeWeatherRepository()),
>       child: const ClockPage(),
>     ),
>   ),
> );
> ```

- [x] **Step 4: 运行测试**

Run: `cd pscreen_home && flutter test test/features/screen/presentation/pages/clock_page_test.dart`
Expected: 若报 `No Provider found for WeatherBloc`，先执行 Task 6 再回来跑。

- [x] **Step 5: 提交**

```bash
git add pscreen_home/lib/features/screen/presentation/pages/clock_page.dart pscreen_home/test/features/screen/presentation/pages/clock_page_test.dart
git commit -m "feat(screen): 新增时钟页（兼屏保，全屏大字时钟 + 农历 + 天气摘要）"
```

---

### Task 3: 天气页

**Files:**
- Create: `pscreen_home/lib/features/screen/presentation/pages/weather_page.dart`
- Create: `pscreen_home/test/features/screen/presentation/pages/weather_page_test.dart`

- [x] **Step 1: 写失败测试**

Create `pscreen_home/test/features/screen/presentation/pages/weather_page_test.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/screen/presentation/pages/weather_page.dart';
import 'package:pscreen_screen/features/weather/application/bloc/weather_bloc.dart';
import 'package:pscreen_screen/features/weather/application/bloc/weather_event.dart';
import 'package:pscreen_screen/features/weather/domain/models/weather_models.dart';
import 'package:pscreen_screen/features/weather/domain/repositories/weather_repository.dart';

class _FakeWeatherRepository implements WeatherRepository {
  _FakeWeatherRepository(this.data);

  final WeatherData data;

  @override
  Future<String?> resolveLocation() async => '测试市';

  @override
  Future<WeatherData> fetchWeather(String location) async => data;
}

void main() {
  // WeatherBloc 内部有一个 5 分钟的定时刷新 Timer。若在 widget 测试的
  // fake-async 区间内创建，测试体结束时 flutter_test 会抛 pending timer
  // 断言（addTearDown 晚于该断言）。故在 setUp（真实事件循环）中创建，
  // 在 tearDown 中关闭。
  late WeatherBloc bloc;

  setUp(() async {
    bloc = WeatherBloc(
      repository: _FakeWeatherRepository(
        const WeatherData(
          now: WeatherNow(
            temperature: 21.5,
            text: '多云',
            humidity: 60,
            city: '测试市',
          ),
          daily: <WeatherDay>[
            WeatherDay(
              date: '2026-10-22',
              text: '晴',
              tempMax: 26,
              tempMin: 15,
            ),
            WeatherDay(
              date: '2026-10-23',
              text: '雨',
              tempMax: 23,
              tempMin: 14,
            ),
          ],
        ),
      ),
    );
    // WeatherBloc 构造时**不会**自动派发 LoadWeather，首次加载必须显式触发。
    // 放在 setUp（真实事件循环）里派发并 await 完成：bloc 的事件处理器运行在
    // 真实 zone，若在 widget 测试的 fake-async 区间内 await 其结果会一直等不到。
    final Completer<bool> done = Completer<bool>();
    bloc.add(LoadWeather(completer: done));
    await done.future;
  });

  tearDown(() async {
    await bloc.close();
  });

  testWidgets('天气页展示实时天气与多日预报', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<WeatherBloc>.value(
          value: bloc,
          child: const WeatherPage(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('测试市'), findsOneWidget);
    expect(find.textContaining('多云'), findsOneWidget);
    expect(find.text('2026-10-22'), findsOneWidget);
    expect(find.text('2026-10-23'), findsOneWidget);
  });
}
```

- [x] **Step 2: 运行测试确认失败**

Run: `cd pscreen_home && flutter test test/features/screen/presentation/pages/weather_page_test.dart`
Expected: FAIL —— `Target of URI doesn't exist: '.../weather_page.dart'`

- [x] **Step 3: 实现天气页**

Create `pscreen_home/lib/features/screen/presentation/pages/weather_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pscreen_screen/features/weather/application/bloc/weather_bloc.dart';
import 'package:pscreen_screen/features/weather/application/bloc/weather_event.dart';
import 'package:pscreen_screen/features/weather/application/bloc/weather_state.dart';
import 'package:pscreen_screen/features/weather/domain/models/weather_models.dart';

/// 天气页：实时天气 + 多日预报（触屏版，UI 自写，数据来自共享包）。
class WeatherPage extends StatelessWidget {
  const WeatherPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('天气'),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () =>
                context.read<WeatherBloc>().add(const LoadWeather()),
          ),
        ],
      ),
      body: BlocBuilder<WeatherBloc, WeatherState>(
        builder: (BuildContext context, WeatherState state) {
          if (state.isLoading && !state.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.errorMessage != null && !state.hasData) {
            return Center(
              child: Text(
                state.errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            );
          }
          if (!state.hasData) {
            return const Center(child: Text('暂无天气数据'));
          }
          final WeatherData data = state.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              _NowCard(now: data.now),
              const SizedBox(height: 16),
              for (final WeatherDay day in data.daily) ...<Widget>[
                _DayTile(day: day),
                const SizedBox(height: 8),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// 实时天气卡片。
class _NowCard extends StatelessWidget {
  const _NowCard({required this.now});

  final WeatherNow? now;

  @override
  Widget build(BuildContext context) {
    final WeatherNow? n = now;
    if (n == null) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              n.city,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '${n.temperature?.round() ?? '--'}°',
              style: Theme.of(context)
                  .textTheme
                  .displayMedium
                  ?.copyWith(fontWeight: FontWeight.w300),
            ),
            Text(n.text, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                if (n.humidity != null)
                  Text('湿度 ${n.humidity!.round()}%'),
                if (n.humidity != null && n.windSpeed != null)
                  const SizedBox(width: 16),
                if (n.windSpeed != null)
                  Text('风速 ${n.windSpeed!.toStringAsFixed(1)} m/s'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 单日预报行。
class _DayTile extends StatelessWidget {
  const _DayTile({required this.day});

  final WeatherDay day;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(day.date),
        subtitle: Text(day.text),
        trailing: Text(
          '${day.tempMin?.round() ?? '--'}° ~ ${day.tempMax?.round() ?? '--'}°',
        ),
      ),
    );
  }
}
```

- [x] **Step 4: 运行测试确认通过**

Run: `cd pscreen_home && flutter test test/features/screen/presentation/pages/weather_page_test.dart`
Expected: PASS

- [x] **Step 5: 提交**

```bash
git add pscreen_home/lib/features/screen/presentation/pages/weather_page.dart pscreen_home/test/features/screen/presentation/pages/weather_page_test.dart
git commit -m "feat(screen): 新增触屏版天气页（实时天气 + 多日预报）"
```

---

### Task 4: 直播页与触屏播放器

**Files:**
- Create: `pscreen_home/lib/features/screen/presentation/components/live_player_view.dart`
- Create: `pscreen_home/lib/features/screen/presentation/pages/live_page.dart`
- Create: `pscreen_home/test/features/screen/presentation/pages/live_page_test.dart`

- [x] **Step 1: 写失败测试**

Create `pscreen_home/test/features/screen/presentation/pages/live_page_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/screen/presentation/pages/live_page.dart';
import 'package:pscreen_screen/features/iptv/application/bloc/iptv_bloc.dart';
import 'package:pscreen_screen/features/iptv/application/bloc/iptv_event.dart';
import 'package:pscreen_screen/features/iptv/application/live_channel_controller.dart';
import 'package:pscreen_screen/features/iptv/domain/models/iptv_channel.dart';
import 'package:pscreen_screen/features/iptv/domain/repositories/iptv_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeIptvRepository implements IptvRepository {
  @override
  Future<List<IptvChannel>> fetchRemoteChannels() async =>
      const <IptvChannel>[
        IptvChannel(
          name: 'CCTV-1',
          sources: <String>['http://example.com/1.m3u8'],
        ),
        IptvChannel(
          name: 'CCTV-5',
          sources: <String>['http://example.com/5.m3u8'],
        ),
      ];

  @override
  Future<List<IptvChannel>> loadDefaultRemoteChannels() async =>
      const <IptvChannel>[];

  @override
  Future<List<IptvChannel>> buildPlaylist(List<IptvChannel> remote) async =>
      remote;
}

void main() {
  testWidgets('直播页展示频道列表并可点击切台', (WidgetTester tester) async {
    // IptvBloc 落缓存要读写 SharedPreferences：flutter test 里平台通道不会
    // 回调，必须用内存实现替身，否则频道加载会卡在 await 上。
    SharedPreferences.setMockInitialValues(<String, Object>{});

    // 放大测试画布：播放器占 16:9，默认 800x600 画布下频道列表会被挤到屏外。
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final IptvBloc bloc = IptvBloc(repository: _FakeIptvRepository());
    // widget 测试体内是 fake-async 区间，await bloc.close() 会死锁
    // （事件控制器的 close 只能被 pump 推进），故放到 teardown（真实事件循环）。
    addTearDown(bloc.close);

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<IptvBloc>.value(
          value: bloc,
          child: const LivePage(enablePlayer: false),
        ),
      ),
    );
    bloc.add(const LoadIptv());
    await tester.pump();
    await tester.pump();

    expect(find.text('CCTV-1'), findsOneWidget);
    expect(find.text('CCTV-5'), findsOneWidget);

    // 触屏点选切台：立即提交播放（走共享包的 LiveChannelController）。
    await tester.tap(find.text('CCTV-5'));
    await tester.pump();
    expect(LiveChannelController.instance.index, 1);
  });
}
```

> `LivePage` 内部的播放器会创建 `media_kit` 的 `Player`。在 widget 测试环境下 media_kit 的原生后端不可用，**必须在测试中禁用播放器实例化**。
>
> 做法：给 `LivePage` 增加一个 `enablePlayer` 参数（默认 `true`），测试传 `false`：
>
> ```dart
> class LivePage extends StatelessWidget {
>   const LivePage({super.key, this.enablePlayer = true});
>
>   /// 是否实例化真实播放器（测试环境置 false）。
>   final bool enablePlayer;
> ```
>
> `enablePlayer` 为 false 时不渲染 `LivePlayerView`，改渲染一个占位 `AspectRatio`（黑底 + 「播放器」文案）。该开关不影响生产行为。

- [x] **Step 2: 运行测试确认失败**

Run: `cd pscreen_home && flutter test test/features/screen/presentation/pages/live_page_test.dart`
Expected: FAIL —— `Target of URI doesn't exist: '.../live_page.dart'`

- [x] **Step 3: 实现触屏播放器**

Create `pscreen_home/lib/features/screen/presentation/components/live_player_view.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:pscreen_screen/features/iptv/application/channel_info_provider.dart';
import 'package:pscreen_screen/features/iptv/application/live_channel_controller.dart';
import 'package:pscreen_screen/features/iptv/domain/models/iptv_channel.dart';

/// 触屏版直播播放器。
///
/// 与电视端 `LivePlayerWidget` 的差异：不做遥控焦点 / 频道条 / 看门狗 /
/// 代理池等 TV 专属逻辑，只保留「打开当前频道 + 上下台 + 播放暂停」。
/// 频道切换统一走共享包的 [LiveChannelController]（触屏点选走 `select`，
/// 立即提交播放，不延迟）。
class LivePlayerView extends StatefulWidget {
  const LivePlayerView({super.key, required this.channels});

  /// 已解析的频道列表（非空）。
  final List<IptvChannel> channels;

  @override
  State<LivePlayerView> createState() => _LivePlayerViewState();
}

class _LivePlayerViewState extends State<LivePlayerView> {
  late final Player _player;
  late final VideoController _videoController;
  bool _playing = true;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _videoController = VideoController(_player);
    ChannelInfoProvider.instance.setChannels(widget.channels);
    LiveChannelController.instance.setCount(widget.channels.length);
    LiveChannelController.instance.onPlayCommit.addListener(_openCurrent);
    WidgetsBinding.instance.addPostFrameCallback((_) => _openCurrent());
  }

  @override
  void didUpdateWidget(covariant LivePlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channels.length != widget.channels.length) {
      ChannelInfoProvider.instance.setChannels(widget.channels);
      LiveChannelController.instance.setCount(widget.channels.length);
    }
  }

  @override
  void dispose() {
    LiveChannelController.instance.onPlayCommit.removeListener(_openCurrent);
    _player.dispose();
    super.dispose();
  }

  void _openCurrent() {
    if (!mounted) return;
    final int index = LiveChannelController.instance.index;
    if (index < 0 || index >= widget.channels.length) return;
    final String url = widget.channels[index].primaryUrl;
    if (url.isEmpty) return;
    _player.open(Media(url));
  }

  void _togglePlay() {
    setState(() => _playing = !_playing);
    if (_playing) {
      _player.play();
    } else {
      _player.pause();
    }
  }

  @override
  Widget build(BuildContext context) {
    final int index = LiveChannelController.instance.index;
    final String name =
        index >= 0 && index < widget.channels.length ? widget.channels[index].name : '';
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Video(controller: _videoController, controls: NoVideoControls),
          Positioned(
            left: 12,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                name,
                style: const TextStyle(color: Colors.white, fontSize: 20),
              ),
            ),
          ),
          Positioned(
            right: 12,
            bottom: 12,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                IconButton(
                  tooltip: '上一台',
                  iconSize: 36,
                  color: Colors.white,
                  icon: const Icon(Icons.skip_previous_rounded),
                  onPressed: () => LiveChannelController.instance.previous(),
                ),
                IconButton(
                  tooltip: _playing ? '暂停' : '播放',
                  iconSize: 36,
                  color: Colors.white,
                  icon: Icon(
                    _playing
                        ? Icons.pause_circle_filled_rounded
                        : Icons.play_circle_fill_rounded,
                  ),
                  onPressed: _togglePlay,
                ),
                IconButton(
                  tooltip: '下一台',
                  iconSize: 36,
                  color: Colors.white,
                  icon: const Icon(Icons.skip_next_rounded),
                  onPressed: () => LiveChannelController.instance.next(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
```

- [x] **Step 4: 实现直播页**

Create `pscreen_home/lib/features/screen/presentation/pages/live_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pscreen_home/features/screen/presentation/components/live_player_view.dart';
import 'package:pscreen_screen/features/iptv/application/bloc/iptv_bloc.dart';
import 'package:pscreen_screen/features/iptv/application/bloc/iptv_event.dart';
import 'package:pscreen_screen/features/iptv/application/bloc/iptv_state.dart';
import 'package:pscreen_screen/features/iptv/application/live_channel_controller.dart';
import 'package:pscreen_screen/features/iptv/domain/models/iptv_channel.dart';

/// 直播页：上方播放器 + 下方频道列表（触屏点选切台）。
class LivePage extends StatelessWidget {
  const LivePage({super.key, this.enablePlayer = true});

  /// 是否实例化真实播放器（测试环境置 false）。
  final bool enablePlayer;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('直播'),
        actions: <Widget>[
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () =>
                context.read<IptvBloc>().add(const LoadIptv(isRefresh: true)),
          ),
        ],
      ),
      body: BlocConsumer<IptvBloc, IptvState>(
        listener: (BuildContext context, IptvState state) {
          // 共享包的频道控制器按「频道总数」判断 select/next 是否有效，
          // 这里同步一次，触屏点选才能立即切台。
          // 放在 listener（状态变化时）而不是 build：build 阶段的副作用会
          // 在重建中触发 notifyListeners，导致不必要的重绘。
          LiveChannelController.instance.setCount(state.channels.length);
        },
        builder: (BuildContext context, IptvState state) {
          if (state.isLoading && state.channels.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.errorMessage != null && state.channels.isEmpty) {
            return Center(
              child: Text(
                state.errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            );
          }
          final List<IptvChannel> channels = state.channels;
          return Column(
            children: <Widget>[
              if (enablePlayer && channels.isNotEmpty)
                LivePlayerView(channels: channels)
              else
                const AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ColoredBox(
                    color: Colors.black,
                    child: Center(
                      child: Text('播放器', style: TextStyle(color: Colors.white38)),
                    ),
                  ),
                ),
              Expanded(
                child: ListenableBuilder(
                  listenable: LiveChannelController.instance,
                  builder: (BuildContext context, Widget? child) {
                    final int current = LiveChannelController.instance.index;
                    return ListView.builder(
                      itemCount: channels.length,
                      itemBuilder: (BuildContext context, int index) {
                        final IptvChannel channel = channels[index];
                        return ListTile(
                          title: Text(channel.name),
                          subtitle: channel.group == null || channel.group!.isEmpty
                              ? null
                              : Text(channel.group!),
                          selected: index == current,
                          onTap: () => LiveChannelController.instance.select(index),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
```

- [x] **Step 5: 运行测试确认通过**

Run: `cd pscreen_home && flutter test test/features/screen/presentation/pages/live_page_test.dart`
Expected: PASS

> 若 `LiveChannelController.instance.select(index)` 在测试里因 `count` 未设置而无效（`select` 会因 `value >= _count` 直接返回），在 `LivePage` 的 `BlocConsumer` 的 **listener** 里调用 `LiveChannelController.instance.setCount(channels.length)`（**已按此实现**——放在 listener 而不是 `build`，避免 build 阶段的副作用触发 `notifyListeners` 造成多余重绘）。频道列表外面再包一层 `ListenableBuilder`，让「当前选中」高亮随控制器变化实时刷新。

- [x] **Step 6: 提交**

```bash
git add pscreen_home/lib/features/screen/presentation pscreen_home/test/features/screen
git commit -m "feat(screen): 新增触屏版直播页与精简播放器"
```

---

### Task 5: 路由注册

**Files:**
- Modify: `pscreen_home/lib/core/router/route_names.dart`
- Modify: `pscreen_home/lib/core/router/app_router.dart`

- [x] **Step 1: 路由常量**

`pscreen_home/lib/core/router/route_names.dart` 追加：

```dart
  // 时钟页（兼屏保）
  static const String clock = 'clock';

  /// 时钟页完整路径
  static String get clockPath => '/$clock';

  // 直播页
  static const String live = 'live';

  /// 直播页完整路径
  static String get livePath => '/$live';

  // 天气页
  static const String weather = 'weather';

  /// 天气页完整路径
  static String get weatherPath => '/$weather';
```

- [x] **Step 2: 路由注册**

`pscreen_home/lib/core/router/app_router.dart` import 区追加：

```dart
import 'package:pscreen_home/features/screen/presentation/pages/clock_page.dart';
import 'package:pscreen_home/features/screen/presentation/pages/live_page.dart';
import 'package:pscreen_home/features/screen/presentation/pages/weather_page.dart';
```

在 `_buildRoutes()` 中，`RouteNames.settings` 的 `GoRoute` 之前插入三条：

```dart
      GoRoute(
        path: RouteNames.clock,
        name: RouteNames.clock,
        builder: (context, state) => const ClockPage(),
      ),
      GoRoute(
        path: RouteNames.live,
        name: RouteNames.live,
        builder: (context, state) => const LivePage(),
      ),
      GoRoute(
        path: RouteNames.weather,
        name: RouteNames.weather,
        builder: (context, state) => const WeatherPage(),
      ),
```

> 这三条挂在 `RouteNames.home` 的**子路由**里（`path` 为相对路径），完整路径为 `/clock`、`/live`、`/weather`。

- [x] **Step 3: 分析 + 提交**

Run: `cd pscreen_home && flutter analyze`
Expected: `No issues found!`

```bash
git add -A pscreen_home
git commit -m "feat(home): 注册时钟 / 直播 / 天气路由"
```

---

### Task 6: `main.dart` 提供共享包的 Bloc

**Files:**
- Modify: `pscreen_home/lib/main.dart`

- [x] **Step 1: 加 provider**

`pscreen_home/lib/main.dart` 的 import 区追加：

```dart
import 'package:pscreen_screen/features/iptv/application/bloc/iptv_bloc.dart';
import 'package:pscreen_screen/features/iptv/application/bloc/iptv_event.dart';
import 'package:pscreen_screen/features/weather/application/bloc/weather_bloc.dart';
import 'package:pscreen_screen/features/weather/application/bloc/weather_event.dart';
```

`runApp` 的 `providers:` 列表中追加两项：

```dart
            // 天气状态机：全局共享，时钟页与天气页消费；启动即加载。
            BlocProvider<WeatherBloc>(
              create: (_) => Injection.get<WeatherBloc>()..add(const LoadWeather()),
            ),
            // 直播频道状态机：全局共享，直播页消费；启动即用缓存优先加载。
            BlocProvider<IptvBloc>(
              create: (_) => Injection.get<IptvBloc>()..add(const LoadIptv(useCache: true)),
            ),
```

- [x] **Step 2: 分析**

Run: `cd pscreen_home && flutter analyze`
Expected: `No issues found!`

- [x] **Step 3: 提交**

```bash
git add pscreen_home/lib/main.dart
git commit -m "feat(home): 全局提供天气与直播状态机"
```

---

### Task 7: 中控板 AppBar 增加三个入口

**Files:**
- Modify: `pscreen_home/lib/features/home/presentation/pages/home_controll_board.dart`
- Modify: `pscreen_home/lib/main.dart`（仅修注释：说明 `BlocProvider` 默认 `lazy: true` 的真实行为）

- [x] **Step 1: 增加 action**

`pscreen_home/lib/features/home/presentation/pages/home_controll_board.dart` 的 `AppBar.actions` 中，「遥控」按钮之前插入：

```dart
            IconButton(
              tooltip: '时钟',
              icon: const Icon(Icons.schedule_rounded),
              onPressed: () =>
                  Injection.get<AppRouter>().push(RouteNames.clockPath),
            ),
            IconButton(
              tooltip: '直播',
              icon: const Icon(Icons.live_tv_rounded),
              onPressed: () =>
                  Injection.get<AppRouter>().push(RouteNames.livePath),
            ),
            IconButton(
              tooltip: '天气',
              icon: const Icon(Icons.cloud_outlined),
              onPressed: () =>
                  Injection.get<AppRouter>().push(RouteNames.weatherPath),
            ),
```

最终的 `actions` 顺序（自左向右）：

```
[连接状态] [刷新] [时钟] [直播] [天气] [遥控] [设置]
```

- [x] **Step 2: 分析 + 提交**

`pscreen_home/lib/main.dart` 顺带修正两处注释：`BlocProvider` 默认 `lazy: true`，
weather / iptv 两个 bloc **首次被页面读取时**才创建并派发初始事件，
因此「启动即加载」的旧描述不准确（真实行为更优：不开直播页就不会拉频道列表）。
**不加 `lazy: false`**。

Run: `cd pscreen_home && flutter analyze`
Expected: `No issues found!`
实际: `No issues found! (ran in 19.5s)`；`flutter test` → `00:26 +262: All tests passed!`

```bash
git add -A pscreen_home docs/superpowers/plans
git commit -m "feat(screen): 中控板 AppBar 增加时钟/直播/天气入口并完成 S4 验收"
git push origin feature/home_integrate
```

---

### Task 8: S4 门槛验收

**Files:**
- 无（纯验证）

- [x] **Step 1: 分析零问题**

Run: `cd pscreen_home && flutter analyze`
Expected: `No issues found!`
实际: `Analyzing pscreen_home...` → `No issues found! (ran in 19.5s)`

- [x] **Step 2: 测试全绿**

Run: `cd pscreen_home && flutter test`
Expected: 全部通过
实际: `00:26 +262: All tests passed!`

- [x] **Step 3: 构建**

Run: `cd pscreen_home && flutter build windows --debug; if ($?) { flutter build apk --debug }`
Expected: 两个都 `Built ...`
实际: `Built build\windows\x64\runner\Debug\pscreen_home.exe`；`Built build\app\outputs\flutter-apk\app-debug.apk`
（apk 构建的 media_kit libmpv jar 走本地缓存 `build/media_kit_libs_android_video/v1.1.7/`，本次一次通过，未重试。）

- [x] **Step 4: 人工验证（G18）—— 清单已产出（**待用户真机执行**）**

> 本步骤的产出是**可执行清单**（见文末「S4 完成定义 → G18 人工验证清单」）。
> 清单需要 15 寸真机 + （第 7 条）电视端真机，自动化无法覆盖，故**执行结果待人工填写**。

启动 `pscreen_home`（`flutter run -d windows`），逐项确认：

1. 中控板 AppBar 出现 **时钟 / 直播 / 天气 / 遥控** 四个新按钮（加上原有「刷新 / 设置 / 连接状态」共 7 个 action）
2. 点「时钟」→ 全屏深色大字号时钟，显示日期、星期、农历；点画面切换秒显示；左上角箭头可返回
3. 点「直播」→ 播放器区出现（16:9）；频道列表有内容；点某频道后画面切换，该行高亮跟随
4. 点「天气」→ 显示城市、温度、天气描述、湿度、风速与多日预报；右上角刷新有反应
5. 点「遥控」→ 遥控面板 + 会话两个 tab 可用
6. 点「设置」→ HA 配置 + 遥控（云信）配置都在
7. 电视端 `pscreen/potatokid_screen` 仍能正常启动、播放、显示浮层（**S4 不能破坏电视端**）

> 直播无画面时检查：`.env` 的 `BASE_URL` 与频道源可达性；`MediaKit.ensureInitialized()` 是否在 `main.dart`。
> 天气无数据时检查：`.env` 的 `SENIVERSE_*` 键与「定位失败」分支。
> 时钟无农历时检查：共享包 `lunarDateOf` 只覆盖 1900–2099。

- [x] **Step 5: 提交（若本任务改了文件）**

```bash
git status --short
```

---

## S4 完成定义

### 门槛结果（实际输出）

| # | 门槛 | 结果 | 证据（实际输出） |
| --- | --- | --- | --- |
| G15 | `pscreen_home` analyze 零问题 | ✅ PASS | `Analyzing pscreen_home...` → `No issues found! (ran in 19.5s)` |
| G16 | `pscreen_home` test 全绿 | ✅ PASS | `00:26 +262: All tests passed!` |
| G17 | windows + apk 构建成功 | ✅ PASS | `Built build\windows\x64\runner\Debug\pscreen_home.exe`；`Built build\app\outputs\flutter-apk\app-debug.apk` |
| G18 | 三个页面人工验证通过 | ⏳ **待人工验证** | 需 15 寸真机（+ 电视端），可执行清单见下 |

- [x] G15 `pscreen_home` analyze 零问题
- [x] G16 `pscreen_home` test 全绿
- [x] G17 windows + apk 构建成功
- [ ] G18 三个页面人工验证通过 —— **待人工验证**（清单见下，执行结果待回填）
- [x] 中控板 AppBar 五个入口（时钟 / 直播 / 天气 / 遥控 / 设置）代码侧全部落地（按钮已加、路由已注册）；页面可用性随 G18 人工确认

### 附加检查（实际输出）

| 检查项 | 命令 | 结果 |
| --- | --- | --- |
| 共享包 analyze | `cd packages/pscreen_screen; flutter analyze` | ✅ `No issues found! (ran in 9.1s)` |
| 共享包 test | `cd packages/pscreen_screen; flutter test` | ✅ `00:11 +122: All tests passed!` |
| 电视端 analyze | `cd pscreen/potatokid_screen; flutter analyze --no-pub` | ✅ `No issues found! (ran in 21.4s)` |
| 电视端 test | `cd pscreen/potatokid_screen; flutter test --no-pub` | ✅ `00:00 +2: All tests passed!` |
| 电视端 windows 构建 | `cd pscreen/potatokid_screen; flutter build windows --debug` | ✅ `Built build\windows\x64\runner\Debug\potatokid_screen.exe` |
| 旧包引用清零 | grep `package:pscreen_control`（`pscreen_home/lib`、`pscreen_home/test`、`packages/pscreen_screen/`） | ✅ **0 hits** |
| 包不依赖宿主 | grep `package:pscreen_home`（`packages/pscreen_screen/`） | ✅ **0 hits** |
| 锁文件未污染 | `pscreen_home/pubspec.lock`、`pscreen/potatokid_screen/pubspec.lock`、`packages/pscreen_screen/pubspec.lock` | ✅ 三份均为 `pub.dev` **0 处**（全部 `pub.flutter-io.cn`：127 / 155 / 128 处） |

### G18 人工验证清单（**请在真机上执行，勾选后回填**）

> 环境：15 寸 Android 触屏面板（`pscreen_home`，1920×1080）；第 7 条另需电视端 `pscreen/potatokid_screen`。
> 启动：`cd pscreen_home; flutter run`（或 `flutter run -d windows` 桌面模拟）。

| # | 操作 | 预期现象 | 若不满足，优先查这里 |
| --- | --- | --- | --- |
| 1 | 启动 `pscreen_home` → 观察中控板 AppBar | 出现 **时钟 / 直播 / 天气 / 遥控** 四个新按钮（连同原有「刷新 / 设置 / 连接状态」共 7 个 action，无重叠、无截断） | 按钮是否渲染 → `home_controll_board.dart` 的 `AppBar.actions`；点击无响应 → `RouteNames.clockPath / livePath / weatherPath` 与 `app_router.dart` 的路由注册 |
| 2 | 点「时钟」 | 全屏深色大字号时钟；显示日期、星期、农历；**点画面切换秒显示**；左上角箭头可返回中控台 | 无农历 → 共享包 `lunarDateOf` 只覆盖 1900–2099；秒不切换 → `clock_page.dart` 的点击手势；返回失效 → `Navigator` 栈 / 路由 `pop` |
| 3 | 点「直播」 | 播放器区出现（16:9）；频道列表有内容；**点某频道后画面切换**，该行高亮跟随 | 无画面 → `.env` 的 `BASE_URL` 与频道源可达性；`MediaKit.ensureInitialized()` 是否在 `main.dart`；列表空 → `IptvBloc` 的 `LoadIptv(useCache: true)` 与缓存目录权限 |
| 4 | 点「天气」 | 显示城市、温度、天气描述、湿度、风速与多日预报；右上角刷新有反应 | 无数据 → `.env` 的 `SENIVERSE_*` 键是否齐全，以及「定位失败」分支（手动指定城市）；刷新无反应 → `WeatherBloc` 的 `LoadWeather` 事件是否派发 |
| 5 | 点「遥控」 | 遥控面板 + 会话两个 tab 可用 | 扫码/绑定失败 → `nim_core_v2` 原生注册与相机权限；无会话 → `NimManager` 初始化与自动登录（`NIM_PASSWORD` / 账号） |
| 6 | 点「设置」 | HA 配置 + 遥控（云信）配置都在 | 配置项缺失 → `settings_page.dart` 的分组；保存不生效 → `SettingsStore` 持久化 |
| 7 | 启动电视端 `pscreen/potatokid_screen` | 正常启动、正常播放、浮层正常显示（**S4 不能破坏电视端**） | 电视端异常 → 共享包 `packages/pscreen_screen` 的改动（`flutter analyze --no-pub` 与 `flutter test --no-pub` 已全绿，若仍异常则回滚对照） |

### 已知遗留（不在 S4 范围）

- `pscreen_control/` 目录保留作为回退路径，README 顶部已标注「已废弃」；**不删除**（见设计文档 §十 风险 8）。
- `pscreen/potatokid_screen/.env` 仍被 Git 跟踪（历史遗留，仓库内含明文密钥）；`pscreen_home/.env` 已被 `.gitignore` 排除。轮换与 `git rm --cached` 需单独决策。

---

## 全流程完成定义（S1–S4 全部结束）

- [x] `packages/pscreen_screen` 存在且被两个 App 共同依赖
      （`pscreen_home/pubspec.yaml` → `path: ../packages/pscreen_screen`；`pscreen/potatokid_screen/pubspec.yaml` → `path: ../../packages/pscreen_screen`）
- [x] `pscreen/potatokid_screen` 仍可独立构建发布（电视端产物不受影响）
      （S4 后复核：`flutter analyze --no-pub` → `No issues found!`；`flutter test --no-pub` → `+2: All tests passed!`；`flutter build windows --debug` → `Built ...\potatokid_screen.exe`）
- [x] `pscreen_home` 一个包内具备：HA 中控 + 时钟 + 直播 + 天气 + 遥控 + 设置
      （页面与路由均在 `pscreen_home/lib/features/screen/`，AppBar 入口见 Task 7；可用性待 G18 真机确认）
- [x] `pscreen_control` 已标注废弃，代码全部并入
      （`pscreen_control/README.md` 顶部「已废弃」说明；代码迁至 `pscreen_home/lib/features/remote_control/`）
- [ ] `docs/superpowers/specs/2026-10-21-screen-capability-shared-package-design.md` 的验收项全部达成
      （§十 风险 1–8 均已闭环；余下仅 G14 / G18 两项**真机人工验证**待用户执行）

