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
  });
}
