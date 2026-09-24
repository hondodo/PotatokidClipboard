const express = require('express');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const crypto = require('crypto');
const cookieParser = require('cookie-parser');
const config = require('./config');
const definds = require('./definds');

const app = express();
const PORT = config.port;

// 配置信任代理，以便正确获取用户真实IP
app.set('trust proxy', true);

// 请求日志中间件
app.use((req, res, next) => {
    const timestamp = new Date().toISOString();
    const method = req.method;
    const url = req.url;
    const userAgent = req.get('User-Agent') || 'Unknown';
    const ip = req.ip || req.connection.remoteAddress || 'Unknown';

    console.log(`[${timestamp}] ${method} ${url} - ${ip} - ${userAgent}`);

    // 记录响应时间
    const startTime = Date.now();
    res.on('finish', () => {
        const duration = Date.now() - startTime;
        console.log(`[${timestamp}] ${method} ${url} - ${res.statusCode} - ${duration}ms`);
    });

    next();
});

// 配置JSON解析中间件
app.use(express.json({ limit: config.limits.jsonLimit }));
app.use(express.urlencoded({ extended: true, limit: config.limits.urlencodedLimit }));

// 配置cookie解析中间件
app.use(cookieParser());

// 配置静态文件服务 - Flutter Web应用
const webAppPath = path.resolve(config.directories.webApp);
console.log(`Flutter Web应用绝对路径: ${webAppPath}`);
app.use(express.static(webAppPath));

// 确保数据目录存在
const datasDir = path.join(__dirname, '../datas');
if (!fs.existsSync(datasDir)) {
    fs.mkdirSync(datasDir, { recursive: true });
}

// 确保用户目录存在
const usersDir = path.join(datasDir, 'users');
if (!fs.existsSync(usersDir)) {
    fs.mkdirSync(usersDir, { recursive: true });
}

// 确保翻译目录存在
const translationsDir = path.join(datasDir, 'translations');
if (!fs.existsSync(translationsDir)) {
    fs.mkdirSync(translationsDir, { recursive: true });
}

// 确保注册用户目录存在
const registerUsersDir = path.join(datasDir, 'register', 'users');
if (!fs.existsSync(registerUsersDir)) {
    fs.mkdirSync(registerUsersDir, { recursive: true });
}

// 保持向后兼容的上传目录
const uploadDir = path.join(__dirname, config.directories.uploads);
if (!fs.existsSync(uploadDir)) {
    fs.mkdirSync(uploadDir, { recursive: true });
}

// 配置multer用于文件上传
const storage = multer.diskStorage({
    destination: function (req, file, cb) {
        // 获取用户名
        const username = req.cookies?.username;

        if (username) {
            // 如果已登录，保存到用户个人目录
            const userUploadDir = path.join(usersDir, username, 'uploads');
            if (!fs.existsSync(userUploadDir)) {
                fs.mkdirSync(userUploadDir, { recursive: true });
            }
            req._uploadTargetDir = userUploadDir;
            cb(null, userUploadDir);
        } else {
            // 未登录用户，使用传统目录
            const uploadPath = req.body.uploadPath || '/uploads';
            const fullPath = path.join(__dirname, '..', uploadPath);

            // 确保目录存在
            if (!fs.existsSync(fullPath)) {
                fs.mkdirSync(fullPath, { recursive: true });
            }

            req._uploadTargetDir = fullPath;
            cb(null, fullPath);
        }
    },
    filename: function (req, file, cb) {
        let originalName = file.originalname;

        // 检测并修复中文文件名编码问题
        try {
            // 如果文件名包含乱码字符，尝试修复编码
            if (/[\u00C0-\u00FF]/.test(originalName)) {
                originalName = Buffer.from(originalName, 'latin1').toString('utf8');
            }
        } catch (error) {
            // 如果修复失败，使用原始文件名
            console.warn('文件名编码修复失败，使用原始文件名:', error.message);
        }

        // 仅使用基本文件名，忽略路径片段
        originalName = path.basename(originalName);
        const saveDir = req._uploadTargetDir;
        const ext = path.extname(originalName);
        const nameWithoutExt = path.basename(originalName, ext);

        /** 目录中无同名文件则用原名；否则使用 name(1).ext、name(2).ext … */
        function resolveSaveName(dir) {
            const directPath = path.join(dir, originalName);
            if (!fs.existsSync(directPath)) {
                return originalName;
            }
            let n = 1;
            while (true) {
                const candidate = `${nameWithoutExt}(${n})${ext}`;
                if (!fs.existsSync(path.join(dir, candidate))) {
                    return candidate;
                }
                n++;
            }
        }

        try {
            const finalName = saveDir ? resolveSaveName(saveDir) : `${nameWithoutExt}_${Date.now()}${ext}`;
            cb(null, finalName);
        } catch (error) {
            console.error('生成上传文件名错误:', error);
            cb(error);
        }
    }
});

const upload = multer({
    storage: storage,
    limits: {
        fileSize: config.limits.fileSize
    }
});

// 启用CORS
app.use((req, res, next) => {
    res.header('Access-Control-Allow-Origin', config.cors.origin);
    res.header('Access-Control-Allow-Methods', config.cors.methods.join(', '));
    res.header('Access-Control-Allow-Headers', config.cors.allowedHeaders.join(', '));

    if (req.method === 'OPTIONS') {
        res.sendStatus(200);
    } else {
        next();
    }
});

