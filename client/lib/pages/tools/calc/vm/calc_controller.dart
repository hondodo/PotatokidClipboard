import 'dart:math';

import 'package:dart_eval/dart_eval.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:potatokid_clipboard/framework/base/base_get_vm.dart';
import 'package:flutter/material.dart';
import 'package:potatokid_clipboard/utils/calc_voice_helper.dart';
import 'package:vibration/vibration.dart';

class CalcResult {
  final num value;
  // 是否超过处理精度
  final bool isOverPrecision;
  final String errorMessage;
  final String valueString;
  final bool isError;
  final String expression;
  CalcResult(
      {required this.value,
      required this.isOverPrecision,
      required this.errorMessage,
      required this.valueString,
      required this.isError,
      required this.expression});

  String getExpressionText() {
    if (isError) {
      return '@expression=@error'
          .trParams({'expression': expression, 'error': '出错了'.tr});
    }
    return '$expression=$valueString';
  }
}

class CalcController extends BaseGetVM {
  RxList<CalcResult> expressionHistory = <CalcResult>[].obs;
  String currentExpression = '';
  final ScrollController scrollController = ScrollController();
  List<String> operatorList = ['+', '-', '*', '/', '%', '×', '÷'];
  List<CalcVoiceType> voiceTypeList = [
    CalcVoiceType.putonghua,
    CalcVoiceType.yinyue,
    CalcVoiceType.yueyu
  ];
  final currentVoiceTypeIndex = 0.obs;

  void onKeyTabDownFeedback() {
    Vibration.vibrate(duration: 20, amplitude: 255, sharpness: 1.0);
  }

  void onKeyTabUpFeedback() {}

  bool isEndWithOperator(String expression) {
    if (expression.isEmpty) {
      return false;
    }
    return operatorList.contains(expression.substring(expression.length - 1));
  }

  bool isContainOperator(String expression) {
    for (String op in operatorList) {
      if (expression.contains(op)) {
        return true;
      }
    }
    return false;
  }

  String removeFirstZero(String numbers) {
    while (numbers.startsWith('0')) {
      numbers = numbers.substring(1);
    }
    if (numbers.startsWith('.')) {
      numbers = '0$numbers';
    }
    if (numbers.isEmpty) {
      numbers = '0';
    }
    // 如果超过两个.，那么只保留第一个.
    if (numbers.contains('.')) {
      var dotParts = numbers.split('.');
      if (dotParts.length > 2) {
        numbers = '${dotParts[0]}.${dotParts[1]}';
        for (int i = 2; i < dotParts.length; i++) {
          numbers += dotParts[i];
        }
      }
    }
    return numbers;
  }

  void onKeyboardNumberPressed(String text) {
    currentExpression += text;
    bool hasChanged = false;
    for (String op in operatorList) {
      if (currentExpression.contains(op)) {
        var parts = currentExpression.split(op);
        if (parts.length > 1) {
          var newParts = parts.map((part) => removeFirstZero(part)).toList();
          currentExpression = newParts.join(op);
          hasChanged = true;
        }
      }
    }
    if (!hasChanged) {
      currentExpression = removeFirstZero(currentExpression);
    }
    updateExpressionHistory();
  }

  void onKeyboardOperatorPressed(String text) {
    while (currentExpression.endsWith('.')) {
      currentExpression =
          currentExpression.substring(0, currentExpression.length - 1);
    }
    if (currentExpression.isNotEmpty) {
      String lastChar =
          currentExpression.substring(currentExpression.length - 1);
      if (operatorList.contains(lastChar)) {
        currentExpression =
            currentExpression.substring(0, currentExpression.length - 1);
      }
    }
    if (currentExpression.isEmpty) {
      currentExpression = '0';
    }
    if (text != '%') {
      for (String operator in operatorList) {
        if (currentExpression.contains(operator)) {
          calcCurrentExpression();
        }
      }
    }
    currentExpression += text;
    updateExpressionHistory();
    if (text == '%') {
      calcCurrentExpression();
    }
  }

  void onKeyboardEqualPressed() {
    if (currentExpression.endsWith('.')) {
      currentExpression =
          currentExpression.substring(0, currentExpression.length - 1);
    } else if (!currentExpression.endsWith('%') &&
        isEndWithOperator(currentExpression)) {
      currentExpression =
          currentExpression.substring(0, currentExpression.length - 1);
    }
    calcCurrentExpression();
  }

  void calcCurrentExpression() {
    if (currentExpression.isEmpty) {
      return;
    }
    String expression = currentExpression;
    CalcResult result = evaluateExpression(expression);
    bool isError = result.isError;
    expressionHistory.add(result);
    currentExpression = isError ? '' : result.valueString;
    updateExpressionHistory();
  }

  void onKeyboardBackspacePressed() {
    if (currentExpression.isEmpty) {
      return;
    }
    currentExpression =
        currentExpression.substring(0, max(0, currentExpression.length - 1));
    updateExpressionHistory();
  }

  void onKeyboardClearPressed() {
    currentExpression = '';
    updateExpressionHistory();
  }

  CalcResult evaluateExpression(String expression) {
    try {
      var calcExpression = expression
          .replaceAll('×', '*')
          .replaceAll('÷', '/')
          .replaceAll('%', '/100.0');
      final result = eval(calcExpression);
      return _formatNumber(result, expression);
    } catch (e) {
      return CalcResult(
          value: 0,
          isError: true,
          isOverPrecision: false,
          errorMessage: e.toString(),
          valueString: '',
          expression: expression);
    }
  }

