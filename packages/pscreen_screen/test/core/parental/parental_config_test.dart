import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_screen/core/parental/parental_config.dart';

/// `ParentalConfig` 解析与生效判定（方案 §2.2 配置结构）：
/// - `fromJson` 宽容解析（坏条目忽略、枚举回退缺省）；
/// - 生效判定式 `mode=='on' && children` 非空；
/// - 悬空 id 过滤 `resolveActiveChildIds`（部分悬空保留剩余 / 全部悬空归零 /
///   去重 / null 输入）。
void main() {
  group('ParentalConfig.fromJson 宽容解析', () {
    test('完整结构往返：children / activeChildIds / unlockMode / ownerAccount', () {
      final ParentalConfig config = ParentalConfig.fromJson(<String, dynamic>{
        'mode': 'on',
        'activeChildIds': <String>['c1', 'c2'],
        'children': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'c1',
            'name': '小明',
            'age': 8,
            'profileMode': 'strict',
            'locked': true,
            'allowGroups': <String>['央视频道'],
            'allowChannels': <String>['CCTV-*'],
            'sessionLimitMin': 30,
            'dailyLimitMin': 120,
            'quietHours': <String>['21:00-07:00'],
          },
          <String, dynamic>{
            'id': 'c2',
            'name': '小红',
            'profileMode': 'mild',
            'hideGroups': <String>['境外频道'],
          },
        ],
        'unlockMode': 'pin',
        'pin': '1234',
        'ownerAccount': '1000002',
      });

      expect(config.mode, 'on');
      expect(config.enabled, isTrue);
      expect(config.activeChildIds, <String>['c1', 'c2']);
      expect(config.children, hasLength(2));

      final ChildProfile strict = config.childById('c1')!;
      expect(strict.name, '小明');
      expect(strict.age, 8);
      expect(strict.isStrict, isTrue);
      expect(strict.locked, isTrue);
      expect(strict.allowGroups, <String>['央视频道']);
      expect(strict.allowChannels, <String>['CCTV-*']);
      expect(strict.sessionLimitMin, 30);
      expect(strict.dailyLimitMin, 120);
      expect(strict.quietHours.single.format(), '21:00-07:00');

      final ChildProfile mild = config.childById('c2')!;
      expect(mild.isStrict, isFalse);
      expect(mild.hideGroups, <String>['境外频道']);

      expect(config.unlockMode, 'pin');
      expect(config.pin, '1234');
      expect(config.ownerAccount, '1000002');
    });

    test('坏数据回退缺省：非法 mode/unlockMode、无 id 档案、非数值限额', () {
      final ParentalConfig config = ParentalConfig.fromJson(<String, dynamic>{
        'mode': 'yes', // 非 'on' → off
        'unlockMode': 'gesture', // 非法 → remote
        'children': <Object>[
          <String, dynamic>{'name': '没有 id'}, // 无 id → 丢弃
          <String, dynamic>{
            'id': 'c1',
            'name': '正常',
            'profileMode': 'unknown', // 非法档位 → mild
            'sessionLimitMin': -5, // 负数 → 0
            'dailyLimitMin': 'abc', // 非数值 → 0
          },
        ],
      });
      expect(config.mode, 'off');
      expect(config.unlockMode, 'remote');
      expect(config.children, hasLength(1));
      final ChildProfile c = config.childById('c1')!;
      expect(c.isStrict, isFalse);
      expect(c.sessionLimitMin, 0);
      expect(c.dailyLimitMin, 0);
    });

    test('老配置缺 parental 字段语义：children 空时判定式不成立', () {
      expect(const ParentalConfig().enabled, isFalse);
      expect(
        ParentalConfig.fromJson(const <String, dynamic>{'mode': 'on'}).enabled,
        isFalse,
      );
      expect(
        ParentalConfig.fromJson(const <String, dynamic>{
          'children': <Map<String, dynamic>>[
            <String, dynamic>{'id': 'x', 'name': 'X'},
          ],
        }).enabled,
        isFalse, // mode 缺省 off
      );
    });
  });

  group('resolveActiveChildIds 悬空过滤', () {
    final ParentalConfig config = ParentalConfig.fromJson(<String, dynamic>{
      'mode': 'on',
      'children': <Map<String, dynamic>>[
        <String, dynamic>{'id': 'a', 'name': '甲'},
        <String, dynamic>{'id': 'b', 'name': '乙'},
      ],
    });

    test('部分悬空 → 保留剩余有效 id（按传入顺序）', () {
      expect(
        config.resolveActiveChildIds(<String>['ghost', 'b', 'a']),
        <String>['b', 'a'],
      );
    });

    test('全部悬空 → 空列表（视为未选，回退选人页）', () {
      expect(config.resolveActiveChildIds(<String>['g1', 'g2']), isEmpty);
    });

    test('重复 id 去重；null 输入返回空', () {
      expect(config.resolveActiveChildIds(<String>['a', 'a', 'b']),
          <String>['a', 'b']);
      expect(config.resolveActiveChildIds(null), isEmpty);
    });

    test('profilesOf 悬空过滤后按 ids 顺序取档案', () {
      final List<ChildProfile> profiles =
          config.profilesOf(<String>['b', 'ghost', 'a']);
      expect(profiles.map((ChildProfile p) => p.id).toList(),
          <String>['b', 'a']);
    });
  });
}