// 用户注册接口
app.post('/api/register', (req, res) => {
    try {
        const { username, password } = req.body;

        if (!username || !password) {
            return res.status(200).json({
                [definds.txt.CODE]: definds.code.FAILED,
                [definds.txt.MSG]: '用户名和密码不能为空',
            });
        }

        // 验证用户名长度
        if (username.length < 2 || username.length > 20) {
            return res.status(200).json({
                [definds.txt.CODE]: definds.code.FAILED,
                [definds.txt.MSG]: '用户名长度必须在2-20个字符之间',
            });
        }

        // 验证密码长度
        if (password.length < 4 || password.length > 50) {
            return res.status(200).json({
                [definds.txt.CODE]: definds.code.FAILED,
                [definds.txt.MSG]: '密码长度必须在4-50个字符之间',
            });
        }

        // 检查用户名是否已存在
        const userFilePath = path.join(registerUsersDir, username);
        if (fs.existsSync(userFilePath)) {
            return res.status(200).json({
                [definds.txt.CODE]: definds.code.FAILED,
                [definds.txt.MSG]: '用户名已存在',
            });
        }

        // 生成密码的MD5哈希
        const passwordHash = password;  // 改成在客户端做加密了，传入的就是加密后的密码 // crypto.createHash('md5').update(password).digest('hex');

        // 创建用户文件
        fs.writeFileSync(userFilePath, passwordHash, 'utf8');

        // 读取用户最大id，如果文件不存在，则创建和设置初始化值为0
        const maxIdFilePath = path.join(registerUsersDir, 'max_id.txt');
        let userMaxId = 0;
        if (fs.existsSync(maxIdFilePath)) {
            const maxIdContent = fs.readFileSync(maxIdFilePath, 'utf8').trim();
            if (maxIdContent) {
                userMaxId = parseInt(maxIdContent) || 0;
            }
        }
        const newUserId = userMaxId + 1;
        fs.writeFileSync(maxIdFilePath, newUserId.toString(), 'utf8');

        // 记录这个用户信息到用户文件 users/username_info.txt
        const userInfoFilePath = path.join(registerUsersDir, username + '_info.txt');
        const userInfo = {
            id: newUserId,
            name: username,
            createdAt: new Date().toISOString()
        };
        fs.writeFileSync(userInfoFilePath, JSON.stringify(userInfo, null, 2), 'utf8');

        console.log(`用户注册成功: ${username}`);

        res.json({
            [definds.txt.CODE]: definds.code.SUCCESS,
            [definds.txt.MSG]: '注册成功',
            [definds.txt.DATA]: {
                user: userInfo
            }
        });
    } catch (error) {
        console.error('注册处理错误:', error);
        res.status(200).json({
            [definds.txt.CODE]: definds.code.FAILED,
            [definds.txt.MSG]: error.message,
        });
    }
});

// 用户登录接口
app.post('/api/login', (req, res) => {
    try {
        const { username, password } = req.body;

        if (!username || !password) {
            return res.status(200).json({
                [definds.txt.CODE]: definds.code.FAILED,
                [definds.txt.MSG]: '用户名和密码不能为空',
            });
        }

        // 检查用户文件是否存在
        const userFilePath = path.join(registerUsersDir, username);
        if (!fs.existsSync(userFilePath)) {
            console.log(`登录失败: ${username} - 用户不存在`);
            return res.status(200).json({
                [definds.txt.CODE]: definds.code.FAILED,
                [definds.txt.MSG]: '用户不存在',
            });
        }

        // 读取用户文件中的密码哈希
        const storedPasswordHash = fs.readFileSync(userFilePath, 'utf8').trim();

        // 计算输入密码的MD5哈希
        const inputPasswordHash = password;  // 改成在客户端做加密了，传入的就是加密后的密码 //crypto.createHash('md5').update(password).digest('hex');

        // 验证密码
        if (storedPasswordHash !== inputPasswordHash) {
            console.log(`登录失败: ${username} - 密码错误`);
            return res.status(200).json({
                [definds.txt.CODE]: definds.code.FAILED,
                [definds.txt.MSG]: '密码错误',
            });
        }

        // 密码验证成功，设置cookie
        res.cookie('username', username, {
            maxAge: 14 * 24 * 60 * 60 * 1000, // 14天
            httpOnly: false, // 允许前端访问
            secure: false, // 开发环境设为false
            sameSite: 'lax'
        });

        // 记录这个用户信息到用户文件 users/username_info.txt
        const userInfoFilePath = path.join(registerUsersDir, username + '_info.txt');
        if (!fs.existsSync(userInfoFilePath)) {
            console.log(`登录失败: ${username} - 用户信息文件不存在`);
            return res.status(200).json({
                [definds.txt.CODE]: definds.code.FAILED,
                [definds.txt.MSG]: '用户信息文件不存在，请重新注册',
            });
        }
        // 读取用户信息
        const userInfo = JSON.parse(fs.readFileSync(userInfoFilePath, 'utf8'));
        // 更新登录时间
        userInfo.loginTime = new Date().toISOString();
        // 保存用户信息
        fs.writeFileSync(userInfoFilePath, JSON.stringify(userInfo, null, 2), 'utf8');

        console.log(`用户登录成功: ${username}`);

        const userData = {
            user: userInfo,
        };
        res.json({
            [definds.txt.CODE]: definds.code.SUCCESS,
            [definds.txt.MSG]: '登录成功',
            [definds.txt.DATA]: userData
        });
    } catch (error) {
        console.error('登录处理错误:', error);
        res.status(200).json({
            [definds.txt.CODE]: definds.code.FAILED,
            [definds.txt.MSG]: error.message,
        });
    }
});

// 自动登录接口
app.post('/api/autoLogin', (req, res) => {
    try {
        // 从cookie中获取username
        const username = req.cookies?.username;
        if (!username) {
            return res.status(200).json({
                [definds.txt.CODE]: definds.code.FAILED,
                [definds.txt.MSG]: '用户未登录',
            });
        }

        // 检查用户文件是否存在
        const userFilePath = path.join(registerUsersDir, username);
        if (!fs.existsSync(userFilePath)) {
            console.log(`自动登录失败: ${username} - 用户不存在`);
            return res.status(200).json({
                [definds.txt.CODE]: definds.code.FAILED,
                [definds.txt.MSG]: '用户不存在',
            });
        }

        // 密码验证成功，设置cookie
        res.cookie('username', username, {
            maxAge: 14 * 24 * 60 * 60 * 1000, // 14天
            httpOnly: false, // 允许前端访问
            secure: false, // 开发环境设为false
            sameSite: 'lax'
        });

        // 记录这个用户信息到用户文件 users/username_info.txt
        const userInfoFilePath = path.join(registerUsersDir, username + '_info.txt');
        if (!fs.existsSync(userInfoFilePath)) {
            console.log(`自动登录失败: ${username} - 用户信息文件不存在`);
            return res.status(200).json({
                [definds.txt.CODE]: definds.code.FAILED,
                [definds.txt.MSG]: '用户信息文件不存在，请重新注册',
            });
        }
        // 读取用户信息
        const userInfo = JSON.parse(fs.readFileSync(userInfoFilePath, 'utf8'));
        // 更新登录时间
        userInfo.loginTime = new Date().toISOString();
        // 保存用户信息
        fs.writeFileSync(userInfoFilePath, JSON.stringify(userInfo, null, 2), 'utf8');

        console.log(`自动登录成功: ${username}`);

        const userData = {
            user: userInfo,
        };
        res.json({
            [definds.txt.CODE]: definds.code.SUCCESS,
            [definds.txt.MSG]: '自动登录成功',
            [definds.txt.DATA]: userData
        });
    } catch (error) {
        console.error('自动登录处理错误:', error);
        res.status(200).json({
            [definds.txt.CODE]: definds.code.FAILED,
            [definds.txt.MSG]: error.message,
        });
    }
});

