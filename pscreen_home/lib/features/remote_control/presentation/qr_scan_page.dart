import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// 扫码页：扫 TV 端「远程」行二维码，返回账号字符串。
class QrScanPage extends StatefulWidget {
  const QrScanPage({super.key});

  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('扫码')),
      body: MobileScanner(
        onDetect: (BarcodeCapture capture) {
          if (_done) return;
          final String? value = capture.barcodes.isEmpty
              ? null
              : capture.barcodes.first.rawValue;
          if (value == null || value.isEmpty) return;
          _done = true;
          if (!mounted) return;
          Navigator.of(context).pop(value);
        },
      ),
    );
  }
}
