import 'dart:math';

import 'package:dart_eval/dart_eval.dart';
import 'package:decimal/decimal.dart';
import 'package:get/get.dart';
import 'package:potatokid_clipboard/framework/base/base_get_vm.dart';
import 'package:flutter/material.dart';

class CalcResult {
  final num value;
  // 是否超过处理精度
  final bool isOverPrecision;
  final String errorMessage;
  final String valueString;
  final bool isError;
  CalcResult(
      {required this.value,
      required this.isOverPrecision,
      required this.errorMessage,
      required this.valueString,
      required this.isError});
}

class CalcController extends BaseGetVM {
  RxList<String> expressionHistory = <String>[].obs;
  String currentExpression = '';
  final ScrollController scrollController = ScrollController();
  List<String> operatorList = ['+', '-', '*', '/', '%', '×', '÷'];

  void onKeyboardNumberPressed(String text) {
    currentExpression += text;
    updateExpressionHistory();
  }

  void onKeyboardOperatorPressed(String text) {
    if (currentExpression.isNotEmpty) {
      String lastChar =
          currentExpression.substring(currentExpression.length - 1);
      if (operatorList.contains(lastChar)) {
        currentExpression =
            currentExpression.substring(0, currentExpression.length - 1);
      }
    }
    for (String operator in operatorList) {
      if (currentExpression.contains(operator)) {
        onKeyboardEqualPressed();
      }
    }
    currentExpression += text;
    updateExpressionHistory();
    if (text == '%') {
      onKeyboardEqualPressed();
    }
  }

  void onDotPressed() {
    if (currentExpression.contains('.')) {
      return;
    }
    while (currentExpression.startsWith('0')) {
      currentExpression = currentExpression.substring(1);
    }
    if (currentExpression.isEmpty) {
      currentExpression = '0';
    }
    while (currentExpression.endsWith('.')) {
      currentExpression =
          currentExpression.substring(0, max(0, currentExpression.length - 1));
    }
    if (currentExpression.startsWith('.')) {
      currentExpression = '0$currentExpression';
    }
    currentExpression += '.';
    updateExpressionHistory();
  }

  void onKeyboardEqualPressed() {
    if (currentExpression.isEmpty) {
      return;
    }
    String expression = currentExpression;
    expression = expression
        .replaceAll('×', '*')
        .replaceAll('÷', '/')
        .replaceAll('%', '/100.0');
    CalcResult result = evaluateExpression(expression);
    bool isError = result.isError;
    String resultString = isError ? '出错了'.tr : result.valueString;
    expressionHistory.add('$currentExpression=$resultString');
    currentExpression = isError ? '' : resultString;
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
      final result = eval(expression);
      return _formatNumber(result);
    } catch (e) {
      return CalcResult(
          value: 0,
          isError: true,
          isOverPrecision: false,
          errorMessage: e.toString(),
          valueString: '');
    }
  }

  /// 格式化数字，去除浮点数精度误差和尾随零
  CalcResult _formatNumber(num value) {
    if (value is int) {
      return CalcResult(
          value: value,
          isOverPrecision: false,
          errorMessage: '',
          isError: false,
          valueString: _formatNumberForDisplay(value));
    }

    // 检测到精度误差，尝试智能四舍五入
    final absValue = value.abs();

    // 从高精度到低精度尝试，找到最合理的表示
    // 最多尝试15位小数精度
    for (int precision = 15; precision >= 0; precision--) {
      final rounded = double.parse(value.toStringAsFixed(precision));
      // 检查四舍五入后的值是否足够接近原值
      final error = (rounded - value).abs();
      // 使用绝对误差和相对误差的组合来判断
      final threshold = absValue > 1 ? 1e-10 : 1e-15;
      if (error < threshold) {
        return CalcResult(
            value: rounded,
            isOverPrecision: false,
            errorMessage: '',
            valueString: _formatNumberForDisplay(rounded),
            isError: false);
      }
    }

    return CalcResult(
        value: value,
        isOverPrecision: true,
        errorMessage: '',
        valueString: _formatNumberForDisplay(value),
        isError: false);
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

    // 对于浮点数，使用 toStringAsFixed 然后去除尾随零
    String formatted = value.toStringAsFixed(15);

    // 去除尾随零
    if (formatted.contains('.')) {
      formatted = formatted.replaceAll(RegExp(r'0+$'), '');
      formatted = formatted.replaceAll(RegExp(r'\.$'), '');
    }

    return formatted;
  }
}