// 处理文件上传
app.post('/api/upload', upload.single('file'), (req, res) => {
    const startTime = Date.now();
    console.log(`[文件上传] 开始处理上传请求`);

    try {
        if (!req.file) {
            console.log(`[文件上传] 错误: 未接收到文件`);
            return res.status(200).json({
                [definds.txt.CODE]: definds.code.FAILED,
                [definds.txt.MSG]: '没有接收到文件',
            });
        }

        const duration = Date.now() - startTime;
        console.log(`[文件上传] 成功: ${req.file.originalname} (${req.file.size} bytes) - ${duration}ms`);
        console.log(`[文件上传] 详情: 保存路径=${req.file.path}, 文件名=${req.file.filename}`);

        res.json({
            [definds.txt.CODE]: definds.code.SUCCESS,
            [definds.txt.MSG]: '文件上传成功',
            [definds.txt.DATA]: {
                file: req.file
            }
        });
    } catch (error) {
        console.error('上传处理错误:', error);
        res.status(200).json({
            [definds.txt.CODE]: definds.code.FAILED,
            [definds.txt.MSG]: error.message,
        });
    }
});

// 获取已上传文件列表
app.get('/api/files', (req, res) => {
    const startTime = Date.now();
    console.log(`[文件列表] 开始获取文件列表`);

    try {
        const username = req.cookies?.username;
        let targetDir = uploadDir; // 默认目录

        if (username) {
            // 如果已登录，获取用户个人文件
            const userUploadDir = path.join(usersDir, username, 'uploads');
            if (fs.existsSync(userUploadDir)) {
                targetDir = userUploadDir;
            }
        }

        const files = fs.readdirSync(targetDir).map(filename => {
            const filePath = path.join(targetDir, filename);
            const stats = fs.statSync(filePath);
            return {
                name: filename,
                size: stats.size,
                uploadTime: stats.mtime.toISOString()
            };
        });

        // 按时间倒序排列（最新的文件在前面）
        files.sort((a, b) => new Date(b.uploadTime) - new Date(a.uploadTime));

        const duration = Date.now() - startTime;
        console.log(`[文件列表] 成功: 找到 ${files.length} 个文件，已按时间倒序排列 - ${duration}ms`);

        res.json({
            [definds.txt.CODE]: definds.code.SUCCESS,
            [definds.txt.MSG]: '获取文件列表成功',
            [definds.txt.DATA]: {
                files: files
            }
        });
    } catch (error) {
        const duration = Date.now() - startTime;
        console.error(`[文件列表] 错误: ${error.message} - ${duration}ms`);
        res.status(200).json({
            [definds.txt.CODE]: definds.code.FAILED,
            [definds.txt.MSG]: error.message,
        });
    }
});

// 删除文件
app.delete('/api/files/:filename', (req, res) => {
    try {
        const filename = req.params.filename;
        const username = req.cookies?.username;

        let filePath;
        if (username) {
            // 如果已登录，删除用户个人文件
            const userUploadDir = path.join(usersDir, username, 'uploads');
            filePath = path.join(userUploadDir, filename);
        } else {
            // 未登录用户，删除传统目录文件
            filePath = path.join(uploadDir, filename);
        }

        // 检查文件是否存在
        if (!fs.existsSync(filePath)) {
            return res.status(200).json({
                [definds.txt.CODE]: definds.code.FAILED,
                [definds.txt.MSG]: '文件不存在',
            });
        }

        // 删除文件
        fs.unlinkSync(filePath);

        console.log(`文件已删除: ${filename}`);

        res.json({
            [definds.txt.CODE]: definds.code.SUCCESS,
            [definds.txt.MSG]: '文件删除成功',
        });
    } catch (error) {
        console.error('删除文件错误:', error);
        res.status(200).json({
            [definds.txt.CODE]: definds.code.FAILED,
            [definds.txt.MSG]: error.message,
        });
    }
});

// 笔记相关API - 使用新的用户目录结构
// 确保用户笔记目录存在（在用户个人目录下）

// 创建笔记
app.post('/api/notes', (req, res) => {
    try {
        const { content } = req.body;
        const username = req.cookies?.username;

        if (!username) {
            return res.status(200).json({
                [definds.txt.CODE]: definds.code.FAILED,
                [definds.txt.MSG]: '请先登录',
            });
        }

        if (!content) {
            return res.status(200).json({
                [definds.txt.CODE]: definds.code.FAILED,
                [definds.txt.MSG]: '笔记内容不能为空',
            });
        }

        // 创建用户笔记目录
        const userNotesDir = path.join(usersDir, username, 'notes');
        if (!fs.existsSync(userNotesDir)) {
            fs.mkdirSync(userNotesDir, { recursive: true });
        }

        // 生成笔记ID和时间戳
        const noteId = Date.now().toString();
        const timestamp = new Date().toISOString();
        const filename = `note_${noteId}.txt`;
        const filePath = path.join(userNotesDir, filename);

        // 创建笔记内容
        const noteContent = {
            id: noteId,
            username: username,
            content: content,
            createdAt: timestamp
        };

        // 保存到文件
        fs.writeFileSync(filePath, JSON.stringify(noteContent, null, 2));

        console.log(`笔记已创建: ${username}/${filename}`);

        res.json({
            [definds.txt.CODE]: definds.code.SUCCESS,
            [definds.txt.MSG]: '笔记创建成功',
            [definds.txt.DATA]: {
                note: noteContent
            }
        });
    } catch (error) {
        console.error('创建笔记错误:', error);
        res.status(200).json({
            [definds.txt.CODE]: definds.code.FAILED,
            [definds.txt.MSG]: error.message,
        });
    }
});

// 获取用户笔记列表
app.get('/api/notes', (req, res) => {
    try {
        const username = req.cookies?.username;

        if (!username) {
            return res.status(200).json({
                [definds.txt.CODE]: definds.code.FAILED,
                [definds.txt.MSG]: '请先登录',
            });
        }

        const userNotesDir = path.join(usersDir, username, 'notes');

        if (!fs.existsSync(userNotesDir)) {
            return res.json({
                [definds.txt.CODE]: definds.code.SUCCESS,
                [definds.txt.MSG]: '获取笔记列表成功',
                [definds.txt.DATA]: {
                    notes: []
                }
            });
        }

        // 读取用户目录下的所有笔记文件
        const files = fs.readdirSync(userNotesDir).filter(file => file.endsWith('.txt'));
        const notes = files.map(filename => {
            const filePath = path.join(userNotesDir, filename);
            const content = fs.readFileSync(filePath, 'utf8');
            return JSON.parse(content);
        }).sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));

        res.json({
            [definds.txt.CODE]: definds.code.SUCCESS,
            [definds.txt.MSG]: '获取笔记列表成功',
            [definds.txt.DATA]: {
                notes: notes
            }
        });
    } catch (error) {
        console.error('获取笔记列表错误:', error);
        res.status(200).json({
            [definds.txt.CODE]: definds.code.FAILED,
            [definds.txt.MSG]: error.message,
        });
    }
});

