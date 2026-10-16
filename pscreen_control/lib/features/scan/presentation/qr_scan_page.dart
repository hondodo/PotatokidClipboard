import 'package:flutter/material.dart';

/// 扫码页占位（Task 5 填充真 UI；返回扫码得到的账号字符串）。
class QrScanPage extends StatelessWidget {
  const QrScanPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('扫码')),
      body: Center(
        child: TextButton(
          onPressed: () => Navigator.of(context).pop<String>('TV_001'),
          child: const Text('占位：返回 TV_001（Task 5 填充）'),
        ),
      ),
    );
  }
}
