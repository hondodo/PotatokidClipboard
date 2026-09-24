#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
简单的文件上传服务器
使用Python内置的http.server模块
"""

import http.server
import socketserver
import urllib.parse
import json
import os
from datetime import datetime

class FileUploadHandler(http.server.BaseHTTPRequestHandler):
    def do_OPTIONS(self):
        """处理CORS预检请求"""
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.send_header('Content-Length', '0')
        self.end_headers()

    def do_POST(self):
        """处理文件上传请求"""
        if self.path == '/upload':
            self.handle_file_upload()
        else:
            self.send_error(404, "Not Found")

    def handle_file_upload(self):
        """处理文件上传"""
        try:
            # 设置CORS头
            self.send_response(200)
            self.send_header('Access-Control-Allow-Origin', '*')
            self.send_header('Content-Type', 'application/json')
            self.end_headers()

            # 获取内容长度
            content_length = int(self.headers['Content-Length'])
            
            # 读取请求数据
            post_data = self.rfile.read(content_length)
            
            # 解析multipart数据
            boundary = self.headers['Content-Type'].split('boundary=')[1]
            parts = post_data.split(b'--' + boundary.encode())
            
            file_info = {}
            for part in parts:
                if b'Content-Disposition: form-data' in part:
                    if b'filename=' in part:
                        # 这是文件部分
                        lines = part.split(b'\r\n')
                        for line in lines:
                            if b'filename=' in line:
                                filename = line.decode().split('filename="')[1].split('"')[0]
                                file_info['filename'] = filename
                                break
                        # 获取文件内容（跳过头部信息）
                        file_content_start = part.find(b'\r\n\r\n') + 4
                        file_content = part[file_content_start:-2]  # 去掉最后的\r\n
                        file_info['size'] = len(file_content)
                        file_info['content'] = file_content
                    else:
                        # 这是表单字段
                        lines = part.split(b'\r\n')
                        for line in lines:
                            if b'name=' in line and b'filename=' not in line:
                                field_name = line.decode().split('name="')[1].split('"')[0]
                                field_value_start = part.find(b'\r\n\r\n') + 4
                                field_value = part[field_value_start:-2].decode()
                                file_info[field_name] = field_value
                                break

            # 创建上传目录
            upload_dir = 'uploads'
            if not os.path.exists(upload_dir):
                os.makedirs(upload_dir)

            # 保存文件
            if 'filename' in file_info and 'content' in file_info:
                timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
                safe_filename = f"{timestamp}_{file_info['filename']}"
                file_path = os.path.join(upload_dir, safe_filename)
                
                with open(file_path, 'wb') as f:
                    f.write(file_info['content'])
                
                response = {
                    'success': True,
                    'message': '文件上传成功',
                    'file': {
                        'originalName': file_info['filename'],
                        'savedName': safe_filename,
                        'size': file_info['size'],
                        'path': file_path,
                        'uploadTime': datetime.now().isoformat()
                    }
                }
            else:
                response = {
                    'success': False,
                    'message': '未找到文件数据'
                }

            # 发送响应
            self.wfile.write(json.dumps(response, ensure_ascii=False).encode('utf-8'))
            
        except Exception as e:
            self.send_response(500)
            self.send_header('Access-Control-Allow-Origin', '*')
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            
            error_response = {
                'success': False,
                'message': f'服务器错误: {str(e)}'
            }
            self.wfile.write(json.dumps(error_response, ensure_ascii=False).encode('utf-8'))

    def do_GET(self):
        """处理GET请求"""
        if self.path == '/files':
            self.list_files()
        else:
            self.send_error(404, "Not Found")

    def list_files(self):
        """列出已上传的文件"""
        try:
            upload_dir = 'uploads'
            if not os.path.exists(upload_dir):
                files = []
            else:
                files = []
                for filename in os.listdir(upload_dir):
                    file_path = os.path.join(upload_dir, filename)
                    if os.path.isfile(file_path):
                        stat = os.stat(file_path)
                        files.append({
                            'name': filename,
                            'size': stat.st_size,
                            'uploadTime': datetime.fromtimestamp(stat.st_mtime).isoformat()
                        })

            self.send_response(200)
            self.send_header('Access-Control-Allow-Origin', '*')
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            
            response = {
                'success': True,
                'files': files
            }
            self.wfile.write(json.dumps(response, ensure_ascii=False).encode('utf-8'))
            
        except Exception as e:
            self.send_response(500)
            self.send_header('Access-Control-Allow-Origin', '*')
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            
            error_response = {
                'success': False,
                'message': f'获取文件列表失败: {str(e)}'
            }
            self.wfile.write(json.dumps(error_response, ensure_ascii=False).encode('utf-8'))

    def log_message(self, format, *args):
        """自定义日志格式"""
        print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] {format % args}")

def run_server(port=3000):
    """启动服务器"""
    with socketserver.TCPServer(("", port), FileUploadHandler) as httpd:
        print(f"文件上传服务器运行在 http://localhost:{port}")
        print(f"上传目录: {os.path.abspath('uploads')}")
        print("支持的功能:")
        print("- POST /upload - 上传文件")
        print("- GET /files - 获取文件列表")
        print("按 Ctrl+C 停止服务器")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\n服务器已停止")

if __name__ == "__main__":
    run_server()
