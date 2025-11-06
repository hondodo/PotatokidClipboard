import 'package:json_annotation/json_annotation.dart';
part 'user_model.g.dart';

@JsonSerializable()
class UserModel {
  bool get isEmpty => id == null || name == null;
  bool get isNotEmpty => !isEmpty;
  bool get isLogin => isNotEmpty;
  bool get isNotLogin => !isLogin;

  @JsonKey(name: 'id')
  int? id;
  @JsonKey(name: 'name')
  String? name;

  @JsonKey(name: 'loginTime')
  String? loginTime;

  @JsonKey(name: 'createdAt')
  String? createdAt;

  UserModel({this.id, this.name});

  factory UserModel.fromJson(Map<String, dynamic> json) =>
      _$UserModelFromJson(json);
  Map<String, dynamic> toJson() => _$UserModelToJson(this);
}
