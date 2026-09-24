// 服务器配置文件
module.exports = {
    // 文件大小限制
    limits: {
        fileSize: 600 * 1024 * 1024, // 600MB
        jsonLimit: '5mb',
        urlencodedLimit: '5mb'
    },

    // 端口配置
    port: process.env.PORT || 3000,

    // 目录配置
    directories: {
        uploads: '../uploads',
        notes: '../notes',
        translations: '../translations',
        webApp: process.env.WEB_APP_PATH || '../build/web'
    },

    // CORS配置
    cors: {
        origin: '*',
        methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
        allowedHeaders: ['Origin', 'X-Requested-With', 'Content-Type', 'Accept', 'Authorization']
    }
};
