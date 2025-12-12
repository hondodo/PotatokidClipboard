/// GENERATED CODE - DO NOT MODIFY BY HAND
/// *****************************************************
///  FlutterGen
/// *****************************************************

// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: directives_ordering,unnecessary_import,implicit_dynamic_list_literal,deprecated_member_use

import 'package:flutter/widgets.dart';

class $AssetsDatasGen {
  const $AssetsDatasGen();

  /// File path: assets/datas/timezone.csv
  String get timezone => 'assets/datas/timezone.csv';

  /// List of all assets
  List<String> get values => [timezone];
}

class $AssetsImagesGen {
  const $AssetsImagesGen();

  /// Directory path: assets/images/common
  $AssetsImagesCommonGen get common => const $AssetsImagesCommonGen();

  /// Directory path: assets/images/icon
  $AssetsImagesIconGen get icon => const $AssetsImagesIconGen();
}

class $AssetsImagesCommonGen {
  const $AssetsImagesCommonGen();

  /// File path: assets/images/common/common_loading.png
  AssetGenImage get commonLoading =>
      const AssetGenImage('assets/images/common/common_loading.png');

  /// List of all assets
  List<AssetGenImage> get values => [commonLoading];
}

class $AssetsImagesIconGen {
  const $AssetsImagesIconGen();

  /// File path: assets/images/icon/icon_off.ico
  String get iconOffIco => 'assets/images/icon/icon_off.ico';

  /// File path: assets/images/icon/icon_off.png
  AssetGenImage get iconOffPng =>
      const AssetGenImage('assets/images/icon/icon_off.png');

  /// File path: assets/images/icon/icon_on.ico
  String get iconOnIco => 'assets/images/icon/icon_on.ico';

  /// File path: assets/images/icon/icon_on.pdn
  String get iconOnPdn => 'assets/images/icon/icon_on.pdn';

  /// File path: assets/images/icon/icon_on.png
  AssetGenImage get iconOnPng =>
      const AssetGenImage('assets/images/icon/icon_on.png');

  /// List of all assets
  List<dynamic> get values => [
    iconOffIco,
    iconOffPng,
    iconOnIco,
    iconOnPdn,
    iconOnPng,
  ];
}

class Assets {
  const Assets._();

  static const $AssetsDatasGen datas = $AssetsDatasGen();
  static const $AssetsImagesGen images = $AssetsImagesGen();
}

class AssetGenImage {
  const AssetGenImage(this._assetName, {this.size, this.flavors = const {}});

  final String _assetName;

  final Size? size;
  final Set<String> flavors;

  Image image({
    Key? key,
    AssetBundle? bundle,
    ImageFrameBuilder? frameBuilder,
    ImageErrorWidgetBuilder? errorBuilder,
    String? semanticLabel,
    bool excludeFromSemantics = false,
    double? scale,
    double? width,
    double? height,
    Color? color,
    Animation<double>? opacity,
    BlendMode? colorBlendMode,
    BoxFit? fit,
    AlignmentGeometry alignment = Alignment.center,
    ImageRepeat repeat = ImageRepeat.noRepeat,
    Rect? centerSlice,
    bool matchTextDirection = false,
    bool gaplessPlayback = true,
    bool isAntiAlias = false,
    String? package,
    FilterQuality filterQuality = FilterQuality.medium,
    int? cacheWidth,
    int? cacheHeight,
  }) {
    return Image.asset(
      _assetName,
      key: key,
      bundle: bundle,
      frameBuilder: frameBuilder,
      errorBuilder: errorBuilder,
      semanticLabel: semanticLabel,
      excludeFromSemantics: excludeFromSemantics,
      scale: scale,
      width: width,
      height: height,
      color: color,
      opacity: opacity,
      colorBlendMode: colorBlendMode,
      fit: fit,
      alignment: alignment,
      repeat: repeat,
      centerSlice: centerSlice,
      matchTextDirection: matchTextDirection,
      gaplessPlayback: gaplessPlayback,
      isAntiAlias: isAntiAlias,
      package: package,
      filterQuality: filterQuality,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
    );
  }

  ImageProvider provider({AssetBundle? bundle, String? package}) {
    return AssetImage(_assetName, bundle: bundle, package: package);
  }

  String get path => _assetName;

  String get keyName => _assetName;
}
