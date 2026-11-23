/// 主页卡片拖拽顺序的纯计算逻辑。
///
/// 顺序模型：
/// - 「全部」维护一份全局顺序；
/// - 每个家庭维护一份家庭顺序；
/// - 房间不单独存，房间视图直接过滤所属家庭的顺序。
///
/// 联动规则（家庭 → 全部单向）：
/// - 在家庭/房间拖动：更新家庭顺序，并把该家庭卡片在全局顺序里的
///   槽位替换为新顺序；其他家庭的卡片位置不变；
/// - 在「全部」拖动：只更新全局顺序，不反写家庭顺序。
///
/// 新卡片：保存列表里不存在的 key 追加到末尾，保持默认排序。
class CardOrderPlan {
  const CardOrderPlan({required this.allOrder, required this.homeOrders});

  final List<String> allOrder;
  final Map<String, List<String>> homeOrders;
}

class CardOrderPlanner {
  const CardOrderPlanner._();

  /// 合并保存顺序与当前卡片：保留墓碑 key，新 key 追加到末尾。
  static List<String> merge(List<String> saved, Iterable<String> currentKeys) {
    final List<String> result = <String>[];
    final Set<String> seen = <String>{};
    for (final String key in saved) {
      if (key.isNotEmpty && seen.add(key)) result.add(key);
    }
    for (final String key in currentKeys) {
      if (key.isNotEmpty && seen.add(key)) result.add(key);
    }
    return result;
  }

  /// 计算一次拖拽后的全局顺序与家庭顺序。
  ///
  /// [allCurrentKeys] 为当前全部卡片 key（默认排序）；
  /// [homeByKey] 为卡片 key → 家庭名（`''` 表示未分配家庭）；
  /// [viewHome] 为 `''` 表示「全部」，否则为当前家庭名；
  /// [visibleNewOrder] 为当前视图拖动后的可见卡片顺序。
  static CardOrderPlan apply({
    required List<String> allOrder,
    required Map<String, List<String>> homeOrders,
    required List<String> allCurrentKeys,
    required Map<String, String> homeByKey,
    required String viewHome,
    required List<String> visibleNewOrder,
  }) {
    final Set<String> currentKeySet = allCurrentKeys.toSet();
    final List<String> visible = <String>[];
    final Set<String> visibleSeen = <String>{};
    for (final String key in visibleNewOrder) {
      if (currentKeySet.contains(key) && visibleSeen.add(key)) {
        visible.add(key);
      }
    }
    if (visible.isEmpty) {
      return CardOrderPlan(
        allOrder: merge(allOrder, allCurrentKeys),
        homeOrders: <String, List<String>>{
          for (final MapEntry<String, List<String>> entry in homeOrders.entries)
            entry.key: List<String>.of(entry.value),
        },
      );
    }

    final List<String> all = merge(allOrder, allCurrentKeys);
    final Map<String, List<String>> homes = <String, List<String>>{
      for (final MapEntry<String, List<String>> entry in homeOrders.entries)
        entry.key: List<String>.of(entry.value),
    };

    // 「全部」视图：只改全局顺序。
    if (viewHome.isEmpty) {
      return CardOrderPlan(
        allOrder: _replaceSlots(all, visible.toSet(), visible),
        homeOrders: homes,
      );
    }

    // 家庭 / 房间视图：先重排家庭顺序，再同步全局顺序中该家庭的槽位。
    final List<String> homeCurrentKeys = allCurrentKeys
        .where((String key) => homeByKey[key] == viewHome)
        .toList(growable: false);
    if (homeCurrentKeys.isEmpty) {
      return CardOrderPlan(allOrder: all, homeOrders: homes);
    }

    final List<String> savedHome = homes[viewHome]?.isNotEmpty == true
        ? homes[viewHome]!
        : all
              .where((String key) => homeByKey[key] == viewHome)
              .toList(growable: false);
    final List<String> home = merge(savedHome, homeCurrentKeys);
    final List<String> newHome = _replaceSlots(home, visible.toSet(), visible);
    homes[viewHome] = newHome;

    // 家庭顺序里只取当前存在的卡片，用于替换全局槽位。
    final Set<String> homeKeySet = homeCurrentKeys.toSet();
    final List<String> currentHomeOrder = newHome
        .where((String key) => homeKeySet.contains(key))
        .toList(growable: false);
    final List<String> newAll = _replaceSlots(
      all,
      homeKeySet,
      currentHomeOrder,
    );

    return CardOrderPlan(allOrder: newAll, homeOrders: homes);
  }

  /// 把 [base] 中属于 [visibleSet] 的槽位替换为 [newVisible]。
  ///
  /// 槽位保持不动，因此被过滤掉的卡片位置不受影响。
  /// [newVisible] 多出的新卡片追加到末尾；不足时删除末尾多余槽位。
  static List<String> _replaceSlots(
    List<String> base,
    Set<String> visibleSet,
    List<String> newVisible,
  ) {
    final List<int> positions = <int>[];
    for (int i = 0; i < base.length; i++) {
      if (visibleSet.contains(base[i])) positions.add(i);
    }
    final List<String> result = List<String>.of(base);
    if (newVisible.length <= positions.length) {
      for (int i = 0; i < newVisible.length; i++) {
        result[positions[i]] = newVisible[i];
      }
      for (int i = positions.length - 1; i >= newVisible.length; i--) {
        result.removeAt(positions[i]);
      }
    } else {
      for (int i = 0; i < positions.length; i++) {
        result[positions[i]] = newVisible[i];
      }
      result.addAll(newVisible.sublist(positions.length));
    }
    return result;
  }
}
