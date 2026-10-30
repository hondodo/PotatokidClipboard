import 'package:flutter_test/flutter_test.dart';
import 'package:potatokid_screen/features/app/application/app_tab_controller.dart';
import 'package:potatokid_screen/features/app/application/tv_scene_provider.dart';
import 'package:pscreen_screen/features/iptv/application/channel_info_provider.dart';
import 'package:pscreen_screen/features/iptv/application/live_channel_controller.dart';
import 'package:pscreen_screen/features/iptv/domain/models/iptv_channel.dart';
import 'package:pscreen_screen/features/msg/application/current_scene_provider.dart';

void main() {
  const TvSceneProvider provider = TvSceneProvider();

  setUp(() {
    ChannelInfoProvider.instance.setChannels(
      List<IptvChannel>.generate(
        10,
        (int i) => IptvChannel(name: 'CH-${i + 1}', sources: <String>['u']),
      ),
    );
    LiveChannelController.instance.setCount(10);
    AppTabController.branchIndex = 0;
  });

  tearDown(() {
    ChannelInfoProvider.instance.setChannels(<IptvChannel>[]);
    LiveChannelController.instance.setCount(0); // count 归零 → index 复位
    AppTabController.branchIndex = 0;
  });

  test('直播页：频道名走 channelName 字段', () {
    LiveChannelController.instance.select(5);
    final SceneSnapshot snap = provider.snapshot();
    expect(snap.kind, SceneKind.live);
    expect(snap.channelName, 'CH-6');
    final Map<String, Object?> json = snap.toJson();
    expect(json['channelName'], 'CH-6');
    expect(json['channelIndex'], 5);
  });

  test('非直播页：上报 JSON 顶层仍带当前频道（遥控定位用）', () {
    LiveChannelController.instance.select(5);
    for (final int tab in const <int>[1, 2, 3]) {
      AppTabController.branchIndex = tab;
      final SceneSnapshot snap = provider.snapshot();
      expect(
        snap.channelName,
        isNull,
        reason: 'channelName 字段仅直播页用，保证 key 不随换台变化',
      );
      final Map<String, Object?> json = snap.toJson();
      expect(json['channelName'], 'CH-6', reason: 'tab $tab 的 JSON 应带频道名');
      expect(json['channelIndex'], 5);
      expect(snap.key, isNot(contains('CH-6')), reason: 'tab $tab 的 key 不含频道');
    }
  });

  test('非直播页换台：key 不变（不误发场景切换），上报频道随之更新', () {
    AppTabController.branchIndex = 2;
    LiveChannelController.instance.select(5);
    final String keyBefore = provider.snapshot().key;
    LiveChannelController.instance.select(6);
    final SceneSnapshot after = provider.snapshot();
    expect(after.key, keyBefore);
    expect(after.toJson()['channelName'], 'CH-7');
  });

  test('频道列表未加载时：非直播页不带频道', () {
    ChannelInfoProvider.instance.setChannels(<IptvChannel>[]);
    AppTabController.branchIndex = 3;
    expect(provider.snapshot().toJson().containsKey('channelName'), isFalse);
  });
}
