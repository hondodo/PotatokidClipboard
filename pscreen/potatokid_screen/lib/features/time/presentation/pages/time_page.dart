import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// 「时间」Tab 占位页：后续在此实现时间 / 日程相关功能。
class TimePage extends StatelessWidget {
  const TimePage({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            Icons.schedule_outlined,
            size: 64,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text('time_title'.tr(), style: theme.textTheme.headlineSmall),
        ],
      ),
    );
  }
}
