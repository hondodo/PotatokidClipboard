import 'package:flutter/material.dart';
import 'package:potatokid_clipboard/framework/base/base_stateless_sub_widget.dart';
import 'package:potatokid_clipboard/pages/home/tabs/files/controller/file_upload_controller.dart';

class FileUploadPage extends BaseStatelessSubWidget<FileUploadController> {
  const FileUploadPage({super.key});

  @override
  Widget buildBody(BuildContext context) {
    return Center(
      child: Text('上传'),
    );
  }
}
