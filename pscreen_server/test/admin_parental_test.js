// 服务端 parental 校验的最小测试（阶段 3）：直接驱动 admin.js 导出的
// normalizeParental，覆盖「整体拒绝 vs 安全归一」两侧行为。
// 运行：node test/admin_parental_test.js（在 pscreen_server 目录下）。
'use strict';

const assert = require('assert');
const path = require('path');
const { normalizeParental, normalizeQuizQuestions } = require(path.join(__dirname, '..', 'server', 'admin.js'));

let passed = 0;
function ok(name, fn) {
    fn();
    passed += 1;
    console.log(`  ✓ ${name}`);
}
function reject(name, input, keyword) {
    ok(name, () => {
        assert.throws(() => normalizeParental(input), (error) => {
            assert.ok(
                String(error.message).includes(keyword),
                `期望错误信息含「${keyword}」，实际：${error.message}`,
            );
            return true;
        });
    });
}

console.log('[admin parental] 校验测试');

// ---- 合法配置：归一后结构完整 ----
ok('完整配置归一（含 strict 档与禁看时段）', () => {
    const result = normalizeParental({
        mode: 'on',
        activeChildIds: ['c1', 'c1', 'c2'],
        children: [
            {
                id: ' c1 ',
                name: ' 小宝 ',
                age: 6.7,
                profileMode: 'strict',
                allowGroups: ['📺央视频道', '📺央视频道'],
                allowChannels: ['*少儿*'],
                sessionLimitMin: 30.9,
                dailyLimitMin: 120,
                quietHours: ['22:00-06:00'],
            },
            { id: 'c2', name: '姐姐', profileMode: 'mild', locked: true, hideGroups: ['📺购物频道'] },
        ],
        unlockMode: 'pin',
        pin: '1234',
        ownerAccount: '1000001',
    });
    assert.strictEqual(result.mode, 'on');
    assert.deepStrictEqual(result.activeChildIds, ['c1', 'c2']); // 去重
    assert.strictEqual(result.children.length, 2);
    assert.strictEqual(result.children[0].id, 'c1'); // 裁剪空白
    assert.strictEqual(result.children[0].name, '小宝');
    assert.strictEqual(result.children[0].age, 6); // 取整
    assert.strictEqual(result.children[0].sessionLimitMin, 30); // 取整
    assert.deepStrictEqual(result.children[0].allowGroups, ['📺央视频道']); // 去重
    assert.deepStrictEqual(result.children[0].quietHours, ['22:00-06:00']);
    assert.strictEqual(result.children[1].locked, true);
    assert.strictEqual(result.children[1].profileMode, 'mild');
    assert.strictEqual(result.unlockMode, 'pin');
    assert.strictEqual(result.pin, '1234');
});

ok('可选字段缺失补默认（与客户端 fromJson 一致）', () => {
    const result = normalizeParental({ mode: 'off', children: [{ id: 'c1', name: '小宝' }] });
    assert.strictEqual(result.mode, 'off');
    assert.strictEqual(result.unlockMode, 'remote');
    assert.strictEqual(result.pin, '');
    assert.strictEqual(result.ownerAccount, '');
    assert.deepStrictEqual(result.activeChildIds, []);
    const child = result.children[0];
    assert.strictEqual(child.profileMode, 'mild');
    assert.strictEqual(child.locked, false);
    assert.strictEqual(child.sessionLimitMin, 0);
    assert.strictEqual(child.dailyLimitMin, 0);
    assert.deepStrictEqual(child.quietHours, []);
    assert.ok(!('age' in child));
});

ok('null → 清除 parental', () => {
    assert.strictEqual(normalizeParental(null), null);
    assert.strictEqual(normalizeParental(undefined), null);
});

// ---- 整体拒绝：结构/枚举/数值非法 ----
reject('mode 缺失拒绝', { children: [] }, 'mode');
reject('mode 枚举外拒绝', { mode: 'ON', children: [] }, 'mode');
reject('children 非数组拒绝', { mode: 'on', children: 'c1' }, 'children');
reject('children 超 12 个拒绝', {
    mode: 'on',
    children: Array.from({ length: 13 }, (_, i) => ({ id: `c${i}`, name: `孩子${i}` })),
}, '12');
reject('档案 id 重复拒绝', {
    mode: 'on',
    children: [{ id: 'c1', name: 'a' }, { id: 'c1', name: 'b' }],
}, '重复');
reject('档案 id 缺失拒绝', { mode: 'on', children: [{ name: 'a' }] }, 'id');
reject('档案 name 空拒绝', { mode: 'on', children: [{ id: 'c1', name: '  ' }] }, 'name');
reject('profileMode 枚举外拒绝', {
    mode: 'on',
    children: [{ id: 'c1', name: 'a', profileMode: 'super' }],
}, 'profileMode');
reject('age 超范围拒绝', { mode: 'on', children: [{ id: 'c1', name: 'a', age: 200 }] }, 'age');
reject('age 非数值拒绝', { mode: 'on', children: [{ id: 'c1', name: 'a', age: '6' }] }, 'age');
reject('限额为负拒绝', { mode: 'on', children: [{ id: 'c1', name: 'a', sessionLimitMin: -1 }] }, 'sessionLimitMin');
reject('限额非数值拒绝', { mode: 'on', children: [{ id: 'c1', name: 'a', dailyLimitMin: '30' }] }, 'dailyLimitMin');
reject('unlockMode 枚举外拒绝', { mode: 'on', unlockMode: 'face' }, 'unlockMode');
reject('名单非数组拒绝', { mode: 'on', children: [{ id: 'c1', name: 'a', hideGroups: '购物' }] }, 'hideGroups');
reject('名单元素非字符串拒绝', { mode: 'on', children: [{ id: 'c1', name: 'a', allowChannels: [1] }] }, 'allowChannels');
reject('quietHours 格式非法拒绝', {
    mode: 'on',
    children: [{ id: 'c1', name: 'a', quietHours: ['2200-0600'] }],
}, 'HH:MM');
reject('quietHours 起止相同拒绝', {
    mode: 'on',
    children: [{ id: 'c1', name: 'a', quietHours: ['22:00-22:00'] }],
}, '相同');
reject('parental 非对象拒绝', ['off'], '对象');
reject('locked 非布尔拒绝', { mode: 'on', children: [{ id: 'c1', name: 'a', locked: 'yes' }] }, 'locked');

