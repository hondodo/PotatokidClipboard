#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""把 web/realtime.html 内联单 IIFE 机械拆分为多个 <script src>（原理同 _split_admin.py）。"""
import sys, os

SRC = 'web/realtime.html'
OUT_DIR = 'web/realtime_js'

# body 1-based 787..1855（首常量 .. boot();）
SEGMENTS = [
    ('01-core.js',   787,  998),  # 常量/state/DOM引用/工具函数
    ('02-net.js',    999, 1366),  # ws连接/请求/handleFrame
    ('03-data.js',  1367, 1479),  # normalize/addEvent/refresh/selectPeer
    ('04-render.js',1480, 1810),  # 所有 render 函数
    ('05-boot.js',  1811, 1855),  # bindEvents/boot/boot()
]
BODY_START, BODY_END = 787, 1855


def main():
    lines = open(SRC, encoding='utf-8', newline='').read().split('\n')
    assert lines[782].strip() == '<script>', lines[782]
    assert lines[783].strip() == '(() => {', lines[783]
    assert lines[784].strip() == "'use strict';", lines[784]
    assert lines[1854].strip() == 'boot();', lines[1854]
    assert lines[1855].strip() == '})();', lines[1855]

    orig_body = '\n'.join(lines[BODY_START - 1:BODY_END])  # 787..1855
    os.makedirs(OUT_DIR, exist_ok=True)
    pieces = []
    for name, start, end in SEGMENTS:
        seg = '\n'.join(lines[start - 1:end])
        with open(os.path.join(OUT_DIR, name), 'w', encoding='utf-8', newline='\n') as f:
            f.write("'use strict';\n\n" + seg + '\n')
        pieces.append(seg)
        print(f"  {name:16s} 行 {start}-{end}  ({end-start+1} 行)")

    rebuilt = '\n'.join(pieces)
    if rebuilt != orig_body:
        print("FAIL: 拼接不一致", file=sys.stderr)
        for i, (a, b) in enumerate(zip(rebuilt, orig_body)):
            if a != b:
                print(f"  差异@{i}: {rebuilt[max(0,i-30):i+30]!r} vs {orig_body[max(0,i-30):i+30]!r}", file=sys.stderr)
                break
        sys.exit(1)
    print("PASS: 分片拼接 === 原 IIFE body，行为等价。")

    # CSS：8..712（<style> 在 7，</style> 在 713）
    css = '\n'.join(lines[7:712])
    with open('web/realtime.css', 'w', encoding='utf-8', newline='\n') as f:
        f.write(css + '\n')
    print(f"  web/realtime.css ({len(lines[7:712])} 行)")

    # 新 HTML：行1-6 + css link + 行714-782 + scripts + 行1857-1859
    head = lines[0:6]
    css_link = ['  <link rel="stylesheet" href="realtime.css">']
    mid = lines[713:782]
    scripts = [f'  <script src="realtime_js/{n}"></script>' for n, _, _ in SEGMENTS]
    tail = lines[1856:1859]
    new_html = '\n'.join(head + css_link + mid + scripts + tail)
    with open('web/realtime.html.new', 'w', encoding='utf-8', newline='\n') as f:
        f.write(new_html)
    print(f"  web/realtime.html.new 已生成 ({len(new_html.splitlines())} 行)")


if __name__ == '__main__':
    main()
