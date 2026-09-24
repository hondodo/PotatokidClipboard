// ignore_for_file: constant_identifier_names

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:potatokid_clipboard/components/app_button_new.dart';
import 'package:potatokid_clipboard/framework/base/base_stateless_sub_widget.dart';
import 'package:potatokid_clipboard/framework/theme/app_text_theme.dart';
import 'package:potatokid_clipboard/pages/tools/calc/vm/calc_controller.dart';
import 'package:potatokid_clipboard/utils/calc_voice_helper.dart';

const double KeyboardPaddingLeft = 16;
const double KeyboardPaddingRight = 16;
const double KeyboardSpacing = 8;
const double KeyboardHeight = 42;
const int KeyboardColumnCount = 4;

class CalcPage extends BaseStatelessSubWidget<CalcController> {
  const CalcPage({super.key});

  @override
  Widget buildBody(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, top: 16),
            child: ListView.builder(
                controller: controller.scrollController,
                itemBuilder: (context, index) {
                  if (index >= controller.expressionHistory.length) {
                    return GestureDetector(
                      onTap: () {
                        controller
                            .onTabLine(controller.getCurrentExpressionText());
                      },
                      child: Text(
                        controller.getCurrentExpressionText(),
                        style: AppTextTheme.textStyle.title.resize(
                          AppTextTheme.fontSizeXXXXXXXLarge,
                        ),
                      ),
                    );
                  } else {
                    return GestureDetector(
                      onTap: () {
                        controller.onTabExpressionHistory(
                            controller.expressionHistory[index]);
                      },
                      onLongPress: () {
                        controller.onLongPressExpressionHistory(
                            controller.expressionHistory[index]);
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          controller.expressionHistory[index]
                              .getExpressionText(),
                          style: AppTextTheme.textStyle.title.hint
                              .resize(AppTextTheme.fontSizeSmall),
                        ),
                      ),
                    );
                  }
                },
                itemCount: controller.expressionHistory.length + 1),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: KeyboardColumnCount,
            crossAxisSpacing: KeyboardSpacing,
            mainAxisSpacing: KeyboardSpacing,
            childAspectRatio: (Get.width - 32 - (KeyboardSpacing * 3)) /
                (KeyboardColumnCount * KeyboardHeight),
            children: [
              _buildKeyboard(item: CalcVoiceItem.functionClear),
              _buildKeyboard(item: CalcVoiceItem.functionBackspace),
              _buildKeyboard(item: CalcVoiceItem.operatorPercent),
              _buildKeyboard(item: CalcVoiceItem.operatorDivide),
              _buildKeyboard(item: CalcVoiceItem.number7),
              _buildKeyboard(item: CalcVoiceItem.number8),
              _buildKeyboard(item: CalcVoiceItem.number9),
              _buildKeyboard(item: CalcVoiceItem.operatorMultiply),
              _buildKeyboard(item: CalcVoiceItem.number4),
              _buildKeyboard(item: CalcVoiceItem.number5),
              _buildKeyboard(item: CalcVoiceItem.number6),
              _buildKeyboard(item: CalcVoiceItem.operatorSubtract),
              _buildKeyboard(item: CalcVoiceItem.number1),
              _buildKeyboard(item: CalcVoiceItem.number2),
              _buildKeyboard(item: CalcVoiceItem.number3),
              _buildKeyboard(item: CalcVoiceItem.operatorAdd),
              _buildKeyboard(item: CalcVoiceItem.voiceType),
              _buildKeyboard(item: CalcVoiceItem.number0),
              _buildKeyboard(item: CalcVoiceItem.numberDot),
              _buildKeyboard(item: CalcVoiceItem.operatorEqual),
            ],
          ),
        ),
      ],
    );
  }

  double getBoxSize() {
    double screenWidth = Get.width;
    double screenHeight = Get.height;
    double boxSize = math.min(screenWidth, screenHeight);
    return boxSize;
  }

  double getKeyboardSize() {
    // 左、右padding各16（16x2），一行有4个按钮，每个按钮间距8（8x3）
    double keyboardWidth = getBoxSize() -
        (KeyboardPaddingLeft + KeyboardPaddingRight) -
        (KeyboardSpacing * 3);
    return keyboardWidth / KeyboardColumnCount;
  }

  Widget _buildKeyboard({
    // required String text,
    // required VoidCallback onPressed,
    required CalcVoiceItem item,
  }) {
    return AppButtonCommon.primaryWithTextIcon(
      onPressed: () {
        if (item.value == CalcVoiceItem.voiceType.value) {
          controller.onVoiceTypePressed();
          return;
        }
        controller.onVoiceItemPressed(item);
      },
      onTapDown: (details) {
        controller.onKeyTabDownFeedback();
      },
      onTapUp: (details) {
        controller.onKeyTabUpFeedback();
      },
      text: item.value == CalcVoiceItem.voiceType.value
          ? controller
              .voiceTypeList[controller.currentVoiceTypeIndex.value].iconText
          : item.text,
      textSize: AppTextTheme.fontSizeLarge,
      textWeightStyle: TextWeightStyle.bold,
    );
  }
}
