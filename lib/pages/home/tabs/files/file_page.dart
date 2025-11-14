import 'package:flutter/material.dart';
import 'package:potatokid_clipboard/framework/base/base_stateless_sub_widget.dart';
import 'package:potatokid_clipboard/pages/home/tabs/files/controller/file_controller.dart';
import 'package:potatokid_clipboard/pages/home/tabs/files/file_download_page.dart';

class FilePage extends BaseStatelessSubWidget<FileController> {
  const FilePage({super.key});

  @override
  Widget buildBody(BuildContext context) {
    return const FileDownloadPage();
  }
}
