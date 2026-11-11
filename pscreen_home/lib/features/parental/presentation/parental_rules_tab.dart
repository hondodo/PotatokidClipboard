import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pscreen_home/features/parental/data/parental_admin_api.dart';
import 'package:pscreen_home/features/parental/domain/parental_config.dart';
import 'package:pscreen_home/features/parental/presentation/parental_common.dart';
import 'package:pscreen_home/features/parental/presentation/parental_quiz_editor.dart';
import 'package:pscreen_home/features/parental/presentation/parental_sections.dart';
import 'package:pscreen_home/features/parental/presentation/parental_subpages.dart';

/// Tab 二：规则（孩子列表 + 全局设置）。
///
/// 孩子档案 CRUD 复用 [ChildrenSection]（含按档位显隐字段、题库入口）；
/// 全局解锁方式作为独立下钻页，避免与单台电视配置混在一起。
class ParentalRulesView extends StatelessWidget {
  const ParentalRulesView({
    super.key,
    required this.config,
    required this.selected,
    required this.actions,
  });

  final ParentalConfig config;
  final ParentalMachine? selected;
  final ParentalActions actions;

  Future<void> _openFirstChildQuiz(BuildContext context) async {
    if (selected == null || config.children.isEmpty) return;
    await ParentalQuizEditorSheet.show(
      context,
      deviceId: selected!.id,
      child: config.children.first,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: <Widget>[
        ChildrenSection(
          config: config,
          onSave: actions.saveConfig,
          deviceId: selected?.id,
          shrinkWrap: true,
        ),
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '全局设置',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('解锁方式'),
                  subtitle: Text(unlockModeLabel(config.unlockMode)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => unawaited(actions.push(ParentalRulesSettingsPage(
                    config: config,
                    machine: selected,
                    onSave: actions.saveConfig,
                  ))),
                ),
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('答题题库'),
                  subtitle: const Text('在「儿童档案」卡片里维护，按孩子分库'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => unawaited(_openFirstChildQuiz(context)),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