  /// 格式化数字，去除浮点数精度误差和尾随零
  CalcResult _formatNumber(num value, String rawExpression) {
    if (value is int) {
      return CalcResult(
          value: value,
          isOverPrecision: false,
          errorMessage: '',
          isError: false,
          valueString: _formatNumberForDisplay(value),
          expression: rawExpression);
    }

    // 检测到精度误差，尝试智能四舍五入
    final absValue = value.abs();

    // 使用更精确的方法：从低精度到高精度尝试，找到最接近的简单表示
    // 这样可以优先找到像 566.04 这样的简单小数，而不是 566.040000000000077
    for (int precision = 0; precision <= 15; precision++) {
      // 使用数学方法进行四舍五入，避免字符串转换带来的精度误差
      final multiplier = pow(10, precision);
      final rounded = (value * multiplier).round() / multiplier;

      // 检查四舍五入后的值是否足够接近原值
      final error = (rounded - value).abs();
      // 使用更宽松的阈值，因为浮点数精度误差通常很小
      // 对于接近整数的值使用更严格的阈值
      final threshold = absValue > 1 ? max(1e-10, absValue * 1e-14) : 1e-15;

      if (error < threshold) {
        return CalcResult(
            value: rounded,
            isOverPrecision: false,
            errorMessage: '',
            valueString: _formatNumberForDisplay(rounded),
            expression: rawExpression,
            isError: false);
      }
    }

    return CalcResult(
        value: value,
        isOverPrecision: true,
        errorMessage: '',
        valueString: _formatNumberForDisplay(value),
        isError: false,
        expression: rawExpression);
  }

  void updateExpressionHistory() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scrollController.jumpTo(
        scrollController.position.maxScrollExtent,
      );
    });
    expressionHistory.refresh();
  }

  String getCurrentExpressionText() {
    if (currentExpression.isEmpty) {
      return '0';
    }
    return currentExpression;
  }

  /// 格式化数字用于显示，去除尾随零
  String _formatNumberForDisplay(num value) {
    if (value is int) {
      return value.toString();
    }

    // 对于浮点数，使用更智能的方法来格式化
    // 先尝试找到合适的小数位数，避免使用 toStringAsFixed(15) 带来的精度误差

    // 如果值非常接近整数，直接显示为整数
    if ((value - value.round()).abs() < 1e-10) {
      return value.round().toString();
    }

    // 尝试从少到多的小数位数，找到最简洁的表示
    for (int precision = 0; precision <= 15; precision++) {
      final multiplier = pow(10, precision);
      final rounded = (value * multiplier).round() / multiplier;

      // 如果四舍五入后的值足够接近原值，使用这个精度
      if ((rounded - value).abs() < 1e-10) {
        // 使用字符串格式化，但只使用必要的精度
        String formatted = rounded.toStringAsFixed(precision);

        // 去除尾随零
        if (formatted.contains('.')) {
          formatted = formatted.replaceAll(RegExp(r'0+$'), '');
          formatted = formatted.replaceAll(RegExp(r'\.$'), '');
        }

        return formatted;
      }
    }

    // 如果以上方法都失败，使用默认的 toString 方法
    // 但先尝试去除可能的尾随零
    String formatted = value.toString();
    if (formatted.contains('.')) {
      formatted = formatted.replaceAll(RegExp(r'0+$'), '');
      formatted = formatted.replaceAll(RegExp(r'\.$'), '');
    }
    return formatted;
  }

  Future<void> onTabLine(String line) async {
    await Clipboard.setData(ClipboardData(text: line));
    showSuccess(
      '已复制@line到剪贴板'.trParams({
        'line': line,
      }),
      timeout: 1000,
    );
  }

  Future<void> onTabExpressionHistory(CalcResult result) async {
    if (isContainOperator(currentExpression)) {
      if (result.isError) {
        return;
      }
      // 将 123+456-567 拆为 123+456 和 567 两部分，只保留123+456-部分，将567替换为result.valueString
      // +/- 是operatorList任意一个操作符
      // 从后往前遍历，找到第一个 +/- 操作符，将 +/- 操作符前的部分替换为result.valueString
      for (int i = currentExpression.length - 1; i >= 0; i--) {
        if (operatorList.contains(currentExpression[i])) {
          currentExpression = currentExpression.substring(0, i) +
              currentExpression[i] +
              result.valueString;
          break;
        }
      }
    } else {
      if (result.isError) {
        currentExpression = result.expression;
      } else {
        currentExpression = result.valueString;
      }
    }
    updateExpressionHistory();
  }

  Future<void> onLongPressExpressionHistory(CalcResult result) async {
    if (result.isError) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: result.valueString));
    showSuccess(
      '已复制@line到剪贴板'.trParams({
        'line': result.valueString,
      }),
      timeout: 1000,
    );
  }

  void onVoiceTypePressed() {
    int index = currentVoiceTypeIndex.value;
    index++;
    if (index >= voiceTypeList.length) {
      index = 0;
    }
    currentVoiceTypeIndex.value = index;
  }

  void onVoiceItemPressed(CalcVoiceItem item) {
    CalcVoiceHelper.instance
        .playVoice(voiceTypeList[currentVoiceTypeIndex.value], item);
  }
}
