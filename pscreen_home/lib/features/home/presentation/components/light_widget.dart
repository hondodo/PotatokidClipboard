import 'package:flutter/material.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/presentation/components/button_widget.dart';

/// 灯光类控件：开 = 暖黄光晕，关 = 灰暗，复用 [ButtonWidget] 的卡片结构。
class LightWidget extends StatelessWidget {
  const LightWidget({
    super.key,
    required this.entity,
    required this.isToggling,
    required this.onToggle,
    this.areaLabel,
  });

  final HaEntityStateModel entity;
  final bool isToggling;
  final VoidCallback onToggle;
  final String? areaLabel;

  @override
  Widget build(BuildContext context) {
    return ButtonWidget(
      entity: entity,
      isToggling: isToggling,
      onToggle: onToggle,
      areaLabel: areaLabel,
      icon: Icons.lightbulb_rounded,
      activeColor: Colors.amber,
    );
  }
}
