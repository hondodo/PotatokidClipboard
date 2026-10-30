import 'package:flutter/widgets.dart';

class OnlineDot extends StatelessWidget {
  const OnlineDot({super.key, required this.online});

  final bool online;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: online ? const Color(0xFF34C759) : const Color(0xFFBDBDBD),
      ),
    );
  }
}
