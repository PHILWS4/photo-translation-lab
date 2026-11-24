#!/bin/bash
cd "$(dirname "$0")" || exit 1
printf '手机联调服务器（同一局域网），关闭请按 Control+C\n'
printf '如果旧的“启动服务器”窗口仍在运行，请先在旧窗口按 Control+C。\n'
printf '让 Mac 和 iPhone 连接同一个 Wi-Fi，然后在手机应用中填入下面适用的地址：\n'
for interface in en0 en1 en2; do
  address=$(/usr/sbin/ipconfig getifaddr "$interface" 2>/dev/null)
  if [ -n "$address" ]; then printf '  %s: http://%s:8765\n' "$interface" "$address"; fi
done
printf '电脑自检：http://127.0.0.1:8765/health\n接口文档：http://127.0.0.1:8765/docs\n'
printf '仅用于可信局域网实验；此脚本会监听所有本机网络接口。\n'
.venv/bin/python -m uvicorn lab.server:app --host 0.0.0.0 --port 8765
read -r -p '服务已结束，按回车关闭…'
