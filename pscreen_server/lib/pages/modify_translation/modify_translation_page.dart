import 'package:app_translator_web/pages/modify_translation/widget/modify_translation_page_content.dart';
import 'package:flutter/material.dart';

class ModifyTranslationPage extends StatefulWidget {
  const ModifyTranslationPage({super.key});

  @override
  State<ModifyTranslationPage> createState() => _ModifyTranslationPageState();
}

class _ModifyTranslationPageState extends State<ModifyTranslationPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // appBar: AppBar(
      //   title: const Text('修改翻译'),
      //   backgroundColor: Colors.blue,
      //   foregroundColor: Colors.white,
      //   leading: IconButton(
      //     icon: const Icon(Icons.arrow_back),
      //     onPressed: () => Navigator.pop(context),
      //   ),
      // ),
      body: const ModifyTranslationPageContent(),
    );
  }
}
