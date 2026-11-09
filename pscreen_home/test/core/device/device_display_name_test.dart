import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/core/device/device_display_name.dart';

void main() {
  test('优先级：本机别名 > 家长别名 > displayName > 设备备注 > 账号 id', () {
    expect(
      DeviceDisplayName.resolve(
        account: 'tv.tv.0e208908bebea19a',
        localAlias: '本机备注',
        alias: '家长别名',
        displayName: '小米电视',
        machineName: '客厅',
      ),
      '本机备注',
    );
    expect(
      DeviceDisplayName.resolve(
        account: 'tv.tv.0e208908bebea19a',
        alias: '家长别名',
        displayName: '小米电视',
        machineName: '客厅',
      ),
      '家长别名',
    );
    expect(
      DeviceDisplayName.resolve(
        account: 'tv.tv.0e208908bebea19a',
        displayName: '小米电视',
        machineName: '客厅',
      ),
      '小米电视',
    );
    expect(
      DeviceDisplayName.resolve(
        account: 'tv.tv.0e208908bebea19a',
        machineName: '客厅',
      ),
      '客厅',
    );
    expect(
      DeviceDisplayName.resolve(account: 'tv.tv.0e208908bebea19a'),
      'tv.tv.0e208908bebea19a',
    );
  });

  test('历史占位符与空白层一律跳过', () {
    expect(
      DeviceDisplayName.resolve(
        account: 'tv.tv.0e208908bebea19a',
        alias: '  ',
        displayName: ' ',
        machineName: '未命名设备',
      ),
      'tv.tv.0e208908bebea19a',
    );
  });

  test('别名两侧空白会被裁掉', () {
    expect(
      DeviceDisplayName.resolve(account: 'acct', alias: ' 客厅电视 '),
      '客厅电视',
    );
  });
}
