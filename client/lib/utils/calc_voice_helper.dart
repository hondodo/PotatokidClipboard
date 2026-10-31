import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:just_audio/just_audio.dart';
import 'package:potatokid_clipboard/utils/file_path.dart';

/// 计算器语音类型：普通话、音乐、粤语
enum CalcVoiceType {
  putonghua(0),
  yinyue(1),
  yueyu(2),
  ;

  final int value;
  const CalcVoiceType(this.value);

  static CalcVoiceType fromValue(int value) {
    return CalcVoiceType.values.firstWhere((element) => element.value == value,
        orElse: () => CalcVoiceType.putonghua);
  }

  String get text {
    switch (this) {
      case CalcVoiceType.putonghua:
        return '普通话'.tr;
      case CalcVoiceType.yinyue:
        return '音乐'.tr;
      case CalcVoiceType.yueyu:
        return '粤语'.tr;
    }
  }

  String get iconText {
    switch (this) {
      case CalcVoiceType.putonghua:
        return '国'.tr;
      case CalcVoiceType.yinyue:
        return '♫'.tr;
      case CalcVoiceType.yueyu:
        return '粤'.tr;
    }
  }

  String get voicePath {
    switch (this) {
      case CalcVoiceType.putonghua:
        return 'assets/audio/calc/putonghua/';
      case CalcVoiceType.yinyue:
        return 'assets/audio/calc/yinyue/';
      case CalcVoiceType.yueyu:
        return 'assets/audio/calc/yueyu/';
    }
  }
}

/// 计算器按键
enum CalcVoiceItem {
  // /// 00
  // number00(0),

  none(0),

  /// 0
  number0(1),

  /// 1
  number1(2),

  /// 2
  number2(3),

  /// 3
  number3(4),

  /// 4
  number4(5),

  /// 5
  number5(6),

  /// 6
  number6(7),

  /// 7
  number7(8),

  /// 8
  number8(9),

  /// 9
  number9(10),

  /// .
  numberDot(11),

  /// +
  operatorAdd(12),

  /// -
  operatorSubtract(13),

  /// ×
  operatorMultiply(14),

  /// ÷
  operatorDivide(15),

  /// %
  operatorPercent(16),

  /// =
  functionEqual(17),

  /// 清除
  functionClear(18),

  /// 退格
  functionBackspace(19),

  /// 语音类型
  functionVoiceType(20),

  /// × -> *
  operatorMultiplyToDart(21),

  /// ÷ -> /
  operatorDivideToDart(22),
  ;

  final int value;
  const CalcVoiceItem(this.value);

  static CalcVoiceItem fromValue(int value) {
    return CalcVoiceItem.values.firstWhere((element) => element.value == value,
        orElse: () => CalcVoiceItem.number0);
  }

  String get text {
    switch (this) {
      case CalcVoiceItem.none:
        return ''.tr;
      // case CalcVoiceItem.number00:
      //   return '00'.tr;
      case CalcVoiceItem.number0:
        return '0'.tr;
      case CalcVoiceItem.number1:
        return '1'.tr;
      case CalcVoiceItem.number2:
        return '2'.tr;
      case CalcVoiceItem.number3:
        return '3'.tr;
      case CalcVoiceItem.number4:
        return '4'.tr;
      case CalcVoiceItem.number5:
        return '5'.tr;
      case CalcVoiceItem.number6:
        return '6'.tr;
      case CalcVoiceItem.number7:
        return '7'.tr;
      case CalcVoiceItem.number8:
        return '8'.tr;
      case CalcVoiceItem.number9:
        return '9'.tr;
      case CalcVoiceItem.numberDot:
        return '.'.tr;
      case CalcVoiceItem.operatorAdd:
        return '+'.tr;
      case CalcVoiceItem.operatorSubtract:
        return '-'.tr;
      case CalcVoiceItem.operatorMultiply:
        return '×'.tr;
      case CalcVoiceItem.operatorDivide:
        return '÷'.tr;
      case CalcVoiceItem.functionEqual:
        return '='.tr;
      case CalcVoiceItem.operatorPercent:
        return '%'.tr;
      case CalcVoiceItem.functionClear:
        return 'C'.tr;
      case CalcVoiceItem.functionBackspace:
        return '←'.tr;
      case CalcVoiceItem.functionVoiceType:
        return '语音'.tr;
      case CalcVoiceItem.operatorMultiplyToDart:
        return '*';
      case CalcVoiceItem.operatorDivideToDart:
        return '/';
    }
  }

  CalcVoiceItem stringToItem(String string) {
    switch (string) {
      case '':
        return CalcVoiceItem.none;
      case '*':
        return CalcVoiceItem.operatorMultiplyToDart;
      case '/':
        return CalcVoiceItem.operatorDivideToDart;
      case '0':
        return CalcVoiceItem.number0;
      case '1':
        return CalcVoiceItem.number1;
      case '2':
        return CalcVoiceItem.number2;
      case '3':
        return CalcVoiceItem.number3;
      case '4':
        return CalcVoiceItem.number4;
      case '5':
        return CalcVoiceItem.number5;
      case '6':
        return CalcVoiceItem.number6;
      case '7':
        return CalcVoiceItem.number7;
      case '8':
        return CalcVoiceItem.number8;
      case '9':
        return CalcVoiceItem.number9;
      case '.':
        return CalcVoiceItem.numberDot;
      case '+':
        return CalcVoiceItem.operatorAdd;
      case '-':
        return CalcVoiceItem.operatorSubtract;
      case '×':
        return CalcVoiceItem.operatorMultiply;
      case '÷':
        return CalcVoiceItem.operatorDivide;
      case '=':
        return CalcVoiceItem.functionEqual;
      case '%':
        return CalcVoiceItem.operatorPercent;
      case 'C':
        return CalcVoiceItem.functionClear;
      case '←':
        return CalcVoiceItem.functionBackspace;
      case '语音':
        return CalcVoiceItem.functionVoiceType;
    }
    return CalcVoiceItem.none;
  }

