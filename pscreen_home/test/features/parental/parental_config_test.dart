import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/parental/domain/parental_config.dart';

void main() {
  group('ParentalConfig 生效判定', () {
    const ParentalChild child = ParentalChild(id: 'c1', name: '小明');

    test('mode=on 且有档案才算启用', () {
      expect(ParentalConfig.empty.enabled, isFalse);
      expect(
        ParentalConfig(mode: 'on').enabled,
        isFalse,
        reason: '总开关开着但没有档案也不生效',
      );
      expect(
        ParentalConfig(mode: 'off', children: <ParentalChild>[child]).enabled,
        isFalse,
      );
      expect(
        ParentalConfig(mode: 'on', children: <ParentalChild>[child]).enabled,
        isTrue,
      );
    });
  });

  group('ParentalConfig 序列化', () {
    test('fromJson/toJson 往返保持字段', () {
      final ParentalConfig config = ParentalConfig.fromJson(<String, dynamic>{
        'mode': 'on',
        'activeChildIds': <String>['c1', 'c2'],
        'children': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'c1',
            'name': '小明',
            'age': 8,
            'profileMode': 'strict',
            'allowChannels': <String>['CCTV1'],
            'dailyLimitMin': 60,
            'quietHours': <String>['22:00-06:00'],
            'locked': true,
          },
        ],
        'unlockMode': 'pin',
        'pin': '1234',
        'ownerAccount': 'parent01',
      });

      final ParentalConfig roundTrip =
          ParentalConfig.fromJson(config.toJson());
      expect(roundTrip.mode, 'on');
      expect(roundTrip.activeChildIds, <String>['c1', 'c2']);
      expect(roundTrip.unlockMode, 'pin');
      expect(roundTrip.pin, '1234');
      expect(roundTrip.ownerAccount, 'parent01');
      expect(roundTrip.children, hasLength(1));
      final ParentalChild child = roundTrip.children.single;
      expect(child.name, '小明');
      expect(child.age, 8);
      expect(child.isStrict, isTrue);
      expect(child.allowChannels, <String>['CCTV1']);
      expect(child.dailyLimitMin, 60);
      expect(child.quietHours, <String>['22:00-06:00']);
      expect(child.locked, isTrue);
    });

    test('缺字段 / 非法值按保守默认回落', () {
      final ParentalConfig config = ParentalConfig.fromJson(<String, dynamic>{
        'mode': 'on',
        'children': <dynamic>[
          <String, dynamic>{'id': 'c1', 'name': '小明', 'profileMode': 'ultra'},
        ],
      });
      expect(config.unlockMode, 'remote');
      expect(config.ownerAccount, '');
      expect(config.activeChildIds, isEmpty);
      expect(
        config.children.single.profileMode,
        'mild',
        reason: '非法档位回落温和档',
      );
    });

    test('mode 缺省视为未启用', () {
      expect(ParentalConfig.fromJson(<String, dynamic>{}).enabled, isFalse);
    });

    test('档案共享：sharedTo 与 shared[] 坐标往返保持', () {
      const ParentalSharedRef ref = ParentalSharedRef(
        refId: 'bed:c11',
        owner: 'mama88',
        machineId: 'bed',
        childId: 'c11',
        createdAtMs: 1700000000000,
      );
      final ParentalConfig config = ParentalConfig.fromJson(<String, dynamic>{
        'mode': 'on',
        'children': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'c1',
            'name': '小薯',
            'sharedTo': <String>['mama88', 'grandpa88'],
          },
        ],
        'shared': <Map<String, dynamic>>[ref.toJson()],
      });

      final ParentalConfig roundTrip =
          ParentalConfig.fromJson(config.toJson());
      expect(roundTrip.children.single.sharedTo,
          <String>['mama88', 'grandpa88']);
      expect(roundTrip.shared, hasLength(1));
      expect(roundTrip.shared.single.refId, 'bed:c11');
      expect(roundTrip.shared.single.owner, 'mama88');
      expect(roundTrip.shared.single.machineId, 'bed');
      expect(roundTrip.shared.single.childId, 'c11');
      expect(roundTrip.shared.single.createdAtMs, 1700000000000);
    });

    test('展示层 readOnly 引用档案不会被写回 children[] 主本', () {
      final ParentalConfig display = ParentalConfig(
        mode: 'on',
        children: <ParentalChild>[
          const ParentalChild(id: 'c1', name: '主本'),
          const ParentalChild(
            id: 'c11',
            name: '引用来的逗逗',
            readOnly: true,
            sourceLabel: '妈妈 · 卧室电视',
          ),
        ],
        shared: const <ParentalSharedRef>[
          ParentalSharedRef(
            refId: 'bed:c11',
            owner: 'mama88',
            machineId: 'bed',
            childId: 'c11',
          ),
        ],
      );

      final Map<String, dynamic> json = display.toJson();
      expect(
        (json['children'] as List).map((dynamic item) => item['id']).toList(),
        <String>['c1'],
        reason: '引用档案只是展示展开，不能复制成本台主本',
      );
      expect(json['shared'], hasLength(1));
    });
  });
}
