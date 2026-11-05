import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_screen/core/parental/parental_config.dart';
import 'package:pscreen_screen/core/parental/parental_quiz.dart';

/// 答题解锁：题库选择规则与题目解析。
///
/// 规则：年龄从大到小分组 → 同岁合并按 id 去重 → 当前组无题看下一组 →
/// 未填年龄排最后（全部未填视为同组）→ 全部无题返回空（调用方回退算术）。
void main() {
  ChildProfile child(String id, {int? age}) =>
      ChildProfile(id: id, name: id, age: age);

  ParentalQuizQuestion q(String id) =>
      ParentalQuizQuestion(id: id, type: 'fill', prompt: id, accept: <String>[id]);

  group('ParentalQuizSelector', () {
    test('取年龄最大的孩子题库', () {
      final List<ParentalQuizQuestion> picked = ParentalQuizSelector.select(
        profiles: <ChildProfile>[child('young', age: 5), child('old', age: 9)],
        banks: <String, List<ParentalQuizQuestion>>{
          'young': <ParentalQuizQuestion>[q('q5')],
          'old': <ParentalQuizQuestion>[q('q9')],
        },
      );
      expect(picked.map((ParentalQuizQuestion item) => item.id), <String>['q9']);
    });

    test('同岁合并并按 id 去重', () {
      final List<ParentalQuizQuestion> picked = ParentalQuizSelector.select(
        profiles: <ChildProfile>[
          child('a', age: 8),
          child('b', age: 8),
          child('c', age: 8),
        ],
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

    test('年龄最大的一组无题时继续找下一组', () {
      final List<ParentalQuizQuestion> picked = ParentalQuizSelector.select(
        profiles: <ChildProfile>[child('old', age: 10), child('mid', age: 7)],
        banks: <String, List<ParentalQuizQuestion>>{
          'old': <ParentalQuizQuestion>[],
          'mid': <ParentalQuizQuestion>[q('q7')],
        },
      );
      expect(picked.single.id, 'q7');
    });

    test('未填年龄排最后；全体未填视为同组', () {
      final List<ParentalQuizQuestion> picked = ParentalQuizSelector.select(
        profiles: <ChildProfile>[child('noAge'), child('kid', age: 6)],
        banks: <String, List<ParentalQuizQuestion>>{
          'kid': <ParentalQuizQuestion>[],
          'noAge': <ParentalQuizQuestion>[q('n1')],
        },
      );
      expect(picked.single.id, 'n1');

      final List<ParentalQuizQuestion> merged = ParentalQuizSelector.select(
        profiles: <ChildProfile>[child('x'), child('y')],
        banks: <String, List<ParentalQuizQuestion>>{
          'x': <ParentalQuizQuestion>[q('x1')],
          'y': <ParentalQuizQuestion>[q('y1')],
        },
      );
      expect(merged.map((ParentalQuizQuestion item) => item.id), <String>['x1', 'y1']);
    });

    test('全部无题返回空（调用方回退算术题）', () {
      final List<ParentalQuizQuestion> picked = ParentalQuizSelector.select(
        profiles: <ChildProfile>[child('a', age: 4)],
        banks: const <String, List<ParentalQuizQuestion>>{},
      );
      expect(picked, isEmpty);
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
