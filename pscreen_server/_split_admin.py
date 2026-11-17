#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
把 web/admin.html 内联的单 IIFE 按功能边界机械拆分为多个 <script src> 文件。

原理：多个经典 <script> 共享同一全局词法作用域，顶层 const/let/function
跨文件互相可见（已在 vm 中验证）。因此只需把原 IIFE 的内容按顺序切段，
每段原样搬到独立 .js 文件，去掉 (()=>{ 'use strict'; ... })() 包装即可，
无需改动任何一行函数体，行为完全等价。

严格验证：所有分片按顺序拼接（去掉各文件头部的 'use strict'; 与空行），
必须逐字节等于原 IIFE body（去掉首行 'use strict';）。不相等则中止。

切点为顶层函数/常量声明的起始行（绝对行号），绝不在函数中间切开。
"""
import sys

SRC = 'web/admin.html'
OUT_DIR = 'web/admin_js'

# (文件名, 起始绝对行, 结束绝对行含) —— body 范围 1179..5419
# 起点是 state 定义行；'use strict'(1178) 与 IIFE 包装由脚本处理。
SEGMENTS = [
    ('01-core.js',          1180, 1383),  # state/$/esc/api/认证/renderAll
    ('02-machines.js',      1384, 1890),  # 机器/用户列表渲染、排序、工具
    ('03-dialogs.js',       1891, 2093),  # openDialog/editHomes/改名
    ('04-ha.js',            2094, 2967),  # HA 实体库/选择器/绑定
    ('05-config.js',        2968, 3135),  # ESP动作标签/editHaConfig/editFirmware
    ('06-parental.js',      3136, 3496),  # 家长控制
    ('07-layouts.js',       3497, 3631),  # 布局渲染
    ('08-traffic.js',       3632, 3926),  # 流量统计/家长记录
    ('09-programs.js',      3927, 4162),  # 节目管理
    ('10-device-types.js',  4163, 4540),  # 设备类型字典/规则引擎
    ('11-esp.js',           4541, 5380),  # ESP 设备配置
    ('12-boot.js',          5381, 5419),  # activateTab/事件绑定/tryAutoLogin
]

BODY_START, BODY_END = 1180, 5419  # 首个声明行 .. tryAutoLogin(); 行


def read_lines(path):
    with open(path, 'r', encoding='utf-8', newline='') as f:
        return f.read().split('\n')


def main():
    lines = read_lines(SRC)  # lines[i] 对应第 i+1 行
    # 校验边界（0-based 索引 = 1-based 行号 - 1）
    assert lines[1175].strip() == "<script>", ('line1176', lines[1175])
    assert lines[1176].strip() == "(() => {", ('line1177', lines[1176])
    assert lines[1177].strip() == "'use strict';", ('line1178', lines[1177])
    assert lines[5418].strip() == "tryAutoLogin();", ('line5419', lines[5418])
    assert lines[5419].strip() == "})();", ('line5420', lines[5419])

    # 原始 body（1-based 1180..5419）→ lines[1179:5419]
    orig_body = '\n'.join(lines[1179:5419])

    import os
    os.makedirs(OUT_DIR, exist_ok=True)

    pieces = []
    for name, start, end in SEGMENTS:
        seg = '\n'.join(lines[start - 1:end])  # 1-based inclusive
        # 每个文件加 'use strict'; 前缀（经典 script 各自严格模式）
        content = "'use strict';\n\n" + seg + "\n"
        with open(os.path.join(OUT_DIR, name), 'w', encoding='utf-8', newline='\n') as f:
            f.write(content)
        pieces.append(seg)
        print(f"  {name:22s} 行 {start}-{end}  ({end - start + 1} 行)")

    # 等价性验证：分片拼接（每个 seg 之间原本就是连续行，用 \n 连接）
    rebuilt = '\n'.join(pieces)
    if rebuilt != orig_body:
        print("FAIL: 拼接结果与原始 body 不一致！", file=sys.stderr)
        # 找出第一个差异
        for i, (a, b) in enumerate(zip(rebuilt, orig_body)):
            if a != b:
                print(f"  首个差异位置 {i}: rebuilt={a!r} orig={b!r}", file=sys.stderr)
                print(f"  rebuilt 片段: {rebuilt[max(0,i-40):i+40]!r}", file=sys.stderr)
                print(f"  orig    片段: {orig_body[max(0,i-40):i+40]!r}", file=sys.stderr)
                break
        else:
            print(f"  长度不同: rebuilt={len(rebuilt)} orig={len(orig_body)}", file=sys.stderr)
        sys.exit(1)

    print("PASS: 所有分片拼接后与原始 IIFE body 逐字节一致，行为等价。")

    # ---- 抽 CSS：1-based 行 9..683（<style> 在 8，</style> 在 684）----
    css = '\n'.join(lines[8:683])
    with open('web/admin.css', 'w', encoding='utf-8', newline='\n') as f:
        f.write(css + '\n')
    print(f"  web/admin.css  ({len(lines[8:683])} 行)")

    # ---- 生成新 HTML（先写 .new，验证后再原子替换）----
    # 结构：行1-7(含 link shared.css) + link admin.css + 行685-1175
    #       + 12 个 script 标签(按序) + 行5422-5423(</body></html>)
    head = lines[0:7]                       # 行 1-7
    css_link = ['  <link rel="stylesheet" href="admin.css">']
    mid = lines[684:1175]                   # 行 685-1175
    scripts = [f'  <script src="admin_js/{name}"></script>'
               for name, _, _ in SEGMENTS]
    tail = lines[5421:5423]                 # 行 5422-5423
    new_html = '\n'.join(head + css_link + mid + scripts + tail)
    with open('web/admin.html.new', 'w', encoding='utf-8', newline='\n') as f:
        f.write(new_html)
    print("  web/admin.html.new 已生成（待验证后替换）")
    print(f"  新 HTML 行数: {len(new_html.splitlines())}")


if __name__ == '__main__':
    main()
