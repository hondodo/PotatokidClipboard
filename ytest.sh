#!/bin/bash
set -e
cd /home/honghao/services/app_server
CJ=/tmp/ycj.txt
rm -f $CJ
curl -s --noproxy 127.0.0.1 -c $CJ -X POST http://127.0.0.1:47293/api/admin/login \
  -H 'Content-Type: application/json' -H 'X-Admin-Request: 1' -H 'Origin: http://127.0.0.1:47293' \
  --data '{"username":"honghao","password":"123456"}' >/dev/null
echo login_done
INIT=$(curl -s --noproxy 127.0.0.1 -b $CJ -c $CJ -X POST http://127.0.0.1:47293/api/admin/uploads/init \
  -H 'Content-Type: application/json' -H 'X-Admin-Request: 1' -H 'Origin: http://127.0.0.1:47293' \
  --data '{"appId":"potatokid-home-parent","platform":"apk","abi":"universal","filename":"test.apk","size":8388608,"sha256":"0000000000000000000000000000000000000000000000000000000000000000","version":"1.0.6","build":11,"pubspecBuildConfirmed":true}')
echo "INIT=$INIT"
MYUID=$(echo "$INIT" | grep -o '"uploadId":"[^"]*"' | sed 's/.*:"//; s/"//')
echo "uid=$MYUID"
head -c 8388608 /dev/urandom > /tmp/big.bin
echo "=== PUT 8MB chunk (local 127.0.0.1) ==="
curl -s --noproxy 127.0.0.1 -b $CJ -X PUT --data-binary @/tmp/big.bin \
  -H 'X-Admin-Request: 1' -H 'Origin: http://127.0.0.1:47293' \
  "http://127.0.0.1:47293/api/admin/uploads/$MYUID/chunks/0"; echo
echo "=== chunks dir ==="
ls -la uploads/tmp/$MYUID/chunks/ 2>/dev/null
curl -s --noproxy 127.0.0.1 -b $CJ -X DELETE -H 'X-Admin-Request: 1' -H 'Origin: http://127.0.0.1:47293' \
  "http://127.0.0.1:47293/api/admin/uploads/$MYUID" >/dev/null; echo cleaned
