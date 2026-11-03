import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('probe: AppBloc load across pumps then unmount',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      BlocProvider<AppBloc>(
        create: (BuildContext _) => AppBloc(),
        child: const SizedBox(),
      ),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}

