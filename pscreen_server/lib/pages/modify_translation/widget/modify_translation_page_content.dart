// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:convert';
import 'package:app_translator_web/app/app_const.dart';
import 'package:app_translator_web/pages/modify_translation/widget/modify_translation_setting_widget.dart';
import 'package:app_translator_web/pages/modify_translation/widget/tip_widget.dart';
import 'package:app_translator_web/utils/cookie_helper.dart';
import 'package:app_translator_web/apis.dart';
// import 'package:app_translator_web/utils/real_cookie_storage.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ModifyTranslationPageContent extends StatefulWidget {
  const ModifyTranslationPageContent({super.key});

  @override
  State<ModifyTranslationPageContent> createState() =>
      _ModifyTranslationPageContentState();
}

class _ModifyTranslationPageContentState
    extends State<ModifyTranslationPageContent> {
  // 状态变量
  String? _selectedApp;
  String? _selectedLanguage;
  bool _isLoadingApps = true;
  bool _isLoadingTranslations = false;
  bool _isSaving = false;

  // 数据
  List<Map<String, dynamic>> _availableApps = [];
  List<Map<String, dynamic>> _availableLanguages = [];
  Map<String, dynamic>? _sourceData;
  List<String>? _availableKeys;
  final Map<String, Map<String, dynamic>> _translationData = {};
  final List<TranslationItem> _translationItems = [];

  // 编辑状态
  final Set<String> _editingFields = {}; // 跟踪正在编辑的字段
  final Map<String, TextEditingController> _textControllers =
      {}; // 缓存TextEditingController

  // 筛选状态
  final Set<String> _selectedFilters = {}; // 选中的筛选条件
  List<TranslationItem> _filteredItems = []; // 筛选后的项目

  // 搜索状态
  String _searchKeyword = ''; // 搜索关键词
  bool _searchExclude = false; // 是否排除包含关键词的项目
  bool _isShowSearch = false; // 是否显示搜索

  // 滚动控制器
  final ScrollController _scrollController = ScrollController();

  // 搜索输入框控制器
  final TextEditingController _searchController = TextEditingController();

  // 定时保存相关
  Timer? _autoSaveTimer;
  int? _autoSaveInterval; // 自动保存间隔（分钟），null表示关闭
  final Map<String, String> _lastSavedTranslations = {}; // 上次保存的翻译内容，用于检测改动

  // 下拉框刷新键
  final GlobalKey _appDropdownKey = GlobalKey();
  final GlobalKey _languageDropdownKey = GlobalKey();

  // 临时状态，用于控制下拉框显示
  String? _tempSelectedApp;
  String? _tempSelectedLanguage;

  Timer? _clearTipTimer;
  OverlayEntry? _overlayEntry;

  final TipController _tipController = TipController();

  // 获取或创建TextEditingController
  TextEditingController _getTextController(String key, String initialValue) {
    if (!_textControllers.containsKey(key)) {
      _textControllers[key] = TextEditingController(text: initialValue);
    } else {
      // 如果值已经改变，更新controller的文本
      if (_textControllers[key]!.text != initialValue) {
        _textControllers[key]!.text = initialValue;
      }
    }
    return _textControllers[key]!;
  }

  @override
  void initState() {
    super.initState();
    _loadApps().then((value) {
      _loadSettings(); // 加载设置
      _loadLastSelectedTranslation();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    // 清理所有缓存的TextEditingController
    for (var controller in _textControllers.values) {
      controller.dispose();
    }
    _textControllers.clear();
    _autoSaveTimer?.cancel(); // 取消定时器
    _clearTipTimer?.cancel();
    _removeCustomTip(); // 清理Overlay
    super.dispose();
  }

  void _loadLastSelectedTranslation() {
    try {
      _selectedApp = CookieHelper.getCookie('tsapp');
      _selectedLanguage = CookieHelper.getCookie('tslang');

      if (_selectedApp != null &&
          _selectedApp!.isNotEmpty &&
          _selectedLanguage != null &&
          _selectedLanguage!.isNotEmpty) {
        _loadLanguagesForApp(_selectedApp ?? '').then((value) {
          _loadTranslations();
        });
      }
    } catch (e) {
      print('加载上次选中翻译失败: $e');
      _showError('加载上次选中翻译失败: $e');
    }
  }

  // 记录用户选择到服务器
  Future<void> _recordSelectionToServer() async {
    try {
      if (_selectedApp != null &&
          _selectedApp!.isNotEmpty &&
          _selectedLanguage != null &&
          _selectedLanguage!.isNotEmpty) {
        final response = await http.post(
          Uri.parse(Apis.recordTranslationSelection),
          headers: {
            'Content-Type': 'application/json',
          },
          body: json.encode({
            'tsapp': _selectedApp,
            'tslang': _selectedLanguage,
          }),
        );

        if (response.statusCode == 200) {
          final result = json.decode(response.body);
          if (result[AppConst.CODE] == AppConst.CODE_SUCCESS) {
            print('选择已记录到服务器: App=$_selectedApp, Language=$_selectedLanguage');
          } else {
            print('记录选择失败: ${result[AppConst.MSG] ?? '未知错误'}');
          }
        } else {
          print('记录选择请求失败: ${response.statusCode}');
        }
      }
    } catch (e) {
      print('记录选择到服务器失败: $e');
    }
  }

  // 加载设置
  void _loadSettings() {
    // 默认设置：1分钟自动保存
    _autoSaveInterval = 1;
    _startAutoSaveTimer();
  }

  // 启动定时保存
  void _startAutoSaveTimer() {
    _stopAutoSaveTimer(); // 先停止现有定时器

    if (_autoSaveInterval != null && _autoSaveInterval! > 0) {
      _autoSaveTimer = Timer.periodic(
        Duration(seconds: (_autoSaveInterval!) * 60),
        (timer) => _performAutoSave(),
      );
      print('定时保存已启动，间隔: $_autoSaveInterval分钟');
    }
  }

  // 停止定时保存
  void _stopAutoSaveTimer() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = null;
  }

  // 执行自动保存
  Future<void> _performAutoSave() async {
    if (_selectedApp == null || _selectedLanguage == null) return;
    if (_isSaving) return; // 如果正在保存，跳过

    // 检测是否有改动
    bool hasChanges = _hasTranslationChanges();
    if (!hasChanges) {
      print('定时保存：无改动，跳过保存');
      return;
    }

    print('定时保存：检测到改动，开始保存');
    try {
      await _saveTranslations(true);
    } catch (e) {
      _showError('自动保存失败: $e');
    }
  }

  // 检测翻译是否有改动
  bool _hasTranslationChanges() {
    if (_selectedLanguage == null) return false;

    // 获取当前翻译内容
    Map<String, String> currentTranslations = {};
    for (var item in _translationItems) {
      if (item.translations.containsKey(_selectedLanguage)) {
        currentTranslations[item.key] = item.translations[_selectedLanguage!]!;
      }
    }

    // 比较与上次保存的内容
    if (_lastSavedTranslations.length != currentTranslations.length) {
      return true;
    }

    for (String key in currentTranslations.keys) {
      if (_lastSavedTranslations[key] != currentTranslations[key]) {
        return true;
      }
    }

    return false;
  }

  // 更新保存后的翻译内容记录
  void _updateLastSavedTranslations() {
    if (_selectedLanguage == null) return;

    _lastSavedTranslations.clear();
    for (var item in _translationItems) {
      if (item.translations.containsKey(_selectedLanguage)) {
        _lastSavedTranslations[item.key] =
            item.translations[_selectedLanguage!]!;
      }
    }
  }

  // 加载App列表
  Future<void> _loadApps() async {
    try {
      final response = await http.get(
        Uri.parse(Apis.translationConfig),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data[AppConst.CODE] == AppConst.CODE_SUCCESS) {
          setState(() {
            _availableApps = List<Map<String, dynamic>>.from(
                data[AppConst.DATA]['apps'] ?? []);
            _isLoadingApps = false;
          });
        } else {
          _showError('加载App列表失败: ${data[AppConst.MSG]}');
          setState(() {
            _isLoadingApps = false;
          });
        }
      } else {
        _showError('加载App列表失败');
        setState(() {
          _isLoadingApps = false;
        });
      }
    } catch (e) {
      _showError('加载App列表失败: $e');
      setState(() {
        _isLoadingApps = false;
      });
    }
  }

  // 加载App对应的语言列表
  Future<void> _loadLanguagesForApp(String appName) async {
    try {
      // 从已加载的App配置中找到对应的语言列表
      final selectedApp = _availableApps.firstWhere(
        (app) => app['appName'] == appName,
        orElse: () => {},
      );

      if (selectedApp.containsKey('languages')) {
        setState(() {
          _availableLanguages =
              List<Map<String, dynamic>>.from(selectedApp['languages']);
        });
        print(
            '加载语言列表: ${_availableLanguages.map((lang) => '${lang['lanName']}(${lang['lanFile']})').toList()}');
      }
    } catch (e) {
      _showError('加载语言列表失败: $e');
    }
  }

  // 加载翻译数据
  Future<void> _loadTranslations() async {
    if (_selectedApp == null || _selectedLanguage == null) return;

    setState(() {
      _isLoadingTranslations = true;
    });

    try {
      // 加载source.json
      final sourceResponse = await http.get(
        Uri.parse(Apis.downloadTranslationFile(_selectedApp!, 'source.json')),
      );

      if (sourceResponse.statusCode != 200) {
        _showError('未找到source.json文件，请先上传源文文件');
        setState(() {
          _isLoadingTranslations = false;
        });
        return;
      }

      final sourceJson = json.decode(sourceResponse.body);
      // 处理嵌套的source结构
      _sourceData = sourceJson['source'] ?? sourceJson;

      // 加载available.keys（可选）
      try {
        final availableResponse = await http.get(
          Uri.parse(
              Apis.downloadTranslationFile(_selectedApp!, 'available.keys')),
        );
        if (availableResponse.statusCode == 200) {
          _availableKeys =
              List<String>.from(json.decode(availableResponse.body));
        }
      } catch (e) {
        // available.keys文件不存在，继续处理
        _availableKeys = null;
      }

      // 加载选中的翻译文件
      try {
        final response = await http.get(
          Uri.parse(
              Apis.downloadTranslationFile(_selectedApp!, _selectedLanguage!)),
        );
        if (response.statusCode == 200) {
          final translationJson = json.decode(response.body);
          print('原始翻译数据: ${translationJson.keys.toList()}');

          // 获取当前选中语言的tsKey
          final selectedLanguageConfig = _availableLanguages.firstWhere(
            (lang) => lang['lanFile'] == _selectedLanguage,
            orElse: () => {},
          );
          final tsKey = selectedLanguageConfig['tsKey'] as String?;
          print('使用tsKey: $tsKey');

          // 使用tsKey来提取翻译数据
          if (tsKey != null && translationJson.containsKey(tsKey)) {
            _translationData[_selectedLanguage!] =
                Map<String, dynamic>.from(translationJson[tsKey]);
            print(
                '翻译数据加载成功 (使用tsKey): ${_translationData[_selectedLanguage!]?.keys.length} 个键');
            print(
                '翻译数据键: ${_translationData[_selectedLanguage!]?.keys.take(5).toList()}');
          } else if (translationJson.containsKey(_selectedLanguage)) {
            // 回退到使用文件名作为键
            _translationData[_selectedLanguage!] =
                Map<String, dynamic>.from(translationJson[_selectedLanguage]);
            print(
                '翻译数据加载成功 (使用文件名): ${_translationData[_selectedLanguage!]?.keys.length} 个键');
            print(
                '翻译数据键: ${_translationData[_selectedLanguage!]?.keys.take(5).toList()}');
          } else {
            // 如果没有嵌套结构，直接使用整个JSON
            _translationData[_selectedLanguage!] =
                Map<String, dynamic>.from(translationJson);
            print(
                '翻译数据加载成功 (直接结构): ${_translationData[_selectedLanguage!]?.keys.length} 个键');
            print(
                '翻译数据键: ${_translationData[_selectedLanguage!]?.keys.take(5).toList()}');
          }
        } else {
          _showError('未找到翻译文件: $_selectedLanguage');
          setState(() {
            _isLoadingTranslations = false;
          });
          return;
        }
      } catch (e) {
        _showError('加载翻译文件失败: $e');
        setState(() {
          _isLoadingTranslations = false;
        });
        return;
      }

      // 构建翻译项目列表
      _buildTranslationItems();

      setState(() {
        _isLoadingTranslations = false;
      });
    } catch (e) {
      _showError('加载翻译数据失败: $e');
      setState(() {
        _isLoadingTranslations = false;
      });
    }
  }

  // 应用筛选和搜索
  void _applyFilters() {
    List<TranslationItem> items = List.from(_translationItems);

    // 应用状态筛选
    if (_selectedFilters.isNotEmpty) {
      items = items.where((item) {
        bool hasTranslation =
            item.translations.containsKey(_selectedLanguage) &&
                item.translations[_selectedLanguage!]!.isNotEmpty;
        bool isInAvailableKeys = item.isInAvailableKeys;

        bool hasTranslationFilter = _selectedFilters.contains('未翻译') ||
            _selectedFilters.contains('已翻译');
        bool availableFilter = _selectedFilters.contains('生效中') ||
            _selectedFilters.contains('已失效');

        if (hasTranslationFilter && availableFilter) {
          bool translationMatch =
              _selectedFilters.contains('未翻译') && !hasTranslation ||
                  _selectedFilters.contains('已翻译') && hasTranslation;

          bool availableMatch =
              _selectedFilters.contains('生效中') && isInAvailableKeys ||
                  _selectedFilters.contains('已失效') && !isInAvailableKeys;

          return translationMatch && availableMatch;
        } else {
          if (_selectedFilters.contains('未翻译') && !hasTranslation) return true;
          if (_selectedFilters.contains('已翻译') && hasTranslation) return true;
          if (_selectedFilters.contains('生效中') && isInAvailableKeys) {
            return true;
          }
          if (_selectedFilters.contains('已失效') && !isInAvailableKeys) {
            return true;
          }

          return false;
        }
      }).toList();
    }

    // 应用搜索筛选
    if (_searchKeyword.isNotEmpty) {
      items = items.where((item) {
        String searchText = _searchKeyword.toLowerCase();

        // 搜索翻译键
        bool keyMatch = item.key.toLowerCase().contains(searchText);

        // 搜索源文值
        bool sourceMatch = item.sourceValue.toLowerCase().contains(searchText);

        // 搜索翻译值
        String translationValue = item.translations[_selectedLanguage] ?? '';
        bool translationMatch =
            translationValue.toLowerCase().contains(searchText);

        bool hasMatch = keyMatch || sourceMatch || translationMatch;

        return _searchExclude ? !hasMatch : hasMatch;
      }).toList();
    }

    _filteredItems = items;
  }

  // 构建翻译项目列表
  void _buildTranslationItems() {
    _translationItems.clear();

    if (_sourceData == null || _selectedLanguage == null) return;

    print(
        '开始构建翻译项目: sourceData keys=${_sourceData!.keys.length}, selectedLanguage=$_selectedLanguage');
    print('翻译数据: ${_translationData.keys}');

    int index = 1; // 从1开始的序号
    _sourceData!.forEach((key, value) {
      final item = TranslationItem(
        key: key,
        sourceValue: value.toString(),
        translations: {},
        isInAvailableKeys: _availableKeys?.contains(key) ?? true,
        originalIndex: index, // 添加原始序号
      );

      // 加载选中语言的翻译
      if (_translationData.containsKey(_selectedLanguage)) {
        final languageData = _translationData[_selectedLanguage!]!;
        print('语言数据键: ${languageData.keys.take(5).toList()}...');
        if (languageData.containsKey(key)) {
          item.translations[_selectedLanguage!] = languageData[key].toString();
          print('找到翻译: $key -> ${languageData[key]}');
        } else {
          print('未找到翻译: $key');
        }
      } else {
        print('未找到语言数据: $_selectedLanguage');
      }

      _translationItems.add(item);
      index++; // 递增序号
    });

    // 应用筛选
    _applyFilters();

    // 更新上次保存的翻译内容，用于检测改动
    _updateLastSavedTranslations();
  }

  // 保存翻译
  Future<void> _saveTranslations(bool isAutoSave) async {
    if (_selectedApp == null || _selectedLanguage == null) return;

    setState(() {
      _isSaving = true;
    });

    try {
      // 获取当前选中语言的tsKey
      final selectedLanguageConfig = _availableLanguages.firstWhere(
        (lang) => lang['lanFile'] == _selectedLanguage,
        orElse: () => {},
      );
      final tsKey = selectedLanguageConfig['tsKey'] as String?;

      if (tsKey == null) {
        throw Exception('未找到语言配置的tsKey');
      }

      // 构建嵌套格式的翻译数据
      final translationData = <String, dynamic>{};
      for (var item in _translationItems) {
        if (item.translations.containsKey(_selectedLanguage)) {
          translationData[item.key] = item.translations[_selectedLanguage!]!;
        }
      }

      // 构建最终的保存格式：{tsKey: {key: value, ...}}
      final finalData = <String, dynamic>{
        tsKey: translationData,
      };

      // 备份原文件
      try {
        await http.post(
          Uri.parse(Apis.backupTranslation),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'app': _selectedApp,
            'fileName': _selectedLanguage,
          }),
        );
      } catch (e) {
        print('备份文件失败: $_selectedLanguage - $e');
      }

      // 保存新文件
      final saveResponse = await http.post(
        Uri.parse(Apis.saveTranslation),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'app': _selectedApp,
          'fileName': _selectedLanguage,
          'data': finalData,
        }),
      );

      if (saveResponse.statusCode != 200) {
        throw Exception('保存文件失败: $_selectedLanguage');
      }

      // 更新保存后的翻译内容记录
      _updateLastSavedTranslations();

      final data = json.decode(saveResponse.body);
      if (data[AppConst.CODE] == AppConst.CODE_SUCCESS) {
        if (isAutoSave) {
          _showTip('自动保存成功');
        } else {
          _showSuccess('翻译保存成功');
        }
      } else {
        throw Exception('保存文件失败: ${data[AppConst.MSG]}');
      }
    } catch (e) {
      if (isAutoSave) {
        _showTip('自动保存失败');
      } else {
        _showError('保存翻译失败: $e');
      }
    } finally {
      setState(() {
        _isSaving = false;
      });
    }
  }

  String getAppDescription(String appName) {
    for (var app in _availableApps) {
      if (app['appName'] == appName) {
        return app['description'] ?? '暂无说明';
      }
    }
    return '暂无说明';
  }

  // 设置翻译配置
  Future<void> _setTranslationConfig() async {
    // 打开设置页面
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (context) {
          return ModifyTranslationSettingWidget(
            model: ModifyTranslationSettingModel(
              appName: _selectedApp ?? '未选择',
              autoSaveInterval: _autoSaveInterval,
              howToUseDescription: getAppDescription(_selectedApp ?? ''),
            ),
            onSaveSetting: (newConfig) {
              setState(() {
                _autoSaveInterval = newConfig.autoSaveInterval;
              });
              _startAutoSaveTimer(); // 重新启动定时器
              Navigator.pop(context);
              _showSuccess('设置已保存');
            },
          );
        });
  }

  // // 自动保存单个翻译项
  // Future<void> _autoSaveTranslation(String key, String value) async {
  //   if (_selectedApp == null || _selectedLanguage == null) return;

  //   try {
  //     // 获取当前选中语言的tsKey
  //     final selectedLanguageConfig = _availableLanguages.firstWhere(
  //       (lang) => lang['lanFile'] == _selectedLanguage,
  //       orElse: () => {},
  //     );
  //     final tsKey = selectedLanguageConfig['tsKey'] as String?;

  //     if (tsKey == null) {
  //       print('自动保存失败: 未找到语言配置的tsKey');
  //       return;
  //     }

  //     // 构建嵌套格式的单个翻译项数据
  //     final translationData = <String, String>{};
  //     translationData[key] = value;

  //     // 构建最终的保存格式：{tsKey: {key: value}}
  //     final finalData = <String, dynamic>{
  //       tsKey: translationData,
  //     };

  //     // 保存单个翻译项
  //     final saveResponse = await http.post(
  //       Uri.parse('${Apis.baseUrl}/save_translation'),
  //       headers: {'Content-Type': 'application/json'},
  //       body: json.encode({
  //         'app': _selectedApp,
  //         'fileName': _selectedLanguage,
  //         'data': finalData,
  //       }),
  //     );

  //     if (saveResponse.statusCode == 200) {
  //       print('自动保存成功: $key');
  //     } else {
  //       print('自动保存失败: $key');
  //     }
  //   } catch (e) {
  //     print('自动保存翻译失败: $e');
  //   }
  // }

  // 滚动到顶部
  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  // 滚动到底部
  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
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

  void _showTip(String message) {
    if (mounted) {
      // 使用Overlay显示自定义提示
      _showCustomTip(message);
    }
  }

  void _showCustomTip(String message) {
    // 移除之前的提示
    _removeCustomTip();

    // 计算最大宽度
    final screenWidth = MediaQuery.of(context).size.width;
    final maxWidth = (screenWidth * 0.5).clamp(0.0, 500.0);

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: 80,
        left: 0,
        right: 0,
        child: Center(
          child: AnimatedOpacity(
            opacity: 1,
            duration: const Duration(milliseconds: 300),
            child: Container(
              constraints: BoxConstraints(
                maxWidth: maxWidth,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blue,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  decoration: TextDecoration.none, // 明确禁用装饰
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);

    // 2秒后自动移除
    _clearTipTimer?.cancel();
    _clearTipTimer = Timer(const Duration(seconds: 2), () {
      _removeCustomTip();
    });
  }

  void _removeCustomTip() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  // 显示切换保存对话框
  Future<bool> _showSwitchSaveDialog(
      String title, String content, VoidCallback onConfirm) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: Text(title),
              content: Text(content),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(false); // 取消操作
                  },
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(true); // 不保存，直接切换
                    onConfirm();
                  },
                  child: const Text('不保存'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop(true); // 保存后切换
                    _saveTranslations(false).then((_) {
                      onConfirm();
                    }).catchError((error) {
                      _showError('保存失败: $error');
                    });
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingApps) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('加载App列表中...'),
          ],
        ),
      );
    }

    var padding = Padding(
      // padding: const EdgeInsets.only(
      //     top: 12.0, left: 12.0, right: 12.0, bottom: 12.0),
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding:
                const EdgeInsets.only(left: 16, right: 16, top: 12, bottom: 4),
            child: Row(
              children: [
                // App选择
                Expanded(
                  flex: 1,
                  child: DropdownButtonFormField<String>(
                    key: _appDropdownKey,
                    value: _tempSelectedApp ?? _selectedApp,
                    decoration: const InputDecoration(
                      labelText: '选择App',
                      labelStyle: TextStyle(fontSize: 12),
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                    style: const TextStyle(fontSize: 12),
                    items: _availableApps.map((app) {
                      return DropdownMenuItem<String>(
                        value: app['appName'] as String,
                        child: Text(
                          app['appName'] as String,
                          style: const TextStyle(fontSize: 12),
                        ),
                      );
                    }).toList(),
                    onChanged: (value) async {
                      // 如果选择的是当前应用，不需要切换
                      if (value == _selectedApp) {
                        return;
                      }

                      // 先更新临时状态，让下拉框显示新选择
                      setState(() {
                        _tempSelectedApp = value;
                      });

                      // 检查是否有未保存的改动
                      if (_hasTranslationChanges()) {
                        bool shouldSwitch = await _showSwitchSaveDialog(
                          '切换应用',
                          '当前翻译有未保存的改动，是否保存？',
                          () {
                            // 执行切换逻辑
                            setState(() {
                              _selectedApp = value;
                              _selectedLanguage = null;
                              _translationItems.clear();
                              _translationData.clear();
                              _editingFields.clear();
                              _availableLanguages.clear();
                              _selectedFilters.clear();
                              _filteredItems.clear();
                              _searchKeyword = '';
                              _searchExclude = false;
                              _lastSavedTranslations.clear();
                              _tempSelectedApp = null; // 清除临时状态
                            });
                            if (value != null) {
                              _recordSelectionToServer();
                              _loadLanguagesForApp(value);
                            }
                          },
                        );
                        if (!shouldSwitch) {
                          // 用户取消，恢复到原来的选择
                          setState(() {
                            _tempSelectedApp = null; // 清除临时状态，恢复显示原选择
                          });
                          return;
                        }
                      } else {
                        // 没有改动，直接切换
                        setState(() {
                          _selectedApp = value;
                          _selectedLanguage = null;
                          _translationItems.clear();
                          _translationData.clear();
                          _editingFields.clear();
                          _availableLanguages.clear();
                          _selectedFilters.clear();
                          _filteredItems.clear();
                          _searchKeyword = '';
                          _searchExclude = false;
                          _lastSavedTranslations.clear();
                          _tempSelectedApp = null; // 清除临时状态
                        });
                        if (value != null) {
                          _recordSelectionToServer();
                          _loadLanguagesForApp(value);
                        }
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                // 语言选择
                Expanded(
                  flex: 1,
                  child: DropdownButtonFormField<String>(
                    key: _languageDropdownKey,
                    value: _tempSelectedLanguage ?? _selectedLanguage,
                    decoration: const InputDecoration(
                      labelText: '选择语言',
                      labelStyle: TextStyle(fontSize: 12),
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                    style: const TextStyle(fontSize: 12),
                    items: _availableLanguages.map((language) {
                      return DropdownMenuItem<String>(
                        value: language['lanFile'] as String,
                        // child: Text(
                        //     '${language['lanName']} (${language['lanFile']})'),
                        child: Text(
                          '${language['lanName']}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      );
                    }).toList(),
                    onChanged: _selectedApp != null
                        ? (value) async {
                            // 如果选择的是当前语言，不需要切换
                            if (value == _selectedLanguage) {
                              return;
                            }

                            // 先更新临时状态，让下拉框显示新选择
                            setState(() {
                              _tempSelectedLanguage = value;
                            });

                            // 检查是否有未保存的改动
                            if (_hasTranslationChanges()) {
                              bool shouldSwitch = await _showSwitchSaveDialog(
                                '切换语言',
                                '当前翻译有未保存的改动，是否保存？',
                                () {
                                  // 执行切换逻辑
                                  setState(() {
                                    _selectedLanguage = value;
                                    _translationItems.clear();
                                    _translationData.clear();
                                    _editingFields.clear();
                                    _selectedFilters.clear();
                                    _filteredItems.clear();
                                    _searchKeyword = '';
                                    _searchExclude = false;
                                    _lastSavedTranslations.clear();
                                    _tempSelectedLanguage = null; // 清除临时状态
                                  });
                                  if (value != null) {
                                    _recordSelectionToServer();
                                    _loadTranslations();
                                  }
                                },
                              );
                              if (!shouldSwitch) {
                                // 用户取消，恢复到原来的选择
                                setState(() {
                                  _tempSelectedLanguage =
                                      null; // 清除临时状态，恢复显示原选择
                                });
                                return;
                              }
                            } else {
                              // 没有改动，直接切换
                              setState(() {
                                _selectedLanguage = value;
                                _translationItems.clear();
                                _translationData.clear();
                                _editingFields.clear();
                                _selectedFilters.clear();
                                _filteredItems.clear();
                                _searchKeyword = '';
                                _searchExclude = false;
                                _lastSavedTranslations.clear();
                                _tempSelectedLanguage = null; // 清除临时状态
                              });
                              if (value != null) {
                                _recordSelectionToServer();
                                _loadTranslations();
                              }
                            }
                          }
                        : null,
                  ),
                ),
                const SizedBox(width: 4),
                TipWidget(controller: _tipController),
                const SizedBox(width: 4),
                // 保存按钮
                IconButton(
                  onPressed: _isSaving ? null : () => _saveTranslations(false),
                  icon: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save, color: Colors.blue),
                  // label: Text(_isSaving ? '保存中...' : '保存翻译'),
                  style: ElevatedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                  ),
                ),
                const SizedBox(width: 4),
                // 设置按钮
                IconButton(
                  onPressed: _isSaving ? null : _setTranslationConfig,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.settings, color: Colors.blue),
                  // label: Text(_isSaving ? '保存中...' : '保存翻译'),
                  style: ElevatedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                  ),
                ),
              ],
            ),
          ),

          // SizedBox(height: 8),

          // 翻译编辑区域
          if (_selectedApp != null && _selectedLanguage != null) ...[
            if (_isLoadingTranslations)
              const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('加载翻译数据中...'),
                  ],
                ),
              )
            else if (_translationItems.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Center(
                    child: Text(
                      '未找到翻译数据，请重新选择（如果app名称和语言均已选择，请确保source.json文件已上传）',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              )
            else ...[
              // 翻译表格
              Expanded(
                child: Card(
                  child: Column(
                    children: [
                      // 表格头部
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(8),
                            topRight: Radius.circular(8),
                          ),
                        ),
                        child: Column(
                          children: [
                            // // 搜索框
                            // Row(
                            //   children: [
                            //     Expanded(
                            //       flex: 3,
                            //       child: TextField(
                            //         decoration: InputDecoration(
                            //           hintText: '搜索翻译键、源文值或翻译值...',
                            //           prefixIcon: Icon(Icons.search),
                            //           suffixIcon: _searchKeyword.isNotEmpty
                            //               ? IconButton(
                            //                   icon: Icon(Icons.clear),
                            //                   onPressed: () {
                            //                     setState(() {
                            //                       _searchKeyword = '';
                            //                       _applyFilters();
                            //                     });
                            //                   },
                            //                 )
                            //               : null,
                            //           border: OutlineInputBorder(
                            //             borderRadius: BorderRadius.circular(8),
                            //           ),
                            //           isDense: true,
                            //         ),
                            //         onChanged: (value) {
                            //           setState(() {
                            //             _searchKeyword = value;
                            //             _applyFilters();
                            //           });
                            //         },
                            //       ),
                            //     ),
                            //     SizedBox(width: 16),
                            //     Expanded(
                            //       flex: 1,
                            //       child: Row(
                            //         children: [
                            //           Checkbox(
                            //             value: _searchExclude,
                            //             onChanged: (value) {
                            //               setState(() {
                            //                 _searchExclude = value ?? false;
                            //                 _applyFilters();
                            //               });
                            //             },
                            //           ),
                            //           Text(
                            //             '排除',
                            //             style: TextStyle(fontSize: 12),
                            //           ),
                            //         ],
                            //       ),
                            //     ),
                            //   ],
                            // ),
                            // SizedBox(height: 12),
                            // 筛选器
                            Row(
                              children: [
                                // Text(
                                //   '状态筛选:',
                                //   style: TextStyle(
                                //     fontWeight: FontWeight.bold,
                                //     fontSize: 14,
                                //   ),
                                // ),
                                // SizedBox(width: 16),
                                Expanded(
                                  child: Wrap(
                                    spacing: 4,
                                    runSpacing: 4,
                                    children: [
                                      FilterChip(
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        visualDensity: VisualDensity.compact,
                                        // padding:
                                        //     EdgeInsets.symmetric(horizontal: 4),
                                        labelPadding: EdgeInsets.zero,
                                        showCheckmark: false,
                                        label: const Text(
                                          '未翻译',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                        selected:
                                            _selectedFilters.contains('未翻译'),
                                        onSelected: (selected) {
                                          setState(() {
                                            if (selected) {
                                              _selectedFilters.add('未翻译');
                                            } else {
                                              _selectedFilters.remove('未翻译');
                                            }
                                            _applyFilters();
                                          });
                                        },
                                        selectedColor: Colors.red.shade100,
                                        checkmarkColor: Colors.red,
                                      ),
                                      FilterChip(
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        visualDensity: VisualDensity.compact,
                                        labelPadding: EdgeInsets.zero,
                                        showCheckmark: false,
                                        label: const Text(
                                          '已翻译',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                        selected:
                                            _selectedFilters.contains('已翻译'),
                                        onSelected: (selected) {
                                          setState(() {
                                            if (selected) {
                                              _selectedFilters.add('已翻译');
                                            } else {
                                              _selectedFilters.remove('已翻译');
                                            }
                                            _applyFilters();
                                          });
                                        },
                                        selectedColor: Colors.green.shade100,
                                        checkmarkColor: Colors.green,
                                      ),
                                      FilterChip(
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        visualDensity: VisualDensity.compact,
                                        labelPadding: EdgeInsets.zero,
                                        showCheckmark: false,
                                        label: const Text(
                                          '生效中',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                        selected:
                                            _selectedFilters.contains('生效中'),
                                        onSelected: (selected) {
                                          setState(() {
                                            if (selected) {
                                              _selectedFilters.add('生效中');
                                            } else {
                                              _selectedFilters.remove('生效中');
                                            }
                                            _applyFilters();
                                          });
                                        },
                                        selectedColor: Colors.blue.shade100,
                                        checkmarkColor: Colors.blue,
                                      ),
                                      FilterChip(
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        visualDensity: VisualDensity.compact,
                                        labelPadding: EdgeInsets.zero,
                                        showCheckmark: false,
                                        label: const Text(
                                          '已失效',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                        selected:
                                            _selectedFilters.contains('已失效'),
                                        onSelected: (selected) {
                                          setState(() {
                                            if (selected) {
                                              _selectedFilters.add('已失效');
                                            } else {
                                              _selectedFilters.remove('已失效');
                                            }
                                            _applyFilters();
                                          });
                                        },
                                        selectedColor: Colors.orange.shade100,
                                        checkmarkColor: Colors.orange,
                                      ),
                                      // if (_selectedFilters.isNotEmpty)
                                      //   ActionChip(
                                      //     materialTapTargetSize:
                                      //         MaterialTapTargetSize.shrinkWrap,
                                      //     visualDensity: VisualDensity.compact,
                                      //     labelPadding: EdgeInsets.zero,
                                      //     label: Text(
                                      //       '清除筛选',
                                      //       style: TextStyle(fontSize: 12),
                                      //     ),
                                      //     onPressed: () {
                                      //       setState(() {
                                      //         _selectedFilters.clear();
                                      //         _applyFilters();
                                      //       });
                                      //     },
                                      //   ),
                                      FilterChip(
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        visualDensity: VisualDensity.compact,
                                        labelPadding: EdgeInsets.zero,
                                        showCheckmark: false,
                                        label: const Text(
                                          '搜索',
                                          style: TextStyle(fontSize: 12),
                                        ),
                                        selected: _isShowSearch,
                                        onSelected: (selected) {
                                          setState(() {
                                            if (selected) {
                                              _isShowSearch = true;
                                            } else {
                                              _isShowSearch = false;
                                            }
                                          });
                                        },
                                        selectedColor: Colors.orange.shade100,
                                        checkmarkColor: Colors.orange,
                                      ),
                                      // 搜索框
                                      Visibility(
                                        visible: _isShowSearch,
                                        child: Row(
                                          children: [
                                            Flexible(
                                              // width: 200,
                                              child: TextField(
                                                controller: _searchController,
                                                style: const TextStyle(
                                                    fontSize: 12),
                                                decoration: InputDecoration(
                                                  hintText: '搜索翻译键、源文值或翻译值...',
                                                  hintStyle: const TextStyle(
                                                      fontSize: 12),
                                                  contentPadding:
                                                      EdgeInsets.zero,
                                                  prefixIcon: const Icon(
                                                      Icons.search,
                                                      size: 16),
                                                  suffixIcon:
                                                      _searchKeyword.isNotEmpty
                                                          ? IconButton(
                                                              icon: const Icon(
                                                                  Icons.clear,
                                                                  size: 16),
                                                              onPressed: () {
                                                                setState(() {
                                                                  _searchKeyword =
                                                                      '';
                                                                  _searchController
                                                                      .clear();
                                                                  _applyFilters();
                                                                });
                                                              },
                                                              padding:
                                                                  const EdgeInsets
                                                                      .all(4),
                                                              // constraints:
                                                              //     BoxConstraints(
                                                              //   minWidth: 24,
                                                              //   minHeight: 24,
                                                              // ),
                                                            )
                                                          : null,
                                                  border: OutlineInputBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            6),
                                                  ),
                                                  isDense: true,
                                                ),
                                                onChanged: (value) {
                                                  setState(() {
                                                    _searchKeyword = value;
                                                    _applyFilters();
                                                  });
                                                },
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Row(
                                              children: [
                                                Checkbox(
                                                  value: _searchExclude,
                                                  onChanged: (value) {
                                                    setState(() {
                                                      _searchExclude =
                                                          value ?? false;
                                                      _applyFilters();
                                                    });
                                                  },
                                                ),
                                                const Text(
                                                  '排除',
                                                  style:
                                                      TextStyle(fontSize: 12),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Text(
                                //   '显示 ${_filteredItems.length}/${_translationItems.length} 项',
                                //   style: TextStyle(
                                //     fontSize: 12,
                                //     color: Colors.grey.shade600,
                                //   ),
                                // ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            // 表格列标题
                            Row(
                              children: [
                                const Expanded(
                                  flex: 1,
                                  child: Text(
                                    '序号',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                const Expanded(
                                  flex: 2,
                                  child: Text(
                                    '翻译键',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                const Expanded(
                                  flex: 2,
                                  child: Text(
                                    '源文值',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Row(
                                    children: [
                                      const Text(
                                        '翻译值',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const Spacer(),
                                      IconButton(
                                        icon: const Icon(
                                            Icons.keyboard_arrow_up,
                                            size: 16),
                                        onPressed: () {
                                          if (_filteredItems.isNotEmpty) {
                                            // 滚动到顶部
                                            _scrollToTop();
                                          }
                                        },
                                        tooltip: '滚动到顶部',
                                        padding: const EdgeInsets.all(4),
                                        constraints: const BoxConstraints(
                                          minWidth: 24,
                                          minHeight: 24,
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                            Icons.keyboard_arrow_down,
                                            size: 16),
                                        onPressed: () {
                                          if (_filteredItems.isNotEmpty) {
                                            // 滚动到底部
                                            _scrollToBottom();
                                          }
                                        },
                                        tooltip: '滚动到底部',
                                        padding: const EdgeInsets.all(4),
                                        constraints: const BoxConstraints(
                                          minWidth: 24,
                                          minHeight: 24,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // 表格内容
                      Expanded(
                        child: ListView.builder(
                          controller: _scrollController,
                          itemCount: _filteredItems.length,
                          itemExtent: 80.0, // 固定高度，提升滚动性能
                          cacheExtent: 200.0, // 缓存范围，减少重建
                          itemBuilder: (context, index) {
                            final item = _filteredItems[index];
                            return _TranslationRow(
                              item: item,
                              selectedLanguage: _selectedLanguage,
                              editingFields: _editingFields,
                              getTextController: _getTextController,
                              onTap: (controllerKey) {
                                setState(() {
                                  _editingFields.add(controllerKey);
                                });
                              },
                              onChanged: (controllerKey, value) {
                                item.translations[_selectedLanguage!] = value;
                              },
                              onEditingComplete: (controllerKey) {
                                setState(() {
                                  _editingFields.remove(controllerKey);
                                });
                              },
                              // onAutoSave: (key, value) {
                              //   _autoSaveTranslation(key, value);
                              // },
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // SizedBox(height: 16),

              // // 保存按钮
              // SizedBox(
              //   width: double.infinity,
              //   child: ElevatedButton.icon(
              //     onPressed: _isSaving ? null : _saveTranslations,
              //     icon: _isSaving
              //         ? SizedBox(
              //             width: 16,
              //             height: 16,
              //             child: CircularProgressIndicator(strokeWidth: 2),
              //           )
              //         : Icon(Icons.save),
              //     label: Text(_isSaving ? '保存中...' : '保存翻译'),
              //     style: ElevatedButton.styleFrom(
              //       padding: EdgeInsets.symmetric(vertical: 16),
              //     ),
              //   ),
              // ),
            ],
          ],
        ],
      ),
    );
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) {
          return;
        }
        if (!_hasTranslationChanges()) {
          Navigator.of(context).pop(); // 关闭修改翻译页面
          return;
        }
        // 弹出是否保存对话框
        showDialog(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: Text('是否保存翻译'),
              content: Text('是否保存翻译'),
              actions: [
                TextButton(
                    onPressed: () {
                      // 取消操作，继续在这个页面
                      Navigator.of(context).pop(); // 关闭弹窗
                    },
                    child: Text('取消')),
                TextButton(
                    onPressed: () {
                      Navigator.of(context).pop(); // 关闭弹窗
                      Navigator.of(context).pop(); // 关闭修改翻译页面
                    },
                    child: Text('不保存')),
                TextButton(
                    onPressed: () {
                      // 保存翻译
                      _saveTranslations(false).then((value) {
                        Navigator.of(context).pop(); // 关闭弹窗
                        Navigator.of(context).pop(); // 关闭修改翻译页面
                      });
                    },
                    child: Text('保存')),
              ],
            );
          },
        );
      },
      child: Stack(
        children: [
          Positioned.fill(
              child: Container(
            color: Colors.white,
          )),
          padding,
          // Center(
          //   child: AnimatedOpacity(
          //       opacity: _currentTipString.isNotEmpty ? 1 : 0,
          //       duration: const Duration(milliseconds: 300),
          //       child: Container(
          //         padding:
          //             const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          //         decoration: BoxDecoration(
          //           color: Colors.blue,
          //           borderRadius: BorderRadius.circular(12),
          //         ),
          //         child: Text(_currentTipString),
          //       )),
          // ),
        ],
      ),
    );
  }
}

// 优化的翻译行组件
class _TranslationRow extends StatelessWidget {
  final TranslationItem item;
  final String? selectedLanguage;
  final Set<String> editingFields;
  final Function(String, String) getTextController;
  final Function(String) onTap;
  final Function(String, String) onChanged;
  final Function(String) onEditingComplete;
  // final Function(String, String)? onAutoSave;

  const _TranslationRow({
    required this.item,
    required this.selectedLanguage,
    required this.editingFields,
    required this.getTextController,
    required this.onTap,
    required this.onChanged,
    required this.onEditingComplete,
    // this.onAutoSave,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.grey.shade200,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // 序号
          Expanded(
            flex: 1,
            child: Center(
              child: Text(
                '${item.originalIndex}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
            ),
          ),
          // 翻译键
          Expanded(
            flex: 2,
            child: SelectableText(
              item.key,
              style: TextStyle(
                fontSize: 12,
                color: item.isInAvailableKeys ? Colors.black : Colors.red,
                fontWeight: item.isInAvailableKeys
                    ? FontWeight.normal
                    : FontWeight.bold,
              ),
            ),
          ),

          // 源文值
          Expanded(
            flex: 2,
            child: SelectableText(
              item.sourceValue,
              style: const TextStyle(fontSize: 12),
            ),
          ),

          // 翻译值
          Expanded(
            flex: 3,
            child: _buildTranslationInput(),
          ),
        ],
      ),
    );
  }

  Widget _buildTranslationInput() {
    if (selectedLanguage == null) {
      return const Text(
        '请先选择语言',
        style: TextStyle(
          color: Colors.grey,
          fontSize: 12,
        ),
      );
    }

    final controllerKey = '${item.key}_$selectedLanguage';
    final isEditing = editingFields.contains(controllerKey);

    // 检查是否有翻译内容
    final hasTranslation = item.translations.containsKey(selectedLanguage);
    final translationValue =
        hasTranslation ? item.translations[selectedLanguage!] : '';

    // 如果正在编辑，显示TextField
    if (isEditing) {
      return TextField(
        controller: getTextController(controllerKey, translationValue ?? ''),
        maxLines: null, // 支持换行

        decoration: InputDecoration(
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 8,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
          ),
          hintText: hasTranslation ? null : '点击添加翻译',
          hintStyle: TextStyle(
            color: Colors.grey.shade400,
            fontSize: 12,
          ),
        ),
        style: const TextStyle(fontSize: 12),
        onChanged: (value) {
          onChanged(controllerKey, value);
          // 自动保存已关闭
          // if (onAutoSave != null) {
          //   onAutoSave!(item.key, value);
          // }
        },
        onSubmitted: (value) {
          onEditingComplete(controllerKey);
        },
        onEditingComplete: () {
          onEditingComplete(controllerKey);
        },
      );
    }

    // 未编辑时显示Text，点击时切换到编辑状态
    return GestureDetector(
      onTap: () => onTap(controllerKey),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 8,
          vertical: 4,
        ),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          (translationValue?.isEmpty ?? true) ? '点击添加翻译' : translationValue!,
          style: TextStyle(
            fontSize: 12,
            color: (translationValue?.isEmpty ?? true)
                ? Colors.grey.shade400
                : Colors.black87,
          ),
        ),
      ),
    );
  }
}

// 翻译项目数据类
class TranslationItem {
  final String key;
  final String sourceValue;
  final Map<String, String> translations;
  final bool isInAvailableKeys;
  final int originalIndex; // 在JSON文件中的原始序号

  TranslationItem({
    required this.key,
    required this.sourceValue,
    required this.translations,
    required this.isInAvailableKeys,
    required this.originalIndex,
  });
}
