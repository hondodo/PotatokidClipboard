import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_screen/core/parental/parental_config.dart';
import 'package:pscreen_screen/core/parental/parental_quiz.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 答题解锁：题库合并规则、随机顺序与跨重启轮换。
///
/// 规则：所有在看的档案题库合并、按题目 id 去重；出题顺序由
/// [ParentalQuizRotation] 做「稳定随机打乱 + 游标持久化」。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ChildProfile child(String id, {int? age}) =>
      ChildProfile(id: id, name: id, age: age);

  ParentalQuizQuestion q(String id) =>
      ParentalQuizQuestion(id: id, type: 'fill', prompt: id, accept: <String>[id]);

  group('ParentalQuizSelector', () {
    test('合并所有在看的儿童题库（不再只取年龄最大的）', () {
      final List<ParentalQuizQuestion> picked = ParentalQuizSelector.select(
        profiles: <ChildProfile>[child('young', age: 5), child('old', age: 9)],
        banks: <String, List<ParentalQuizQuestion>>{
          'young': <ParentalQuizQuestion>[q('q5')],
          'old': <ParentalQuizQuestion>[q('q9')],
        },
      );
      expect(
        picked.map((ParentalQuizQuestion item) => item.id).toSet(),
        <String>{'q5', 'q9'},
      );
    });

    test('同一道题（id 相同）只出现一次', () {
      final List<ParentalQuizQuestion> picked = ParentalQuizSelector.select(
        profiles: <ChildProfile>[child('a'), child('b'), child('c')],
        banks: <String, List<ParentalQuizQuestion>>{
          'a': <ParentalQuizQuestion>[q('shared'), q('a1')],
          'b': <ParentalQuizQuestion>[q('shared'), q('b1')],
          'c': <ParentalQuizQuestion>[q('c1')],
        },
      );
      expect(
        picked.map((ParentalQuizQuestion item) => item.id).toList(),
        <String>['shared', 'a1', 'b1', 'c1'],
      );
    });

    test('某个档案没有题库不影响其它档案合并', () {
      final List<ParentalQuizQuestion> picked = ParentalQuizSelector.select(
        profiles: <ChildProfile>[child('old', age: 10), child('mid', age: 7)],
        banks: <String, List<ParentalQuizQuestion>>{
          'old': <ParentalQuizQuestion>[],
          'mid': <ParentalQuizQuestion>[q('q7')],
        },
      );
      expect(picked.single.id, 'q7');
    });

    test('全部无题返回空（调用方回退算术题）', () {
      final List<ParentalQuizQuestion> picked = ParentalQuizSelector.select(
        profiles: <ChildProfile>[child('a', age: 4)],
        banks: const <String, List<ParentalQuizQuestion>>{},
      );
      expect(picked, isEmpty);
    });
  });

  group('ParentalQuizRotation', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    List<ParentalQuizQuestion> bank() => <ParentalQuizQuestion>[
      q('q1'),
      q('q2'),
      q('q3'),
      q('q4'),
      q('q5'),
    ];

    test('同一题库顺序稳定，首次从第 1 题开始', () async {
      final ParentalQuizRotation first = await ParentalQuizRotation.prepare(bank());
      final ParentalQuizRotation second = await ParentalQuizRotation.prepare(bank());
      expect(first.start, 0);
      expect(
        first.questions.map((ParentalQuizQuestion item) => item.id).toList(),
        second.questions.map((ParentalQuizQuestion item) => item.id).toList(),
      );
      expect(
        first.questions.map((ParentalQuizQuestion item) => item.id).toSet(),
        <String>{'q1', 'q2', 'q3', 'q4', 'q5'},
      );
    });

    test('答完一题后（模拟重启）从下一题开始', () async {
      final ParentalQuizRotation first = await ParentalQuizRotation.prepare(bank());
      await ParentalQuizRotation.markAnswered(first.questions, 0);
      final ParentalQuizRotation next = await ParentalQuizRotation.prepare(bank());
      expect(next.start, 1);
      expect(next.questions[next.start].id, first.questions[1].id);
    });

    test('答到最后一题后回到第一题', () async {
      final ParentalQuizRotation first = await ParentalQuizRotation.prepare(bank());
      await ParentalQuizRotation.markAnswered(first.questions, first.questions.length - 1);
      final ParentalQuizRotation next = await ParentalQuizRotation.prepare(bank());
      expect(next.start, 0);
      expect(next.questions.first.id, first.questions.first.id);
    });

    test('题库增删题后重新打乱并归零', () async {
      final ParentalQuizRotation first = await ParentalQuizRotation.prepare(bank());
      await ParentalQuizRotation.markAnswered(first.questions, 2);
      final List<ParentalQuizQuestion> changed = <ParentalQuizQuestion>[
        ...bank(),
        q('q6'),
      ];
      final ParentalQuizRotation next = await ParentalQuizRotation.prepare(changed);
      expect(next.start, 0);
      expect(next.questions.length, 6);
    });
  });

  group('ParentalQuizQuestion.fromJson', () {
    test('选择题：字符串选项兼容 + 答案/图片解析', () {
      final ParentalQuizQuestion question = ParentalQuizQuestion.fromJson(
        <String, dynamic>{
          'id': 'q1',
          'type': 'choice',
          'prompt': '1+1=?',
          'multiple': true,
          'options': <dynamic>['2', <String, dynamic>{'image': '/api/parental/quiz-image/x.png'}],
          'answers': <dynamic>[0, 1],
        },
      );
      expect(question.isChoice, isTrue);
      expect(question.multiple, isTrue);
      expect(question.options.length, 2);
      expect(question.options[1].image, '/api/parental/quiz-image/x.png');
      expect(question.answers, <int>[0, 1]);
    });

    test('图片地址补全为绝对地址', () {
      expect(
        ParentalQuizQuestion.resolveImageUrl('/api/parental/quiz-image/x.png'),
        contains('/api/parental/quiz-image/x.png'),
      );
      expect(
        ParentalQuizQuestion.resolveImageUrl('https://a.example/x.png'),
        'https://a.example/x.png',
      );
      expect(ParentalQuizQuestion.resolveImageUrl(''), '');
    });
  });
}
