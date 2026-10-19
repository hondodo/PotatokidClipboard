import 'package:json_annotation/json_annotation.dart';

part 'ip_model.g.dart';

@JsonSerializable()
class IpModel extends Object {
  @JsonKey(name: 'ip')
  String? ip;

  @JsonKey(name: 'network')
  String? network;

  @JsonKey(name: 'version')
  String? version;

  @JsonKey(name: 'city')
  String? city;

  @JsonKey(name: 'region')
  String? region;

  @JsonKey(name: 'region_code')
  String? regionCode;

  @JsonKey(name: 'country')
  String? country;

  @JsonKey(name: 'country_name')
  String? countryName;

  @JsonKey(name: 'country_code')
  String? countryCode;

  @JsonKey(name: 'country_code_iso3')
  String? countryCodeIso3;

  @JsonKey(name: 'country_capital')
  String? countryCapital;

  @JsonKey(name: 'country_tld')
  String? countryTld;

  @JsonKey(name: 'continent_code')
  String? continentCode;

  @JsonKey(name: 'in_eu')
  bool? inEu;

  @JsonKey(name: 'latitude')
  double? latitude;

  @JsonKey(name: 'longitude')
  double? longitude;

  @JsonKey(name: 'timezone')
  String? timezone;

  @JsonKey(name: 'utc_offset')
  String? utcOffset;

  @JsonKey(name: 'country_calling_code')
  String? countryCallingCode;

  @JsonKey(name: 'currency')
  String? currency;

  @JsonKey(name: 'currency_name')
  String? currencyName;

  @JsonKey(name: 'languages')
  String? languages;

  @JsonKey(name: 'country_area')
  int? countryArea;

  @JsonKey(name: 'country_population')
  int? countryPopulation;

  @JsonKey(name: 'asn')
  String? asn;

  @JsonKey(name: 'org')
  String? org;

  IpModel(
    this.ip,
    this.network,
    this.version,
    this.city,
    this.region,
    this.regionCode,
    this.country,
    this.countryName,
    this.countryCode,
    this.countryCodeIso3,
    this.countryCapital,
    this.countryTld,
    this.continentCode,
    this.inEu,
    this.latitude,
    this.longitude,
    this.timezone,
    this.utcOffset,
    this.countryCallingCode,
    this.currency,
    this.currencyName,
    this.languages,
    this.countryArea,
    this.countryPopulation,
    this.asn,
    this.org,
  );

  factory IpModel.fromJson(Map<String, dynamic> srcJson) =>
      _$IpModelFromJson(srcJson);

  Map<String, dynamic> toJson() => _$IpModelToJson(this);
}
