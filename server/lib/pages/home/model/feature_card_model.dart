import 'package:flutter/material.dart';

class FeatureCardModel {
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final String route;

  FeatureCardModel(
      {required this.title,
      required this.description,
      required this.icon,
      required this.color,
      required this.route});
}
