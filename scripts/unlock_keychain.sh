#!/bin/bash
# 解锁钥匙串以允许 Flutter CLI 进行代码签名
# 使用方法: ./scripts/unlock_keychain.sh

echo "正在解锁钥匙串..."
security unlock-keychain ~/Library/Keychains/login.keychain-db

if [ $? -eq 0 ]; then
    echo "钥匙串已解锁"
    # 设置钥匙串分区列表，允许 codesign 访问
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "" ~/Library/Keychains/login.keychain-db
    echo "钥匙串配置已更新"
else
    echo "警告: 钥匙串解锁失败，可能需要手动输入密码"
    echo "请运行: security unlock-keychain ~/Library/Keychains/login.keychain-db"
fi



