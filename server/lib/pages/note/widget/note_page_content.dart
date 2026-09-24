import 'dart:convert';
import 'dart:html' as html;
import 'package:app_translator_web/app/app_const.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../apis.dart';
import '../../../utils/time_utils.dart';
import '../../../utils/cookie_helper.dart';

class NotePageContent extends StatefulWidget {
  const NotePageContent({super.key});
  @override
  State<NotePageContent> createState() => _NotePageContentState();
}

class _NotePageContentState extends State<NotePageContent> {
  final TextEditingController _contentController = TextEditingController();

  bool _isLoading = false;
  String _currentUsername = '';
  List<Note> _notes = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _getCurrentUser();
  }

  void _getCurrentUser() {
    final username = CookieHelper.getCookie('username');
    if (username != null && username.isNotEmpty) {
      setState(() {
        _currentUsername = username;
      });
      _loadNotes();
    } else {
      setState(() {
        _currentUsername = '';
      });
    }
  }

  @override
  void dispose() {
    _contentController.dispose();
    super.dispose();
  }

  // 保存笔记
  Future<void> _saveNote() async {
    if (_currentUsername.isEmpty) {
      _showSnackBar('用户未登录', Colors.red);
      return;
    }

    if (_contentController.text.trim().isEmpty) {
      _showSnackBar('请输入笔记内容', Colors.red);
      return;
    }

    // 调试信息：检查登录状态
    final username = CookieHelper.getCookie('username');
    print('🔍 调试信息 - 保存笔记 - 当前用户名: $username');
    print('🔍 调试信息 - 保存笔记 - _currentUsername: $_currentUsername');
    print('🔍 调试信息 - 保存笔记 - API地址: ${Apis.notes}');

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await html.HttpRequest.request(
        Apis.notes,
        method: 'POST',
        requestHeaders: {
          'Content-Type': 'application/json',
        },
        sendData: json.encode({
          'content': _contentController.text.trim(),
        }),
      );

      if (response.status == 200) {
        final responseData = jsonDecode(response.responseText!);
        if (responseData[AppConst.CODE] == AppConst.CODE_SUCCESS) {
          _showSnackBar('笔记保存成功！', Colors.green);
          _contentController.clear();
          _loadNotes();
        } else {
          _showSnackBar('笔记保存失败: ${responseData[AppConst.MSG]}', Colors.red);
        }
      } else {
        _showSnackBar('保存失败: ${response.status}', Colors.red);
      }
    } catch (e) {
      _showSnackBar('保存失败: $e', Colors.red);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 加载笔记
  Future<void> _loadNotes() async {
    if (_currentUsername.isEmpty) {
      _showSnackBar('用户未登录', Colors.orange);
      return;
    }

    // 调试信息：检查登录状态
    final username = CookieHelper.getCookie('username');
    debugPrint('🔍 调试信息 - 当前用户名: $username');
    debugPrint('🔍 调试信息 - _currentUsername: $_currentUsername');
    debugPrint('🔍 调试信息 - API地址: ${Apis.notes}');

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await http.get(
        Uri.parse(Apis.notes),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data[AppConst.CODE] == AppConst.CODE_SUCCESS) {
          setState(() {
            _notes = (data[AppConst.DATA]['notes'] as List)
                .map((note) => Note.fromJson(note))
                .toList();
          });
        } else {
          setState(() {
            _errorMessage = data[AppConst.MSG] ?? '获取笔记失败';
          });
        }
      } else {
        setState(() {
          _errorMessage = '服务器错误: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = '网络错误: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 删除笔记
  Future<void> _deleteNote(String noteId) async {
    try {
      final response = await http.delete(
        Uri.parse(Apis.deleteNote(noteId)),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        if (responseData[AppConst.CODE] == AppConst.CODE_SUCCESS) {
          _showSnackBar('笔记删除成功', Colors.green);
          _loadNotes();
        } else {
          _showSnackBar('笔记删除失败: ${responseData[AppConst.MSG]}', Colors.red);
        }
      } else {
        _showSnackBar('删除失败: ${response.statusCode}', Colors.red);
      }
    } catch (e) {
      _showSnackBar('删除失败: $e', Colors.red);
    }
  }

  // 导出笔记为TXT文件
  Future<void> _exportNote(Note note) async {
    try {
      // 生成文件名：username_xxxx.txt
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = '${note.username}_$timestamp.txt';

      // 创建文件内容
      final content = note.content;

      // 创建Blob并下载
      final blob = html.Blob([content], 'text/plain');
      final url = html.Url.createObjectUrlFromBlob(blob);
      // final anchor =
      html.AnchorElement(href: url)
        ..setAttribute('download', fileName)
        ..click();
      html.Url.revokeObjectUrl(url);

      _showSnackBar('笔记导出成功', Colors.green);
    } catch (e) {
      _showSnackBar('导出失败: $e', Colors.red);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(16.0),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // 当前用户信息
              if (_currentUsername.isNotEmpty) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Icon(
                          Icons.person,
                          color: Colors.purple.shade700,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '当前用户: $_currentUsername',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.purple.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // 添加笔记区域
              if (_currentUsername.isNotEmpty) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '添加新笔记',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _contentController,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: '笔记内容',
                            hintText: '请输入您的笔记内容...',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.note),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isLoading ? null : _saveNote,
                            icon: _isLoading
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.save),
                            label: Text(_isLoading ? '保存中...' : '保存笔记'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                const Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        const Icon(Icons.info, color: Colors.orange, size: 48),
                        const SizedBox(height: 16),
                        const Text(
                          '用户未登录',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '请先登录您的账户，然后就可以创建和管理笔记了',
                          style: TextStyle(color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 16),

              // 笔记列表区域
              if (_currentUsername.isNotEmpty) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              '笔记列表',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            TextButton.icon(
                              onPressed: _loadNotes,
                              icon: const Icon(Icons.refresh),
                              label: const Text('刷新'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (_isLoading)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(32.0),
                              child: CircularProgressIndicator(),
                            ),
                          )
                        else if (_errorMessage != null)
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Column(
                              children: [
                                const Icon(Icons.error,
                                    color: Colors.red, size: 48),
                                const SizedBox(height: 8),
                                Text(
                                  _errorMessage!,
                                  style: const TextStyle(color: Colors.red),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  onPressed: _loadNotes,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('重试'),
                                ),
                              ],
                            ),
                          )
                        else if (_notes.isEmpty)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(32.0),
                              child: Column(
                                children: [
                                  Icon(Icons.note,
                                      size: 64, color: Colors.grey),
                                  SizedBox(height: 16),
                                  Text(
                                    '暂无笔记',
                                    style: TextStyle(
                                        fontSize: 18, color: Colors.grey),
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    '请添加您的第一条笔记',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          ..._notes.map((note) => Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: Colors.purple,
                                    child: const Icon(Icons.note,
                                        color: Colors.white),
                                  ),
                                  title: Text(
                                    note.content.length > 50
                                        ? '${note.content.substring(0, 50)}...'
                                        : note.content,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w500),
                                  ),
                                  subtitle: Text(
                                    '创建时间: ${_formatDateTime(note.createdAt)}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  trailing: PopupMenuButton<String>(
                                    onSelected: (value) {
                                      if (value == 'export') {
                                        _exportNote(note);
                                      } else if (value == 'delete') {
                                        _showDeleteDialog(note);
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(
                                        value: 'export',
                                        child: Row(
                                          children: [
                                            Icon(Icons.download,
                                                color: Colors.blue),
                                            SizedBox(width: 8),
                                            Text('导出'),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Row(
                                          children: [
                                            Icon(Icons.delete,
                                                color: Colors.red),
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
                    ),
                  ),
                ),
              ],
            ]),
          ),
        ),
      ],
    );
  }

  void _showDeleteDialog(Note note) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text(
            '确定要删除这条笔记吗？\n\n"${note.content.length > 30 ? '${note.content.substring(0, 30)}...' : note.content}"'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _deleteNote(note.id);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(String dateTime) {
    return TimeUtils.formatLocalTime(dateTime);
  }
}

// 笔记数据类
class Note {
  final String id;
  final String username;
  final String content;
  final String createdAt;

  Note({
    required this.id,
    required this.username,
    required this.content,
    required this.createdAt,
  });

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      id: json['id'] ?? '',
      username: json['username'] ?? '',
      content: json['content'] ?? '',
      createdAt: json['createdAt'] ?? '',
    );
  }
}
