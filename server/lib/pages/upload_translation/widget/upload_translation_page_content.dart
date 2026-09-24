import 'dart:html' as html;
import 'dart:convert';
import 'package:app_translator_web/app/app_const.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../apis.dart';
import '../../../utils/time_utils.dart';

class UploadTranslationPageContent extends StatefulWidget {
  const UploadTranslationPageContent({super.key});

  @override
  State<UploadTranslationPageContent> createState() =>
      _UploadTranslationPageContentState();
}

class _UploadTranslationPageContentState
    extends State<UploadTranslationPageContent> {
  // 文件选择状态
  String? _selectedFileName;
  html.File? _selectedFile;
  String? _selectedSourceFileName;
  html.File? _selectedSourceFile;
  String? _selectedAvailableFileName;
  html.File? _selectedAvailableFile;

  // 其他状态
  String? _selectedApp;
  String? _selectedLanguage;
  bool _isUploading = false;
  List<Map<String, dynamic>> _uploadedFiles = [];
  bool _showUploadedFiles = false;
  bool _isLoadingConfig = true;

  // 动态配置数据
  List<Map<String, dynamic>> _availableApps = [];
  List<Map<String, dynamic>> _availableLanguages = [];

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  // 加载配置
  Future<void> _loadConfig() async {
    try {
      final response = await http.get(
        Uri.parse(Apis.translationConfig),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _availableApps = List<Map<String, dynamic>>.from(
              data[AppConst.DATA]['apps'] ?? []);
          _isLoadingConfig = false;
        });
      } else {
        _showError('加载配置失败: ${response.body}');
        setState(() {
          _isLoadingConfig = false;
        });
      }
    } catch (e) {
      _showError('加载配置失败: $e');
      setState(() {
        _isLoadingConfig = false;
      });
    }
  }

  // 选择翻译文件
  Future<void> _selectFile() async {
    final input = html.FileUploadInputElement();
    input.accept = '.json';
    input.click();

    input.onChange.listen((event) {
      final files = input.files;
      if (files != null && files.isNotEmpty) {
        final file = files[0];
        if (file.name.toLowerCase().endsWith('.json')) {
          setState(() {
            _selectedFileName = file.name;
            _selectedFile = file;
          });
        } else {
          _showError('请选择.json文件');
        }
      }
    });
  }

  // 选择源文文件
  Future<void> _selectSourceFile() async {
    final input = html.FileUploadInputElement();
    input.accept = '.json';
    input.click();

    input.onChange.listen((event) {
      final files = input.files;
      if (files != null && files.isNotEmpty) {
        final file = files[0];
        if (file.name.toLowerCase().endsWith('.json')) {
          setState(() {
            _selectedSourceFileName = file.name;
            _selectedSourceFile = file;
          });
        } else {
          _showError('请选择.json文件');
        }
      }
    });
  }

  // 选择可用值文件
  Future<void> _selectAvailableFile() async {
    final input = html.FileUploadInputElement();
    input.accept = '.keys';
    input.click();

    input.onChange.listen((event) {
      final files = input.files;
      if (files != null && files.isNotEmpty) {
        final file = files[0];
        if (file.name.toLowerCase().endsWith('.keys')) {
          setState(() {
            _selectedAvailableFileName = file.name;
            _selectedAvailableFile = file;
          });
        } else {
          _showError('请选择.keys文件');
        }
      }
    });
  }

  // 上传文件
  Future<void> _uploadFile() async {
    if (_selectedApp == null || _selectedLanguage == null) {
      _showError('请选择App和语言');
      return;
    }

    // 检查是否至少选择了一个文件
    if (_selectedFile == null &&
        _selectedSourceFile == null &&
        _selectedAvailableFile == null) {
      _showError('请至少选择一个文件');
      return;
    }

    // 显示确认对话框
    final confirmed = await _showUploadConfirmation();
    if (!confirmed) {
      return;
    }

    setState(() {
      _isUploading = true;
    });

    try {
      // 使用简单的XMLHttpRequest进行上传
      final request = html.HttpRequest();
      request.open('POST', Apis.uploadTranslation);

      // 监听上传完成
      request.onLoad.listen((event) {
        if (request.status == 200) {
          try {
            final response = json.decode(request.responseText ?? '{}');
            if (response[AppConst.CODE] == AppConst.CODE_SUCCESS) {
              _showSuccess('文件上传成功');
              _loadUploadedFiles();
              setState(() {
                _selectedFileName = null;
                _selectedFile = null;
                _selectedSourceFileName = null;
                _selectedSourceFile = null;
                _selectedAvailableFileName = null;
                _selectedAvailableFile = null;
                _selectedApp = null;
                _selectedLanguage = null;
              });
            } else {
              _showError('上传失败: ${response[AppConst.MSG] ?? '未知错误'}');
            }
          } catch (e) {
            _showError('上传失败: 响应解析错误');
          }
        } else {
          _showError('上传失败: HTTP ${request.status} - ${request.responseText}');
        }
        setState(() {
          _isUploading = false;
        });
      });

      // 监听上传错误
      request.onError.listen((event) {
        _showError('上传失败: 网络错误');
        setState(() {
          _isUploading = false;
        });
      });

      // 创建FormData
      final formData = html.FormData();

      // 添加翻译文件
      if (_selectedFile != null) {
        formData.appendBlob('file', _selectedFile!);
      }

      // 添加源文文件
      if (_selectedSourceFile != null) {
        formData.appendBlob('source', _selectedSourceFile!);
      }

      // 添加可用值文件
      if (_selectedAvailableFile != null) {
        formData.appendBlob('available', _selectedAvailableFile!);
      }

      formData.append('app', _selectedApp!);
      formData.append('language', _selectedLanguage!);

      // 发送请求
      request.send(formData);
    } catch (e) {
      _showError('上传失败: $e');
      setState(() {
        _isUploading = false;
      });
    }
  }

  // 加载已上传的文件
  Future<void> _loadUploadedFiles() async {
    if (_selectedApp == null) return;

    try {
      final response = await http.get(
        Uri.parse(Apis.translationFilesForApp(_selectedApp!)),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data[AppConst.CODE] == AppConst.CODE_SUCCESS) {
          setState(() {
            _uploadedFiles = List<Map<String, dynamic>>.from(
                data[AppConst.DATA]['files'] ?? []);
          });
        } else {
          _showError('加载文件列表失败: ${data[AppConst.MSG]}');
          setState(() {
            _uploadedFiles = [];
          });
        }
      }
    } catch (e) {
      debugPrint('加载文件列表失败: $e');
    }
  }

  // 删除文件
  Future<void> _deleteFile(String fileName) async {
    try {
      final response = await http.delete(
        Uri.parse(Apis.deleteTranslationFile(_selectedApp!, fileName)),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data[AppConst.CODE] == AppConst.CODE_SUCCESS) {
          _showSuccess('文件删除成功');
          _loadUploadedFiles();
        } else {
          _showError('删除失败: ${data[AppConst.MSG]}');
        }
      } else {
        _showError('删除失败: ${response.body}');
      }
    } catch (e) {
      _showError('删除失败: $e');
    }
  }

  // 下载文件
  void _downloadFile(String fileName) {
    final url = Apis.downloadTranslationFile(_selectedApp!, fileName);
    final anchor = html.AnchorElement(href: url);
    anchor.download = fileName;
    anchor.click();
  }

  // 显示备份文件
  void _showBackupFiles(String fileName) async {
    try {
      final response = await http.get(
        Uri.parse(Apis.translationBackups(_selectedApp!, fileName)),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data[AppConst.CODE] == AppConst.CODE_SUCCESS) {
          final backupFiles = List<Map<String, dynamic>>.from(
              data[AppConst.DATA]['files'] ?? []);

          if (mounted) {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: Text('备份文件 - $fileName'),
                content: SizedBox(
                  width: double.maxFinite,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: backupFiles.length,
                    itemBuilder: (context, index) {
                      final backup = backupFiles[index];
                      return ListTile(
                        leading: Icon(Icons.history),
                        title: Text(backup['fileName'] ?? ''),
                        subtitle: Text(
                            '备份时间: ${TimeUtils.formatLocalTime(backup['backupTime'])}'),
                        trailing: IconButton(
                          icon: Icon(Icons.download),
                          onPressed: () =>
                              _downloadBackupFile(backup['fileName']),
                        ),
                      );
                    },
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('关闭'),
                  ),
                ],
              ),
            );
          }
        } else {
          _showError('获取备份文件列表失败: ${data[AppConst.MSG]}');
        }
      } else {
        _showError('获取备份文件列表失败: ${response.body}');
      }
    } catch (e) {
      _showError('获取备份文件列表失败: $e');
    }
  }

  // 下载备份文件
  void _downloadBackupFile(String fileName) {
    final url = Apis.downloadBackupFile(_selectedApp!, fileName);
    final anchor = html.AnchorElement(href: url);
    anchor.download = fileName;
    anchor.click();
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.red),
      );
    }
  }

  void _showSuccess(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: Colors.green),
      );
    }
  }

  // 显示上传确认对话框
  Future<bool> _showUploadConfirmation() async {
    // 构建文件列表信息
    final List<String> selectedFiles = [];
    if (_selectedFile != null) {
      selectedFiles.add('翻译文件: ${_selectedFileName}');
    }
    if (_selectedSourceFile != null) {
      selectedFiles.add('源文文件: ${_selectedSourceFileName}');
    }
    if (_selectedAvailableFile != null) {
      selectedFiles.add('可用值文件: ${_selectedAvailableFileName}');
    }

    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext context) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.upload, color: Colors.blue),
                  SizedBox(width: 8),
                  Text('确认上传'),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '请确认以下上传信息：',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 16),

                    // App信息
                    _buildInfoRow('目标App:', _selectedApp ?? '未选择'),

                    // 语言信息
                    _buildInfoRow('目标语言:', _selectedLanguage ?? '未选择'),

                    SizedBox(height: 12),

                    // 文件信息
                    Text(
                      '上传文件:',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 8),
                    ...selectedFiles
                        .map((file) => Padding(
                              padding: EdgeInsets.only(left: 16, bottom: 4),
                              child: Row(
                                children: [
                                  Icon(Icons.attach_file,
                                      size: 16, color: Colors.grey),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      file,
                                      style: TextStyle(fontSize: 14),
                                    ),
                                  ),
                                ],
                              ),
                            ))
                        .toList(),

                    SizedBox(height: 16),

                    // 警告信息
                    Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning, color: Colors.orange, size: 20),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '如果目标文件已存在，将自动备份原文件',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.orange.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text('取消'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                  child: Text('确认上传'),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  // 构建信息行
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.blue.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingConfig) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('加载配置中...'),
          ],
        ),
      );
    }

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
                      Text(
                        '上传翻译文件',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 16),

                      // 文件选择区域
                      Text(
                        '选择要上传的文件（可多选）',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: 12),

                      // 翻译文件选择
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _selectFile,
                              icon: Icon(Icons.translate),
                              label: Text(_selectedFileName ?? '选择翻译文件(.json)'),
                            ),
                          ),
                          SizedBox(width: 16),
                          if (_selectedFile != null)
                            Icon(Icons.check_circle, color: Colors.green),
                        ],
                      ),

                      SizedBox(height: 12),

                      // 源文文件选择
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _selectSourceFile,
                              icon: Icon(Icons.source),
                              label: Text(_selectedSourceFileName ??
                                  '选择源文文件(source.json)'),
                            ),
                          ),
                          SizedBox(width: 16),
                          if (_selectedSourceFile != null)
                            Icon(Icons.check_circle, color: Colors.green),
                        ],
                      ),

                      SizedBox(height: 12),

                      // 可用值文件选择
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _selectAvailableFile,
                              icon: Icon(Icons.list),
                              label: Text(_selectedAvailableFileName ??
                                  '选择可用值文件(available.keys)'),
                            ),
                          ),
                          SizedBox(width: 16),
                          if (_selectedAvailableFile != null)
                            Icon(Icons.check_circle, color: Colors.green),
                        ],
                      ),

                      SizedBox(height: 16),

                      // App选择
                      DropdownButtonFormField<String>(
                        value: _selectedApp,
                        decoration: InputDecoration(
                          labelText: '选择App',
                          border: OutlineInputBorder(),
                        ),
                        items: _availableApps.map((app) {
                          return DropdownMenuItem<String>(
                            value: app['appName'] as String,
                            child: Text(app['appName'] as String),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedApp = value;
                            _uploadedFiles.clear();
                            _selectedLanguage = null;
                            // 更新可用语言列表
                            if (value != null) {
                              final selectedAppData = _availableApps.firstWhere(
                                (app) => app['appName'] == value,
                                orElse: () => {'languages': []},
                              );
                              _availableLanguages =
                                  List<Map<String, dynamic>>.from(
                                selectedAppData['languages'] ?? [],
                              );
                            } else {
                              _availableLanguages = [];
                            }
                          });
                          if (value != null) {
                            _loadUploadedFiles();
                          }
                        },
                      ),

                      SizedBox(height: 16),

                      // 语言选择
                      DropdownButtonFormField<String>(
                        value: _selectedLanguage,
                        decoration: InputDecoration(
                          labelText: '选择语言',
                          border: OutlineInputBorder(),
                        ),
                        items: _availableLanguages.map((language) {
                          return DropdownMenuItem<String>(
                            value: language['lanName'] as String,
                            child: Text(language['lanName'] as String),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedLanguage = value;
                          });
                        },
                      ),

                      SizedBox(height: 24),

                      // 上传按钮
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isUploading ||
                                  (_selectedFile == null &&
                                      _selectedSourceFile == null &&
                                      _selectedAvailableFile == null) ||
                                  _selectedApp == null ||
                                  _selectedLanguage == null
                              ? null
                              : _uploadFile,
                          icon: _isUploading
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Icon(Icons.upload),
                          label: Text(_isUploading ? '上传中...' : '上传到服务器'),
                          style: ElevatedButton.styleFrom(
                            padding: EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              SizedBox(height: 16),

              // 已上传文件区域
              if (_selectedApp != null) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '$_selectedApp 的翻译文件',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            IconButton(
                              onPressed: () {
                                setState(() {
                                  _showUploadedFiles = !_showUploadedFiles;
                                });
                              },
                              icon: Icon(_showUploadedFiles
                                  ? Icons.expand_less
                                  : Icons.expand_more),
                            ),
                          ],
                        ),
                        if (_showUploadedFiles) ...[
                          SizedBox(height: 16),
                          if (_uploadedFiles.isEmpty)
                            Text('暂无上传的翻译文件')
                          else
                            ..._uploadedFiles.map((file) {
                              final backupCount = file['backupCount'] ?? 0;
                              return ListTile(
                                leading: Icon(Icons.translate),
                                title: Text(file['fileName'] ?? ''),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('语言: ${file['language'] ?? ''}'),
                                    if (backupCount > 0)
                                      Text(
                                        '备份文件: $backupCount 个',
                                        style: TextStyle(
                                          color: Colors.orange,
                                          fontSize: 12,
                                        ),
                                      ),
                                  ],
                                ),
                                trailing: PopupMenuButton(
                                  itemBuilder: (context) => [
                                    PopupMenuItem(
                                      value: 'download',
                                      child: Row(
                                        children: [
                                          Icon(Icons.download),
                                          SizedBox(width: 8),
                                          Text('下载'),
                                        ],
                                      ),
                                    ),
                                    if (backupCount > 0)
                                      PopupMenuItem(
                                        value: 'backups',
                                        child: Row(
                                          children: [
                                            Icon(Icons.history),
                                            SizedBox(width: 8),
                                            Text('查看备份 ($backupCount)'),
                                          ],
                                        ),
                                      ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Row(
                                        children: [
                                          Icon(Icons.delete, color: Colors.red),
                                          SizedBox(width: 8),
                                          Text('删除',
                                              style:
                                                  TextStyle(color: Colors.red)),
                                        ],
                                      ),
                                    ),
                                  ],
                                  onSelected: (value) {
                                    if (value == 'download') {
                                      _downloadFile(file['fileName']);
                                    } else if (value == 'backups') {
                                      _showBackupFiles(file['fileName']);
                                    } else if (value == 'delete') {
                                      _deleteFile(file['fileName']);
                                    }
                                  },
                                ),
                              );
                            }).toList(),
                        ],
                      ],
                    ),
                  ),
                ),
              ],

              SizedBox(height: 16),

              // 使用说明
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
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
                        '1. 选择要上传的文件（可多选）：\n'
                        '   • 翻译文件：目标语言的翻译内容\n'
                        '   • 源文文件：原始文本内容(source.json)\n'
                        '   • 可用值文件：可用的键值对(available.keys)\n'
                        '2. 选择对应的App（从服务器配置获取）\n'
                        '3. 选择翻译语言（从服务器配置获取）\n'
                        '4. 点击"上传到服务器"完成上传\n'
                        '5. 可以查看和管理已上传的翻译文件',
                        style: TextStyle(fontSize: 14),
                      ),
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
