// 生产环境配置文件
module.exports = {
    port: 3000,
    webAppPath: 'D:\\www\\app_translator_web\\build\\web',
    uploadDir: '../uploads',
    cors: {
        origin: '*',
        methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
        allowedHeaders: ['Origin', 'X-Requested-With', 'Content-Type', 'Accept', 'Authorization']
    },
    multer: {
        limits: {
            fileSize: 600 * 1024 * 1024 // 600MB
        }
    }
};
