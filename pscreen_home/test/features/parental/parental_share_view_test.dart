import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/parental/domain/parental_share.dart';

void main() {
  group('ParentalShareView 解析', () {
    test('主本 / 正常引用 / 失效引用 / 两类候选按服务端结构展开', () {
      final ParentalShareView view = ParentalShareView.fromJson(
        <String, dynamic>{
          'masters': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'c2',
              'name': '档案2 · 大薯',
              'profileMode': 'strict',
              'dailyLimitMin': 60,
              'sharedTo': <String>['mama88'],
              'isMaster': true,
              'readOnly': false,
            },
          ],
          'imported': <Map<String, dynamic>>[
            <String, dynamic>{
              'refId': 'bed:c11',
              'id': 'c11',
              'name': '逗逗',
              'profileMode': 'mild',
              'dailyLimitMin': 30,
              'isMaster': false,
              'readOnly': true,
              'status': 'ok',
              'source': <String, dynamic>{
                'machineId': 'bed',
                'machineName': '卧室电视',
                'owner': 'mama88',
                'childId': 'c11',
              },
            },
            <String, dynamic>{
              'refId': 'bed:c10',
              'id': 'c10',
              'name': '原「小宝」档案',
              'isMaster': false,
              'readOnly': true,
              'status': 'broken',
              'reason': 'child-missing',
              'source': <String, dynamic>{
                'machineId': 'bed',
                'owner': 'mama88',
                'childId': 'c10',
              },
            },
          ],
          'candidates': <Map<String, dynamic>>[
            <String, dynamic>{
              'machineId': 'study',
              'machineName': '书房电视',
              'owner': 'AA_parent',
              'childId': 'c3',
              'name': '奶奶',
              'via': 'same-account',
              'isTv': true,
            },
            <String, dynamic>{
              'machineId': 'bed',
              'machineName': '卧室电视',
              'owner': 'mama88',
              'childId': 'c12',
              'name': '果果',
              'via': 'shared-to-me',
              'isTv': true,
            },
          ],
        },
      );

      expect(view.masters, hasLength(1));
      expect(view.masters.single.sharedTo, <String>['mama88']);
      expect(view.masters.single.isStrict, isTrue);

      expect(view.imported, hasLength(2));
      final ParentalShareImported ok = view.imported.first;
      expect(ok.isBroken, isFalse);
      expect(ok.readOnly, isTrue);
      expect(ok.sourceLabel, 'mama88 · 卧室电视');
      final ParentalShareImported broken = view.imported.last;
      expect(broken.isBroken, isTrue);
      expect(parentalShareReasonLabel(broken.reason), contains('主本档案已删除'));

      expect(
        view.candidates.where((ParentalShareCandidate c) => c.isSameAccount),
        hasLength(1),
      );
      expect(
        view.candidates.where((ParentalShareCandidate c) => !c.isSameAccount),
        hasLength(1),
      );
      expect(view.candidates.last.groupLabel, '其他家长分享给我');
    });

    test('缺字段 / 空响应回落到安全空视图', () {
      final ParentalShareView view =
          ParentalShareView.fromJson(<String, dynamic>{});
      expect(view.isEmpty, isTrue);
      expect(ParentalShareView.empty.imported, isEmpty);
      expect(parentalShareReasonLabel(null), contains('保留占位'));
    });
  });
}
