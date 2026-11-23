import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/core/ui/ui_scale.dart';

void main() {
  group('HomeDesign 分场景设计画布', () {
    test('横屏 1920×1080：scale=1.5，逻辑画布 1280×720，4 列内容不变', () {
      const Size screen = Size(1920, 1080);
      expect(HomeDesign.isPortrait(screen), isFalse);
      final double scale = defaultUiScaleFor(screen);
      expect(scale, closeTo(1.5, 1e-6));
      expect(
        screen.width / scale,
        closeTo(HomeDesign.landscapeCanvas.width, 1e-6),
      );
      expect(
        screen.height / scale,
        closeTo(HomeDesign.landscapeCanvas.height, 1e-6),
      );
      expect(HomeDesign.landscapeColumns, 4);
    });

    test('小窗口横屏按自动缩放适配，已固化的 1.0 不再生效', () {
      // 936×508 这类小窗口：过去 ui_scale=1.0 覆盖后内容按物理像素 1:1
      // 布局导致卡片被裁；现在必须走自动缩放，高度约束给出 720 的画布，
      // 宽度随窗口比例扩展到 1326（不拉伸、不裁切）。
      const Size screen = Size(936, 508);
      final UiScaleController controller = UiScaleController();
      final double scale = controller.resolve(screen);
      expect(scale, closeTo(defaultUiScaleFor(screen), 1e-6));
      expect(scale, lessThan(1.0));
      expect(screen.height / scale, closeTo(720, 1e-6));
      expect(screen.width / scale, greaterThan(1280));
    });

    test('横屏 2560×1440 继续放大，不被上限截断', () {
      expect(defaultUiScaleFor(const Size(2560, 1440)), closeTo(2.0, 1e-6));
    });

    test('横屏 4:3 屏用宽度约束，多出高度扩展逻辑画布，不裁切', () {
      const Size screen = Size(1024, 768);
      final double scale = defaultUiScaleFor(screen);
      expect(scale, closeTo(0.8, 1e-6));
      expect(screen.width / scale, closeTo(1280, 1e-6));
      expect(screen.height / scale, closeTo(960, 1e-6));
    });

    test('竖屏 390×844：scale=1.0，按手机画布布局，2 列', () {
      const Size screen = Size(390, 844);
      expect(HomeDesign.isPortrait(screen), isTrue);
      expect(defaultUiScaleFor(screen), 1.0);
      expect(HomeDesign.portraitColumns, 2);
      expect(HomeDesign.canvasFor(screen), HomeDesign.portraitCanvas);
    });

    test('竖屏更大手机按更受限的一维等比放大', () {
      const Size screen = Size(480, 1080);
      // min(480/390, 1080/844) = 480/390，宽度更受限。
      expect(defaultUiScaleFor(screen), closeTo(480 / 390, 1e-6));
    });

    test('横竖屏判定边界', () {
      expect(HomeDesign.isPortrait(const Size(844, 390)), isFalse);
      expect(HomeDesign.isPortrait(const Size(768, 1024)), isTrue);
      expect(HomeDesign.isPortrait(const Size(1080, 1920)), isTrue);
    });

    testWidgets('UiScaleScope 把逻辑画布整屏缩放到物理尺寸，内容不变', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1920, 1080));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: UiScaleScope(
            scale: 1.5,
            child: Builder(
              builder: (BuildContext context) {
                final Size logical = MediaQuery.sizeOf(context);
                return ColoredBox(
                  color: Colors.transparent,
                  child: Center(
                    child: Text(
                      '${logical.width.round()}x${logical.height.round()}',
                      textDirection: TextDirection.ltr,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 逻辑画布与物理尺寸按统一 scale 换算，字号等常量写一次即可。
      expect(find.text('1280x720'), findsOneWidget);
    });
  });
}
