import 'package:flutter/material.dart';

/// 发送端主页占位（Task 4 填充真 UI）。
class SendPage extends StatelessWidget {
  const SendPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('发送')),
      body: const Center(child: Text('发送页占位（Task 4）')),
    );
  }
}
