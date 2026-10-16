import 'package:flutter_test/flutter_test.dart';

import 'package:pscreen_control/main.dart';

void main() {
  testWidgets('App renders placeholder home', (WidgetTester tester) async {
    await tester.pumpWidget(const PscreenControlApp());
    expect(find.text('PScreen Control'), findsOneWidget);
  });
}
