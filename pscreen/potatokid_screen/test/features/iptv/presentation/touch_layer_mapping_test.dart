import 'package:flutter_test/flutter_test.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_state.dart';
import 'package:potatokid_screen/features/iptv/presentation/components/live_player_widget.dart';

/// 触屏「长按递进」与「操作提示文案」的分层规则。
///
/// 这两条规则是纯函数，抽出来单测是为了让它们**不依赖真机**就能回归：
/// - 长按在每一层该做什么（全屏/频道信息 → 频道列表；频道列表 → 功能菜单）；
/// - 每层该显示什么提示文案（`tv` 提示按返回键，`phone`/`board` 提示长按）。
void main() {
  group('touchLongPressTargetFor', () {
    test('全屏与频道信息层长按 → 呼出频道列表', () {
      expect(
        touchLongPressTargetFor(HomeRemoteLayer.fullscreen),
        TouchLongPressTarget.channelPanel,
      );
      expect(
        touchLongPressTargetFor(HomeRemoteLayer.channelInfo),
        TouchLongPressTarget.channelPanel,
      );
    });

    test('频道列表层长按 → 进入功能菜单（长按递进第二级）', () {
      expect(
        touchLongPressTargetFor(HomeRemoteLayer.channelList),
        TouchLongPressTarget.capsuleMenu,
      );
    });

    test('功能菜单层长按 → 无动作', () {
      expect(
        touchLongPressTargetFor(HomeRemoteLayer.capsuleControls),
        TouchLongPressTarget.none,
      );
    });
  });

  group('touchHintKeyForLayer', () {
    test('有触屏（phone/board）：提示长按', () {
      expect(
        touchHintKeyForLayer(
          HomeRemoteLayer.channelInfo,
          remoteOnly: false,
        ),
        'touch_hint_longpress_channels',
      );
      expect(
        touchHintKeyForLayer(
          HomeRemoteLayer.channelList,
          remoteOnly: false,
        ),
        'touch_hint_longpress_menu',
      );
    });

    test('只有遥控（tv）：提示按返回键', () {
      expect(
        touchHintKeyForLayer(
          HomeRemoteLayer.channelInfo,
          remoteOnly: true,
        ),
        'touch_hint_back_channels',
      );
      expect(
        touchHintKeyForLayer(
          HomeRemoteLayer.channelList,
          remoteOnly: true,
        ),
        'touch_hint_back_menu',
      );
    });

    test('全屏与功能菜单层不提示（空串）', () {
      for (final bool remoteOnly in <bool>[true, false]) {
        expect(
          touchHintKeyForLayer(HomeRemoteLayer.fullscreen, remoteOnly: remoteOnly),
          '',
        );
        expect(
          touchHintKeyForLayer(
            HomeRemoteLayer.capsuleControls,
            remoteOnly: remoteOnly,
          ),
          '',
        );
      }
    });
  });
}
