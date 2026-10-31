// ignore_for_file: avoid_web_libraries_in_flutter

import 'dart:convert';
import 'dart:html' as html;
import 'package:app_translator_web/app/app_const.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../apis.dart';
import '../../../utils/time_utils.dart';

class ViewUploadPageContent extends StatefulWidget {
  /// 未登录时为 true：浏览公共上传目录，界面不提供删除（与未登录用户一致）。
  final bool isGuest;

  const ViewUploadPageContent({super.key, this.isGuest = false});

  @override
  State<ViewUploadPageContent> createState() => _ViewUploadPageContentState();
}

class _ViewUploadPageContentState extends State<ViewUploadPageContent> {
  List<FileInfo> files = [];
  bool isLoading = false;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  // 从服务器获取文件列表
  Future<void> _loadFiles() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final response = await http.get(
        Uri.parse(Apis.files),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data[AppConst.CODE] == AppConst.CODE_SUCCESS) {
          setState(() {
            var filesList = data[AppConst.DATA]['files'];
            files = (filesList as List)
                .map((file) => FileInfo.fromJson(file))
                .toList();
          });
        } else {
          setState(() {
            errorMessage = '获取文件列表失败: ${data[AppConst.MSG]}';
          });
        }
      } else {
        setState(() {
          errorMessage = '服务器错误: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        errorMessage = '网络错误: $e';
      });
    } finally {
      setState(() {
        isLoading = false;
      });
    }
  }

  // 删除文件
  Future<void> _deleteFile(String fileName) async {
    try {
      final response = await http.delete(
        Uri.parse('${Apis.deleteFile}/$fileName'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data[AppConst.CODE] == AppConst.CODE_SUCCESS) {
          // 删除成功，重新加载文件列表
          _loadFiles();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('文件删除成功')),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除失败: ${response.statusCode}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('删除失败: $e')),
        );
      }
    }
  }

  // 下载文件
  Future<void> _downloadFile(String fileName) async {
    try {
      final response = await http.get(
        Uri.parse(Apis.downloadFile(fileName)),
      );

      if (response.statusCode == 200) {
        // 创建下载链接
        final bytes = response.bodyBytes;
        final blob = html.Blob([bytes]);
        final url = html.Url.createObjectUrlFromBlob(blob);
        // final anchor =
        html.AnchorElement(href: url)
          ..setAttribute('download', fileName)
          ..click();
        html.Url.revokeObjectUrl(url);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('文件下载开始')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('下载失败: ${response.statusCode}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载失败: $e')),
        );
      }
    }
  }

  // 格式化文件大小
  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  // 格式化日期时间
  String _formatDateTime(String dateTime) {
    return TimeUtils.formatLocalTime(dateTime);
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(16.0),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // 加载状态
              if (isLoading)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Center(
                      child: Column(
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('正在加载文件列表...'),
                        ],
                      ),
                    ),
                  ),
                ),

              // 错误信息
              if (errorMessage != null)
                Card(
                  color: Colors.red.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        const Icon(Icons.error, color: Colors.red, size: 48),
                        const SizedBox(height: 8),
                        Text(
                          errorMessage!,
                          style: const TextStyle(color: Colors.red),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _loadFiles,
                          icon: const Icon(Icons.refresh),
                          label: const Text('重试'),
                        ),
                      ],
                    ),
                  ),
                ),

              // 文件列表
              if (!isLoading && errorMessage == null) ...[
                if (widget.isGuest)
                  Card(
                    color: Colors.amber.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
                        children: [
                          Icon(Icons.folder_shared, color: Colors.amber.shade800),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '访客模式：正在查看公共上传目录，登录后可管理个人文件。',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.amber.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (widget.isGuest) const SizedBox(height: 12),
                // 统计信息
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            Column(
                              children: [
                                Text(
                                  '${files.length}',
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue,
                                  ),
                                ),
                                const Text('文件总数'),
                              ],
                            ),
                            Column(
                              children: [
                                Text(
                                  _formatFileSize(files.fold(
                                      0, (sum, file) => sum + file.size)),
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                                const Text('总大小'),
                              ],
                            ),
                          ],
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

                const SizedBox(height: 16),

                // 文件列表
                if (files.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(32.0),
                      child: Column(
                        children: [
                          const Icon(Icons.folder_open, size: 64, color: Colors.grey),
                          const SizedBox(height: 16),
                          const Text(
                            '暂无上传文件',
                            style: TextStyle(fontSize: 18, color: Colors.grey),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            widget.isGuest
                                ? '公共目录中暂无文件'
                                : '请先上传一些文件',
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ...files.map((file) => Card(
                        margin: const EdgeInsets.only(bottom: 8.0),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _getFileTypeColor(file.name),
                            child: Icon(
                              _getFileTypeIcon(file.name),
                              color: Colors.white,
                            ),
                          ),
                          title: Text(
                            file.name,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('大小: ${_formatFileSize(file.size)}'),
                              Text('上传时间: ${_formatDateTime(file.uploadTime)}'),
                            ],
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'download') {
                                _downloadFile(file.name);
                              } else if (value == 'delete') {
                                _showDeleteDialog(file);
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'download',
                                child: Row(
                                  children: [
                                    Icon(Icons.download, color: Colors.blue),
                                    SizedBox(width: 8),
                                    Text('下载'),
                                  ],
                                ),
                              ),
                              if (!widget.isGuest)
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete, color: Colors.red),
                                      SizedBox(width: 8),
                                      Text('删除'),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      )),
              ],
            ]),
          ),
        ),
      ],
    );
  }

  // 显示删除确认对话框
  void _showDeleteDialog(FileInfo file) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除文件 "${file.name}" 吗？\n此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _deleteFile(file.name);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  // 根据文件扩展名获取图标
  IconData _getFileTypeIcon(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;
    switch (extension) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow;
      case 'txt':
        return Icons.text_snippet;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        return Icons.image;
      case 'mp4':
      case 'avi':
      case 'mov':
        return Icons.video_file;
      case 'mp3':
      case 'wav':
        return Icons.audio_file;
      case 'zip':
      case 'rar':
        return Icons.archive;
      default:
        return Icons.insert_drive_file;
    }
  }

  // 根据文件类型获取颜色
  Color _getFileTypeColor(String fileName) {
    final extension = fileName.toLowerCase().split('.').last;
    switch (extension) {
      case 'pdf':
        return Colors.red;
      case 'doc':
      case 'docx':
        return Colors.blue;
      case 'xls':
      case 'xlsx':
        return Colors.green;
      case 'ppt':
      case 'pptx':
        return Colors.orange;
      case 'txt':
        return Colors.grey;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        return Colors.purple;
      case 'mp4':
      case 'avi':
      case 'mov':
        return Colors.indigo;
      case 'mp3':
      case 'wav':
        return Colors.teal;
      case 'zip':
      case 'rar':
        return Colors.brown;
      default:
        return Colors.blueGrey;
    }
  }
}

// 文件信息数据类
class FileInfo {
  final String name;
  final int size;
  final String uploadTime;

  FileInfo({
    required this.name,
    required this.size,
    required this.uploadTime,
  });

  factory FileInfo.fromJson(Map<String, dynamic> json) {
    return FileInfo(
      name: json['name'] ?? '',
      size: json['size'] ?? 0,
      uploadTime: json['uploadTime'] ?? '',
    );
  }
}
