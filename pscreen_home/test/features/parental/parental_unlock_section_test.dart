import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/parental/data/parental_admin_api.dart';
import 'package:pscreen_home/features/parental/domain/parental_config.dart';
import 'package:pscreen_home/features/parental/presentation/parental_unlock_section.dart';

ParentalMachine _machine({String name = '红米笔记本'}) => ParentalMachine(
      id: 'm1',
      name: name,
      nameSet: true,
      kind: 'tv',
      owner: 'owner1',
      parents: const <String>['owner1'],
      commAccount: 'mi10s',
      online: true,
    );

ParentalConfig _config({String mode = 'remote', String pin = ''}) => ParentalConfig(
      mode: 'on',
      children: <ParentalChild>[ParentalChild(id: 'c1', name: '弟弟')],
      unlockMode: mode,
      pin: pin,
      ownerAccount: 'owner1',
    );

Widget _wrap({
  required ParentalConfig config,
  required ParentalMachine? machine,
  required List<ParentalConfig> saved,
  VoidCallback? onOpenQuiz,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: ParentalUnlockSection(
          config: config,
          machine: machine,
          onSave: (ParentalConfig next) async {
            saved.add(next);
          },
          onOpenQuiz: onOpenQuiz ?? () {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('解锁方式：4 张说明卡齐全，选中态为「当前」',
      (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(
      config: _config(mode: 'remote'),
      machine: _machine(),
      saved: <ParentalConfig>[],
    ));
    await tester.pumpAndSettle();

    expect(find.text('远程确认'), findsOneWidget);
    expect(find.text('PIN 码'), findsOneWidget);
    expect(find.text('算术题'), findsOneWidget);
    expect(find.text('答题解锁'), findsOneWidget);
    // 只有选中的模式带「当前」标签。
    expect(find.text('当前'), findsOneWidget);
    // 说明卡文案来自设计稿。
    expect(find.textContaining('孩子在电视上发起请求，你在手机上批准'), findsOneWidget);
    expect(find.textContaining('选择后立即生效并回读确认'), findsOneWidget);
  });

  testWidgets('解锁方式：顶部标注当前配置目标电视名（不用上翻找设备）',
      (WidgetTester tester) async {
    await tester.pumpWidget(_wrap(
      config: _config(),
      machine: _machine(name: '客厅电视'),
      saved: <ParentalConfig>[],
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('当前配置目标：客厅电视'), findsOneWidget);
    expect(find.textContaining('下面四种方式只对这台电视生效'), findsOneWidget);
    expect(find.textContaining('去上面「我的电视」点它的名字切换'), findsOneWidget);
  });

  testWidgets('解锁方式：点选另一种方式即保存，且沿用原 PIN 不误清空',
      (WidgetTester tester) async {
    final List<ParentalConfig> saved = <ParentalConfig>[];
    await tester.pumpWidget(_wrap(
      config: _config(mode: 'remote', pin: '2580'),
      machine: _machine(),
      saved: saved,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('算术题'));
    await tester.pumpAndSettle();

    expect(saved.length, 1);
    expect(saved.first.unlockMode, 'arith');
    // 切到非 PIN 模式，PIN 沿用原值而非被清空。
    expect(saved.first.pin, '2580');
    expect(saved.first.ownerAccount, 'owner1');
  });

  testWidgets('解锁方式：PIN 选中时就地展开输入 + 保存 PIN（校验 4 位）',
      (WidgetTester tester) async {
    final List<ParentalConfig> saved = <ParentalConfig>[];
    await tester.pumpWidget(_wrap(
      config: _config(mode: 'pin', pin: ''),
      machine: _machine(),
      saved: saved,
    ));
    await tester.pumpAndSettle();

    // PIN 模式默认展开输入框与就地保存按钮，无需跨 Tab。
    expect(find.text('设定 PIN（4 位数字）'), findsOneWidget);
    expect(find.text('保存 PIN'), findsOneWidget);

    // 非法 PIN 不提交，给出就地错误。
    await tester.enterText(find.byType(TextField), '12');
    await tester.tap(find.text('保存 PIN'));
    await tester.pumpAndSettle();
    expect(saved, isEmpty);
    expect(find.textContaining('PIN 需为 4 位数字'), findsOneWidget);

    // 合法 PIN 提交。
    await tester.enterText(find.byType(TextField), '2580');
    await tester.tap(find.text('保存 PIN'));
    await tester.pumpAndSettle();
    expect(saved.length, 1);
    expect(saved.first.unlockMode, 'pin');
    expect(saved.first.pin, '2580');
  });

  testWidgets('解锁方式：答题解锁就地给出题库入口', (WidgetTester tester) async {
    final List<ParentalConfig> saved = <ParentalConfig>[];
    int quizOpened = 0;
    await tester.pumpWidget(_wrap(
      config: _config(mode: 'quiz'),
      machine: _machine(),
      saved: saved,
      onOpenQuiz: () => quizOpened++,
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('题库为空或只有填空题时'), findsOneWidget);
    expect(find.text('管理题库 ›'), findsOneWidget);
    await tester.tap(find.text('管理题库 ›'));
    await tester.pumpAndSettle();
    expect(quizOpened, 1);
  });

  testWidgets('解锁方式：未选设备时卡片禁用并提示先去选电视',
      (WidgetTester tester) async {
    final List<ParentalConfig> saved = <ParentalConfig>[];
    await tester.pumpWidget(_wrap(
      config: _config(),
      machine: null,
      saved: saved,
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('请先在上方「我的电视」点一台'), findsOneWidget);
    // 点选不触发保存（目标设备为空）。
    await tester.tap(find.text('算术题'));
    await tester.pumpAndSettle();
    expect(saved, isEmpty);
  });
}
