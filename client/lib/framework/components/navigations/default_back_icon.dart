import 'package:flutter/material.dart';
import '../../../framework/app/app_enum.dart';

class DefaultBackIcon extends StatelessWidget {
  const DefaultBackIcon({super.key, required this.pageStyle});
  final AppPageStyle pageStyle;

  @override
  Widget build(BuildContext context) {
    return pageStyle == AppPageStyle.light
        ? const Icon(Icons.arrow_back_ios_new, color: Colors.black)
        : const Icon(Icons.arrow_back_ios_new, color: Colors.white);
  }
}
