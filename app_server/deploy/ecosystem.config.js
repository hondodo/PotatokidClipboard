// pm2 进程配置（部署侧模板，随 deploy.sh 同步到 server/ecosystem.config.js）
module.exports = {
  apps: [
    {
      name: 'app-server',
      script: 'server.js',
      cwd: __dirname,
      exec_mode: 'fork', // JSON 文件存储 + 进程内串行锁，只能单进程
      instances: 1,
      autorestart: true,
      max_restarts: 10,
      restart_delay: 3000,
      max_memory_restart: '500M',
      env: {
        NODE_ENV: 'production',
        NODE_OPTIONS: '--max-old-space-size=384',
      },
      error_file: '../logs/error.log',
      out_file: '../logs/out.log',
      time: true,
    },
  ],
};