  String get filename {
    switch (this) {
      case CalcVoiceItem.none:
        return '';
      // case CalcVoiceItem.number00:
      //   return '00.mp3';
      case CalcVoiceItem.number0:
        return '0.mp3';
      case CalcVoiceItem.number1:
        return '1.mp3';
      case CalcVoiceItem.number2:
        return '2.mp3';
      case CalcVoiceItem.number3:
        return '3.mp3';
      case CalcVoiceItem.number4:
        return '4.mp3';
      case CalcVoiceItem.number5:
        return '5.mp3';
      case CalcVoiceItem.number6:
        return '6.mp3';
      case CalcVoiceItem.number7:
        return '7.mp3';
      case CalcVoiceItem.number8:
        return '8.mp3';
      case CalcVoiceItem.number9:
        return '9.mp3';
      case CalcVoiceItem.numberDot:
        return 'dot.mp3';
      case CalcVoiceItem.operatorAdd:
        return 'add.mp3';
      case CalcVoiceItem.operatorSubtract:
        return 'subtract.mp3';
      case CalcVoiceItem.operatorMultiply:
        return 'multiply.mp3';
      case CalcVoiceItem.operatorDivide:
        return 'divide.mp3';
      case CalcVoiceItem.functionEqual:
        return 'equal.mp3';
      case CalcVoiceItem.operatorPercent:
        return 'percent.mp3';
      case CalcVoiceItem.functionClear:
        return 'clear.mp3';
      case CalcVoiceItem.functionBackspace:
        return 'backspace.mp3';
      case CalcVoiceItem.functionVoiceType:
        return 'voice_type.mp3';
      case CalcVoiceItem.operatorMultiplyToDart:
        return 'multiply.mp3';
      case CalcVoiceItem.operatorDivideToDart:
        return 'divide.mp3';
    }
  }
}

class CalcVoiceHelper {
  // 单例
  static final CalcVoiceHelper _instance = CalcVoiceHelper._internal();
  factory CalcVoiceHelper() => _instance;
  CalcVoiceHelper._internal() {
    initVoicePathMap();
  }

  Map<String, AudioPlayer> audioPlayerMap = {};

  static CalcVoiceHelper get instance => _instance;

  Map<CalcVoiceType, List<String>> voicePathMap = {};

  List<AudioSource> playlist = [];

  String getVoicePath(CalcVoiceType type, CalcVoiceItem item) {
    String dir = FilePath(type.voicePath).dir;
    String path = FilePath(dir).filePath(item.filename);
    return path;
  }

  void initVoicePathMap() {
    for (CalcVoiceType type in CalcVoiceType.values) {
      List<String> pathList = [];
      for (CalcVoiceItem item in CalcVoiceItem.values) {
        String path = getVoicePath(type, item);
        pathList.add(path);
      }
      voicePathMap[type] = pathList;
    }
  }

  void initPlaylist(CalcVoiceType type) {
    playlist.clear();
    List<String> pathList = voicePathMap[type] ?? [];
    for (String filepath in pathList) {
      playlist.add(AudioSource.asset(filepath));
    }
  }

  AudioPlayer? currentAudioPlayer;

  Future<void> playVoice(CalcVoiceType type, CalcVoiceItem item) async {
    if (item == CalcVoiceItem.none) {
      return;
    }
    if (type != CalcVoiceType.putonghua) {
      debugPrint(
          '[Calc Audio Player] skip play voice for type: $type, 还没录音，还不能播放');
      return;
    }
    String path = getVoicePath(type, item);
    // currentAudioPlayer?.stop();
    var audioPlayer = audioPlayerMap[path];
    if (audioPlayer == null) {
      audioPlayer = AudioPlayer();
      audioPlayerMap[path] = audioPlayer;
      audioPlayer.setAsset(path);
      audioPlayer.setVolume(1.0);
      audioPlayer.playerStateStream.listen((state) {
        debugPrint('[Calc Audio Player] playerState: $state');
      });
      audioPlayer.playerEventStream.listen((event) {
        debugPrint('[Calc Audio Player] playerEvent: $event');
      });
      audioPlayer.bufferedPositionStream.listen((position) {
        debugPrint('[Calc Audio Player] bufferedPosition: $position');
      });
      audioPlayer.positionStream.listen((position) {
        debugPrint('[Calc Audio Player] position: $position');
      });
      audioPlayer.durationStream.listen((duration) {
        debugPrint('[Calc Audio Player] duration: $duration');
      });
    }
    // currentAudioPlayer = audioPlayer;
    audioPlayer.seek(Duration.zero);
    await audioPlayer.play();
  }
}
