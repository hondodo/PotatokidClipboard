import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/remote_control/data/tv_directory.dart';

void main() {
  test('从 JSON 列表解析设备', () {
    final List<TvDevice> list = TvDirectory.parseJson(
      '[{"name":"客厅电视","account":"TV_001"},{"name":"卧室","account":"TV_002"}]',
    );
    expect(list.length, 2);
    expect(list.first.name, '客厅电视');
    expect(list.first.account, 'TV_001');
  });

  test('坏 JSON 返回空列表', () {
    expect(TvDirectory.parseJson('{oops'), isEmpty);
  });

  test('nameOf：命中返回名称，未命中返回账号本身', () {
    final TvDirectory dir = TvDirectory(
      devices: TvDirectory.parseJson(
        '[{"name":"客厅电视","account":"TV_001"}]',
      ),
    );
    expect(dir.nameOf('TV_001'), '客厅电视');
    expect(dir.nameOf('TV_999'), 'TV_999');
  });
}
