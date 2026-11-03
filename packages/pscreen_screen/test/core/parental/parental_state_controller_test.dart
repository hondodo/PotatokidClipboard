import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_screen/core/parental/parental_config.dart';
import 'package:pscreen_screen/core/parental/parental_state_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `ParentalStateController` 阶段 3 双源优先级与选人状态（三 key 解耦）：
/// - 启动加载：服务端缓存（`parental_server_config_v1`）优先，其次本地调试
///   配置（`parental_local_config_v1`）；选中状态独立在
///   `parental_active_ids_v1`（配置推送冲不掉电视端选人结果）；
/// - `applyServerConfig`：服务端 parental 为对象即为准（owner 富化），
///   管理端清除（null）回退本地调试配置；
/// - `setActiveChildren`：悬空 id 过滤 + 确认即回调（`parental_child_active` 上报口）。
///
/// 单例按文件内声明顺序串行推进（`ensureLoaded` 只读一次，后续用
/// `applyServerConfig` 驱动到各自前置状态）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  tearDown(() {
    final ParentalStateController c = ParentalStateController.instance;
    c.onActiveChildrenChanged = null;
    // 收尾停表：纯 test() 不检查 pending Timer，但避免单例 1s ticker 带到
    // 后续测试文件（enabled:false → configure 内部 _stopTicker）。
    c.timer.configure(
      enabled: false,
      profiles: const <String, ChildProfile>{},
      quietHours: const <QuietHour>[],
      activeChildIds: const <String>[],
    );
  });

  test('启动加载：服务端缓存优先，activeIds 独立持久化并过滤悬空 id', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      // 本地调试配置（应被服务端缓存压过）。
      ParentalStateController.storageKey: jsonEncode(<String, dynamic>{
        'mode': 'on',
        'children': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'local1', 'name': '本地档案'},
        ],
      }),
      // 服务端缓存（管理端已配置）。
      ParentalStateController.serverStorageKey: jsonEncode(<String, dynamic>{
        'mode': 'on',
        'activeChildIds': <String>['a'],
        'children': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'a', 'name': '甲'},
          <String, dynamic>{'id': 'b', 'name': '乙'},
        ],
      }),
      // 电视端自己的选择：b 有效、ghost 悬空。
      ParentalStateController.activeIdsStorageKey:
          jsonEncode(<String>['b', 'ghost']),
    });

    final ParentalStateController c = ParentalStateController.instance;
    await c.timer.ensureLoaded();
    await c.ensureLoaded();

    expect(c.loaded, isTrue);
    expect(c.serverConfigured, isTrue);
    // 服务端缓存生效（不是本地 local1）。
    expect(
      c.config.children.map((ChildProfile p) => p.id).toList(),
      <String>['a', 'b'],
    );
    expect(c.enabled, isTrue);
    // 选中状态独立读取 + 悬空过滤（ghost 剔除，保留 b）。
    expect(c.activeChildIds, <String>['b']);
  });

  test('applyServerConfig：服务端为准并富化 owner；清除时回退本地调试', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      ParentalStateController.storageKey: jsonEncode(<String, dynamic>{
        'mode': 'off',
        'children': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'local1', 'name': '本地档案'},
        ],
      }),
    });
    final ParentalStateController c = ParentalStateController.instance;
    // 单例跨测试携带上一例的选中（['b']，在新配置中悬空）→ 先清空，
    // 顺带覆盖「首次拿到服务端配置且无选择 → 播种默认预选」分支。
    await c.setActiveChildren(const <String>[]);

    // 服务端 parental 是对象 → 以服务端为准；ownerAccount 空 → 同帧 owner 富化。
    await c.applyServerConfig(<String, dynamic>{
      'owner': '1234567',
      'parental': <String, dynamic>{
        'mode': 'on',
        'ownerAccount': '',
        'activeChildIds': <String>['a'],
        'children': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'a', 'name': '甲'},
        ],
      },
    });
    expect(c.serverConfigured, isTrue);
    expect(c.enabled, isTrue);
    expect(c.config.ownerAccount, '1234567');
    expect(c.activeChildIds, <String>['a']);

    // 管理端清除 parental → 回退本地调试配置（mode=off → 判定式不成立）。
    await c.applyServerConfig(<String, dynamic>{'parental': null});
    expect(c.serverConfigured, isFalse);
    expect(c.config.children, hasLength(1));
    expect(c.config.children.single.id, 'local1');
    expect(c.enabled, isFalse);
    // 判定式不再成立 → 解除管控（清空选中）。
    expect(c.activeChildIds, isEmpty);
  });

  test('setActiveChildren：悬空过滤 + 确认即回调（上报口）', () async {
    final ParentalStateController c = ParentalStateController.instance;
    final List<List<String>> reported = <List<String>>[];
    c.onActiveChildrenChanged = reported.add;

    await c.applyServerConfig(<String, dynamic>{
      'parental': <String, dynamic>{
        'mode': 'on',
        'children': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'a', 'name': '甲'},
          <String, dynamic>{'id': 'b', 'name': '乙'},
        ],
        'activeChildIds': <String>['a'],
      },
    });

    // 部分悬空 → 过滤后应用（结果与当前相同也照发回调：确认即上报）。
    await c.setActiveChildren(<String>['a', 'ghost']);
    expect(c.activeChildIds, <String>['a']);
    expect(reported, <List<String>>[
      <String>['a'],
    ]);

    // 有变化 → 回调携带新选择。
    await c.setActiveChildren(<String>['b']);
    expect(c.activeChildIds, <String>['b']);
    expect(reported, <List<String>>[
      <String>['a'],
      <String>['b'],
    ]);

    // 全部悬空 → 视为未选（回退选人页）。
    await c.setActiveChildren(<String>['ghost']);
    expect(c.activeChildIds, isEmpty);
    expect(reported.last, isEmpty);

    c.onActiveChildrenChanged = null;
  });
}