// 删除笔记
app.delete('/api/notes/:noteId', (req, res) => {
    try {
        const { noteId } = req.params;
        const username = req.cookies?.username;

        if (!username) {
            return res.status(200).json({
                [definds.txt.CODE]: definds.code.FAILED,
                [definds.txt.MSG]: '请先登录',
            });
        }

        const userNotesDir = path.join(usersDir, username, 'notes');
        const filename = `note_${noteId}.txt`;
        const filePath = path.join(userNotesDir, filename);

        if (!fs.existsSync(filePath)) {
            return res.status(200).json({
                [definds.txt.CODE]: definds.code.FAILED,
                [definds.txt.MSG]: '笔记不存在',
            });
        }

        // 删除文件
        fs.unlinkSync(filePath);

        console.log(`笔记已删除: ${username}/${filename}`);

        res.json({
            [definds.txt.CODE]: definds.code.SUCCESS,
            [definds.txt.MSG]: '笔记删除成功',
        });
    } catch (error) {
        console.error('删除笔记错误:', error);
        res.status(200).json({
            [definds.txt.CODE]: definds.code.FAILED,
            [definds.txt.MSG]: error.message,
        });
    }
});

// 文件下载API，如果下载成功则200，否则400、500，错误信息返回给前端（code:400\500,msg:错误信息）
app.get('/api/download/:filename', (req, res) => {
    try {
        const filename = req.params.filename;
        const username = req.cookies?.username;

        let filePath;
        if (username) {
            // 如果已登录，下载用户个人文件
            const userUploadDir = path.join(usersDir, username, 'uploads');
            filePath = path.join(userUploadDir, filename);
        } else {
            // 未登录用户，下载传统目录文件
            filePath = path.join(uploadDir, filename);
        }

        // 检查文件是否存在
        if (!fs.existsSync(filePath)) {
            return res.status(404).json({
                [definds.txt.CODE]: definds.code.FAILED,
                [definds.txt.MSG]: '文件不存在',
            });
        }

        // 设置下载头，处理中文文件名
        const encodedFilename = encodeURIComponent(filename);
        res.setHeader('Content-Disposition', `attachment; filename*=UTF-8''${encodedFilename}`);
        res.setHeader('Content-Type', 'application/octet-stream');

        // 发送文件
        res.sendFile(filePath);

        console.log(`文件下载: ${filename}`);
    } catch (error) {
        console.error('文件下载错误:', error);
        res.status(500).json({
            [definds.txt.CODE]: definds.code.FAILED,
            [definds.txt.MSG]: error.message,
        });
    }
});

// 翻译文件目录已在上方定义，使用新的datas/translations目录

// 获取App和语言配置
app.get('/api/translation_config', (req, res) => {
    try {
        const configPath = path.join(__dirname, 'translation-config.json');
        let translationConfig;

        if (fs.existsSync(configPath)) {
            const configData = fs.readFileSync(configPath, 'utf8');
            translationConfig = JSON.parse(configData);
        } else {
            // 默认配置
            translationConfig = {
                apps: [
                    {
                        appName: "myStar",
                        languages: [
                            { lanName: "英文", lanFile: "en_US.json" },
                            { lanName: "日文", lanFile: "ja_JP.json" },
                            { lanName: "中文", lanFile: "zh_CN.json" }
                        ]
                    },
                    {
                        appName: "PicsAi",
                        languages: [
                            { lanName: "英文", lanFile: "en_US.json" },
                            { lanName: "日文", lanFile: "ja_JP.json" },
                            { lanName: "中文", lanFile: "zh_CN.json" }
                        ]
                    }
                ]
            };
        }

        res.json({
            [definds.txt.CODE]: definds.code.SUCCESS,
            [definds.txt.MSG]: '获取翻译配置成功',
            [definds.txt.DATA]: translationConfig
        });
    } catch (error) {
        console.error('获取翻译配置错误:', error);
        res.status(200).json({
            [definds.txt.CODE]: definds.code.FAILED,
            [definds.txt.MSG]: error.message,
        });
    }
});

// 配置翻译文件上传的multer - 使用临时目录
const translationStorage = multer.diskStorage({
    destination: function (req, file, cb) {
        // 先保存到临时目录
        const tempDir = path.join(translationsDir, 'temp');

        console.log(`[翻译上传] 临时目录: ${tempDir}`);

        // 确保临时目录存在
        if (!fs.existsSync(tempDir)) {
            fs.mkdirSync(tempDir, { recursive: true });
        }

        cb(null, tempDir);
    },
    filename: function (req, file, cb) {
        // 使用时间戳作为临时文件名，兼容处理中文文件名
        const timestamp = Date.now();
        let originalName = file.originalname;

        // 检测并修复中文文件名编码问题
        try {
            // 如果文件名包含乱码字符，尝试修复编码
            if (/[\u00C0-\u00FF]/.test(originalName)) {
                originalName = Buffer.from(originalName, 'latin1').toString('utf8');
            }
        } catch (error) {
            // 如果修复失败，使用原始文件名
            console.warn('[翻译上传] 文件名编码修复失败，使用原始文件名:', error.message);
        }

        const tempFileName = `temp_${timestamp}_${originalName}`;

        console.log(`[翻译上传] 临时文件名: ${tempFileName}`);
        cb(null, tempFileName);
    }
});

const translationUpload = multer({
    storage: translationStorage,
    limits: {
        fileSize: config.limits.fileSize
    },
    fileFilter: function (req, file, cb) {
        // 允许.json和.keys文件
        const fileName = file.originalname.toLowerCase();
        if (file.mimetype === 'application/json' ||
            fileName.endsWith('.json') ||
            fileName.endsWith('.keys')) {
            cb(null, true);
        } else {
            cb(new Error('只允许上传.json或.keys文件'), false);
        }
    }
});

