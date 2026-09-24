import 'package:freezed_annotation/freezed_annotation.dart';

part 'home_model.freezed.dart';
part 'home_model.g.dart';

/// 首页列表项数据模型（freezed + json_serializable）
@freezed
abstract class HomeModel with _$HomeModel {
  const factory HomeModel({
    @Default('') String id,
    @Default('') String title,
    @Default('') String subtitle,
  }) = _HomeModel;

  factory HomeModel.fromJson(Map<String, dynamic> json) =>
      _$HomeModelFromJson(json);
}
