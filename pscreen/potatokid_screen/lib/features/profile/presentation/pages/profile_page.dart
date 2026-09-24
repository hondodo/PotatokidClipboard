import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:potatokid_screen/core/di/injection.dart';
import 'package:potatokid_screen/core/router/app_router.dart';
import 'package:potatokid_screen/core/router/route_params.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_bloc.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_event.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_state.dart';

/// 支持切换的语言列表（Locale 与翻译文件 key 一一对应）
const List<(Locale, String)> _supportedLanguages = <(Locale, String)>[
  (Locale('zh', 'CN'), 'language_zh_cn'),
  (Locale('zh', 'TW'), 'language_zh_tw'),
  (Locale('en', 'US'), 'language_en_us'),
  (Locale('ja', 'JP'), 'language_ja_jp'),
];

/// 「我的」Tab 页面：演示全局 [AppBloc]（主题切换）与 EasyLocalization（多语言切换）的消费方式。
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('profile_title'.tr())),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Text(
            'theme_mode_title'.tr(),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          BlocBuilder<AppBloc, AppState>(
            builder: (context, state) {
              return SegmentedButton<ThemeMode>(
                segments: <ButtonSegment<ThemeMode>>[
                  ButtonSegment<ThemeMode>(
                    value: ThemeMode.system,
                    label: Text('theme_system'.tr()),
                  ),
                  ButtonSegment<ThemeMode>(
                    value: ThemeMode.light,
                    label: Text('theme_light'.tr()),
                  ),
                  ButtonSegment<ThemeMode>(
                    value: ThemeMode.dark,
                    label: Text('theme_dark'.tr()),
                  ),
                ],
                selected: <ThemeMode>{state.themeMode},
                onSelectionChanged: (selection) => context
                    .read<AppBloc>()
                    .add(ChangeThemeMode(selection.first)),
              );
            },
          ),
          const SizedBox(height: 24),
          Text(
            'language_mode_title'.tr(),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final (Locale locale, String labelKey) in _supportedLanguages)
                ChoiceChip(
                  label: Text(labelKey.tr()),
                  selected: context.locale == locale,
                  onSelected: (_) => context.setLocale(locale),
                ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => Injection.get<AppRouter>().pushSettingsSheet(
              const SettingsSheetParams(from: 'profile'),
            ),
            child: Text('action_settings'.tr()),
          ),
        ],
      ),
    );
  }
}
