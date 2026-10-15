import 'package:flutter_test/flutter_test.dart';
import 'package:potatokid_screen/features/msg/application/message_overlay_controller.dart';

void main() {
  late MessageOverlayController c;

  setUp(() {
    c = MessageOverlayController();
    c.deferActive = false;
  });

  tearDown(() => c.dispose());

  test('show 后可见，close 隐藏', () {
    c.show('你好');
    expect(c.visible, isTrue);
    expect(c.text, '你好');
    expect(c.detail, isFalse);
    c.close();
    expect(c.visible, isFalse);
  });

  test('显示期间新消息直接替换内容', () {
    c.show('第一条');
    c.show('第二条');
    expect(c.text, '第二条');
    expect(c.visible, isTrue);
  });

  test('OK 开详情，详情内 Back 回浮层，再 Back 关闭（两级返回）', () {
    c.show('内容');
    expect(c.handleOk(), isTrue);
    expect(c.detail, isTrue);
    expect(c.handleBack(), isTrue);
    expect(c.detail, isFalse);
    expect(c.visible, isTrue);
    expect(c.handleBack(), isTrue);
    expect(c.visible, isFalse);
  });

  test('不可见时 Back/OK 不消费', () {
    expect(c.handleBack(), isFalse);
    expect(c.handleOk(), isFalse);
  });

  test('详情中 OK 不消费', () {
    c.show('内容');
    c.openDetail();
    expect(c.handleOk(), isFalse);
  });

  test('deferActive 时 show 缓存不弹出，结束后 flush', () {
    c.deferActive = true;
    c.show('屏保中的消息');
    expect(c.visible, isFalse);
    expect(c.pending, '屏保中的消息');
    c.deferActive = false;
    c.onDeferEnd();
    expect(c.visible, isTrue);
    expect(c.text, '屏保中的消息');
  });

  test('defer 期间多条只留最新', () {
    c.deferActive = true;
    c.show('旧');
    c.show('新');
    c.deferActive = false;
    c.onDeferEnd();
    expect(c.text, '新');
  });

  test('visible 变化触发通知（供 UI 订阅）', () {
    int n = 0;
    c.addListener(() => n++);
    c.show('x');
    expect(n, 1);
  });
}
