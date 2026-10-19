import 'dart:convert';
import 'dart:typed_data';
import 'dart:async';
import 'package:app_translator_web/app/app_const.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import '../../../apis.dart';

class UploadPageContent extends StatefulWidget {
  const UploadPageContent({super.key});

  @override
  State<UploadPageContent> createState() => _UploadPageContentState();
}

class _UploadPageContentState extends State<UploadPageContent> {
  PlatformFile? selectedFile;
  bool isUploading = false;
  String uploadStatus = '';
  String? errorMessage;

  // 选择文件
  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        setState(() {
          selectedFile = result.files.first;
          errorMessage = null;
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = '选择文件时出错: $e';
      });
    }
  }

  // 上传文件到指定目录
  Future<void> _uploadFile() async {
    if (selectedFile == null) {
      setState(() {
        errorMessage = '请先选择一个文件';
      });
      return;
    }

    setState(() {
      isUploading = true;
      uploadStatus = '正在上传...';
      errorMessage = null;
    });

    try {
      // 读取文件内容
      Uint8List fileBytes = selectedFile!.bytes!;
      String fileName = selectedFile!.name;

      // 创建multipart请求
      var request = http.MultipartRequest(
        'POST',
        Uri.parse(Apis.upload),
      );

      // 添加文件
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          fileBytes,
          filename: fileName,
        ),
      );

      // 添加额外的字段（可选）
      request.fields['uploadPath'] = '/uploads'; // 指定保存目录
      request.fields['timestamp'] =
          DateTime.now().millisecondsSinceEpoch.toString();

      // 发送请求并等待响应
      var streamedResponse = await request.send();

      // 立即将流转换为 Response（确保流只被读取一次）
      http.Response response;
      try {
        response = await http.Response.fromStream(streamedResponse);
      } catch (streamError) {
        // 如果 fromStream 失败，创建一个空的响应对象
        response = http.Response('', streamedResponse.statusCode,
            headers: streamedResponse.headers);
        print('转换响应流失败，使用空响应: $streamError');
      }

      int statusCode = response.statusCode;
      String responseBody = response.body;

      // 解析响应数据
      Map<String, dynamic>? responseData;
      try {
        responseData = json.decode(responseBody) as Map<String, dynamic>;
      } catch (e) {
        // 如果响应不是有效的JSON，使用空数据
        responseData = null;
      }

      if (statusCode == 200) {
        if (responseData != null &&
            responseData[AppConst.CODE] == AppConst.CODE_SUCCESS) {
          setState(() {
            uploadStatus = '文件上传成功！';
            selectedFile = null;
          });
        } else {
          setState(() {
            errorMessage = '上传失败: ${responseData?[AppConst.MSG] ?? '未知错误'}';
          });
        }
      } else {
        setState(() {
          errorMessage =
              '上传失败: HTTP $statusCode - ${responseData?[AppConst.MSG] ?? responseBody}';
        });
      }
    } catch (e) {
      String errorMsg = '上传过程中出错: $e';

      // 检查是否是连接错误
      if (e.toString().contains('Failed to fetch') ||
          e.toString().contains('Connection refused')) {
        errorMsg = '无法连接到服务器。请确保服务器正在运行在 ${Apis.baseUrl}';
      } else if (e.toString().contains('ClientException')) {
        errorMsg = '网络连接错误。请检查网络连接或服务器状态。';
      } else if (e.toString().contains('Stream has already been listened to')) {
        errorMsg = '响应处理错误。请重试上传。';
      }

      setState(() {
        errorMessage = errorMsg;
      });
    } finally {
      setState(() {
        isUploading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(16.0),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // 文件选择区域
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '选择文件',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _pickFile,
                              icon: const Icon(Icons.folder_open),
                              label: const Text('选择文件'),
                            ),
                          ),
                        ],
                      ),
                      Visibility(
                        visible: selectedFile != null,
                        child: Column(
                          children: [
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.only(top: 16),
                              child: Text(
                                '已选择: ${selectedFile?.name ?? ''}',
                                style: const TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.only(top: 16),
                              child: ElevatedButton.icon(
                                onPressed: isUploading ? null : _uploadFile,
                                icon: const Icon(Icons.cloud_upload),
                                label: const Text('上传到服务器'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 32,
                                    vertical: 16,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Row(
                      //   children: [
                      //     Expanded(
                      //       child: OutlinedButton.icon(
                      //         onPressed: _pickFile,
                      //         icon: const Icon(Icons.folder_open),
                      //         label: const Text('选择文件'),
                      //       ),
                      //     ),
                      //     const SizedBox(width: 12),
                      //     if (selectedFile != null)
                      //       Expanded(
                      //         child: Text(
                      //           '已选择: ${selectedFile!.name}',
                      //           style: const TextStyle(
                      //             color: Colors.green,
                      //             fontWeight: FontWeight.w500,
                      //           ),
                      //         ),
                      //       ),
                      //   ],
                      // ),
                      // const SizedBox(height: 16),
                      // Center(
                      //   child: ElevatedButton.icon(
                      //     onPressed: isUploading ? null : _uploadFile,
                      //     icon: const Icon(Icons.cloud_upload),
                      //     label: const Text('上传到服务器'),
                      //     style: ElevatedButton.styleFrom(
                      //       backgroundColor: Colors.blue,
                      //       foregroundColor: Colors.white,
                      //       padding: const EdgeInsets.symmetric(
                      //         horizontal: 32,
                      //         vertical: 16,
                      //       ),
                      //     ),
                      //   ),
                      // ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // 状态显示
              if (isUploading ||
                  uploadStatus.isNotEmpty ||
                  errorMessage != null)
                Card(
                  color: errorMessage != null
                      ? Colors.red.shade50
                      : Colors.blue.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '状态信息',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (isUploading)
                          const Row(
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(width: 8),
                              Text('处理中...'),
                            ],
                          ),
                        if (uploadStatus.isNotEmpty)
                          Text(
                            uploadStatus,
                            style: TextStyle(
                              color: errorMessage != null
                                  ? Colors.red
                                  : Colors.green,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        if (errorMessage != null)
                          Text(
                            errorMessage!,
                            style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 16),

              // 使用说明
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '使用说明',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '1. 点击"选择文件"按钮选择要上传的文件（最大600MB）\n'
                        '2. 点击"上传到服务器"将文件发送到服务器\n'
                        '3. 上传过程中请勿关闭页面',
                        style: TextStyle(fontSize: 14),
                      ),
                      // const SizedBox(height: 12),
                      // Container(
                      //   padding: const EdgeInsets.all(8.0),
                      //   decoration: BoxDecoration(
                      //     color: Colors.blue.shade50,
                      //     borderRadius: BorderRadius.circular(4),
                      //     border: Border.all(color: Colors.blue.shade200),
                      //   ),
                      //   child: Text(
                      //     Apis.debugInfo,
                      //     style: TextStyle(
                      //       fontSize: 12,
                      //       color: Colors.blue.shade700,
                      //       fontFamily: 'monospace',
                      //     ),
                      //   ),
                      // ),
                    ],
                  ),
                ),
              ),
            ]),
          ),
        ),
      ],
    );
  }
}
