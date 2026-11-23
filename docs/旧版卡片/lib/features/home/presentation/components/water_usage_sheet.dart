import 'package:flutter/material.dart';
import 'package:pscreen_home/core/di/injection.dart';
import 'package:pscreen_home/features/home/domain/models/water_usage_record.dart';
import 'package:pscreen_home/features/home/domain/repositories/home_repository.dart';

/// 使用记录周期
enum UsagePeriod {
  week('周'),
  month('月'),
  year('年');

  const UsagePeriod(this.label);

  final String label;
}

/// 热水器使用记录面板：周 / 月 / 年，用水 / 用气柱状图与合计。
///
/// 数据来自 HA `history/history_during_period` 的 `event.*_usage_record`
/// 历史；米家的周/月/年就是这些单次记录的和。
class WaterUsageSheet extends StatefulWidget {
  const WaterUsageSheet({
    super.key,
    required this.entityId,
    required this.title,
  });

  final String entityId;
  final String title;

  @override
  State<WaterUsageSheet> createState() => _WaterUsageSheetState();
}

class _WaterUsageSheetState extends State<WaterUsageSheet> {
  UsagePeriod _period = UsagePeriod.week;
  bool _loading = true;
  String? _error;
  List<WaterUsageRecord> _records = const <WaterUsageRecord>[];
  int _requestId = 0;

  static const Color _waterColor = Color(0xFF64B5F6);
  static const Color _gasColor = Color(0xFFFFB74D);

  @override
  void initState() {
    super.initState();
    _load();
  }

  (DateTime, DateTime) get _range {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime start = switch (_period) {
      UsagePeriod.week =>
        today.subtract(Duration(days: now.weekday % 7)),
      UsagePeriod.month => DateTime(now.year, now.month, 1),
      UsagePeriod.year => DateTime(now.year, 1, 1),
    };
    final DateTime end = DateTime(
      now.year,
      now.month,
      now.day,
      23,
      59,
      59,
    );
    return (start, end);
  }

