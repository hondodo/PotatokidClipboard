import 'package:app_translator_web/pages/upload_translation/widget/upload_translation_page_content.dart';
import 'package:flutter/material.dart';

class UploadTranslationPage extends StatefulWidget {
  const UploadTranslationPage({super.key});

  @override
  State<UploadTranslationPage> createState() => _UploadTranslationPageState();
}

class _UploadTranslationPageState extends State<UploadTranslationPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('上传翻译'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: const UploadTranslationPageContent(),
    );
  }
}
