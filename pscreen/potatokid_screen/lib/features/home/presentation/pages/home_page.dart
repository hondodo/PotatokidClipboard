import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:potatokid_screen/core/di/injection.dart';
import 'package:potatokid_screen/core/router/app_router.dart';
import 'package:potatokid_screen/core/router/route_params.dart';
import 'package:potatokid_screen/features/home/application/bloc/home_bloc.dart';
import 'package:potatokid_screen/features/home/application/bloc/home_event.dart';
import 'package:potatokid_screen/features/home/application/bloc/home_state.dart';
import 'package:potatokid_screen/features/home/data/models/home_model.dart';

/// 首页：注入 [HomeBloc]（由 DI 提供），进入即触发加载。
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<HomeBloc>(
      create: (_) => Injection.get<HomeBloc>()..add(const LoadHomeList()),
      child: const _HomeView(),
    );
  }
}

class _HomeView extends StatelessWidget {
  const _HomeView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('home_title'.tr()),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Injection.get<AppRouter>().pushSettingsSheet(
              const SettingsSheetParams(from: 'home'),
            ),
          ),
        ],
      ),
      body: BlocBuilder<HomeBloc, HomeState>(
        builder: (context, state) {
          if (state.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state.errorMessage != null) {
            return _ErrorView(
              message: state.errorMessage!,
              onRetry: () =>
                  context.read<HomeBloc>().add(const LoadHomeList()),
            );
          }
          if (state.items.isEmpty) {
            return Center(child: Text('common_empty'.tr()));
          }
          return RefreshIndicator(
            onRefresh: () async {
              context
                  .read<HomeBloc>()
                  .add(const LoadHomeList(forceRefresh: true));
            },
            child: ListView.separated(
              itemCount: state.items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final HomeModel item = state.items[index];
                return ListTile(
                  title: Text(item.title),
                  subtitle: Text(item.subtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Injection.get<AppRouter>().pushHomeDetail(
                    HomeDetailParams(id: item.id, title: item.title),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(message),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: onRetry,
            child: Text('common_retry'.tr()),
          ),
        ],
      ),
    );
  }
}