// 上传翻译文件
app.post('/api/upload_translation', translationUpload.fields([
    { name: 'file', maxCount: 1 },
    { name: 'source', maxCount: 1 },
    { name: 'available', maxCount: 1 }
]), (req, res) => {
    const startTime = Date.now();
    console.log(`[翻译上传] 开始处理翻译文件上传请求`);

    try {
        const { app, language } = req.body;
        if (!app || !language) {
            console.log(`[翻译上传] 错误: 缺少App或语言信息 - App: ${app}, 语言: ${language}`);
            return res.status(200).json({
                [definds.txt.CODE]: definds.code.FAILED,
                [definds.txt.MSG]: '请提供App和语言信息',
            });
        }

        // 检查是否至少有一个文件
        const files = req.files;
        if (!files || (!files.file && !files.source && !files.available)) {
            console.log(`[翻译上传] 错误: 未选择任何文件`);
            return res.status(200).json({
                [definds.txt.CODE]: definds.code.FAILED,
                [definds.txt.MSG]: '请至少选择一个文件',
            });
        }

        console.log(`[翻译上传] 处理文件上传 - App: ${app}, 语言: ${language}`);
        console.log(`[翻译上传] 文件详情:`, {
            translation: files.file ? files.file[0].originalname : '无',
            source: files.source ? files.source[0].originalname : '无',
            available: files.available ? files.available[0].originalname : '无'
        });

        // 获取正确的文件名
        const configPath = path.join(__dirname, 'translation-config.json');
        let targetFileName = `${language}.json`; // 默认文件名

        try {
            if (fs.existsSync(configPath)) {
                const configData = fs.readFileSync(configPath, 'utf8');
                const config = JSON.parse(configData);
                const appConfig = config.apps.find(appItem => appItem.appName === app);
                if (appConfig) {
                    const languageConfig = appConfig.languages.find(lang => lang.lanName === language);
                    if (languageConfig) {
                        targetFileName = languageConfig.lanFile;
                    }
                }
            }
        } catch (error) {
            console.error('读取配置文件错误:', error);
        }

        const appDir = path.join(translationsDir, app);

        // 确保目标目录存在
        if (!fs.existsSync(appDir)) {
            fs.mkdirSync(appDir, { recursive: true });
        }

        const uploadedFiles = [];

        // 处理翻译文件
        if (files.file && files.file[0]) {
            const translationFile = files.file[0];
            const targetFile = path.join(appDir, targetFileName);
            const tempFile = translationFile.path;

            console.log(`[翻译上传] 处理翻译文件: ${tempFile} -> ${targetFile}`);

            // 备份现有文件
            if (fs.existsSync(targetFile)) {
                const backupDir = path.join(appDir, 'backups');
                if (!fs.existsSync(backupDir)) {
                    fs.mkdirSync(backupDir, { recursive: true });
                }

                const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
                const backupFileName = `${path.basename(targetFileName, path.extname(targetFileName))}_backup_${timestamp}${path.extname(targetFileName)}`;
                const backupPath = path.join(backupDir, backupFileName);

                fs.copyFileSync(targetFile, backupPath);
                console.log(`[翻译上传] 备份翻译文件: ${backupFileName}`);
            }

            // 移动文件
            fs.renameSync(tempFile, targetFile);
            uploadedFiles.push({ type: 'translation', filename: targetFileName, originalName: translationFile.originalname });
            console.log(`[翻译上传] 翻译文件移动完成: ${targetFile}`);
        }

        // 处理源文文件
        if (files.source && files.source[0]) {
            const sourceFile = files.source[0];
            const targetFile = path.join(appDir, 'source.json');
            const tempFile = sourceFile.path;

            console.log(`[翻译上传] 处理源文文件: ${tempFile} -> ${targetFile}`);

            // 备份现有文件
            if (fs.existsSync(targetFile)) {
                const backupDir = path.join(appDir, 'backups');
                if (!fs.existsSync(backupDir)) {
                    fs.mkdirSync(backupDir, { recursive: true });
                }

                const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
                const backupFileName = `source_backup_${timestamp}.json`;
                const backupPath = path.join(backupDir, backupFileName);

                fs.copyFileSync(targetFile, backupPath);
                console.log(`[翻译上传] 备份源文文件: ${backupFileName}`);
            }

            // 移动文件
            fs.renameSync(tempFile, targetFile);
            uploadedFiles.push({ type: 'source', filename: 'source.json', originalName: sourceFile.originalname });
            console.log(`[翻译上传] 源文文件移动完成: ${targetFile}`);
        }

        // 处理可用值文件
        if (files.available && files.available[0]) {
            const availableFile = files.available[0];
            const targetFile = path.join(appDir, 'available.keys');
            const tempFile = availableFile.path;

            console.log(`[翻译上传] 处理可用值文件: ${tempFile} -> ${targetFile}`);

            // 备份现有文件
            if (fs.existsSync(targetFile)) {
                const backupDir = path.join(appDir, 'backups');
                if (!fs.existsSync(backupDir)) {
                    fs.mkdirSync(backupDir, { recursive: true });
                }

                const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
                const backupFileName = `available_backup_${timestamp}.keys`;
                const backupPath = path.join(backupDir, backupFileName);

                fs.copyFileSync(targetFile, backupPath);
                console.log(`[翻译上传] 备份可用值文件: ${backupFileName}`);
            }

            // 移动文件
            fs.renameSync(tempFile, targetFile);
            uploadedFiles.push({ type: 'available', filename: 'available.keys', originalName: availableFile.originalname });
            console.log(`[翻译上传] 可用值文件移动完成: ${targetFile}`);
        }

        // 清理所有临时文件
        const allFiles = [files.file, files.source, files.available].flat().filter(Boolean);
        allFiles.forEach(file => {
            try {
                if (fs.existsSync(file.path)) {
                    fs.unlinkSync(file.path);
                }
            } catch (error) {
                console.warn(`清理临时文件失败: ${file.path}`, error);
            }
        });

        const duration = Date.now() - startTime;
        console.log(`[翻译上传] 成功: 上传了${uploadedFiles.length}个文件 (App: ${app}, 语言: ${language}) - ${duration}ms`);

        res.json({
            [definds.txt.CODE]: definds.code.SUCCESS,
            [definds.txt.MSG]: `成功上传${uploadedFiles.length}个文件`,
            [definds.txt.DATA]: {
                uploadedFiles: uploadedFiles,
                app: app,
                language: language,
                uploadTime: new Date().toISOString(),
                hasBackup: fs.existsSync(path.join(appDir, 'backups'))
            }
        });
    } catch (error) {
        const duration = Date.now() - startTime;
        console.error(`[翻译上传] 错误: ${error.message} - ${duration}ms`);
        res.status(200).json({
            [definds.txt.CODE]: definds.code.FAILED,
            [definds.txt.MSG]: error.message,
        });
    }
});

