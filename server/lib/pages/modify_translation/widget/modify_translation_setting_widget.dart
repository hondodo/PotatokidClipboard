import 'package:flutter/material.dart';

class ModifyTranslationSettingModel {
  // appName
  final String appName;
  // 自动保存间隔（分）当为null时，不自动保存
  final int? autoSaveInterval;
  // 使用说明
  final String howToUseDescription;

  ModifyTranslationSettingModel({
    required this.appName,
    required this.autoSaveInterval,
    required this.howToUseDescription,
  });
}

class ModifyTranslationSettingWidget extends StatefulWidget {
  const ModifyTranslationSettingWidget({
    super.key,
    required this.model,
    required this.onSaveSetting,
  });

  final ModifyTranslationSettingModel model;
  final Function(ModifyTranslationSettingModel newConfig) onSaveSetting;

  @override
  State<ModifyTranslationSettingWidget> createState() =>
      _ModifyTranslationSettingWidgetState();
}

class _ModifyTranslationSettingWidgetState
    extends State<ModifyTranslationSettingWidget> {
  int? _selectedInterval;

  @override
  void initState() {
    super.initState();
    _selectedInterval = widget.model.autoSaveInterval;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.8, // 限制最大高度为屏幕的80%
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            Row(
              children: [
                const Icon(Icons.settings, color: Colors.blue),
                const SizedBox(width: 8),
                const Text(
                  '翻译设置',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // 自动保存设置
            const Text(
              '自动保存设置',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),

            // 定时保存选项
            ..._buildAutoSaveOptions(),

            const SizedBox(height: 24),

            // 使用说明
            const Text(
              '使用说明',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Text(
                widget.model.howToUseDescription,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ),

            const SizedBox(height: 24),

            // 保存按钮
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final newConfig = ModifyTranslationSettingModel(
                    appName: widget.model.appName,
                    autoSaveInterval: _selectedInterval,
                    howToUseDescription: widget.model.howToUseDescription,
                  );
                  widget.onSaveSetting(newConfig);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  '保存设置',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),

            // 底部安全区域
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildAutoSaveOptions() {
    final options = [
      {'label': '关闭自动保存', 'value': null},
      {'label': '1分钟', 'value': 1},
      {'label': '3分钟', 'value': 3},
      {'label': '5分钟', 'value': 5},
      {'label': '10分钟', 'value': 10},
    ];

    return options.map((option) {
      final value = option['value'] as int?;
      final label = option['label'] as String;
      final isSelected = _selectedInterval == value;

      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        child: InkWell(
          onTap: () {
            setState(() {
              _selectedInterval = value;
            });
          },
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected ? Colors.blue.shade50 : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? Colors.blue : Colors.grey.shade300,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isSelected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: isSelected ? Colors.blue : Colors.grey,
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    color: isSelected ? Colors.blue : Colors.black87,
                    fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }).toList();
  }
}