  Future<void> _load() async {
    final (DateTime start, DateTime end) = _range;
    final int request = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<WaterUsageRecord> records =
          await Injection.get<HomeRepository>().fetchWaterUsageRecords(
        entityId: widget.entityId,
        start: start,
        end: end,
      );
      if (!mounted || request != _requestId) return;
      setState(() {
        _records = records;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || request != _requestId) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final (DateTime start, DateTime end) = _range;
    final List<_Bucket> buckets = _buildBuckets(start, end);
    final double water = _records.fold<double>(
      0,
      (double sum, WaterUsageRecord r) => sum + r.waterLiters,
    );
    final double gas = _records.fold<double>(
      0,
      (double sum, WaterUsageRecord r) => sum + r.gasCubicMeters,
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '使用记录 · ${widget.title}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: '关闭',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SegmentedButton<UsagePeriod>(
            segments: UsagePeriod.values
                .map((UsagePeriod p) => ButtonSegment<UsagePeriod>(
                      value: p,
                      label: Text(p.label),
                    ))
                .toList(growable: false),
            selected: <UsagePeriod>{_period},
            showSelectedIcon: false,
            onSelectionChanged: (Set<UsagePeriod> value) {
              setState(() => _period = value.first);
              _load();
            },
          ),
          const SizedBox(height: 10),
          Text(
            _rangeLabel(start, end),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                '读取历史失败：$_error',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            )
          else ...<Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: _TotalCard(
                    label: '用水量',
                    value: _formatWater(water),
                    unit: 'L',
                    color: _waterColor,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _TotalCard(
                    label: '用气量',
                    value: _formatGas(gas),
                    unit: 'm³',
                    color: _gasColor,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _TotalCard(
                    label: '用水次数',
                    value: '${_records.length}',
                    unit: '次',
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_records.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Text(
                    '这段时间没有使用记录',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ),
              )
            else ...<Widget>[
              _UsageChart(
                title: '用水量',
                unit: 'L',
                color: _waterColor,
                buckets: buckets,
                valueOf: (_Bucket b) => b.water,
                formatValue: _formatWater,
              ),
              const SizedBox(height: 22),
              _UsageChart(
                title: '用气量',
                unit: 'm³',
                color: _gasColor,
                buckets: buckets,
                valueOf: (_Bucket b) => b.gas,
                formatValue: _formatGas,
              ),
            ],
          ],
        ],
      ),
    );
  }

  List<_Bucket> _buildBuckets(DateTime start, DateTime end) {
    final DateTime now = DateTime.now();
    if (_period == UsagePeriod.week) {
      final List<_Bucket> buckets = <_Bucket>[];
      for (int i = 0; i < 7; i++) {
        final DateTime day = start.add(Duration(days: i));
        buckets.add(_Bucket(
          label: '${day.month}/${day.day}',
          water: _sum(day, day.add(const Duration(days: 1)), true),
          gas: _sum(day, day.add(const Duration(days: 1)), false),
        ));
      }
      return buckets;
    }
    if (_period == UsagePeriod.month) {
      final List<_Bucket> buckets = <_Bucket>[];
      final int days = now.day;
      for (int i = 1; i <= days; i++) {
        final DateTime day = DateTime(now.year, now.month, i);
        buckets.add(_Bucket(
          label: '$i',
          water: _sum(day, day.add(const Duration(days: 1)), true),
          gas: _sum(day, day.add(const Duration(days: 1)), false),
        ));
      }
      return buckets;
    }
    final List<_Bucket> buckets = <_Bucket>[];
    for (int month = 1; month <= 12; month++) {
      final DateTime from = DateTime(now.year, month, 1);
      final DateTime to = DateTime(now.year, month + 1, 1);
      buckets.add(_Bucket(
        label: '$month月',
        water: _sum(from, to, true),
        gas: _sum(from, to, false),
      ));
    }
    return buckets;
  }

  double _sum(DateTime from, DateTime to, bool water) {
    double sum = 0;
    for (final WaterUsageRecord record in _records) {
      if (record.timestamp.isBefore(from) ||
          !record.timestamp.isBefore(to)) {
        continue;
      }
      sum += water ? record.waterLiters : record.gasCubicMeters;
    }
    return sum;
  }

  String _rangeLabel(DateTime start, DateTime end) {
    if (_period == UsagePeriod.year) {
      return '${start.year}年1月–${end.month}月';
    }
    return '${start.month}月${start.day}日–${end.month}月${end.day}日';
  }

  static String _formatWater(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);

  static String _formatGas(double value) {
    if (value == 0) return '0';
    if (value < 0.001) return value.toStringAsFixed(4);
    if (value < 1) return value.toStringAsFixed(3);
    return value.toStringAsFixed(2);
  }
}

class _Bucket {
  const _Bucket({
    required this.label,
    required this.water,
    required this.gas,
  });

  final String label;
  final double water;
  final double gas;
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  final String label;
  final String value;
  final String unit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 2),
          Text.rich(
            TextSpan(
              children: <InlineSpan>[
                TextSpan(
                  text: value,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                TextSpan(
                  text: ' $unit',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UsageChart extends StatelessWidget {
  const _UsageChart({
    required this.title,
    required this.unit,
    required this.color,
    required this.buckets,
    required this.valueOf,
    required this.formatValue,
  });

  final String title;
  final String unit;
  final Color color;
  final List<_Bucket> buckets;
  final double Function(_Bucket) valueOf;
  final String Function(double) formatValue;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double maxValue = buckets
        .map(valueOf)
        .fold<double>(0, (double max, double v) => v > max ? v : max);
    final bool sparse = buckets.length > 14;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '$title（$unit）',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 150,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              for (int i = 0; i < buckets.length; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        if (!sparse && valueOf(buckets[i]) > 0)
                          Text(
                            formatValue(valueOf(buckets[i])),
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontSize: 8,
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        const SizedBox(height: 2),
                        Container(
                          height: maxValue == 0
                              ? 2
                              : (valueOf(buckets[i]) / maxValue) * 110,
                          decoration: BoxDecoration(
                            color: valueOf(buckets[i]) == 0
                                ? theme.colorScheme.surfaceContainerHighest
                                : color,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(3),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          sparse && i % 5 != 0 && i != buckets.length - 1
                              ? ''
                              : buckets[i].label,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 8,
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