ok('unlockMode 允许 quiz', () => {
    const result = normalizeParental({ mode: 'on', unlockMode: 'quiz' });
    assert.strictEqual(result.unlockMode, 'quiz');
});

// ---- 答题题库校验 ----
console.log('[admin quiz] 校验测试');

function rejectQuiz(name, input, keyword) {
    ok(name, () => {
        assert.throws(() => normalizeQuizQuestions(input), (error) => {
            assert.ok(
                String(error.message).includes(keyword),
                `期望错误信息含「${keyword}」，实际：${error.message}`,
            );
            return true;
        });
    });
}

ok('选择题归一：字符串选项、答案去重、多选', () => {
    const [q] = normalizeQuizQuestions([
        {
            id: 'q1',
            type: 'choice',
            prompt: ' 选出偶数 ',
            multiple: true,
            options: ['2', '3', '4'],
            answers: [0, 2, 2],
        },
    ]);
    assert.strictEqual(q.prompt, '选出偶数');
    assert.strictEqual(q.multiple, true);
    assert.deepStrictEqual(q.options.map((o) => o.text), ['2', '3', '4']);
    assert.deepStrictEqual(q.answers, [0, 2]);
});

ok('填空题归一：答案裁剪去重、忽略多余字段', () => {
    const [q] = normalizeQuizQuestions([
        {
            id: 'q2',
            type: 'fill',
            prompt: '中国首都？',
            accept: [' 北京 ', 'Beijing', '北京'],
            options: ['x'],
            answers: [0],
        },
    ]);
    assert.strictEqual(q.type, 'fill');
    assert.deepStrictEqual(q.accept, ['北京', 'Beijing']);
    assert.deepStrictEqual(q.options, []);
    assert.deepStrictEqual(q.answers, []);
});

ok('空题库允许（表示清空）', () => {
    assert.deepStrictEqual(normalizeQuizQuestions([]), []);
    assert.deepStrictEqual(normalizeQuizQuestions(undefined), []);
});

ok('题库图片必须是本站地址', () => {
    const [q] = normalizeQuizQuestions([
        {
            id: 'q3',
            type: 'choice',
            promptImage: '/api/parental/quiz-image/abc123.png',
            options: [{ text: 'A' }, { image: '/api/parental/quiz-image/def456.jpg' }],
            answers: [0],
        },
    ]);
    assert.strictEqual(q.promptImage, '/api/parental/quiz-image/abc123.png');
    assert.strictEqual(q.options[1].image, '/api/parental/quiz-image/def456.jpg');
});

rejectQuiz('题库非数组拒绝', { questions: [] }, 'questions');
rejectQuiz('题目类型枚举外拒绝', [{ id: 'q1', type: 'essay', prompt: 'x' }], 'type');
rejectQuiz('题目 id 重复拒绝', [
    { id: 'q1', type: 'fill', prompt: 'a', accept: ['a'] },
    { id: 'q1', type: 'fill', prompt: 'b', accept: ['b'] },
], '重复');
rejectQuiz('题干与图片同时为空拒绝', [{ id: 'q1', type: 'fill', accept: ['a'] }], '题干');
rejectQuiz('选项少于 2 个拒绝', [
    { id: 'q1', type: 'choice', prompt: 'x', options: ['a'], answers: [0] },
], '2~10');
rejectQuiz('选项超过 10 个拒绝', [
    {
        id: 'q1',
        type: 'choice',
        prompt: 'x',
        options: ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11'],
        answers: [0],
    },
], '2~10');
rejectQuiz('答案下标越界拒绝', [
    { id: 'q1', type: 'choice', prompt: 'x', options: ['a', 'b'], answers: [2] },
], 'answers');
rejectQuiz('单选题多个答案拒绝', [
    { id: 'q1', type: 'choice', prompt: 'x', options: ['a', 'b'], answers: [0, 1] },
], '单选题');
rejectQuiz('选择题未给答案拒绝', [
    { id: 'q1', type: 'choice', prompt: 'x', options: ['a', 'b'] },
], 'answers');
rejectQuiz('填空题无可接受答案拒绝', [{ id: 'q1', type: 'fill', prompt: 'x', accept: [] }], 'accept');
rejectQuiz('选项外链图片拒绝', [
    {
        id: 'q1',
        type: 'choice',
        prompt: 'x',
        options: [{ text: 'a' }, { image: 'https://evil.example/a.png' }],
        answers: [0],
    },
], '.image');
rejectQuiz('题干外链图片拒绝', [
    {
        id: 'q1',
        type: 'choice',
        promptImage: 'https://evil.example/a.png',
        options: ['a', 'b'],
        answers: [0],
    },
], 'promptImage');
rejectQuiz('题库超过 200 题拒绝', new Array(201).fill(null).map((_, index) => ({
    id: `q${index}`,
    type: 'fill',
    prompt: 'x',
    accept: ['x'],
})), '200');

console.log(`[admin parental] 通过 ${passed} 项`);
