// ignore_for_file: constant_identifier_names

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:potatokid_clipboard/framework/base/base_stateless_sub_widget.dart';
import 'package:potatokid_clipboard/framework/theme/app_text_theme.dart';
import 'package:potatokid_clipboard/pages/tools/calc/vm/calc_controller.dart';

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
                        controller
                            .onTabLine(controller.expressionHistory[index]);
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          controller.expressionHistory[index],
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
              _buildKeyboard(
                  text: 'C',
                  onPressed: () {
                    controller.onKeyboardClearPressed();
                  }),
              _buildKeyboard(
                  text: '←',
                  onPressed: () {
                    controller.onKeyboardBackspacePressed();
                  }),
              _buildKeyboard(
                  text: '%',
                  onPressed: () {
                    controller.onKeyboardOperatorPressed('%');
                  }),
              _buildKeyboard(
                  text: '÷',
                  onPressed: () {
                    controller.onKeyboardOperatorPressed('÷');
                  }),
              _buildKeyboard(
                  text: '7',
                  onPressed: () {
                    controller.onKeyboardNumberPressed('7');
                  }),
              _buildKeyboard(
                  text: '8',
                  onPressed: () {
                    controller.onKeyboardNumberPressed('8');
                  }),
              _buildKeyboard(
                  text: '9',
                  onPressed: () {
                    controller.onKeyboardNumberPressed('9');
                  }),
              _buildKeyboard(
                  text: '×',
                  onPressed: () {
                    controller.onKeyboardOperatorPressed('×');
                  }),
              _buildKeyboard(
                  text: '4',
                  onPressed: () {
                    controller.onKeyboardNumberPressed('4');
                  }),
              _buildKeyboard(
                  text: '5',
                  onPressed: () {
                    controller.onKeyboardNumberPressed('5');
                  }),
              _buildKeyboard(
                  text: '6',
                  onPressed: () {
                    controller.onKeyboardNumberPressed('6');
                  }),
              _buildKeyboard(
                  text: '-',
                  onPressed: () {
                    controller.onKeyboardOperatorPressed('-');
                  }),
              _buildKeyboard(
                  text: '1',
                  onPressed: () {
                    controller.onKeyboardNumberPressed('1');
                  }),
              _buildKeyboard(
                  text: '2',
                  onPressed: () {
                    controller.onKeyboardNumberPressed('2');
                  }),
              _buildKeyboard(
                  text: '3',
                  onPressed: () {
                    controller.onKeyboardNumberPressed('3');
                  }),
              _buildKeyboard(
                  text: '+',
                  onPressed: () {
                    controller.onKeyboardOperatorPressed('+');
                  }),
              _buildKeyboard(
                  text: '00',
                  onPressed: () {
                    controller.onKeyboardNumberPressed('00');
                  }),
              _buildKeyboard(
                  text: '0',
                  onPressed: () {
                    controller.onKeyboardNumberPressed('0');
                  }),
              _buildKeyboard(
                  text: '.',
                  onPressed: () {
                    controller.onDotPressed();
                  }),
              _buildKeyboard(
                  text: '=',
                  onPressed: () {
                    controller.onKeyboardEqualPressed();
                  }),
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
    required String text,
    required VoidCallback onPressed,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        height: KeyboardHeight,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color.fromARGB(255, 128, 128, 128),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          text,
          style: AppTextTheme.textStyle.title.bold.setColor(Colors.white),
        ),
      ),
    );
  }
}