// 获取指定App的翻译文件列表
app.get('/api/translation_files/:app', (req, res) => {
    try {
        const app = req.params.app;
        const appDir = path.join(translationsDir, app);

        if (!fs.existsSync(appDir)) {
            return res.json([]);
        }

        // 读取配置文件获取语言映射
        const configPath = path.join(__dirname, 'translation-config.json');
        let languageMap = {};

        try {
            if (fs.existsSync(configPath)) {
                const configData = fs.readFileSync(configPath, 'utf8');
                const config = JSON.parse(configData);
                const appConfig = config.apps.find(appItem => appItem.appName === app);
                if (appConfig) {
                    appConfig.languages.forEach(lang => {
                        languageMap[lang.lanFile] = lang.lanName;
                    });
                }
            }
        } catch (error) {
            console.error('读取配置文件错误:', error);
        }

        const files = fs.readdirSync(appDir)
            .filter(filename => !filename.startsWith('.') && filename !== 'backups')
            .map(filename => {
                const filePath = path.join(appDir, filename);
                const stats = fs.statSync(filePath);

                // 从配置文件获取语言名称，如果没有则使用文件名
                const language = languageMap[filename] || filename.replace('.json', '');

                // 计算备份文件数量
                const backupDir = path.join(appDir, 'backups');
                let backupCount = 0;
                if (fs.existsSync(backupDir)) {
                    const baseName = path.basename(filename, path.extname(filename));
                    const backupFiles = fs.readdirSync(backupDir).filter(backupFile =>
                        backupFile.startsWith(`${baseName}_backup_`)
                    );
                    backupCount = backupFiles.length;
                }

                return {
                    fileName: filename,
                    language: language,
                    size: stats.size,
                    uploadTime: stats.mtime.toISOString(),
                    backupCount: backupCount
                };
            });

        res.json({
            [definds.txt.CODE]: definds.code.SUCCESS,
            [definds.txt.MSG]: '获取翻译文件列表成功',
            [definds.txt.DATA]: {
                files: files
            }
        });
    } catch (error) {
        console.error('获取翻译文件列表错误:', error);
        res.status(200).json({
            [definds.txt.CODE]: definds.code.FAILED,
            [definds.txt.MSG]: error.message,
        });
    }
});

// 删除翻译文件
app.delete('/api/translation_files/:app/:filename', (req, res) => {
    try {
        const { app, filename } = req.params;
        const filePath = path.join(translationsDir, app, filename);

        if (!fs.existsSync(filePath)) {
            return res.status(404).json({
                [definds.txt.CODE]: definds.code.FAILED,
                [definds.txt.MSG]: '文件不存在',
            });
        }

        fs.unlinkSync(filePath);
        console.log(`翻译文件删除: ${filename} (App: ${app})`);

        res.json({
            [definds.txt.CODE]: definds.code.SUCCESS,
            [definds.txt.MSG]: '翻译文件删除成功',
        });
    } catch (error) {
        console.error('翻译文件删除错误:', error);
        res.status(200).json({
            [definds.txt.CODE]: definds.code.FAILED,
            [definds.txt.MSG]: error.message,
        });
    }
});

// 下载翻译文件:如果下载成功则200，否则400、500，错误信息返回给前端（code:400\500,msg:错误信息）
app.get('/api/download_translation/:app/:filename', (req, res) => {
    try {
        const { app, filename } = req.params;
        const filePath = path.join(translationsDir, app, filename);

        if (!fs.existsSync(filePath)) {
            return res.status(404).json({
                success: false,
                message: '文件不存在'
            });
        }

        // 设置下载头，处理中文文件名
        const encodedFilename = encodeURIComponent(filename);
        res.setHeader('Content-Disposition', `attachment; filename*=UTF-8''${encodedFilename}`);
        res.setHeader('Content-Type', 'application/json');

        res.sendFile(filePath);

        console.log(`翻译文件下载: ${filename} (App: ${app})`);
    } catch (error) {
        console.error('翻译文件下载错误:', error);
        res.status(500).json({
            success: false,
            message: '翻译文件下载失败',
            error: error.message
        });
    }
});

// 记录用户选择的App和语言
app.post('/api/record_translation_selection', (req, res) => {
    try {
        const { tsapp, tslang } = req.body;

        if (!tsapp || !tslang) {
            return res.status(200).json({
                [definds.txt.CODE]: definds.code.FAILED,
                [definds.txt.MSG]: 'tsapp和tslang参数不能为空',
            });
        }

        // 设置cookie
        res.cookie('tsapp', tsapp, {
            maxAge: 365 * 24 * 60 * 60 * 1000, // 1年
            httpOnly: false, // 允许前端访问
            secure: false, // 开发环境设为false
            sameSite: 'lax'
        });
        res.cookie('tslang', tslang, {
            maxAge: 365 * 24 * 60 * 60 * 1000, // 1年
            httpOnly: false, // 允许前端访问
            secure: false, // 开发环境设为false
            sameSite: 'lax'
        });

        console.log(`记录用户选择: App=${tsapp}, Language=${tslang}`);

        res.json({
            [definds.txt.CODE]: definds.code.SUCCESS,
            [definds.txt.MSG]: '选择已记录',
            [definds.txt.DATA]: {
                tsapp: tsapp,
                tslang: tslang
            }
        });
    } catch (error) {
        console.error('记录用户选择错误:', error);
        res.status(200).json({
            [definds.txt.CODE]: definds.code.FAILED,
            [definds.txt.MSG]: error.message,
        });
    }
});

// 获取备份文件列表
app.get('/api/translation_backups/:app/:filename', (req, res) => {
    try {
        const { app, filename } = req.params;
        const backupDir = path.join(translationsDir, app, 'backups');

        if (!fs.existsSync(backupDir)) {
            return res.json([]);
        }

        const baseName = path.basename(filename, path.extname(filename));
        const backupFiles = fs.readdirSync(backupDir)
            .filter(backupFile => backupFile.startsWith(`${baseName}_backup_`))
            .map(backupFile => {
                const filePath = path.join(backupDir, backupFile);
                const stats = fs.statSync(filePath);
                return {
                    fileName: backupFile,
                    size: stats.size,
                    backupTime: stats.mtime.toISOString()
                };
            })
            .sort((a, b) => new Date(b.backupTime) - new Date(a.backupTime));

        res.json({
            [definds.txt.CODE]: definds.code.SUCCESS,
            [definds.txt.MSG]: '获取备份文件列表成功',
            [definds.txt.DATA]: { files: backupFiles }
        });
    } catch (error) {
        console.error('获取备份文件列表错误:', error);
        res.status(200).json({
            [definds.txt.CODE]: definds.code.FAILED,
            [definds.txt.MSG]: error.message,
        });
    }
});

// 下载备份文件:如果下载成功则200，否则400、500，错误信息返回给前端（code:400\500,msg:错误信息）
app.get('/api/download_backup/:app/:filename', (req, res) => {
    try {
        const { app, filename } = req.params;
        const filePath = path.join(translationsDir, app, 'backups', filename);

        if (!fs.existsSync(filePath)) {
            return res.status(404).json({
                success: false,
                message: '备份文件不存在'
            });
        }

        // 设置下载头，处理中文文件名
        const encodedFilename = encodeURIComponent(filename);
        res.setHeader('Content-Disposition', `attachment; filename*=UTF-8''${encodedFilename}`);
        res.setHeader('Content-Type', 'application/json');
        res.sendFile(filePath);

        console.log(`备份文件下载: ${filename} (App: ${app})`);
    } catch (error) {
        console.error('备份文件下载错误:', error);
        res.status(500).json({
            success: false,
            message: '备份文件下载失败',
            error: error.message
        });
    }
});

