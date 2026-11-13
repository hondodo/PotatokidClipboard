import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/parental/data/parental_admin_api.dart';
import 'package:pscreen_home/features/parental/domain/parental_share.dart';
import 'package:pscreen_home/features/parental/presentation/parental_common.dart';
import 'package:pscreen_home/features/parental/presentation/parental_share_page.dart';

final ParentalMachine _living = ParentalMachine(
  id: 'living',
  name: '客厅电视',
  nameSet: true,
  kind: 'tv',
  owner: 'AA_parent',
  parents: const <String>['AA_parent'],
  commAccount: 'tv.living',
  online: true,
);

ParentalShareView _view({
  List<String> sharedTo = const <String>['mama88'],
  List<ParentalShareImported>? imported,
}) =>
    ParentalShareView(
      masters: <ParentalShareMaster>[
        ParentalShareMaster(
          id: 'c2',
          name: '档案2 · 大薯',
          profileMode: 'strict',
          dailyLimitMin: 60,
          sharedTo: sharedTo,
        ),
      ],
      imported: imported ??
          <ParentalShareImported>[
            ParentalShareImported(
              refId: 'bed:c10',
              id: 'c10',
              name: '原「小宝」档案',
              status: 'broken',
              reason: 'child-missing',
              source: const ParentalShareSource(
                machineId: 'bed',
                machineName: '卧室电视',
                owner: 'mama88',
                childId: 'c10',
              ),
            ),
          ],
      candidates: <ParentalShareCandidate>[
        const ParentalShareCandidate(
          machineId: 'bed',
          machineName: '卧室电视',
          owner: 'mama88',
          childId: 'c11',
          name: '逗逗',
          via: 'shared-to-me',
        ),
      ],
    );

ParentalActions _actions({
  Future<ParentalShareView> Function(ParentalShareMaster, List<String>)?
      onSharedTo,
  Future<ParentalShareView> Function(ParentalShareCandidate)? onAdd,
  Future<ParentalShareView> Function(ParentalShareImported)? onCancel,
}) {
  return ParentalActions(
    reload: () async {},
    saveConfig: (_) async {},
    unlock: (_) async {},
    openDeviceManager: () async {},
    openLoginExisting: () async {},
    openCreateAccount: () async {},
    hasClaimedAccount: true,
    push: (_) async {},
    sendRemoteCommand: (_, _) async {},
    refreshPermission: () async {},
    toggleChildLock: (_) {},
    addChildExtra: (_) {},
    editChild: (_) {},
    unbind: (_) {},
    selectDevice: (_) {},
    renameMachine: (_) {},
    openShareManagement: (_) {},
    loadShareView: (_) async => _view(),
    setSharedTo: (_, ParentalShareMaster child, List<String> sharedTo) =>
        onSharedTo?.call(child, sharedTo) ??
        Future<ParentalShareView>.value(_view(sharedTo: sharedTo)),
    addSharedRef: (_, ParentalShareCandidate candidate) =>
        onAdd?.call(candidate) ?? Future<ParentalShareView>.value(_view()),
    cancelSharedRef: (_, ParentalShareImported item) =>
        onCancel?.call(item) ?? Future<ParentalShareView>.value(_view()),
  );
}

Future<void> _pumpPage(
  WidgetTester tester,
  ParentalActions actions, {
  ParentalShareView? view,
}) async {
  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(MaterialApp(
    home: ParentalSharePage(
      machine: _living,
      machines: <ParentalMachine>[_living],
      actions: actions,
      initialView: view ?? _view(),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('档案共享页：四区分组正常渲染，失效档案显示原因',
      (WidgetTester tester) async {
    await _pumpPage(tester, _actions());

    expect(find.text('档案共享'), findsOneWidget);
    expect(find.text('本台档案 · 主本'), findsOneWidget);
    expect(find.text('档案2 · 大薯'), findsOneWidget);
    expect(find.text('引用进来的档案（主本在别处）'), findsOneWidget);
    expect(find.text('原「小宝」档案'), findsOneWidget);
    expect(find.textContaining('主本档案已删除'), findsOneWidget);
    expect(find.text('同一家长号 · 跨电视引用'), findsOneWidget);
    expect(find.text('其他家长分享给我'), findsOneWidget);
    expect(find.text('逗逗'), findsOneWidget);
    expect(find.textContaining('30 + 20 = 50 分钟'), findsOneWidget);
  });

  testWidgets('分享设置：中英文逗号拆分、去重并回传家长号白名单',
      (WidgetTester tester) async {
    List<String>? saved;
    await _pumpPage(
      tester,
      _actions(onSharedTo: (ParentalShareMaster child, List<String> sharedTo) async {
        saved = sharedTo;
        return _view(sharedTo: sharedTo);
      }),
    );

    await tester.tap(find.text('分享设置'));
    await tester.pumpAndSettle();
    final TextField field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, 'mama88');

    field.controller!.text = 'mama88, grandpa88，mama88';
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(saved, <String>['mama88', 'grandpa88']);
  });

  testWidgets('失效档案点「重新选择」只移除本台引用，不触碰主本',
      (WidgetTester tester) async {
    String? cancelled;
    await _pumpPage(
      tester,
      _actions(onCancel: (ParentalShareImported item) async {
        cancelled = item.refId;
        return _view(imported: const <ParentalShareImported>[]);
      }),
    );

    await tester.tap(find.byTooltip('重新选择（移除失效占位）'));
    await tester.pumpAndSettle();

    expect(cancelled, 'bed:c10');
  });

  testWidgets('其他家长分享的档案可引用，写入的是来源坐标',
      (WidgetTester tester) async {
    ParentalShareCandidate? added;
    await _pumpPage(
      tester,
      _actions(onAdd: (ParentalShareCandidate candidate) async {
        added = candidate;
        return _view();
      }),
    );

    await tester.tap(find.text('＋ 引用'));
    await tester.pumpAndSettle();

    expect(added, isNotNull);
    expect(added!.machineId, 'bed');
    expect(added!.childId, 'c11');
  });
}
