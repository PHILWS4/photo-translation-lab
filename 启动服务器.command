#!/bin/bash
cd "$(dirname "$0")" || exit 1
printf '本机拍照翻译服务器，关闭请按 Control+C\n接口文档：http://127.0.0.1:8765/docs\n'
.venv/bin/python -m uvicorn lab.server:app --host 127.0.0.1 --port 8765
read -r -p '服务已结束，按回车关闭…'
