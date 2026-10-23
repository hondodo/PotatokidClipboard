import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/home/presentation/components/card_title.dart';

void main() {
  test('showArea 为 false 时保持原标题', () {
    expect(
      cardTitle(title: '插座', areaLabel: '客厅', showArea: false),
      '插座',
    );
  });

  test('showArea 为 true 时标题前置房间名', () {
    expect(
      cardTitle(title: '插座', areaLabel: '客厅', showArea: true),
      '客厅 插座',
    );
  });

  test('未分配房间时使用回退文案', () {
    expect(
      cardTitle(title: '插座', areaLabel: null, showArea: true),
      '未分配房间 插座',
    );
  });
}
