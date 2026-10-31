// pm2 部署配置：新机器上 `pm2 start ecosystem.config.js` 即可启动。
//
// 关键点：cwd 固定为本文件所在目录。server.js 里的 ../datas、../uploads、
// ../build/web 全部相对 cwd 解析，启动位置一变这三个路径就全跑偏，
// 所以不要用 `pm2 start server.js` 在别的目录下裸启动。
//
// 注意（实测踩坑）：
//   1) 如果 pm2 里已存在同名 app（my-server），再执行
//      `pm2 start ecosystem.config.js`，pm2 会忽略 `--name`，
//      直接把本文件的配置套到现有 app 上并重启它 —— env 也会被覆盖。
//      要切换必须先 `pm2 delete my-server`。
//   2) 因此不要带 `PORT=xxxx` 对着跑着线上服务的机器测试本文件。
module.exports = {
    apps: [
        {
            name: 'my-server',
            script: 'server.js',
            cwd: __dirname,
            // 服务是有状态的：WebSocket 连接表（realtime.js connections）只在内存里，
            // 多实例之间不共享，因此 instances 只能是 1，不要开 cluster。
            instances: 1,
            autorestart: true,
            max_restarts: 10,
            restart_delay: 3000,
            env: {
                // ecosystem 文件由当前 shell 的 node 加载：
                // PORT=3100 pm2 start ecosystem.config.js 可覆盖，否则 3000
                PORT: process.env.PORT || 3000,
                // WEB_APP_PATH 不写，走 config.js 默认 ../build/web（相对 cwd）
            },
        },
    ],
};
