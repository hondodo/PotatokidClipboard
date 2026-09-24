import 'package:flutter_test/flutter_test.dart';
import 'package:potatokid_screen/features/home/application/bloc/home_state.dart';

void main() {
  group('HomeState', () {
    test('initial 状态默认值', () {
      final HomeState state = HomeState.initial();
      expect(state.isLoading, isFalse);
      expect(state.items, isEmpty);
      expect(state.errorMessage, isNull);
      expect(state.errorType, isNull);
    });

    test('copyWith clearError 清空错误信息', () {
      final HomeState state = HomeState.initial();
      final HomeState loading = state.copyWith(isLoading: true);
      expect(loading.isLoading, isTrue);

      final HomeState cleared = loading.copyWith(
        isLoading: false,
        clearError: true,
      );
      expect(cleared.isLoading, isFalse);
      expect(cleared.errorMessage, isNull);
    });
  });
}