// 备份翻译文件
app.post('/api/backup_translation', (req, res) => {
    try {
        const { app, fileName } = req.body;

        if (!app || !fileName) {
            return res.status(200).json({
                [definds.txt.CODE]: definds.code.FAILED,
                [definds.txt.MSG]: '请提供App和文件名信息',
            });
        }

        const appDir = path.join(translationsDir, app);
        const targetFile = path.join(appDir, fileName);
        const backupDir = path.join(appDir, 'backups');

        if (!fs.existsSync(targetFile)) {
            return res.status(204).json({
                [definds.txt.CODE]: definds.code.FAILED,
                [definds.txt.MSG]: '目标文件不存在',
            });
        }

        // 确保备份目录存在
        if (!fs.existsSync(backupDir)) {
            fs.mkdirSync(backupDir, { recursive: true });
        }

        // 创建备份文件
        const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
        const backupFileName = `${path.basename(fileName, path.extname(fileName))}_edit_${timestamp}${path.extname(fileName)}`;
        const backupPath = path.join(backupDir, backupFileName);

        fs.copyFileSync(targetFile, backupPath);

        console.log(`翻译文件备份: ${fileName} -> ${backupFileName} (App: ${app})`);

        res.json({
            [definds.txt.CODE]: definds.code.SUCCESS,
            [definds.txt.MSG]: '文件备份成功',
            [definds.txt.DATA]: {
                originalFile: fileName,
                backupFile: backupFileName,
                backupTime: new Date().toISOString()
            }
        });
    } catch (error) {
        console.error('备份翻译文件错误:', error);
        res.status(200).json({
            [definds.txt.CODE]: definds.code.FAILED,
            [definds.txt.MSG]: error.message,
        });
    }
});

// 保存翻译文件
app.post('/api/save_translation', (req, res) => {
    try {
        const { app, fileName, data } = req.body;

        if (!app || !fileName || !data) {
            return res.status(200).json({
                [definds.txt.CODE]: definds.code.FAILED,
                [definds.txt.MSG]: '请提供App、文件名和数据信息',
            });
        }

        const appDir = path.join(translationsDir, app);
        const targetFile = path.join(appDir, fileName);

        // 确保目录存在
        if (!fs.existsSync(appDir)) {
            fs.mkdirSync(appDir, { recursive: true });
        }

        // 保存文件
        fs.writeFileSync(targetFile, JSON.stringify(data, null, 2), 'utf8');

        console.log(`翻译文件保存: ${fileName} (App: ${app})`);

        res.json({
            [definds.txt.CODE]: definds.code.SUCCESS,
            [definds.txt.MSG]: '翻译文件保存成功',
            [definds.txt.DATA]: {
                fileName: fileName,
                app: app,
                saveTime: new Date().toISOString()
            }
        });
    } catch (error) {
        console.error('保存翻译文件错误:', error);
        res.status(200).json({
            [definds.txt.CODE]: definds.code.FAILED,
            [definds.txt.MSG]: error.message,
        });
    }
});

// IP位置信息代理接口
app.get('/api/ipinfo', async (req, res) => {
    try {
        // 获取用户真实IP地址
        let userIP = req.ip ||
            req.connection.remoteAddress ||
            req.socket.remoteAddress ||
            (req.connection.socket ? req.connection.socket.remoteAddress : null) ||
            req.headers['x-forwarded-for']?.split(',')[0] ||
            req.headers['x-real-ip'] ||
            '127.0.0.1';

        // 处理IPv6格式的局域网IP
        if (userIP.startsWith('::')) {
            // 处理 ::192.168.70.110 格式
            const ipv4Match1 = userIP.match(/^::(\d+\.\d+\.\d+\.\d+)$/);
            if (ipv4Match1) {
                userIP = ipv4Match1[1];
            }
            // 处理 ::ffff:192.168.70.110 格式
            const ipv4Match2 = userIP.match(/^::ffff:(\d+\.\d+\.\d+\.\d+)$/);
            if (ipv4Match2) {
                userIP = ipv4Match2[1];
            }
        }

        console.log(`代理请求IP位置信息，用户IP: ${userIP}`);

        // 判断是否为本地调试环境
        const isLocalhost = userIP === '::1' || userIP === '127.0.0.1' || userIP === '::ffff:127.0.0.1' ||
            userIP.startsWith('192.168.') || userIP.startsWith('10.') || userIP.startsWith('172.');

        // 使用Node.js的https模块请求外部API
        const https = require('https');

        const options = {
            hostname: 'ipapi.co',
            port: 443,
            path: isLocalhost ? '/json/' : `/${userIP}/json/`,  // 本地调试时使用默认查询
            method: 'GET',
            headers: {
                'User-Agent': 'Mozilla/5.0 (compatible; Server-Proxy/1.0)',
                'Accept': 'application/json'
            }
        };

        const proxyReq = https.request(options, (proxyRes) => {
            let data = '';

            proxyRes.on('data', (chunk) => {
                data += chunk;
            });

            proxyRes.on('end', () => {
                try {
                    const jsonData = JSON.parse(data);
                    console.log('IP位置信息获取成功');
                    res.json({
                        [definds.txt.CODE]: definds.code.SUCCESS,
                        [definds.txt.DATA]: jsonData
                    });
                } catch (parseError) {
                    console.error('解析IP位置信息失败:', parseError);
                    res.status(200).json({
                        [definds.txt.CODE]: definds.code.FAILED,
                        [definds.txt.MSG]: parseError.message,
                    });
                }
            });
        }); proxyReq.on('error', (error) => {
            console.error('代理请求失败:', error);
            res.status(200).json({
                [definds.txt.CODE]: definds.code.FAILED,
                [definds.txt.MSG]: error.message,
            });
        });
        proxyReq.setTimeout(10000, () => {
            console.error('代理请求超时');
            proxyReq.destroy();
            res.status(200).json({
                [definds.txt.CODE]: definds.code.FAILED,
                [definds.txt.MSG]: '请求超时',
            });
        });

        proxyReq.end();

    } catch (error) {
        console.error('IP位置信息代理错误:', error);
        res.status(200).json({
            [definds.txt.CODE]: definds.code.FAILED,
            [definds.txt.MSG]: error.message,
        });
    }
});

