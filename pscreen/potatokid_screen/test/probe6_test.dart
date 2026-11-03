import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:potatokid_screen/core/di/injection.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_bloc.dart';
import 'package:pscreen_screen/core/parental/parental_config.dart';
import 'package:pscreen_screen/core/parental/parental_state_controller.dart';
import 'package:pscreen_screen/core/utils/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
        SharedPreferences.setMockInitialValues(<String, Object>{});
    await EasyLocalization.ensureInitialized();
    await Injection.init();
    await ParentalStateController.instance.saveLocalConfig(const ParentalConfig());
  });

  testWidgets('probeP', (WidgetTester tester) async {
    await tester.pumpWidget(
      BlocProvider<AppBloc>(
        create: (BuildContext _) {
          debugPrint('=== [probe] AppBloc created');
          final AppBloc bloc = AppBloc();
          AppSettings.instance.ensureLoaded().then(
              (_) => debugPrint('=== [probe] ensureLoaded done'));
          return bloc;
        },
        child: Builder(
          builder: (BuildContext context) {
            context.read<AppBloc>();
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    debugPrint('=== [probe] pumped');
    await tester.pumpWidget(const SizedBox());
    debugPrint('=== [probe] unmounted');
  });
}

