const express = require('express');
const multer = require('multer');
const path = require('path');
const fs = require('fs');

const app = express();
const PORT = 3000;

// 确保上传目录存在
const uploadDir = path.join(__dirname, 'uploads');
if (!fs.existsSync(uploadDir)) {
    fs.mkdirSync(uploadDir, { recursive: true });
}

// 配置multer用于文件上传
const storage = multer.diskStorage({
    destination: function (req, file, cb) {
        // 根据请求中的uploadPath字段决定保存目录
        const uploadPath = req.body.uploadPath || '/uploads';
        const fullPath = path.join(__dirname, uploadPath);

        // 确保目录存在
        if (!fs.existsSync(fullPath)) {
            fs.mkdirSync(fullPath, { recursive: true });
        }

        cb(null, fullPath);
    },
    filename: function (req, file, cb) {
        // 生成唯一文件名
        const timestamp = Date.now();
        const originalName = file.originalname;
        const ext = path.extname(originalName);
        const name = path.basename(originalName, ext);
        const uniqueName = `${name}_${timestamp}${ext}`;
        cb(null, uniqueName);
    }
});

const upload = multer({
    storage: storage,
    limits: {
        fileSize: 10 * 1024 * 1024 // 限制文件大小为10MB
    }
});

// 启用CORS
app.use((req, res, next) => {
    res.header('Access-Control-Allow-Origin', '*');
    res.header('Access-Control-Allow-Methods', 'GET, POST, PUT, DELETE, OPTIONS');
    res.header('Access-Control-Allow-Headers', 'Origin, X-Requested-With, Content-Type, Accept, Authorization');

    if (req.method === 'OPTIONS') {
        res.sendStatus(200);
    } else {
        next();
    }
});

// 处理文件上传
app.post('/upload', upload.single('file'), (req, res) => {
    try {
        if (!req.file) {
            return res.status(400).json({
                success: false,
                message: '没有接收到文件'
            });
        }

        console.log('文件上传成功:');
        console.log('- 原始文件名:', req.file.originalname);
        console.log('- 保存路径:', req.file.path);
        console.log('- 文件大小:', req.file.size, 'bytes');
        console.log('- 上传时间:', new Date().toISOString());

        res.json({
            success: true,
            message: '文件上传成功',
            file: {
                originalName: req.file.originalname,
                filename: req.file.filename,
                path: req.file.path,
                size: req.file.size,
                uploadTime: new Date().toISOString()
            }
        });
    } catch (error) {
        console.error('上传处理错误:', error);
        res.status(500).json({
            success: false,
            message: '服务器内部错误',
            error: error.message
        });
    }
});

// 获取已上传文件列表
app.get('/files', (req, res) => {
    try {
        const files = fs.readdirSync(uploadDir).map(filename => {
            const filePath = path.join(uploadDir, filename);
            const stats = fs.statSync(filePath);
            return {
                name: filename,
                size: stats.size,
                uploadTime: stats.mtime.toISOString()
            };
        });

        res.json({
            success: true,
            files: files
        });
    } catch (error) {
        res.status(500).json({
            success: false,
            message: '获取文件列表失败',
            error: error.message
        });
    }
});

// 删除文件
app.delete('/files/:filename', (req, res) => {
    try {
        const filename = req.params.filename;
        const filePath = path.join(uploadDir, filename);

        // 检查文件是否存在
        if (!fs.existsSync(filePath)) {
            return res.status(404).json({
                success: false,
                message: '文件不存在'
            });
        }

        // 删除文件
        fs.unlinkSync(filePath);

        console.log(`文件已删除: ${filename}`);

        res.json({
            success: true,
            message: '文件删除成功'
        });
    } catch (error) {
        console.error('删除文件错误:', error);
        res.status(500).json({
            success: false,
            message: '删除文件失败',
            error: error.message
        });
    }
});

// 启动服务器
app.listen(PORT, () => {
    console.log(`文件上传服务器运行在 http://localhost:${PORT}`);
    console.log(`上传目录: ${uploadDir}`);
    console.log('支持的功能:');
    console.log('- POST /upload - 上传文件');
    console.log('- GET /files - 获取文件列表');
    console.log('- DELETE /files/:filename - 删除文件');
});