// 创建剪贴板
app.post('/api/clipboard', (req, res) => {
    try {
        const { content, os, deviceId } = req.body;
        const username = req.cookies?.username;

        if (!username) {
            return res.status(200).json({
                [definds.txt.CODE]: definds.code.FAILED,
                [definds.txt.MSG]: '请先登录',
            });
        }

        if (!content) {
            return res.status(200).json({
                [definds.txt.CODE]: definds.code.FAILED,
                [definds.txt.MSG]: '剪贴板内容不能为空',
            });
        }

        // 创建用户剪贴板目录
        const saveDir = path.join(usersDir, username, 'clipboard');
        if (!fs.existsSync(saveDir)) {
            fs.mkdirSync(saveDir, { recursive: true });
        }

        // 生成剪贴板ID和时间戳
        const clipboardId = Date.now().toString();
        const timestamp = new Date().toISOString();
        const filename = `clipboard_${clipboardId}.txt`;
        const filePath = path.join(saveDir, filename);

        // 创建剪贴板内容
        const clipboardContent = {
            id: clipboardId,
            username: username,
            content: content,
            os: os,
            deviceId: deviceId,
            createdAt: timestamp
        };

        // 保存到文件
        fs.writeFileSync(filePath, JSON.stringify(clipboardContent, null, 2));

        console.log(`剪贴板已创建: ${username}/${filename}`);

        // 按时间排序，最新的放在最前面，每个用户最多只能有20条，旧的则删除文件
        const files = fs.readdirSync(saveDir).filter(file => file.endsWith('.txt'));
        while (files.length > 20) {
            const oldestFile = files.sort((a, b) => new Date(a.createdAt) - new Date(b.createdAt))[0];
            const filePath = path.join(saveDir, oldestFile);
            if (fs.existsSync(filePath)) {
                fs.unlinkSync(filePath);
                files.splice(files.indexOf(oldestFile), 1);
            }
        }

        res.json({
            [definds.txt.CODE]: definds.code.SUCCESS,
            [definds.txt.MSG]: '剪贴板创建成功',
            [definds.txt.DATA]: {
                clipboard: clipboardContent
            }
        });
    } catch (error) {
        console.error('创建剪贴板错误:', error);
        res.status(200).json({
            [definds.txt.CODE]: definds.code.FAILED,
            [definds.txt.MSG]: error.message,
        });
    }
});

// 获取用户剪贴板列表
app.get('/api/clipboards', (req, res) => {
    try {
        // fromId是一个可选参数，当没传入时默认为0
        // GET请求的参数应该从query中获取，而不是body
        let fromId = 0;
        if (req.query.fromId !== undefined) {
            fromId = parseInt(req.query.fromId, 10);
            if (isNaN(fromId)) {
                return res.status(200).json({
                    [definds.txt.CODE]: definds.code.FAILED,
                    [definds.txt.MSG]: 'fromId必须是一个数字',
                });
            }
        }

        const username = req.cookies?.username;

        if (!username) {
            return res.status(200).json({
                [definds.txt.CODE]: definds.code.FAILED,
                [definds.txt.MSG]: '请先登录',
            });
        }

        const saveDir = path.join(usersDir, username, 'clipboard');

        if (!fs.existsSync(saveDir)) {
            return res.json({
                [definds.txt.CODE]: definds.code.SUCCESS,
                [definds.txt.MSG]: '获取剪贴板列表成功',
                [definds.txt.DATA]: {
                    clipboards: []
                }
            });
        }

        // 如果fromId大于0，则从fromId开始读取，只获取比fromId大的id的剪贴板，否则返回全部
        let clipboards = [];

        // 读取用户目录下的所有剪贴板文件
        const files = fs.readdirSync(saveDir).filter(file => file.endsWith('.txt'));
        clipboards = files.map(filename => {
            const filePath = path.join(saveDir, filename);
            const content = fs.readFileSync(filePath, 'utf8');
            return JSON.parse(content);
        }).sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));

        if (fromId > 0) {
            clipboards = clipboards.filter(clipboard => clipboard.id > fromId);
        }

        res.json({
            [definds.txt.CODE]: definds.code.SUCCESS,
            [definds.txt.MSG]: '获取剪贴板列表成功',
            [definds.txt.DATA]: {
                clipboards: clipboards
            }
        });
    } catch (error) {
        console.error('获取剪贴板列表错误:', error);
        res.status(200).json({
            [definds.txt.CODE]: definds.code.FAILED,
            [definds.txt.MSG]: error.message,
        });
    }
});

// 处理所有其他路由，返回Flutter应用（SPA支持）
app.use((req, res) => {
    const indexPath = path.resolve(webAppPath, 'index.html');
    console.log(`尝试发送文件: ${indexPath}`);

    // 检查文件是否存在
    if (!fs.existsSync(indexPath)) {
        console.error(`文件不存在: ${indexPath}`);
        return res.status(404).json({
            success: false,
            message: 'Flutter Web应用文件未找到',
            path: indexPath
        });
    }

    res.sendFile(indexPath);
});

// 启动服务器
app.listen(PORT, () => {
    console.log(`🚀 应用服务器运行在 http://localhost:${PORT}`);
    console.log(`📁 Flutter Web应用路径: ${webAppPath}`);
    console.log(`📁 上传目录: ${uploadDir}`);
    console.log(`📦 文件大小限制: ${config.limits.fileSize / (1024 * 1024)}MB`);
    console.log('🔧 支持的功能:');
    console.log('- 静态文件服务 (Flutter Web应用)');
    console.log('- POST /api/upload - 上传文件');
    console.log('- GET /api/files - 获取文件列表');
    console.log('- DELETE /api/files/:filename - 删除文件');
    console.log('- GET /api/download/:filename - 下载文件');
    console.log('- POST /api/notes - 创建笔记');
    console.log('- GET /api/notes - 获取用户笔记列表');
    console.log('- DELETE /api/notes/:noteId - 删除笔记');
    console.log('- GET /api/translation_config - 获取翻译配置');
    console.log('- POST /api/upload_translation - 上传翻译文件');
    console.log('- GET /api/translation_files/:app - 获取App翻译文件列表');
    console.log('- DELETE /api/translation_files/:app/:filename - 删除翻译文件');
    console.log('- GET /api/download_translation/:app/:filename - 下载翻译文件');
    console.log('- GET /api/translation_backups/:app/:filename - 获取备份文件列表');
    console.log('- GET /api/download_backup/:app/:filename - 下载备份文件');
    console.log('- POST /api/backup_translation - 备份翻译文件');
    console.log('- POST /api/save_translation - 保存翻译文件');
    console.log('- POST /api/record_translation_selection - 记录用户选择');
    console.log('- POST /api/register - 用户注册');
    console.log('- POST /api/login - 用户登录');
    console.log('- GET /api/ipinfo - 获取IP位置信息代理');
    console.log('- 所有路由重定向到Flutter应用 (SPA支持)');
});

